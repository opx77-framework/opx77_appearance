--- @author DemiAutomatic
--- @file client/presence.lua
--- @description Publishes this player's look and dresses other players' proxies.

OpxAppearance = OpxAppearance or {}

local Config = OPX_APPEARANCE_CONFIG
local State = OpxAppearance.State
local Runtime = OpxAppearance.Runtime
local Clothing = OpxAppearance.Clothing

OpxAppearance.Presence = {}
local Presence = OpxAppearance.Presence

--- @author DemiAutomatic
--- @type {string}
--- @description Net event publishing this player's look to the server.
local PRESENT = 'opx77_appearance:present'

--- @author DemiAutomatic
--- @type {string}
--- @description Net event withdrawing this player's body.
local ABSENT = 'opx77_appearance:absent'

--- @author DemiAutomatic
--- @type {string}
--- @description Net event asking the server for everybody else's look.
local REPLAY = 'opx77_appearance:replay'

--- @author DemiAutomatic
--- @type {string}
--- @description Net event the server answers a publication with.
local ACK = 'opx77_appearance:presentAck'

--- @author DemiAutomatic
--- @type {string}
--- @description Net event the server answers a replay request with.
local REPLAYED = 'opx77_appearance:replayed'

--- @author DemiAutomatic
--- @type {string}
--- @description Net event carrying another player's look.
local LOOK = 'opx77_appearance:look'

--- @author DemiAutomatic
--- @type {string}
--- @description Net event asking every client to publish and ask again.
local RESEND = 'opx77_appearance:resend'

--- @author DemiAutomatic
--- @type {string}
--- @description The platform's package, which hands looks out while it runs.
local OFFICIAL = 'open77_appearance'

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds between two passes over the clothing and the look.
local CHECK_MS = 1000

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds a publication or replay request waits for its answer.
local RETRY_MS = 3000

local SLOTS = Clothing.SLOTS
local OUTFIT_SLOTS = Clothing.OUTFIT_SLOTS

--- @author DemiAutomatic
--- @type {table<string, string|false>}
--- @description The equipment observers get when the registry cannot be read.
local DEFAULT_EQUIPMENT = Clothing.DEFAULT.equipment

--- @author DemiAutomatic
--- @type {table|nil}
--- @description The look last sent to the server.
local sent = nil

--- @author DemiAutomatic
--- @type {integer}
--- @description Request sequence, the last acknowledged, the last sent, and when.
local sequence, acknowledged, sentSequence, sentAtMs = 0, 0, 0, 0

--- @author DemiAutomatic
--- @type {boolean}
--- @description This world entry still needs a replay, its request, and when.
local replayWanted, replaySequence, replayAtMs = true, 0, 0

--- @author DemiAutomatic
--- @type {table<string, boolean>}
--- @description Failures already said in the log, by key.
local warned = {}

--- @author DemiAutomatic
--- @method warnOnce
--- @description Logs a warning once per key.
--- @param key {string}
--- @param line {string}
local function warnOnce(key, line)
	if warned[key] then return end
	warned[key] = true
	Open77.log.warn(line)
end

--- @author DemiAutomatic
--- @method enabled
--- @description Whether this client hands looks out and puts them on.
--- @returns {boolean}
local function enabled()
	if Config.PRESENT_BODIES == false then return false end
	return GetResourceState(OFFICIAL) ~= 'running'
end

--- @author DemiAutomatic
--- @method wearable
--- @description Answers an item this body can wear, or false.
--- @param record {any}
--- @param family {string|nil}
--- @returns {string|false}
local function wearable(record, family)
	if type(record) ~= 'string' or record == '' then return false end
	record = Clothing.Resolve(record)
	local equipment = Open77.equipment
	if family == nil or type(equipment) ~= 'table' or type(equipment.info) ~= 'function' then
		return record
	end
	local read, info = pcall(equipment.info, record)
	if not read or type(info) ~= 'table' then return record end
	return Clothing.Fits(info, family) and record or false
end

--- @author DemiAutomatic
--- @method readClothing
--- @description Reads every equipment slot and the active outfit for a look.
--- @param family {string|nil}
--- @returns {table, table}
local function readClothing(family)
	local equipment = type(Open77.equipment) == 'table' and Open77.equipment or nil
	local called, registry, reason = false, nil, 'Open77.equipment is not on this client'
	if equipment and type(equipment.registry) == 'function' then
		called, registry, reason = pcall(equipment.registry)
	end
	local slots = {}
	if called and type(registry) == 'table' then
		for _, slot in ipairs(SLOTS) do slots[slot] = wearable(registry[slot], family) end
	else
		warnOnce('equipment', ('the equipment registry cannot be read (%s): observers get the ' ..
			'default one'):format(tostring(called and reason or registry or reason)))
		for slot, value in pairs(DEFAULT_EQUIPMENT) do slots[slot] = value end
	end

	local wardrobe = { outfits = {} }
	local outfits = type(Open77.wardrobe) == 'table' and Open77.wardrobe or nil
	if outfits and type(outfits.active) == 'function' then
		local read, active = pcall(outfits.active)
		if read and type(active) == 'number' and active % 1 == 0 and active >= 0 and active <= 6 then
			wardrobe.active = active
			if type(outfits.outfit) == 'function' then
				local opened, outfit = pcall(outfits.outfit, active)
				if opened and type(outfit) == 'table' and type(outfit.registry) == 'function' then
					local listed, overrides = pcall(outfit.registry)
					if listed and type(overrides) == 'table' then
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

--- @author DemiAutomatic
--- @method presentable
--- @description Whether this player's look may be published now.
--- @returns {boolean}
local function presentable()
	if not (State.citizenId ~= nil and State.gameplayAnnounced and State.worldEligible and
		not State.bodyReloading and not State.editing and not State.creatorUp and
		State.AppearanceSettled() and Runtime.InGameplay()) then
		return false
	end
	if Clothing.Previewing() then return false end
	return Clothing.Settled()
end

--- @author DemiAutomatic
--- @method askReplay
--- @description Asks for everybody else's look once per world entry until answered.
local function askReplay()
	if not replayWanted or not State.worldEligible then return end
	local now = Runtime.NowMs()
	if replaySequence ~= 0 and now - replayAtMs < RETRY_MS then return end
	sequence = sequence + 1
	if TriggerServerEvent(REPLAY, sequence) then replaySequence, replayAtMs = sequence, now end
end

--- @author DemiAutomatic
--- @method publish
--- @description Publishes the look when it changed or went unanswered.
local function publish()
	if not presentable() then return end
	local read, body, reason = pcall(Open77.appearance.captureBody)
	if not read or type(body) ~= 'table' then
		warnOnce('body', ('the body cannot be read (%s): other players cannot draw this one')
			:format(tostring(read and reason or body)))
		return
	end
	warned.body = nil
	local equipment, wardrobe = readClothing(body.family)
	local look = { body = body, equipment = equipment, wardrobe = wardrobe }

	local now = Runtime.NowMs()
	if sent ~= nil and Clothing.Same(look, sent) and
		(acknowledged == sentSequence or now - sentAtMs < RETRY_MS) then
		return
	end
	sequence = sequence + 1
	local dispatched, failure = TriggerServerEvent(PRESENT, body, equipment, wardrobe, sequence)
	if not dispatched then
		warnOnce('send', 'the look was not sent: ' .. tostring(failure))
		return
	end
	sent, sentSequence, sentAtMs = look, sequence, now
	Open77.log.debug(('look published: %s, %d groups, sequence %d')
		:format(tostring(body.family), type(body.groups) == 'table' and #body.groups or 0, sequence))
end

--- @author DemiAutomatic
--- @method OpxAppearance.Presence.Check
--- @description Runs one presence pass: the replay request and the publication.
function OpxAppearance.Presence.Check()
	if not enabled() then return end
	askReplay()
	publish()
end

--- @author DemiAutomatic
--- @method OpxAppearance.Presence.Renew
--- @description Starts over for a new world: publish and ask again.
function OpxAppearance.Presence.Renew()
	sequence = sequence + 1
	sent, acknowledged, sentSequence = nil, 0, 0
	replayWanted, replaySequence, replayAtMs = true, 0, 0
end

--- @author DemiAutomatic
--- @method OpxAppearance.Presence.Withdraw
--- @description Withdraws this player's body until the next publication.
function OpxAppearance.Presence.Withdraw()
	if not enabled() then return end
	sequence = sequence + 1
	sent, acknowledged, sentSequence = nil, 0, 0
	TriggerServerEvent(ABSENT)
end

--- @author DemiAutomatic
--- @event opx77_appearance:presentAck
--- @description Records the server's answer to the last publication.
--- @param value {integer}
--- @param accepted {boolean}
RegisterNetEvent(ACK, function(value, accepted)
	if value ~= sentSequence then return end
	acknowledged = value
	if accepted == false then
		warnOnce('refused', "the server could not read this player's body: others cannot draw it")
	end
end)

--- @author DemiAutomatic
--- @event opx77_appearance:replayed
--- @description Records that the server answered this world entry's replay request.
--- @param value {integer}
RegisterNetEvent(REPLAYED, function(value)
	if value == replaySequence then replayWanted = false end
end)

--- @author DemiAutomatic
--- @event opx77_appearance:resend
--- @description Publishes and asks again after the server half restarted.
RegisterNetEvent(RESEND, function()
	Presence.Renew()
end)

--- @author DemiAutomatic
--- @method project
--- @description Makes one puppets call on a proxy, logging a refusal.
--- @param name {string}
local function project(name, ...)
	local puppets = Open77.puppets
	if type(puppets) ~= 'table' or type(puppets[name]) ~= 'function' then
		return warnOnce('puppets.' .. name, ('Open77.puppets.%s is not on this client: other ' ..
			'players are not drawn'):format(name))
	end
	local called, accepted, reason = pcall(puppets[name], ...)
	if not called or not accepted then
		Open77.log.debug(('puppets.%s refused: %s')
			:format(name, tostring(called and reason or accepted)))
	end
end

--- @author DemiAutomatic
--- @event opx77_appearance:look
--- @description Puts another player's look on its proxy, or drops its body.
--- @param player {integer|string}
--- @param look {AppearanceLook|false}
RegisterNetEvent(LOOK, function(player, look)
	player = tonumber(player)
	if not enabled() or player == nil then return end
	if look == false then return project('setBody', player, false) end
	if type(look) ~= 'table' or type(look.body) ~= 'table' then return end
	local equipment = type(look.equipment) == 'table' and look.equipment or DEFAULT_EQUIPMENT
	for _, slot in ipairs(SLOTS) do
		local value = equipment[slot]
		project('setSlot', player, slot, type(value) == 'string' and value or false)
	end
	local wardrobe = type(look.wardrobe) == 'table' and look.wardrobe or {}
	local outfits = {}
	for index, items in pairs(type(wardrobe.outfits) == 'table' and wardrobe.outfits or {}) do
		index = tonumber(index)
		if index ~= nil and type(items) == 'table' then outfits[index] = items end
	end
	project('setWardrobe', player, { active = tonumber(wardrobe.active), outfits = outfits })
	project('setBody', player, look.body)
end)

--- @author DemiAutomatic
--- @event open77:worldReady
--- @description Starts presence over for the new world.
AddEventHandler('open77:worldReady', Presence.Renew)

--- @author DemiAutomatic
--- @event onClientResourceStart
--- @description Starts presence over when this resource starts.
--- @param name {string}
AddEventHandler('onClientResourceStart', function(name)
	if name ~= GetCurrentResourceName() then return end
	if Config.PRESENT_BODIES ~= false and GetResourceState(OFFICIAL) == 'running' then
		Open77.log.warn(OFFICIAL .. ' is running and hands looks out itself; this resource does not')
	end
	Presence.Renew()
end)

CreateThread(function()
	while true do
		Wait(CHECK_MS)
		local ok, failure = pcall(Clothing.Check)
		if not ok then Open77.log.error('clothing worker: ' .. tostring(failure)) end
		local ran, reason = pcall(Presence.Check)
		if not ran then Open77.log.error('presence check: ' .. tostring(reason)) end
	end
end)
