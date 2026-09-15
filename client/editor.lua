--- @author DemiAutomatic
--- @file client/editor.lua
--- @description The two modal transactions: building a new face and editing one.

OpxAppearance = OpxAppearance or {}

local Config = OPX_APPEARANCE_CONFIG
local Locale = OpxAppearance.Locale
local Snapshot = OpxAppearance.Snapshot
local State = OpxAppearance.State
local Runtime = OpxAppearance.Runtime

OpxAppearance.Editor = {}
local Editor = OpxAppearance.Editor

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds between two passes of the modal, reload and announcement worker.
local WATCH_MS = 200

--- @author DemiAutomatic
--- @type {string}
--- @description The operation a core refusal names when it answers a face save.
local SAVE_OPERATION = 'saveAppearance'

--- @author DemiAutomatic
--- @type {integer}
--- @description When the last captured face went out, in milliseconds.
local lastSaveAtMs = 0

--- @author DemiAutomatic
--- @type {table<string, boolean>}
--- @description Every code opx77_core answers a face save with.
local REFUSALS = {
	['appearance.invalid'] = true,
	['appearance.stale'] = true,
	['appearance.tooLarge'] = true,
	['error.badRequest'] = true,
	['error.notLoggedIn'] = true,
	['error.tooFast'] = true,
	['error.unavailable'] = true,
}

--- @author DemiAutomatic
--- @method rollback
--- @description Puts the stored face back after an edit that did not land.
--- @param reason {any}
local function rollback(reason)
	Runtime.FinishMutation()
	if type(State.canonical) ~= 'table' then return end
	CreateThread(function()
		local ok, failure = Runtime.ApplySnapshot(State.canonical, 8, nil)
		if not ok then
			Runtime.Notify('error', 'appearance.rollbackFailed',
				{ reason = tostring(reason), failure = tostring(failure) })
		end
	end)
end

--- @author DemiAutomatic
--- @method send
--- @description Sends a captured face to opx77_core once its cooldown has passed.
--- @param payload {table}
--- @param kind {string} Either edit or create.
--- @param onNotSent {fun(reason: string)}
local function send(payload, kind, onNotSent)
	State.commit = { kind = kind, deadlineMs = 0 }
	local citizen = State.citizenId
	CreateThread(function()
		local idle = Config.SAVE_COOLDOWN_MS - (Runtime.NowMs() - lastSaveAtMs)
		if idle > 0 then Wait(idle) end
		if State.commit == nil then return end
		lastSaveAtMs = Runtime.NowMs()
		State.commit.deadlineMs = Runtime.NowMs() + Config.COMMIT_MS
		local sent, reason = TriggerServerEvent('opx77:server:saveAppearance',
			{ snapshot = payload, citizenId = citizen })
		if sent then return end
		State.commit = nil
		onNotSent(tostring(reason or 'not_sent'))
	end)
end

--- @author DemiAutomatic
--- @method enterPristine
--- @description Ends a creation that stored nothing and settles on the default face.
--- @param reason {any}
local function enterPristine(reason)
	State.creating = false
	State.creatorUp = false
	State.commit = nil
	State.creationRefused = true
	Runtime.Publish({ ok = false, event = 'created', error = tostring(reason),
		citizenId = State.citizenId })
	Runtime.Notify('error', 'appearance.creationNotSaved', { reason = tostring(reason) })
	Runtime.BeginPristine('creation_ended')
end

--- @author DemiAutomatic
--- @type {boolean}
--- @description A creation editor is being waited for or opened.
local creatorOpening = false

--- @author DemiAutomatic
--- @type {integer}
--- @description When the creation editor was last asked for, in milliseconds.
local creatorAskedAtMs = 0

--- @author DemiAutomatic
--- @type {boolean}
--- @description The asked-for creation editor was seen on screen or reported.
local creatorShown = false

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds an asked-for creation editor may stay unseen before a log line.
local CREATOR_UNSEEN_MS = 30000

--- @author DemiAutomatic
--- @method openCreator
--- @description Opens the creation editor on the character's own body, reloading it first.
local function openCreator()
	State.creating = true
	if creatorOpening or State.creatorUp then return end
	creatorOpening = true
	local citizen = State.citizenId
	CreateThread(function()
		while not Runtime.Faceable() or Runtime.IsDown() do
			if not State.creating or State.citizenId ~= citizen then
				creatorOpening = false
				return
			end
			Wait(WATCH_MS)
		end
		creatorOpening = false
		if not State.creating or State.creatorUp or State.citizenId ~= citizen then return end

		local family = Snapshot.IsFamily(State.family) and State.family or nil
		if family ~= nil and Runtime.BodyFamily() ~= family then
			if State.familyAttempts >= Config.FAMILY_RETRIES then
				return enterPristine('body_family_mismatch')
			end
			local outcome, reason = Runtime.SwitchBody(family, true)
			if outcome == 'switching' then
				State.familyAttempts = State.familyAttempts + 1
				return Runtime.Notify('info', 'appearance.creatorSwitching')
			end
			if outcome == nil then
				Runtime.Notify('error', 'appearance.bodyChangeFailed', { reason = tostring(reason) })
				return enterPristine('body_family_mismatch')
			end
		end

		local opened, reason = Open77.appearance.open({ mode = 'ripperdoc', gender = family })
		if opened then
			State.creatorUp = true
			creatorAskedAtMs, creatorShown = Runtime.NowMs(), false
			Open77.log.info(('creation editor asked for on the %s body'):format(tostring(family)))
			return
		end
		Runtime.Notify('error', 'appearance.creatorUnavailable', { reason = tostring(reason) })
		enterPristine('character_creator_unavailable')
	end)
end

--- @author DemiAutomatic
--- @method OpxAppearance.Editor.Creator
--- @description Answers needsCreation by opening the creation editor for the live character.
--- @returns {boolean, string|nil}
function OpxAppearance.Editor.Creator()
	if Runtime.IsDown() then return false, 'player_down' end
	if State.citizenId == nil then return false, 'no_character' end
	if State.creating then return false, 'appearance_busy' end
	if State.editing or Runtime.ModalOnScreen() then return false, 'appearance_busy' end
	if State.commit ~= nil then return false, 'appearance_busy' end
	if State.creationRefused then return false, 'creation_refused' end
	if type(State.canonical) == 'table' then return false, 'already_has_a_face' end
	State.creationAskedAtMs = 0
	openCreator()
	return true
end

--- @author DemiAutomatic
--- @method OpxAppearance.Editor.FinishCreation
--- @description Completes a creation whose face opx77_core stored.
function OpxAppearance.Editor.FinishCreation()
	State.creating = false
	State.creatorUp = false
	State.Wore()
	Runtime.Publish({ ok = true, event = 'created', citizenId = State.citizenId })
	Runtime.Notify('success', 'appearance.created')
	Runtime.Announce()
end

--- @author DemiAutomatic
--- @method confirmCreation
--- @description Checks the body, captures the creation and sends it to opx77_core.
local function confirmCreation()
	State.creatorUp = false

	local family = Runtime.BodyFamily()
	if Snapshot.IsFamily(State.family) and family ~= nil and family ~= State.family then
		Runtime.FinishMutation()
		State.familyAttempts = State.familyAttempts + 1
		if State.familyAttempts > Config.FAMILY_RETRIES then
			return enterPristine('body_family_mismatch')
		end
		Runtime.Notify('warning', 'appearance.wrongBody',
			{ family = Runtime.FamilyText(State.family) })
		return openCreator()
	end

	local payload, why = Snapshot.Capture()
	if payload == nil then
		Runtime.FinishMutation()
		return enterPristine(tostring(why or 'character_capture_failed'))
	end

	send(payload, 'create', function(reason)
		Runtime.FinishMutation()
		enterPristine(reason)
	end)
end

--- @author DemiAutomatic
--- @method OpxAppearance.Editor.Save
--- @description Asks opx77_core to store a face, by default a capture.
--- @param snapshot {AppearanceSnapshot|nil}
--- @returns {boolean, string|nil}
function OpxAppearance.Editor.Save(snapshot)
	if State.citizenId == nil then return false, 'no_character' end
	if State.commit ~= nil then return false, 'appearance_busy' end
	if State.editing or State.creating then return false, 'appearance_busy' end

	local payload, reason
	if snapshot == nil then
		payload, reason = Snapshot.Capture()
	else
		payload, reason = Snapshot.ForNetwork(snapshot)
	end
	if payload == nil then return false, tostring(reason or 'capture_failed') end
	if not Snapshot.BuildAccepted(payload.gameBuild) then
		return false, 'stored_build_mismatch'
	end

	if Snapshot.Same(payload, State.canonical) then
		SetTimeout(0, function()
			Runtime.Publish({ ok = true, event = 'saved', citizenId = State.citizenId,
				unchanged = true })
		end)
		return true
	end

	send(payload, 'edit', function(failure)
		Runtime.Publish({ ok = false, event = 'saved', error = failure,
			citizenId = State.citizenId })
		Runtime.Notify('error', 'appearance.saveFailed', { reason = failure })
	end)
	return true
end

--- @author DemiAutomatic
--- @method OpxAppearance.Editor.Open
--- @description Asks for the native face editor on the live character.
--- @param mode {string} Either ripperdoc or hairdresser.
--- @returns {boolean, string|nil}
function OpxAppearance.Editor.Open(mode)
	mode = tostring(mode or 'ripperdoc'):lower()
	if mode ~= 'ripperdoc' and mode ~= 'hairdresser' then return false, 'invalid_mode' end
	if Runtime.IsDown() then return false, 'player_down' end
	if State.creating then return false, 'character_creation_in_progress' end
	if State.editing or Runtime.ModalOnScreen() then return false, 'appearance_busy' end
	if State.commit ~= nil then return false, 'appearance_busy' end
	if State.citizenId == nil then return false, 'no_character' end

	if type(State.canonical) ~= 'table' or
		not Snapshot.BuildAccepted(State.canonical.gameBuild) then
		Runtime.Notify('warning', 'appearance.editorDefaultFace')
	end

	State.editing = true
	CreateThread(function()
		if Runtime.IsDown() then
			State.editing = false
			return
		end
		local opened, reason = Open77.appearance.open({ mode = mode })
		if opened then return end
		State.editing = false
		Runtime.Notify('error', 'appearance.editorUnavailable', { reason = tostring(reason) })
	end)
	return true
end

--- @author DemiAutomatic
--- @event open77:appearance:confirmed
--- @description Completes whichever modal the player confirmed, or a queued restore.
AddEventHandler('open77:appearance:confirmed', function()
	if State.creatorUp then return confirmCreation() end
	if not State.editing then
		if State.bootstrapToken == State.restoreToken and State.bootstrapQueued then
			State.appearanceConfirmed = true
			Runtime.Announce()
		else
			Runtime.FinishMutation()
		end
		return
	end
	State.editing = false

	local payload, why = Snapshot.Capture()
	if payload == nil then
		why = tostring(why or 'capture_failed')
		rollback(why)
		return Runtime.Notify('error', 'appearance.captureFailed', { reason = why })
	end

	if Snapshot.Same(payload, State.canonical) then
		State.Wore()
		SetTimeout(250, Runtime.FinishMutation)
		Runtime.Publish({ ok = true, event = 'saved', citizenId = State.citizenId,
			unchanged = true })
		return Runtime.Notify('success', 'appearance.saved')
	end

	send(payload, 'edit', function(reason)
		rollback(reason)
		Runtime.Notify('error', 'appearance.saveFailed', { reason = reason })
	end)
end)

--- @author DemiAutomatic
--- @event open77:appearance:cancelled
--- @description Closes the modal; a cancelled creation settles on the default face.
AddEventHandler('open77:appearance:cancelled', function()
	local creation = State.creatorUp
	State.editing = false
	State.creatorUp = false
	Runtime.FinishMutation()
	if creation then enterPristine('character_creation_cancelled') end
end)

--- @author DemiAutomatic
--- @event opx77:client:appearanceSaved
--- @description Completes this client's save, or restores a face stored elsewhere.
--- @param snapshot {table}
AddEventHandler('opx77:client:appearanceSaved', function(snapshot)
	if type(snapshot) ~= 'table' then return end
	local pending = State.commit
	State.commit = nil
	State.canonical = snapshot

	if pending ~= nil and pending.kind == 'create' then return Editor.FinishCreation() end
	if pending ~= nil then
		State.Wore()
		SetTimeout(250, Runtime.FinishMutation)
		Runtime.Publish({ ok = true, event = 'saved', citizenId = State.citizenId })
		Runtime.Notify('success', 'appearance.saved')
		return
	end

	Runtime.BeginRestore(snapshot, 'core')
end)

--- @author DemiAutomatic
--- @event opx77:client:refused
--- @description Ends the pending face save opx77_core refused.
--- @param code {string}
--- @param _ {any}
--- @param operation {string}
AddEventHandler('opx77:client:refused', function(code, _, operation)
	local pending = State.commit
	if pending == nil or operation ~= SAVE_OPERATION then return end
	code = tostring(code)
	if not REFUSALS[code] then
		Open77.log.warn(('save refused with an unlisted code: %s'):format(code))
	end
	State.commit = nil
	if pending.kind == 'create' then return enterPristine(code) end
	Runtime.Publish({ ok = false, event = 'saved', error = code, citizenId = State.citizenId })
	rollback(code)
	if Locale.Exists(code) then return Runtime.Notify('error', code) end
	Runtime.Notify('error', 'appearance.saveFailed', { reason = code })
end)

--- @author DemiAutomatic
--- @method creationStalled
--- @description Whether a creation waits for an editor nothing is opening.
--- @returns {boolean}
local function creationStalled()
	return State.creating and not State.creatorUp and not creatorOpening and State.commit == nil
end

--- @author DemiAutomatic
--- @method resumeFamilyTransition
--- @description Picks up what a body-family reload answered on its other side.
--- @returns {boolean}
local function resumeFamilyTransition()
	local result = Open77.appearance.takeBodyFamilyTransition()
	if type(result) ~= 'string' or result == '' then return false end
	local action, family = result:match('^([^:]+):(.+)$')
	if action == 'error' then
		Runtime.Notify('error', 'appearance.bodyChangeFailed', { reason = tostring(family) })
		State.bodyReloading = false
		Runtime.LiftCover('body_family_transition_error')
		Runtime.MarkWorldEligibility('body_family_transition_error')
		if creationStalled() then return enterPristine('body_family_mismatch') end
		State.settled = false
		Runtime.ResolveCharacter('body_family_transition_error')
		return true
	end
	if action ~= 'edit' then
		Open77.log.debug('body family transition: ' .. result)
		return true
	end
	if not Snapshot.IsFamily(family) then
		Runtime.Notify('error', 'appearance.bodyChangeInvalid')
		return true
	end
	Open77.log.info(('body family transition answered %s'):format(result))
	if creationStalled() then openCreator() end
	return true
end

--- @author DemiAutomatic
--- @method watch
--- @description Runs one worker pass over creations, transitions and save deadlines.
local function watch()
	Runtime.WarnUnanswered()
	resumeFamilyTransition()

	if creationStalled() and Runtime.Faceable() then openCreator() end

	if State.creatorUp and creatorAskedAtMs ~= 0 and not creatorShown then
		local waited = Runtime.NowMs() - creatorAskedAtMs
		if Runtime.ModalOnScreen() then
			creatorShown = true
		elseif waited >= CREATOR_UNSEEN_MS then
			creatorShown = true
			Open77.log.warn(('the creation editor asked for %d ms ago is not on screen: reset=%s life=%s')
				:format(waited, tostring(Runtime.PlayerResetPhase()), tostring(Runtime.LifePhase())))
		end
	end

	local pending = State.commit
	if pending ~= nil and pending.deadlineMs > 0 and Runtime.NowMs() >= pending.deadlineMs then
		State.commit = nil
		if pending.kind == 'create' then
			Runtime.FinishMutation()
			enterPristine('save_timeout')
		else
			rollback('save_timeout')
			Runtime.Notify('error', 'appearance.saveTimedOut')
		end
	end
end

CreateThread(function()
	while true do
		Wait(WATCH_MS)
		local ok, failure = pcall(watch)
		if not ok then Open77.log.error('appearance worker: ' .. tostring(failure)) end
		local watched, reason = pcall(Runtime.WatchReload)
		if not watched then Open77.log.error('reload watch: ' .. tostring(reason)) end
		local announced, problem = pcall(Runtime.Announce)
		if not announced then Open77.log.error('announce worker: ' .. tostring(problem)) end
	end
end)
