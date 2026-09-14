--- The server half: what every other client needs to draw a player at all.
---
--- On this platform an observer builds its proxy of another player from three records the
--- server hands it, not from anything the engine replicates on its own: the body (family and
--- customization groups, put on with `Open77.puppets.setBody`), and the equipment and wardrobe
--- records (`open77:equipment:record`, `open77:wardrobe:record`). The platform's own
--- open77_appearance distributes them; this resource replaces it, so it does too, the same way:
--- to everybody when a player's look is published, to a newcomer for everybody already there,
--- and between the players of a routing bucket whenever somebody enters it, because the native
--- roster retires the replicas of a player who changes bucket.
---
--- What a client publishes is its own presentation, read from its own engine, and it can only
--- ever describe that one player: the server takes the player id from the connection and checks
--- the shape of every record, never its truth. A face is stored by opx77_core, not here; nothing
--- here is persisted, and a restart asks every client to publish again.

local Config = OPX_APPEARANCE_CONFIG

local PRESENT = "opx77_appearance:present"
local ABSENT = "opx77_appearance:absent"
local ACK = "opx77_appearance:presentAck"
local BODY = "opx77_appearance:body"
local RESEND = "opx77_appearance:resend"
local EQUIPMENT = "open77:equipment:record"
local WARDROBE = "open77:wardrobe:record"

--- The least time between two publications of one player, in ms. A client retries a publication
--- nobody acknowledged, so a dropped one costs a second, not a look.
local PUBLISH_FLOOR_MS = 500

--- The most one encoded look may weigh: under the 48 KiB a net event carries.
local MAX_LOOK_BYTES = 40000

local SLOTS = { Head = true, Face = true, InnerChest = true, OuterChest = true, Legs = true,
                Feet = true, Outfit = true, UnderwearTop = true, UnderwearBottom = true }

--- player id -> { body, equipment, wardrobe }, the last look accepted for that player.
---@type table<integer, table>
local looks = {}
--- player id -> true while that player's body is away: a reload is putting a new puppet up.
---@type table<integer, boolean>
local absent = {}
--- player id -> when the last publication was accepted.
---@type table<integer, integer>
local lastAt = {}

local enabled = Config.PRESENT_BODIES ~= false

---@return integer
local function nowMs()
  local read, seconds = pcall(Open77.time.monotonic)
  if read and type(seconds) == "number" and seconds == seconds and seconds >= 0 and
    seconds < math.huge then
    return math.floor(seconds * 1000)
  end
  return 0
end

-- ---------------------------------------------------------------------------
-- Shapes
-- ---------------------------------------------------------------------------

---@param value any
---@return boolean
local function isInteger(value)
  return type(value) == "number" and value == value and value % 1 == 0
end

--- A native hash as the engine prints it: `0x` and sixteen hex digits, not all zero.
---@param value any
---@return boolean
local function fixedHash(value)
  return type(value) == "string" and #value == 18 and value:sub(1, 2) == "0x" and
    value:sub(3):match("^%x+$") ~= nil and value ~= "0x0000000000000000"
end

--- The body `Open77.appearance.captureBody` reads: a family and up to 64 groups of head, body
--- or arms customization keys, each a pair of hashes. The same bounds the platform checks.
---@param body any
---@return boolean
local function validBody(body)
  if type(body) ~= "table" or type(body.groups) ~= "table" then return false end
  if body.family ~= "male" and body.family ~= "female" then return false end
  local count = #body.groups
  if count == 0 or count > 64 then return false end
  local seen = {}
  for index, group in pairs(body.groups) do
    if not isInteger(index) or index < 1 or index > count or type(group) ~= "table" then
      return false
    end
    if group.part ~= "head" and group.part ~= "body" and group.part ~= "arms" then return false end
    if not fixedHash(group.name) or type(group.keys) ~= "table" then return false end
    local id = group.part .. ":" .. group.name:lower()
    if seen[id] then return false end
    seen[id] = true
    local keys = #group.keys
    if keys == 0 or keys > 64 then return false end
    for keyIndex, key in pairs(group.keys) do
      if not isInteger(keyIndex) or keyIndex < 1 or keyIndex > keys or type(key) ~= "table" or
        #key ~= 2 or not fixedHash(key[1]) or not fixedHash(key[2]) then
        return false
      end
    end
  end
  return true
end

--- A record name, or false for an empty slot.
---@param value any
---@return boolean
local function validItem(value)
  return value == false or (type(value) == "string" and #value >= 1 and #value <= 160 and
    value:match("^[%w_%.%-]+$") ~= nil)
end

--- A slot map: the nine equipment slots, or the seven an outfit overrides.
---@param value any
---@param outfit boolean
---@return table|nil
local function slotMap(value, outfit)
  if type(value) ~= "table" then return nil end
  local clean, count = {}, 0
  for slot, item in pairs(value) do
    count = count + 1
    if count > 9 or not SLOTS[slot] or (outfit and slot:match("^Underwear")) or
      not validItem(item) then
      return nil
    end
    clean[slot] = item
  end
  return clean
end

--- The wardrobe record: the active outfit index or none, and the outfits by index "0".."6".
---@param value any
---@return table|nil
local function wardrobeOf(value)
  if type(value) ~= "table" then return nil end
  local active = value.active
  if active ~= nil and (not isInteger(active) or active < 0 or active > 6) then return nil end
  local outfits, count = {}, 0
  for index, slots in pairs(type(value.outfits) == "table" and value.outfits or {}) do
    count = count + 1
    local number = tonumber(index)
    local clean = slotMap(slots, true)
    if count > 7 or not isInteger(number) or number < 0 or number > 6 or not clean then
      return nil
    end
    outfits[tostring(math.floor(number))] = clean
  end
  return { active = active, outfits = outfits, names = {} }
end

-- ---------------------------------------------------------------------------
-- Delivery
-- ---------------------------------------------------------------------------

--- Every connected player id; empty when the host cannot say.
---@return any[]
local function everybody()
  local read, list = pcall(Open77.players.all)
  return read and type(list) == "table" and list or {}
end

--- One player's look to one viewer, or to everybody but that player with -1.
---@param viewer integer
---@param player integer
local function deliver(viewer, player)
  local look = looks[player]
  if look == nil or absent[player] then return end
  if viewer == -1 then
    for _, other in ipairs(everybody()) do
      other = tonumber(other)
      if other and other ~= player then deliver(other, player) end
    end
    return
  end
  -- the records first: an observer's proxy waits for all three, and the body is what dresses it
  TriggerClientEvent(EQUIPMENT, viewer, player, look.equipment)
  TriggerClientEvent(WARDROBE, viewer, player, look.wardrobe)
  TriggerClientEvent(BODY, viewer, player, look.body)
end

--- The ids of the players in a routing bucket, or everybody when the host cannot say.
---@param bucket integer
---@return integer[]
local function playersIn(bucket)
  local reader = type(Open77.players) == "table" and Open77.players.inBucket or nil
  if type(reader) ~= "function" then reader = rawget(_G, "GetPlayersInBucket") end
  local read, list = false, nil
  if type(reader) == "function" then read, list = pcall(reader, bucket) end
  if not read or type(list) ~= "table" then list = everybody() end
  local ids = {}
  for _, id in ipairs(list) do
    id = tonumber(id)
    if id then ids[#ids + 1] = id end
  end
  return ids
end

--- A player the host no longer knows is forgotten.
---@param player integer
local function forget(player)
  looks[player], absent[player], lastAt[player] = nil, nil, nil
end

RegisterNetEvent(PRESENT, function(body, equipment, wardrobe, sequence, fresh)
  local player = tonumber(source)
  if not enabled or not player or player <= 0 or not isInteger(sequence) or sequence < 1 then
    return
  end
  local atMs = nowMs()
  if lastAt[player] and atMs - lastAt[player] < PUBLISH_FLOOR_MS then return end

  local cleanEquipment = slotMap(equipment, false)
  local cleanWardrobe = wardrobeOf(wardrobe)
  if not validBody(body) or not cleanEquipment or not cleanWardrobe then
    Open77.log.warn(("player %d published a look this server cannot read; ignored"):format(player))
    return
  end
  local look = { body = body, equipment = cleanEquipment, wardrobe = cleanWardrobe }
  local encoded, text = pcall(json.encode, look)
  if not encoded or type(text) ~= "string" or #text > MAX_LOOK_BYTES then
    Open77.log.warn(("player %d published a look too large to deliver; ignored"):format(player))
    return
  end

  lastAt[player] = atMs
  local returning = looks[player] == nil or absent[player] == true
  looks[player] = look
  absent[player] = nil
  deliver(-1, player)
  TriggerClientEvent(ACK, player, sequence)

  -- a newcomer, a new world entry or a reloaded body: its own proxies of everybody are gone
  if fresh == true or returning then
    for other in pairs(looks) do
      if other ~= player then deliver(player, other) end
    end
  end
  Open77.log.debug(("look of player %d published (%s, %d groups)")
    :format(player, body.family, #body.groups))
end)

--- The player's body is being reloaded: observers drop their proxy and get it back with the look
--- that follows.
RegisterNetEvent(ABSENT, function()
  local player = tonumber(source)
  if not enabled or not player or player <= 0 or absent[player] then return end
  absent[player] = true
  if looks[player] == nil then return end
  for _, other in ipairs(everybody()) do
    other = tonumber(other)
    if other and other ~= player then TriggerClientEvent(BODY, other, player, false) end
  end
end)

--- The native roster retires a player's replicas when that player changes bucket, and nothing
--- the engine replicates rebuilds them: both sides get each other's records again.
AddEventHandler("onPlayerBucketChange", function(player, bucket, previous)
  player, bucket, previous = tonumber(player), tonumber(bucket), tonumber(previous)
  if not enabled or not player or player <= 0 or not bucket or bucket == previous then return end
  for _, other in ipairs(playersIn(bucket)) do
    if other ~= player then
      deliver(player, other)
      deliver(other, player)
    end
  end
end)

AddEventHandler("onPlayerDisconnected", function(playerId)
  local player = tonumber(playerId)
  if player then forget(player) end
end)

AddEventHandler("playerDropped", function()
  local player = tonumber(source)
  if player then forget(player) end
end)

AddEventHandler("onResourceStart", function(name)
  if name ~= GetCurrentResourceName() or not enabled then return end
  -- nothing survives a restart here: every client already in the world publishes again
  TriggerClientEvent(RESEND, -1)
end)

if not enabled then
  Open77.log.info("PRESENT_BODIES is false: another resource must hand observers every body")
end
