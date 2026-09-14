--- What other players see of this one: its look, published to the server half, and the looks of
--- everybody else, put on their proxies here.
---
--- An observer draws another player only once it holds that player's body and equipment and
--- wardrobe records; nothing the engine replicates by itself stands in for them. So once this
--- player is in the world on its own settled face, this client reads its body
--- (`Open77.appearance.captureBody`) and what it wears, and publishes it, again whenever any of it
--- changes, and again after every world entry. A body reload withdraws it first.

OpxAppearance = OpxAppearance or {}

local Config = OPX_APPEARANCE_CONFIG
local State = OpxAppearance.state
local Runtime = OpxAppearance.runtime

local Presence = {}
OpxAppearance.presence = Presence

local PRESENT = "opx77_appearance:present"
local ABSENT = "opx77_appearance:absent"
local ACK = "opx77_appearance:presentAck"
local BODY = "opx77_appearance:body"
local RESEND = "opx77_appearance:resend"

--- How often the look is read and compared with the one published, in ms.
local CHECK_MS = 1000
--- How long a publication waits for the server's acknowledgement before it goes again, in ms.
local RETRY_MS = 3000

local SLOTS = { "Head", "Face", "InnerChest", "OuterChest", "Legs", "Feet", "Outfit",
                "UnderwearTop", "UnderwearBottom" }
local OUTFIT_SLOTS = { "Head", "Face", "InnerChest", "OuterChest", "Legs", "Feet", "Outfit" }

local enabled = Config.PRESENT_BODIES ~= false

--- The look last sent, its sequence, and the sequence the server acknowledged.
---@type table|nil
local sent = nil
local sequence, acknowledged, sentAtMs = 0, 0, 0
--- The next publication follows a world entry, a restart or a reload: the server also hands this
--- client everybody else's look with it.
local fresh = true
--- A failed read is said once, not once a second.
local warned = {}

---@param key string
---@param line string
local function warnOnce(key, line)
  if warned[key] then return end
  warned[key] = true
  Open77.log.warn(line)
end

--- Whether two plain values are the same, tables by content.
---@param left any
---@param right any
---@return boolean
local function same(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return left == right end
  for key, value in pairs(left) do
    if not same(value, right[key]) then return false end
  end
  for key in pairs(right) do
    if left[key] == nil then return false end
  end
  return true
end

--- A slot map read from a registry: a record name or false per slot, nothing else.
---@param registry any
---@param slots string[]
---@return table
local function slotsOf(registry, slots)
  local out = {}
  if type(registry) ~= "table" then return out end
  for _, slot in ipairs(slots) do
    local value = registry[slot]
    if value == false or (type(value) == "string" and value ~= "") then out[slot] = value end
  end
  return out
end

--- What the player wears: the equipment registry, and the active outfit with its overrides.
---@return table|nil equipment, table wardrobe
local function readClothing()
  local equipment = type(Open77.equipment) == "table" and Open77.equipment or nil
  local called, registry, reason = false, nil, "Open77.equipment is not on this client"
  if equipment and type(equipment.registry) == "function" then
    called, registry, reason = pcall(equipment.registry)
  end
  if not called or type(registry) ~= "table" then
    warnOnce("equipment", ("the equipment registry cannot be read (%s): observers get an " ..
      "empty one"):format(tostring(called and reason or registry or reason)))
    registry = nil
  end

  local wardrobe = { outfits = {} }
  local outfits = type(Open77.wardrobe) == "table" and Open77.wardrobe or nil
  if outfits and type(outfits.active) == "function" then
    local read, active = pcall(outfits.active)
    if read and type(active) == "number" and active % 1 == 0 and active >= 0 and active <= 6 then
      wardrobe.active = active
      if type(outfits.outfit) == "function" then
        local opened, outfit = pcall(outfits.outfit, active)
        if opened and type(outfit) == "table" and type(outfit.registry) == "function" then
          local listed, overrides = pcall(outfit.registry)
          if listed then wardrobe.outfits[tostring(active)] = slotsOf(overrides, OUTFIT_SLOTS) end
        end
      end
    end
  end
  return slotsOf(registry, SLOTS), wardrobe
end

--- Whether this player is one others should see drawn as it is: announced into the gameplay
--- world, on its own settled face, with no editor and no body reload in the way.
---@return boolean
local function presentable()
  return enabled and State.citizenId ~= nil and State.gameplayAnnounced and
    State.worldEligible and not State.bodyReloading and not State.editing and
    not State.creatorUp and State.appearanceSettled() and Runtime.inGameplay()
end

--- Read the look and publish it when it changed, or when the last publication went
--- unacknowledged.
function Presence.check()
  if not presentable() then return end
  local read, body, reason = pcall(Open77.appearance.captureBody)
  if not read or type(body) ~= "table" then
    warnOnce("body", ("the body cannot be read (%s): other players cannot draw this one")
      :format(tostring(read and reason or body)))
    return
  end
  warned.body = nil
  local equipment, wardrobe = readClothing()
  local look = { body = body, equipment = equipment, wardrobe = wardrobe }

  local now = Runtime.nowMs()
  if sent ~= nil and same(look, sent) then
    if acknowledged == sequence or now - sentAtMs < RETRY_MS then return end
  end
  sequence = sequence + 1
  -- fresh until the server acknowledges it: a dropped publication must not lose the replay
  local dispatched, failure = TriggerServerEvent(PRESENT, body, equipment, wardrobe, sequence,
    fresh)
  if not dispatched then
    warnOnce("send", "the look was not sent: " .. tostring(failure))
    return
  end
  sent, sentAtMs = look, now
  Open77.log.debug(("look published: %s, %d groups, sequence %d")
    :format(tostring(body.family), type(body.groups) == "table" and #body.groups or 0, sequence))
end

--- The body is going: a reload, or the character leaving. Observers drop their proxy until the
--- next publication.
function Presence.withdraw()
  if not enabled then return end
  sent, fresh, acknowledged = nil, true, 0
  TriggerServerEvent(ABSENT)
end

--- A new world: this client's proxies of everybody else went with the old one.
function Presence.renew()
  sent, fresh, acknowledged = nil, true, 0
end

RegisterNetEvent(ACK, function(value)
  if value ~= sequence then return end
  acknowledged, fresh = value, false
end)

RegisterNetEvent(RESEND, function()
  Presence.renew()
end)

--- Another player's body for its proxy here, or false while that player's body is away.
RegisterNetEvent(BODY, function(player, body)
  player = tonumber(player)
  if not enabled or player == nil or (type(body) ~= "table" and body ~= false) then return end
  local puppets = Open77.puppets
  if type(puppets) ~= "table" or type(puppets.setBody) ~= "function" then
    return warnOnce("puppets", "Open77.puppets.setBody is not on this client: other players " ..
      "are not drawn")
  end
  local called, accepted, reason = pcall(puppets.setBody, player, body)
  if not called or not accepted then
    Open77.log.debug(("the body of player %d was not put on: %s")
      :format(player, tostring(called and reason or accepted)))
  end
end)

AddEventHandler("open77:worldReady", Presence.renew)
AddEventHandler("opx77:client:onPlayerUnloaded", Presence.withdraw)

AddEventHandler("onClientResourceStart", function(name)
  if name ~= GetCurrentResourceName() or not enabled then return end
  Presence.renew()
  CreateThread(function()
    while true do
      Wait(CHECK_MS)
      local ran, failure = pcall(Presence.check)
      if not ran then Open77.log.error("presence check: " .. tostring(failure)) end
    end
  end)
end)
