--- What the live character wears: put back on its puppet from opx77_core, and handed back to
--- the core when the player changes it.
---
--- The core carries one record per character in `PlayerData.clothing` -- the nine equipment
--- slots, the seven wardrobe outfits and the active one -- as the record, `false` when none is
--- stored, or nil when it could not read one or stores no clothing at all. A record goes on the
--- puppet once this world entry's face has settled and the readiness announcement is out, which
--- is where the platform's presentation service states its own; `false` puts on the record that
--- service gives a character it has no row for; nil touches nothing and saves nothing. Once the
--- puppet reads back what was put on, what it wears is read every second and sent when it has
--- held a new value for `CLOTHING.SAVE_DEBOUNCE_MS`, and never while a modal, a body reload or a
--- face commit is in the way.

OpxAppearance = OpxAppearance or {}

local Config = OPX_APPEARANCE_CONFIG
local State = OpxAppearance.state
local Runtime = OpxAppearance.runtime

local Clothing = {}
OpxAppearance.clothing = Clothing

local SAVE = 'opx77:server:saveClothing'
local SAVE_OPERATION = 'saveClothing'

--- The platform's package: while it runs it owns the clothing, as it does the looks.
local OFFICIAL = 'open77_appearance'

--- How often the puppet is looked at, in ms: the cadence the look is published at.
local CHECK_MS = 1000
--- Put-ons before a world entry gives up on the stored record, and how long each may take to
--- read back before it goes on again, in ms.
local RESTORE_ATTEMPTS = 5
local VERIFY_MS = 2000
--- The longest the published look waits for the clothes to go on, in ms. A player drawn in the
--- wrong clothes for a moment beats a player not drawn at all.
local PRESENCE_HOLD_MS = 15000
--- Failed saves in a row -- unanswered, or refused as unavailable -- before this character
--- stops saving until it is loaded again.
local STRIKES = 2

--- The shipped `CLOTHING.SAVE_DEBOUNCE_MS`, for a config that lost it.
local SAVE_DEBOUNCE_MS = 2000

local SLOTS = { 'Head', 'Face', 'InnerChest', 'OuterChest', 'Legs', 'Feet', 'Outfit',
	'UnderwearTop', 'UnderwearBottom' }
local OUTFIT_SLOTS = { 'Head', 'Face', 'InnerChest', 'OuterChest', 'Legs', 'Feet', 'Outfit' }
local OUTFITS = 7

--- What the platform's presentation service states for a character it has no row for: every
--- slot empty but the basic underwear bottom, and no outfit.
local DEFAULT = {
	schemaVersion = 1,
	equipment = { Head = false, Face = false, InnerChest = false, OuterChest = false,
		Legs = false, Feet = false, Outfit = false, UnderwearTop = false,
		UnderwearBottom = 'Items.Underwear_Basic_01_Bottom' },
	wardrobe = { outfits = {} },
}

-- Per character.
local citizen = nil   ---@type string|nil
local stored = nil    ---@type table|false|nil  the core's word: a record, false, nil
local saving = false  -- this character's changes go to the core
local wanted = nil    ---@type table|nil  what the puppet should wear: last put on, or last sent
local pending = nil   ---@type { record: table, previous: table|nil, deadlineMs: integer }|nil
local lastSentAtMs = nil ---@type integer|nil
local strikes = 0
local told = false    -- the player has been told this character's clothes are not kept

-- Per world entry.
---@type "idle"|"waiting"|"restoring"|"worn"|"failed"
local phase = 'idle'
local target = nil    ---@type table|nil  the record put on, fitted to the body
local attempts, appliedAtMs, holdFromMs = 0, 0, 0
local candidate, candidateAtMs = nil, 0

-- ---------------------------------------------------------------------------
-- Records
-- ---------------------------------------------------------------------------

---@param value any
---@return string|false
local function recordOf(value)
	return type(value) == 'string' and value ~= '' and value or false
end

--- Any clothing-shaped table in the core's canonical form: nine slots stated, outfit keys "0"
--- to "6", empty outfits dropped. Both sides of every comparison go through it.
---@param value any
---@return table|nil
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
				-- false hides the slot; an absent one shows what is worn
				if item == false or (type(item) == 'string' and item ~= '') then
					shown[slot], any = item, true
				end
			end
			if any then out.wardrobe.outfits[tostring(index)] = shown end
		end
	end
	return out
end
Clothing.normalize = normalize

--- Whether two normalized records are the same clothing.
---@param left table|nil
---@param right table|nil
---@return boolean
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
Clothing.same = same

--- A record this body can wear, or false. An item the engine knows and the family cannot wear
--- goes, as the platform's record shows it; so does one the engine does not know at all -- a
--- game update removed it -- or the record would never read back and nothing would save again.
--- Only what goes on is fitted: storage keeps the item until the player changes something.
---@param record string|false
---@param family string|nil
---@param lookups boolean  the catalogue answers at all; when it does not, nothing is dropped
---@return string|false
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

---@param record table
---@param family string|nil
---@return table
local function fitted(record, family)
	local out = normalize(record)
	-- a lookup of the one item every body has tells "unknown item" from "no catalogue right now"
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

-- ---------------------------------------------------------------------------
-- The puppet
-- ---------------------------------------------------------------------------

--- What the puppet wears right now, normalized; nil while any of it cannot be read.
---@return table|nil record, string|nil reason
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
	-- false is "no outfit"; nil is unreadable
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

--- One native call, its refusal collected rather than raised.
---@param failures string[]
---@param label string
local function attempt(failures, label, fn, ...)
	local called, ok, reason = pcall(fn, ...)
	if not called then ok, reason = false, ok end
	if not ok then failures[#failures + 1] = ('%s: %s'):format(label, tostring(reason)) end
end

--- State a whole record on the puppet: every outfit replaced, the active one chosen, then the
--- nine slots. The wardrobe first, as the platform's relay does: a slot cleared under a shown
--- outfit keeps the outfit's visuals. Acceptance is not completion; `verify` reads it back.
---@param record table
---@return boolean, string|nil
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

-- ---------------------------------------------------------------------------
-- The gate
-- ---------------------------------------------------------------------------

--- Whether this client dresses and saves anybody at all.
---@return boolean
local function enabled()
	local config = type(Config.CLOTHING) == 'table' and Config.CLOTHING or {}
	if config.PERSIST == false then return false end
	return GetResourceState(OFFICIAL) ~= 'running'
end

---@return number
local function debounceMs()
	local config = type(Config.CLOTHING) == 'table' and Config.CLOTHING or {}
	local wait = tonumber(config.SAVE_DEBOUNCE_MS)
	if wait == nil or wait ~= wait or wait < 0 or wait >= math.huge then return SAVE_DEBOUNCE_MS end
	return wait
end

--- Whether the puppet may be dressed or read for a save now: this character's face settled and
--- announced, a puppet a face may go on, and no modal, face commit or reload in the way. The
--- platform's own wardrobe waits on the same body-mutation barrier.
---@return boolean
local function ready()
	if State.citizenId == nil or State.citizenId ~= citizen then return false end
	if not State.gameplayAnnounced or not State.appearanceSettled() then return false end
	if State.editing or State.creating or State.creatorUp or State.commit ~= nil then
		return false
	end
	-- a raise counts as on screen, as it does for the panel
	local read, open = pcall(Open77.appearance.isOpen)
	if not read or open == true then return false end
	return Runtime.faceable()
end

-- ---------------------------------------------------------------------------
-- Restoring
-- ---------------------------------------------------------------------------

---@param event string
---@param ok boolean
---@param failure string|nil
local function publish(event, ok, failure)
	Runtime.publish({ ok = ok, event = event, error = failure, citizenId = citizen })
end

--- Say once per character, on screen, that its clothes are not being kept.
---@param key string
---@param reason string
local function tell(key, reason)
	if told then return end
	told = true
	Runtime.notify('warning', key, { reason = reason })
end

local function restore()
	attempts = attempts + 1
	local source = wanted or (stored ~= false and stored or DEFAULT)
	target = fitted(source, Runtime.bodyFamily())
	local ok, reason = putOn(target)
	appliedAtMs = Runtime.nowMs()
	phase = 'restoring'
	if not ok then
		Open77.log.debug(('clothing put-on %d/%d refused: %s'):format(attempts, RESTORE_ATTEMPTS,
			tostring(reason)))
	end
end

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
	if Runtime.nowMs() - appliedAtMs < VERIFY_MS then return end
	if attempts < RESTORE_ATTEMPTS then
		phase = 'waiting'
		return
	end
	-- Nothing is saved for the rest of this world entry: what the puppet wears is not what the
	-- player chose, and a save now would put it over the stored record.
	phase = 'failed'
	Open77.log.warn(('the clothing of %s did not read back after %d put-ons; it is not saved ' ..
		'until the next world entry'):format(tostring(citizen), attempts))
	publish('clothingRestored', false, 'clothing_not_restored')
	tell('appearance.clothingRestoreFailed', 'clothing_not_restored')
end

-- ---------------------------------------------------------------------------
-- Saving
-- ---------------------------------------------------------------------------

---@param record table
local function send(record)
	local now = Runtime.nowMs()
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

--- One failed save: the look is tried again after the cooldown, until `STRIKES` in a row.
---@param failed table
---@param reason string
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

local function capture()
	if not saving or pending ~= nil then return end
	local worn = readWorn()
	if worn == nil then return end
	if same(worn, wanted) then
		candidate = nil
		return
	end
	local now = Runtime.nowMs()
	if candidate == nil or not same(candidate, worn) then
		candidate, candidateAtMs = worn, now
		return
	end
	if now - candidateAtMs < debounceMs() then return end
	local cooldown = tonumber(Config.SAVE_COOLDOWN_MS) or 2000
	if lastSentAtMs ~= nil and now - lastSentAtMs < cooldown then return end
	-- the core already holds it -- a change undone, or a save refused before -- and answers a
	-- save of what it holds with silence
	local holds = stored == false and DEFAULT or normalize(stored)
	if holds ~= nil and same(worn, holds) then
		wanted, candidate = worn, nil
		return
	end
	send(worn)
end

local function expire()
	if pending == nil or Runtime.nowMs() < pending.deadlineMs then return end
	local failed = pending
	pending = nil
	Open77.log.warn(('opx77_core did not answer the clothing save of %s'):format(tostring(citizen)))
	strike(failed, 'save_timeout')
end

-- ---------------------------------------------------------------------------
-- The lifecycle
-- ---------------------------------------------------------------------------

--- A new world entry: the puppet is pristine, so whatever this character wears goes on again.
--- What was last sent survives it, and so does its answer.
function Clothing.enterWorld()
	target, attempts, appliedAtMs, holdFromMs = nil, 0, 0, 0
	candidate = nil
	phase = (citizen ~= nil and stored ~= nil and enabled()) and 'waiting' or 'idle'
end

--- The live character changed: adopt its clothing from PlayerData.
---@param playerData table
function Clothing.adopt(playerData)
	citizen = playerData.citizenId
	local clothing = playerData.clothing
	if clothing == false then
		stored = false
	else
		stored = normalize(clothing)
	end
	saving = stored ~= nil and enabled()
	wanted, pending, lastSentAtMs, strikes, told = nil, nil, nil, 0, false
	Clothing.enterWorld()
	if stored == nil then
		Open77.log.debug(('%s: opx77_core carries no clothing for it; it is left as it is')
			:format(tostring(citizen)))
	end
end

function Clothing.unload()
	citizen, stored, saving, wanted, pending, lastSentAtMs = nil, nil, false, nil, nil, nil
	strikes, told = 0, false
	Clothing.enterWorld()
end

--- Whether the published look may go out: the clothes are on, or given up on, or have been
--- waited on for `PRESENCE_HOLD_MS` since the look first asked.
---@return boolean
function Clothing.settled()
	if phase ~= 'waiting' and phase ~= 'restoring' then return true end
	local now = Runtime.nowMs()
	if holdFromMs == 0 then holdFromMs = now end
	return now - holdFromMs >= PRESENCE_HOLD_MS
end

--- For `state`: what this client is doing with the clothes.
---@return string
function Clothing.report()
	if phase == 'worn' and pending ~= nil then return 'saving' end
	if phase == 'worn' and not saving then return 'unsaved' end
	return phase
end

function Clothing.check()
	expire()
	if phase == 'idle' or phase == 'failed' then return end
	if not ready() then
		-- a change seen before the gate closed has to hold again once it opens
		candidate = nil
		return
	end
	if phase == 'waiting' then return restore() end
	if phase == 'restoring' then return verify() end
	capture()
end

-- ---------------------------------------------------------------------------
-- What opx77_core answers
-- ---------------------------------------------------------------------------

AddEventHandler('opx77:client:clothingSaved', function(record)
	record = normalize(record)
	if record == nil or citizen == nil then return end
	stored = record
	if pending ~= nil and same(pending.record, record) then
		pending, strikes = nil, 0
		return publish('clothingSaved', true)
	end
	if pending ~= nil then return end
	-- stored by something other than this client: the puppet follows it
	wanted = record
	if phase == 'worn' or phase == 'failed' then
		Clothing.enterWorld()
	end
end)

--- A refusal naming `saveClothing`. The core refuses a character selection with the same codes,
--- so the operation decides whether it is this one's.
AddEventHandler('opx77:client:refused', function(code, _, operation)
	if operation ~= SAVE_OPERATION or pending == nil then return end
	local failed = pending
	pending = nil
	code = tostring(code)
	if code == 'error.tooFast' then
		wanted = failed.previous
		return
	end
	-- a character change got there first: the save was for the one before
	if code == 'clothing.stale' or code == 'error.notLoggedIn' then return end
	if code == 'error.unavailable' then return strike(failed, code) end
	-- the look itself was refused: it is not tried again, a later change is
	Open77.log.warn(('clothing save refused: %s'):format(code))
	publish('clothingSaved', false, code)
end)

CreateThread(function()
	while true do
		Wait(CHECK_MS)
		-- a raise from a host call would end this loop, and with it every restore and save
		local ok, failure = pcall(Clothing.check)
		if not ok then Open77.log.error('clothing worker: ' .. tostring(failure)) end
	end
end)
