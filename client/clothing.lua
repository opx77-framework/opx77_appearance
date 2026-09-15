--- @author DemiAutomatic
--- @file client/clothing.lua
--- @description Puts the character's stored clothing on its puppet and saves changes.

OpxAppearance = OpxAppearance or {}

local Config = OPX_APPEARANCE_CONFIG
local State = OpxAppearance.State
local Runtime = OpxAppearance.Runtime

OpxAppearance.Clothing = {}
local Clothing = OpxAppearance.Clothing

--- @author DemiAutomatic
--- @type {string}
--- @description Net event that sends a clothing record to opx77_core.
local SAVE = 'opx77:server:saveClothing'

--- @author DemiAutomatic
--- @type {string}
--- @description The operation a core refusal names when it answers a clothing save.
local SAVE_OPERATION = 'saveClothing'

--- @author DemiAutomatic
--- @type {string}
--- @description The platform's package, which owns clothing while it runs.
local OFFICIAL = 'open77_appearance'

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds between two looks at what the puppet wears.
local CHECK_MS = 1000

--- @author DemiAutomatic
--- @type {integer}
--- @description Put-ons before a world entry gives up on the record.
local RESTORE_ATTEMPTS = 5

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds a put-on may take to read back before the next.
local VERIFY_MS = 2000

--- @author DemiAutomatic
--- @type {integer}
--- @description Longest milliseconds the published look waits for the clothes.
local PRESENCE_HOLD_MS = 15000

--- @author DemiAutomatic
--- @type {integer}
--- @description Failed saves in a row before this character stops saving.
local STRIKES = 2

--- @author DemiAutomatic
--- @type {integer}
--- @description Shipped CLOTHING.SAVE_DEBOUNCE_MS, for a config that lost it.
local SAVE_DEBOUNCE_MS = 2000

--- @author DemiAutomatic
--- @type {string[]}
--- @description The nine equipment slots of a record.
local SLOTS = { 'Head', 'Face', 'InnerChest', 'OuterChest', 'Legs', 'Feet', 'Outfit',
	'UnderwearTop', 'UnderwearBottom' }

--- @author DemiAutomatic
--- @type {string[]}
--- @description The seven visible slots an outfit overrides.
local OUTFIT_SLOTS = { 'Head', 'Face', 'InnerChest', 'OuterChest', 'Legs', 'Feet', 'Outfit' }

--- @author DemiAutomatic
--- @type {integer}
--- @description Wardrobe outfits, indexed 0 to 6.
local OUTFITS = 7

--- @author DemiAutomatic
--- @type {AppearanceClothing}
--- @description The record the platform states for a character without one.
local DEFAULT = {
	schemaVersion = 1,
	equipment = { Head = false, Face = false, InnerChest = false, OuterChest = false,
		Legs = false, Feet = false, Outfit = false, UnderwearTop = false,
		UnderwearBottom = 'Items.Underwear_Basic_01_Bottom' },
	wardrobe = { outfits = {} },
}

--- @author DemiAutomatic
--- @type {string|nil}
--- @description The character whose clothing this client handles.
local citizen = nil

--- @author DemiAutomatic
--- @type {table|false|nil}
--- @description The core's record, false when none is stored, nil when absent.
local stored = nil

--- @author DemiAutomatic
--- @type {boolean}
--- @description This character's changes are sent to the core.
local saving = false

--- @author DemiAutomatic
--- @type {table|nil}
--- @description What the puppet should wear: last put on or last sent.
local wanted = nil

--- @author DemiAutomatic
--- @type {{ record: table, previous: table|nil, deadlineMs: integer }|nil}
--- @description The clothing save sent and not yet answered.
local pending = nil

--- @author DemiAutomatic
--- @type {integer|nil}
--- @description When the last clothing save went out, in milliseconds.
local lastSentAtMs = nil

--- @author DemiAutomatic
--- @type {integer}
--- @description Failed saves in a row for this character.
local strikes = 0

--- @author DemiAutomatic
--- @type {boolean}
--- @description The player was told this character's clothes are not kept.
local told = false

--- @author DemiAutomatic
--- @type {string}
--- @description This world entry's clothing phase.
local phase = 'idle'

--- @author DemiAutomatic
--- @type {table|nil}
--- @description The record put on this world entry, fitted to the body.
local target = nil

--- @author DemiAutomatic
--- @type {integer}
--- @description Put-ons spent, when the last went on, when presence first waited.
local attempts, appliedAtMs, holdFromMs = 0, 0, 0

--- @author DemiAutomatic
--- @type {table|nil}
--- @description A changed record seen on the puppet, and since when.
local candidate, candidateAtMs = nil, 0

--- @author DemiAutomatic
--- @method recordOf
--- @description Answers a record name, or false for an empty slot.
--- @param value {any}
--- @returns {string|false}
local function recordOf(value)
	return type(value) == 'string' and value ~= '' and value or false
end

--- @author DemiAutomatic
--- @method normalize
--- @description Puts a clothing-shaped table in the core's canonical form.
--- @param value {any}
--- @returns {table|nil}
local function normalize(value)
	if type(value) ~= 'table' then return nil end
	local equipment = type(value.equipment) == 'table' and value.equipment or {}
	local wardrobe = type(value.wardrobe) == 'table' and value.wardrobe or {}
	local out = { schemaVersion = 1, equipment = {}, wardrobe = { outfits = {} } }
	for _, slot in ipairs(SLOTS) do out.equipment[slot] = recordOf(equipment[slot]) end
	local active = tonumber(wardrobe.active)
	if active and active % 1 == 0 and active >= 0 and active < OUTFITS then
		out.wardrobe.active = math.floor(active)
	end
	local outfits = type(wardrobe.outfits) == 'table' and wardrobe.outfits or {}
	for index = 0, OUTFITS - 1 do
		local overrides = outfits[tostring(index)] or outfits[index]
		if type(overrides) == 'table' then
			local shown, any = {}, false
			for _, slot in ipairs(OUTFIT_SLOTS) do
				local item = overrides[slot]
				if item == false or (type(item) == 'string' and item ~= '') then
					shown[slot], any = item, true
				end
			end
			if any then out.wardrobe.outfits[tostring(index)] = shown end
		end
	end
	return out
end
OpxAppearance.Clothing.Normalize = normalize

--- @author DemiAutomatic
--- @method same
--- @description Whether two normalized records are the same clothing.
--- @param left {table|nil}
--- @param right {table|nil}
--- @returns {boolean}
local function same(left, right)
	if type(left) ~= 'table' or type(right) ~= 'table' then return false end
	for _, slot in ipairs(SLOTS) do
		if left.equipment[slot] ~= right.equipment[slot] then return false end
	end
	if left.wardrobe.active ~= right.wardrobe.active then return false end
	for index = 0, OUTFITS - 1 do
		local a, b = left.wardrobe.outfits[tostring(index)], right.wardrobe.outfits[tostring(index)]
		if (a == nil) ~= (b == nil) then return false end
		if a ~= nil then
			for _, slot in ipairs(OUTFIT_SLOTS) do
				if a[slot] ~= b[slot] then return false end
			end
		end
	end
	return true
end
OpxAppearance.Clothing.Same = same

--- @author DemiAutomatic
--- @method fit
--- @description Answers an item this body can wear, or false.
--- @param record {string|false}
--- @param family {string|nil}
--- @param lookups {boolean} The catalogue answers at all.
--- @returns {string|false}
local function fit(record, family, lookups)
	if type(record) ~= 'string' then return false end
	if not lookups then return record end
	local read, info = pcall(Open77.equipment.info, record)
	if not read then return record end
	if type(info) ~= 'table' then return false end
	if family == 'male' and info.supportsMale == false then return false end
	if family == 'female' and info.supportsFemale == false then return false end
	return record
end

--- @author DemiAutomatic
--- @method fitted
--- @description Answers a normalized copy of a record fitted to a body family.
--- @param record {table}
--- @param family {string|nil}
--- @returns {table}
local function fitted(record, family)
	local out = normalize(record)
	local equipment = Open77.equipment
	local lookups = type(equipment) == 'table' and type(equipment.info) == 'function'
	if lookups then
		local read, info = pcall(equipment.info, DEFAULT.equipment.UnderwearBottom)
		lookups = read and type(info) == 'table'
	end
	for _, slot in ipairs(SLOTS) do
		out.equipment[slot] = fit(out.equipment[slot], family, lookups)
	end
	for key, shown in pairs(out.wardrobe.outfits) do
		for slot, item in pairs(shown) do
			if item then shown[slot] = fit(item, family, lookups) end
		end
		out.wardrobe.outfits[key] = shown
	end
	return out
end

--- @author DemiAutomatic
--- @method readWorn
--- @description Answers what the puppet wears, normalized, nil while unreadable.
--- @returns {table|nil, string|nil}
local function readWorn()
	local equipment, wardrobe = Open77.equipment, Open77.wardrobe
	if type(equipment) ~= 'table' or type(wardrobe) ~= 'table' then
		return nil, 'equipment_api_unavailable'
	end
	local read, registry, reason = pcall(equipment.registry)
	if not read or type(registry) ~= 'table' then
		return nil, tostring(read and reason or registry)
	end
	local listed, active, why = pcall(wardrobe.active)
	if not listed or active == nil then return nil, tostring(listed and why or active) end
	local record = { equipment = registry, wardrobe = { outfits = {} } }
	if active ~= false then record.wardrobe.active = active end
	for index = 0, OUTFITS - 1 do
		local opened, outfit, failure = pcall(wardrobe.outfit, index)
		if not opened or type(outfit) ~= 'table' or type(outfit.registry) ~= 'function' then
			return nil, tostring(opened and failure or outfit)
		end
		local got, overrides, missing = pcall(outfit.registry)
		if not got or type(overrides) ~= 'table' then
			return nil, tostring(got and missing or overrides)
		end
		record.wardrobe.outfits[tostring(index)] = overrides
	end
	return normalize(record)
end

--- @author DemiAutomatic
--- @method attempt
--- @description Makes one native call, collecting its refusal instead of raising.
--- @param failures {string[]}
--- @param label {string}
--- @param fn {function}
local function attempt(failures, label, fn, ...)
	local called, ok, reason = pcall(fn, ...)
	if not called then ok, reason = false, ok end
	if not ok then failures[#failures + 1] = ('%s: %s'):format(label, tostring(reason)) end
end

--- @author DemiAutomatic
--- @method putOn
--- @description States a whole record on the puppet, wardrobe first.
--- @param record {table}
--- @returns {boolean, string|nil}
local function putOn(record)
	local equipment, wardrobe = Open77.equipment, Open77.wardrobe
	if type(equipment) ~= 'table' or type(wardrobe) ~= 'table' then
		return false, 'equipment_api_unavailable'
	end
	local failures = {}
	for index = 0, OUTFITS - 1 do
		local opened, outfit = pcall(wardrobe.outfit, index)
		if opened and type(outfit) == 'table' and type(outfit.apply) == 'function' then
			attempt(failures, 'outfit ' .. index, outfit.apply,
				record.wardrobe.outfits[tostring(index)] or {}, { allowRestricted = true, replace = true })
		else
			failures[#failures + 1] = ('outfit %d: %s'):format(index, tostring(outfit))
		end
	end
	attempt(failures, 'activate', wardrobe.activate, record.wardrobe.active or false)
	attempt(failures, 'equipment', equipment.apply, record.equipment, { allowRestricted = true })
	if #failures > 0 then return false, table.concat(failures, '; ') end
	return true
end

--- @author DemiAutomatic
--- @method enabled
--- @description Whether this client dresses and saves characters at all.
--- @returns {boolean}
local function enabled()
	local config = type(Config.CLOTHING) == 'table' and Config.CLOTHING or {}
	if config.PERSIST == false then return false end
	return GetResourceState(OFFICIAL) ~= 'running'
end

--- @author DemiAutomatic
--- @method debounceMs
--- @description Answers CLOTHING.SAVE_DEBOUNCE_MS, or the shipped value for an unusable one.
--- @returns {number}
local function debounceMs()
	local config = type(Config.CLOTHING) == 'table' and Config.CLOTHING or {}
	local wait = tonumber(config.SAVE_DEBOUNCE_MS)
	if wait == nil or wait ~= wait or wait < 0 or wait >= math.huge then return SAVE_DEBOUNCE_MS end
	return wait
end

--- @author DemiAutomatic
--- @method ready
--- @description Whether the puppet may be dressed or read for a save now.
--- @returns {boolean}
local function ready()
	if State.citizenId == nil or State.citizenId ~= citizen then return false end
	if not State.gameplayAnnounced or not State.AppearanceSettled() then return false end
	if State.editing or State.creating or State.creatorUp or State.commit ~= nil then
		return false
	end
	local read, open = pcall(Open77.appearance.isOpen)
	if not read or open == true then return false end
	return Runtime.Faceable()
end

--- @author DemiAutomatic
--- @method publish
--- @description Raises a clothing decision on the public event.
--- @param event {string}
--- @param ok {boolean}
--- @param failure {string|nil}
local function publish(event, ok, failure)
	Runtime.Publish({ ok = ok, event = event, error = failure, citizenId = citizen })
end

--- @author DemiAutomatic
--- @method tell
--- @description Tells the player once per character that clothes are not kept.
--- @param key {string}
--- @param reason {string}
local function tell(key, reason)
	if told then return end
	told = true
	Runtime.Notify('warning', key, { reason = reason })
end

--- @author DemiAutomatic
--- @method restore
--- @description Puts the wanted, stored or default record on the puppet.
local function restore()
	attempts = attempts + 1
	local source = wanted or (stored ~= false and stored or DEFAULT)
	target = fitted(source, Runtime.BodyFamily())
	local ok, reason = putOn(target)
	appliedAtMs = Runtime.NowMs()
	phase = 'restoring'
	if not ok then
		Open77.log.debug(('clothing put-on %d/%d refused: %s'):format(attempts, RESTORE_ATTEMPTS,
			tostring(reason)))
	end
end

--- @author DemiAutomatic
--- @method verify
--- @description Reads the put-on record back, retrying or giving up.
local function verify()
	local worn = readWorn()
	if worn ~= nil and same(worn, target) then
		phase = 'worn'
		wanted = target
		candidate = nil
		Open77.log.info(('clothing of %s is on (%s)'):format(tostring(citizen),
			stored == false and 'the default record' or 'the stored record'))
		return publish('clothingRestored', true)
	end
	if Runtime.NowMs() - appliedAtMs < VERIFY_MS then return end
	if attempts < RESTORE_ATTEMPTS then
		phase = 'waiting'
		return
	end
	phase = 'failed'
	Open77.log.warn(('the clothing of %s did not read back after %d put-ons; it is not saved ' ..
		'until the next world entry'):format(tostring(citizen), attempts))
	publish('clothingRestored', false, 'clothing_not_restored')
	tell('appearance.clothingRestoreFailed', 'clothing_not_restored')
end

--- @author DemiAutomatic
--- @method send
--- @description Sends a clothing record to opx77_core and waits for its answer.
--- @param record {table}
local function send(record)
	local now = Runtime.NowMs()
	lastSentAtMs = now
	local sent, reason = TriggerServerEvent(SAVE, { citizenId = citizen, clothing = record })
	if not sent then
		Open77.log.debug('clothing not sent: ' .. tostring(reason))
		return
	end
	local commitMs = tonumber(Config.COMMIT_MS) or 20000
	pending = { record = record, previous = wanted, deadlineMs = now + commitMs }
	wanted = record
	candidate = nil
end

--- @author DemiAutomatic
--- @method strike
--- @description Counts a failed save and stops saving after STRIKES in a row.
--- @param failed {table}
--- @param reason {string}
local function strike(failed, reason)
	wanted = failed.previous
	strikes = strikes + 1
	if strikes < STRIKES then return end
	saving = false
	Open77.log.warn(('the clothing of %s is no longer saved this session: %s'):format(
		tostring(citizen), reason))
	publish('clothingSaved', false, reason)
	tell('appearance.clothingNotSaved', reason)
end

--- @author DemiAutomatic
--- @method capture
--- @description Saves a held change on the puppet once the cooldown passed.
local function capture()
	if not saving or pending ~= nil then return end
	local worn = readWorn()
	if worn == nil then return end
	if same(worn, wanted) then
		candidate = nil
		return
	end
	local now = Runtime.NowMs()
	if candidate == nil or not same(candidate, worn) then
		candidate, candidateAtMs = worn, now
		return
	end
	if now - candidateAtMs < debounceMs() then return end
	local cooldown = tonumber(Config.SAVE_COOLDOWN_MS) or 2000
	if lastSentAtMs ~= nil and now - lastSentAtMs < cooldown then return end
	local holds = stored == false and DEFAULT or normalize(stored)
	if holds ~= nil and same(worn, holds) then
		wanted, candidate = worn, nil
		return
	end
	send(worn)
end

--- @author DemiAutomatic
--- @method expire
--- @description Strikes a clothing save opx77_core did not answer in time.
local function expire()
	if pending == nil or Runtime.NowMs() < pending.deadlineMs then return end
	local failed = pending
	pending = nil
	Open77.log.warn(('opx77_core did not answer the clothing save of %s'):format(tostring(citizen)))
	strike(failed, 'save_timeout')
end

--- @author DemiAutomatic
--- @method OpxAppearance.Clothing.EnterWorld
--- @description Starts a world entry: the pristine puppet is dressed again.
function OpxAppearance.Clothing.EnterWorld()
	target, attempts, appliedAtMs, holdFromMs = nil, 0, 0, 0
	candidate = nil
	phase = (citizen ~= nil and stored ~= nil and enabled()) and 'waiting' or 'idle'
end

--- @author DemiAutomatic
--- @method OpxAppearance.Clothing.Adopt
--- @description Adopts the new live character's clothing from PlayerData.
--- @param playerData {table}
function OpxAppearance.Clothing.Adopt(playerData)
	citizen = playerData.citizenId
	local clothing = playerData.clothing
	if clothing == false then
		stored = false
	else
		stored = normalize(clothing)
	end
	saving = stored ~= nil and enabled()
	wanted, pending, lastSentAtMs, strikes, told = nil, nil, nil, 0, false
	Clothing.EnterWorld()
	if stored == nil then
		Open77.log.debug(('%s: opx77_core carries no clothing for it; it is left as it is')
			:format(tostring(citizen)))
	end
end

--- @author DemiAutomatic
--- @method OpxAppearance.Clothing.Unload
--- @description Forgets the unloaded character's clothing.
function OpxAppearance.Clothing.Unload()
	citizen, stored, saving, wanted, pending, lastSentAtMs = nil, nil, false, nil, nil, nil
	strikes, told = 0, false
	Clothing.EnterWorld()
end

--- @author DemiAutomatic
--- @method OpxAppearance.Clothing.Settled
--- @description Whether the published look may go out, clothes on or waited for.
--- @returns {boolean}
function OpxAppearance.Clothing.Settled()
	if phase ~= 'waiting' and phase ~= 'restoring' then return true end
	local now = Runtime.NowMs()
	if holdFromMs == 0 then holdFromMs = now end
	return now - holdFromMs >= PRESENCE_HOLD_MS
end

--- @author DemiAutomatic
--- @method OpxAppearance.Clothing.Report
--- @description Answers the clothing phase the state export reports.
--- @returns {AppearanceClothingPhase}
function OpxAppearance.Clothing.Report()
	if phase == 'worn' and pending ~= nil then return 'saving' end
	if phase == 'worn' and not saving then return 'unsaved' end
	return phase
end

--- @author DemiAutomatic
--- @method OpxAppearance.Clothing.Check
--- @description Runs one clothing pass: deadline, put-on, read-back or save.
function OpxAppearance.Clothing.Check()
	expire()
	if phase == 'idle' or phase == 'failed' then return end
	if not ready() then
		candidate = nil
		return
	end
	if phase == 'waiting' then return restore() end
	if phase == 'restoring' then return verify() end
	capture()
end

--- @author DemiAutomatic
--- @event opx77:client:clothingSaved
--- @description Completes this client's clothing save, or follows one stored elsewhere.
--- @param record {table}
AddEventHandler('opx77:client:clothingSaved', function(record)
	record = normalize(record)
	if record == nil or citizen == nil then return end
	stored = record
	if pending ~= nil and same(pending.record, record) then
		pending, strikes = nil, 0
		return publish('clothingSaved', true)
	end
	if pending ~= nil then return end
	wanted = record
	if phase == 'worn' or phase == 'failed' then
		Clothing.EnterWorld()
	end
end)

--- @author DemiAutomatic
--- @event opx77:client:refused
--- @description Ends the pending clothing save opx77_core refused.
--- @param code {string}
--- @param _ {any}
--- @param operation {string}
AddEventHandler('opx77:client:refused', function(code, _, operation)
	if operation ~= SAVE_OPERATION or pending == nil then return end
	local failed = pending
	pending = nil
	code = tostring(code)
	if code == 'error.tooFast' then
		wanted = failed.previous
		return
	end
	if code == 'clothing.stale' or code == 'error.notLoggedIn' then return end
	if code == 'error.unavailable' then return strike(failed, code) end
	Open77.log.warn(('clothing save refused: %s'):format(code))
	publish('clothingSaved', false, code)
end)

CreateThread(function()
	while true do
		Wait(CHECK_MS)
		local ok, failure = pcall(Clothing.Check)
		if not ok then Open77.log.error('clothing worker: ' .. tostring(failure)) end
	end
end)
