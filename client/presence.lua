--- What other players see of this one, and what this one sees of them.
---
--- An observer draws another player only from what it is handed: that player's body
--- (`Open77.puppets.setBody`), each equipment slot (`setSlot`) and the wardrobe (`setWardrobe`).
--- The engine replicates none of them, and the platform's open77_equipment and open77_wardrobe
--- relays that would put the last two on do not run without open77_appearance. So this client
--- publishes its own look -- body, equipment registry, active outfit -- once it is in the world
--- on its settled face, again whenever any of it changes, and after every world entry; it asks
--- for everybody else's after every world entry, whatever state its own look is in; and it puts
--- every look it is handed on that player's proxy. A body reload withdraws the body first.

OpxAppearance = OpxAppearance or {}

local Config = OPX_APPEARANCE_CONFIG
local State = OpxAppearance.state
local Runtime = OpxAppearance.runtime

local Presence = {}
OpxAppearance.presence = Presence

local PRESENT = "opx77_appearance:present"
local ABSENT = "opx77_appearance:absent"
local REPLAY = "opx77_appearance:replay"
local ACK = "opx77_appearance:presentAck"
local REPLAYED = "opx77_appearance:replayed"
local LOOK = "opx77_appearance:look"
local RESEND = "opx77_appearance:resend"

local OFFICIAL = "open77_appearance"

--- How often the look is read and compared with the one published, in ms.
local CHECK_MS = 1000
--- How long a publication or a replay request waits for its answer before it goes again, in ms.
local RETRY_MS = 3000

local SLOTS = { "Head", "Face", "InnerChest", "OuterChest", "Legs", "Feet", "Outfit",
                "UnderwearTop", "UnderwearBottom" }
local OUTFIT_SLOTS = { "Head", "Face", "InnerChest", "OuterChest", "Legs", "Feet", "Outfit" }

--- What the platform's presentation service states for a character it has no row for.
local DEFAULT_EQUIPMENT = { Head = false, Face = false, InnerChest = false, OuterChest = false,
  Legs = false, Feet = false, Outfit = false, UnderwearTop = false,
  UnderwearBottom = "Items.Underwear_Basic_01_Bottom" }

--- The look last sent and its sequence; the sequences answered. Every world entry and every
--- withdrawal moves the sequence on, so an answer to an older request settles nothing.
---@type table|nil
local sent = nil
local sequence, acknowledged, sentSequence, sentAtMs = 0, 0, 0, 0
--- The replay this world entry still needs, the request that asked for it, and when.
local replayWanted, replaySequence, replayAtMs = true, 0, 0
--- A failed read is said once, not once a second.
local warned = {}

---@param key string
---@param line string
local function warnOnce(key, line)
  if warned[key] then return end
  warned[key] = true
  Open77.log.warn(line)
end

--- Whether this client takes part: configured on, and the platform's package not running.
---@return boolean
local function enabled()
  if Config.PRESENT_BODIES == false then return false end
  return GetResourceState(OFFICIAL) ~= "running"
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

--- A record this body can wear, or false. An item another body family cannot wear is dropped
--- the way the platform's own record drops it; one this client cannot look up is kept.
---@param record any
---@param family string|nil
---@return string|false
local function wearable(record, family)
  if type(record) ~= "string" or record == "" then return false end
  local equipment = Open77.equipment
  if family == nil or type(equipment) ~= "table" or type(equipment.info) ~= "function" then
    return record
  end
  local read, info = pcall(equipment.info, record)
  if not read or type(info) ~= "table" then return record end
  if family == "male" and info.supportsMale == false then return false end
  if family == "female" and info.supportsFemale == false then return false end
  return record
end

--- What the player wears: every equipment slot stated, and the active outfit with its overrides.
---@param family string|nil
---@return table equipment, table wardrobe
local function readClothing(family)
  local equipment = type(Open77.equipment) == "table" and Open77.equipment or nil
  local called, registry, reason = false, nil, "Open77.equipment is not on this client"
  if equipment and type(equipment.registry) == "function" then
    called, registry, reason = pcall(equipment.registry)
  end
  local slots = {}
  if called and type(registry) == "table" then
    for _, slot in ipairs(SLOTS) do slots[slot] = wearable(registry[slot], family) end
  else
    warnOnce("equipment", ("the equipment registry cannot be read (%s): observers get the " ..
      "default one"):format(tostring(called and reason or registry or reason)))
    for slot, value in pairs(DEFAULT_EQUIPMENT) do slots[slot] = value end
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
          if listed and type(overrides) == "table" then
            local shown = {}
            for _, slot in ipairs(OUTFIT_SLOTS) do
              if overrides[slot] ~= nil then shown[slot] = wearable(overrides[slot], family) end
            end
            wardrobe.outfits[tostring(active)] = shown
          end
        end
      end
    end
  end
  return slots, wardrobe
end

--- Whether this player's look should be published: announced into the gameplay world, on its
--- own settled face, with no editor and no body reload in the way.
---@return boolean
local function presentable()
  return State.citizenId ~= nil and State.gameplayAnnounced and State.worldEligible and
    not State.bodyReloading and not State.editing and not State.creatorUp and
    State.appearanceSettled() and Runtime.inGameplay()
end

--- Ask for everybody else's look, once per world entry, retried until answered. Only from the
--- gameplay world: the pre-game menu's puppets are nobody's.
local function askReplay()
  if not replayWanted or not State.worldEligible then return end
  local now = Runtime.nowMs()
  if replaySequence ~= 0 and now - replayAtMs < RETRY_MS then return end
  sequence = sequence + 1
  if TriggerServerEvent(REPLAY, sequence) then replaySequence, replayAtMs = sequence, now end
end

--- Publish this player's look when it changed, or when the last publication went unanswered.
local function publish()
  if not presentable() then return end
  local read, body, reason = pcall(Open77.appearance.captureBody)
  if not read or type(body) ~= "table" then
    warnOnce("body", ("the body cannot be read (%s): other players cannot draw this one")
      :format(tostring(read and reason or body)))
    return
  end
  warned.body = nil
  local equipment, wardrobe = readClothing(body.family)
  local look = { body = body, equipment = equipment, wardrobe = wardrobe }

  local now = Runtime.nowMs()
  if sent ~= nil and same(look, sent) and
    (acknowledged == sentSequence or now - sentAtMs < RETRY_MS) then
    return
  end
  sequence = sequence + 1
  local dispatched, failure = TriggerServerEvent(PRESENT, body, equipment, wardrobe, sequence)
  if not dispatched then
    warnOnce("send", "the look was not sent: " .. tostring(failure))
    return
  end
  sent, sentSequence, sentAtMs = look, sequence, now
  Open77.log.debug(("look published: %s, %d groups, sequence %d")
    :format(tostring(body.family), type(body.groups) == "table" and #body.groups or 0, sequence))
end

function Presence.check()
  if not enabled() then return end
  askReplay()
  publish()
end

--- A new world: this client's proxies of everybody else went with the old one, and its own
--- look is published again.
function Presence.renew()
  sequence = sequence + 1
  sent, acknowledged, sentSequence = nil, 0, 0
  replayWanted, replaySequence, replayAtMs = true, 0, 0
end

--- The body is going: a reload, or the character leaving. Observers drop their proxy until the
--- next publication.
function Presence.withdraw()
  if not enabled() then return end
  sequence = sequence + 1
  sent, acknowledged, sentSequence = nil, 0, 0
  TriggerServerEvent(ABSENT)
end

RegisterNetEvent(ACK, function(value, accepted)
  if value ~= sentSequence then return end
  acknowledged = value
  if accepted == false then
    warnOnce("refused", "the server could not read this player's body: others cannot draw it")
  end
end)

RegisterNetEvent(REPLAYED, function(value)
  if value == replaySequence then replayWanted = false end
end)

RegisterNetEvent(RESEND, function()
  Presence.renew()
end)

--- Put a call on a proxy, saying why once when the host refuses it.
---@param name string
local function project(name, ...)
  local puppets = Open77.puppets
  if type(puppets) ~= "table" or type(puppets[name]) ~= "function" then
    return warnOnce("puppets." .. name, ("Open77.puppets.%s is not on this client: other " ..
      "players are not drawn"):format(name))
  end
  local called, accepted, reason = pcall(puppets[name], ...)
  if not called or not accepted then
    Open77.log.debug(("puppets.%s refused: %s")
      :format(name, tostring(called and reason or accepted)))
  end
end

--- Another player's look for its proxy here, or false while that player's body is away. The
--- clothing goes on before the body: the proxy is dressed as soon as all three are there.
RegisterNetEvent(LOOK, function(player, look)
  player = tonumber(player)
  if not enabled() or player == nil then return end
  if look == false then return project("setBody", player, false) end
  if type(look) ~= "table" or type(look.body) ~= "table" then return end
  local equipment = type(look.equipment) == "table" and look.equipment or DEFAULT_EQUIPMENT
  for _, slot in ipairs(SLOTS) do
    local value = equipment[slot]
    project("setSlot", player, slot, type(value) == "string" and value or false)
  end
  local wardrobe = type(look.wardrobe) == "table" and look.wardrobe or {}
  local outfits = {}
  for index, items in pairs(type(wardrobe.outfits) == "table" and wardrobe.outfits or {}) do
    index = tonumber(index)
    if index ~= nil and type(items) == "table" then outfits[index] = items end
  end
  project("setWardrobe", player, { active = tonumber(wardrobe.active), outfits = outfits })
  project("setBody", player, look.body)
end)

AddEventHandler("open77:worldReady", Presence.renew)
AddEventHandler("opx77:client:onPlayerUnloaded", Presence.withdraw)

AddEventHandler("onClientResourceStart", function(name)
  if name ~= GetCurrentResourceName() then return end
  if Config.PRESENT_BODIES ~= false and GetResourceState(OFFICIAL) == "running" then
    Open77.log.warn(OFFICIAL .. " is running and hands looks out itself; this resource does not")
  end
  Presence.renew()
  CreateThread(function()
    while true do
      Wait(CHECK_MS)
      local ran, failure = pcall(Presence.check)
      if not ran then Open77.log.error("presence check: " .. tostring(failure)) end
    end
  end)
end)
