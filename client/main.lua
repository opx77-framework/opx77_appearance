--- @author DemiAutomatic
--- @file client/main.lua
--- @description The link to opx77_core, the join bootstrap, the body and the restore.

OpxAppearance = OpxAppearance or {}

local Config = OPX_APPEARANCE_CONFIG
local Snapshot = OpxAppearance.Snapshot
local State = OpxAppearance.State

OpxAppearance.Runtime = {}
local Runtime = OpxAppearance.Runtime

--- @author DemiAutomatic
--- @type {string}
--- @description This resource's own name, for its lifecycle events.
local RESOURCE = GetCurrentResourceName()

--- @author DemiAutomatic
--- @type {string}
--- @description The resource that owns characters, rosters and PlayerData.
local CORE = 'opx77_core'

--- @author DemiAutomatic
--- @type {string}
--- @description The resource toasts are raised through.
local NOTIFY = 'opx77_notify'

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds between two looks at a world a face may go on.
local WATCH_MS = 200

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds between two reads of opx77_core's held roster.
local ROSTER_POLL_MS = 250

--- @author DemiAutomatic
--- @type {integer}
--- @description Shipped BOOTSTRAP.ROSTER_WAIT_MS, for a config that lost it.
local ROSTER_WAIT_MS = 3000

--- @author DemiAutomatic
--- @type {string}
--- @description Shipped BOOTSTRAP.DEFAULT_FAMILY, for a config that lost it.
local DEFAULT_FAMILY = 'female'

--- @author DemiAutomatic
--- @type {integer}
--- @description Shipped BODY_RELOAD_SETTLE_MS, for a config that lost it.
local RELOAD_SETTLE_MS = 10000

--- @author DemiAutomatic
--- @type {table<string, boolean>}
--- @description Life phases a native modal may go up in.
local LIFE_OPEN = { alive = true, recovering = true }

--- @author DemiAutomatic
--- @type {string|nil}
--- @description The body family this client last loaded the world with.
local loadedFamily = nil

--- @author DemiAutomatic
--- @type {boolean}
--- @description The host's reset projection left complete since the switch.
local reloadResetSeen = false

--- @author DemiAutomatic
--- @type {integer}
--- @description Until when a finished reload holds modals back, 0 when none.
local reloadSettleUntilMs = 0

--- @author DemiAutomatic
--- @type {boolean}
--- @description This client spent the one-shot character bootstrap.
local bootstrapResolved = false

--- @author DemiAutomatic
--- @type {boolean}
--- @description The join-time roster wait that picks the bootstrap body runs.
local bootstrapPicking = false

--- @author DemiAutomatic
--- @type {integer}
--- @description Last finite clock reading in milliseconds, held across failed reads.
local lastMs = 0

--- @author DemiAutomatic
--- @method nowMs
--- @description Reads the monotonic clock in milliseconds, keeping the last finite reading.
--- @returns {integer}
local function nowMs()
	local read, seconds = pcall(Open77.time.monotonic)
	if read and type(seconds) == 'number' and seconds == seconds and
		seconds >= 0 and seconds < math.huge then
		lastMs = math.floor(seconds * 1000)
	end
	return lastMs
end
OpxAppearance.Runtime.NowMs = nowMs

--- @author DemiAutomatic
--- @method OpxAppearance.Runtime.Publish
--- @description Raises a decision on the resource's public client event.
--- @param payload {table}
function OpxAppearance.Runtime.Publish(payload)
	TriggerEvent(Config.EVENT, payload)
end

--- @author DemiAutomatic
--- @method OpxAppearance.Runtime.Call
--- @description Calls another resource's client export from a coroutine, checking every level.
--- @param resource {string}
--- @param name {string}
--- @returns {table|nil, string|nil}
function OpxAppearance.Runtime.Call(resource, name, ...)
	if GetResourceState(resource) ~= 'running' then return nil, 'not_running' end
	local promise, reason = Open77.exports.call(resource, name, ...)
	if not promise then return nil, tostring(reason or 'not_dispatched') end
	local result, callError = promise:await()
	if callError then return nil, tostring(callError) end
	if type(result) ~= 'table' then return nil, 'malformed_answer' end
	if result.ok == false then return nil, tostring(result.error or 'refused') end
	return result
end

--- @author DemiAutomatic
--- @method OpxAppearance.Runtime.Notify
--- @description Logs a toast and raises it through opx77_notify when that runs.
--- @param kind {string}
--- @param key {string}
--- @param params {table<string, string|number>|nil}
function OpxAppearance.Runtime.Notify(kind, key, params)
	Open77.log.info(('notify %s: %s'):format(kind, key))
	if Config.NOTIFY ~= true then return end
	if GetResourceState(NOTIFY) ~= 'running' then return end
	local message = locale(key, params)
	CreateThread(function()
		local _, failure = Runtime.Call(NOTIFY, 'show', {
			type = kind,
			title = 'APPEARANCE',
			message = message,
		})
		if failure ~= nil then Open77.log.debug('toast refused: ' .. failure) end
	end)
end

--- @author DemiAutomatic
--- @method OpxAppearance.Runtime.FamilyText
--- @description Answers the player-facing name of a body family.
--- @param family {any}
--- @returns {string}
function OpxAppearance.Runtime.FamilyText(family)
	if family == 'female' then return locale('appearance.familyFemale') end
	if family == 'male' then return locale('appearance.familyMale') end
	return tostring(family)
end

--- @author DemiAutomatic
--- @method inGameplay
--- @description Whether the local puppet is attached, alive and above zero health.
--- @returns {boolean}
local function inGameplay()
	local ok, character = pcall(Open77.character.state)
	return ok and type(character) == 'table' and character.attached == true and
		character.alive == true and (tonumber(character.health) or 0) > 0
end
OpxAppearance.Runtime.InGameplay = inGameplay

--- @author DemiAutomatic
--- @method bootstrapPhase
--- @description Answers the host's character bootstrap phase, or unreadable.
--- @returns {string}
local function bootstrapPhase()
	local ok, bootstrap = pcall(Open77.session.characterBootstrap)
	return ok and type(bootstrap) == 'table' and tostring(bootstrap.phase) or 'unreadable'
end

--- @author DemiAutomatic
--- @method playerResetPhase
--- @description Answers the host's pristine player reset phase, nil where none is projected.
--- @returns {string|nil}
local function playerResetPhase()
	local ok, bootstrap = pcall(Open77.session.characterBootstrap)
	if not ok or type(bootstrap) ~= 'table' or bootstrap.playerReset == nil then return nil end
	return tostring(bootstrap.playerReset)
end
OpxAppearance.Runtime.PlayerResetPhase = playerResetPhase

--- @author DemiAutomatic
--- @type {boolean}
--- @description The life state was found unreadable and said so once.
local lifeUnreadable = false

--- @author DemiAutomatic
--- @method lifePhase
--- @description Answers the local life phase, false without one, nil when unreadable.
--- @returns {string|false|nil}
local function lifePhase()
	if lifeUnreadable then return nil end
	local players = Open77.players
	local called, life, reason = false, nil, 'Open77.players.getLifeState is not on this client'
	if type(players) == 'table' and type(players.getLifeState) == 'function' then
		called, life, reason = pcall(players.getLifeState)
	end
	if called and type(life) == 'table' then return tostring(life.phase) end
	if called and not tostring(reason or ''):find('permission', 1, true) then return false end
	lifeUnreadable = true
	Open77.log.warn(('the life state cannot be read (%s): faces go on without waiting for it')
		:format(tostring(called and reason or life or reason)))
	return nil
end
OpxAppearance.Runtime.LifePhase = lifePhase

--- @author DemiAutomatic
--- @method reloadSettleMs
--- @description Answers BODY_RELOAD_SETTLE_MS, or the shipped value for an unusable one.
--- @returns {number}
local function reloadSettleMs()
	local wait = tonumber(Config.BODY_RELOAD_SETTLE_MS)
	if wait == nil or wait ~= wait or wait < 0 or wait >= math.huge then return RELOAD_SETTLE_MS end
	return wait
end

--- @author DemiAutomatic
--- @method OpxAppearance.Runtime.Faceable
--- @description Whether a face or native modal may go on the puppet now.
--- @returns {boolean}
function OpxAppearance.Runtime.Faceable()
	if not State.worldEligible or State.bodyReloading or not inGameplay() then return false end
	local reset = playerResetPhase()
	if reset ~= nil and reset ~= 'complete' then return false end
	local life = lifePhase()
	if life == false or (life ~= nil and not LIFE_OPEN[life]) then return false end
	if reloadSettleUntilMs ~= 0 then
		if life ~= nil and life ~= 'alive' and nowMs() < reloadSettleUntilMs then
			return false
		end
		reloadSettleUntilMs = 0
	end
	return true
end

--- @author DemiAutomatic
--- @method markWorldEligibility
--- @description Judges from the bootstrap phase whether this is the gameplay world.
--- @param reason {string}
local function markWorldEligibility(reason)
	local phase = bootstrapPhase()
	State.worldEligible = phase == 'ready'
	Open77.log.debug(('world entry (%s): bootstrap phase=%s -> %s'):format(reason, phase,
		State.worldEligible and 'gameplay world' or 'menu, not announcing'))
end
OpxAppearance.Runtime.MarkWorldEligibility = markWorldEligibility

--- @author DemiAutomatic
--- @method OpxAppearance.Runtime.FinishMutation
--- @description Releases the native appearance mutation transaction.
function OpxAppearance.Runtime.FinishMutation()
	local ok, reason = Open77.appearance.finishCommit()
	if not ok then Open77.log.debug('finishCommit: ' .. tostring(reason)) end
end

--- @author DemiAutomatic
--- @method OpxAppearance.Runtime.BodyFamily
--- @description Answers the body family from the engine, this client or the bootstrap.
--- @returns {string|nil}
function OpxAppearance.Runtime.BodyFamily()
	local read, body = pcall(Open77.appearance.captureBody)
	if read and type(body) == 'table' and Snapshot.IsFamily(body.family) then
		return body.family
	end
	if loadedFamily ~= nil then return loadedFamily end
	local ok, bootstrap = pcall(Open77.session.characterBootstrap)
	if ok and type(bootstrap) == 'table' and bootstrap.phase == 'ready' and
		Snapshot.IsFamily(bootstrap.family) then
		return bootstrap.family
	end
	return nil
end

--- @author DemiAutomatic
--- @method OpxAppearance.Runtime.SwitchBody
--- @description Asks the engine to reload the player on a body family.
--- @param family {string}
--- @param edit {boolean} An editor reopens after the reload.
--- @returns {string|nil, string|nil}
function OpxAppearance.Runtime.SwitchBody(family, edit)
	local called, switched, reason = pcall(Open77.appearance.switchBodyFamily, family, edit)
	if not called then return nil, tostring(switched) end
	if switched then
		loadedFamily = family
		State.bodyReloading = true
		reloadResetSeen = false
		reloadSettleUntilMs = 0
		State.Undress()
		if OpxAppearance.Presence then OpxAppearance.Presence.Withdraw() end
		Open77.log.info(('the %s body is reloading (%s)'):format(family,
			edit and 'an editor reopens after it' or 'for the character'))
		return 'switching'
	end
	if tostring(reason) == 'body_family_already_active' then
		loadedFamily = family
		return 'active'
	end
	return nil, tostring(reason or 'body_family_switch_failed')
end

--- @author DemiAutomatic
--- @method OpxAppearance.Runtime.FinishReload
--- @description Ends a body reload once its new puppet has been reset.
--- @param origin {string}
function OpxAppearance.Runtime.FinishReload(origin)
	if not State.bodyReloading then return end
	State.bodyReloading = false
	reloadResetSeen = false
	reloadSettleUntilMs = nowMs() + reloadSettleMs()
	Open77.log.info(('the body reload reached its new puppet (%s)'):format(origin))
	State.EnterWorld()
	State.playerResetDone = true
	markWorldEligibility(origin)
	Runtime.ResolveCharacter('body_reload')
end

--- @author DemiAutomatic
--- @method OpxAppearance.Runtime.WatchReload
--- @description Follows a body reload through the host's reset projection.
function OpxAppearance.Runtime.WatchReload()
	if not State.bodyReloading then return end
	local reset = playerResetPhase()
	if reset == nil then return end
	if reset ~= 'complete' then
		reloadResetSeen = true
	elseif reloadResetSeen then
		Runtime.FinishReload('reset_projection')
	end
end

--- @author DemiAutomatic
--- @method reloadOntoFamily
--- @description Reloads onto the character's body family within FAMILY_RETRIES.
--- @returns {boolean}
local function reloadOntoFamily()
	if not Snapshot.IsFamily(State.family) then return false end
	if State.familyAttempts >= Config.FAMILY_RETRIES then
		if Runtime.BodyFamily() ~= nil then
			Runtime.Notify('error', 'appearance.bodyLoadFailed', { reason = 'body_family_retries' })
		end
		return false
	end
	local outcome, reason = Runtime.SwitchBody(State.family, false)
	if outcome == 'switching' then
		State.familyAttempts = State.familyAttempts + 1
		Runtime.Notify('info', 'appearance.bodySwitching')
		return true
	end
	if outcome == nil then
		Runtime.Notify('error', 'appearance.bodyLoadFailed', { reason = tostring(reason) })
	end
	return false
end

--- @author DemiAutomatic
--- @method ensureFamily
--- @description Puts the puppet on the character's body family before a face.
--- @returns {boolean}
local function ensureFamily()
	if not Snapshot.IsFamily(State.family) or Runtime.BodyFamily() == State.family then
		return true
	end
	return not reloadOntoFamily()
end

--- @author DemiAutomatic
--- @method OpxAppearance.Runtime.Announce
--- @description Sends open77:session:gameplayReady once per settled gameplay world entry.
--- @returns {boolean}
function OpxAppearance.Runtime.Announce()
	if State.gameplayAnnounced or not State.worldEligible then return false end
	if not State.AppearanceSettled() or not inGameplay() then return false end
	local sent, reason = TriggerServerEvent('open77:session:gameplayReady')
	if not sent then
		Open77.log.warn('gameplay-ready not sent: ' .. tostring(reason))
		return false
	end
	State.gameplayAnnounced = true
	Runtime.FinishMutation()
	Runtime.Publish({ ok = true, event = 'gameplayReady', citizenId = State.citizenId })
	return true
end

--- @author DemiAutomatic
--- @type {table<string, boolean>}
--- @description Apply refusals that mean not yet, retried after a short wait.
local RETRYABLE = {
	options_unavailable = true,
	player_unavailable = true,
	customization_state_unavailable = true,
}

--- @author DemiAutomatic
--- @method applySnapshot
--- @description Applies a snapshot from a coroutine, retrying transient refusals.
--- @param snapshot {table}
--- @param attempts {integer}
--- @param token {integer|nil} The restore generation, nil when none is owned.
--- @returns {boolean, string|nil}
local function applySnapshot(snapshot, attempts, token)
	if type(snapshot) ~= 'table' then return false, 'invalid_snapshot' end
	for attempt = 1, attempts do
		if token ~= nil and not State.Current(token) then return false, 'superseded' end
		local ok, reason = Open77.appearance.apply(snapshot)
		if ok then return true end
		if not RETRYABLE[tostring(reason)] or attempt >= attempts then return false, reason end
		Wait(400)
	end
	return false, 'restore_timeout'
end
OpxAppearance.Runtime.ApplySnapshot = applySnapshot

--- @author DemiAutomatic
--- @method awaitWorld
--- @description Waits for a faceable puppet, answering false once superseded.
--- @param token {integer}
--- @param label {string}
--- @returns {boolean}
local function awaitWorld(token, label)
	local waitedFrom, said = nowMs(), false
	while not Runtime.Faceable() do
		if not State.Current(token) then return false end
		if not said and nowMs() - waitedFrom > 60000 then
			said = true
			Open77.log.warn(('%s token=%d is still waiting: eligible=%s reloading=%s gameplay=%s ' ..
				'reset=%s life=%s'):format(label, token, tostring(State.worldEligible),
					tostring(State.bodyReloading), tostring(inGameplay()), tostring(playerResetPhase()),
					tostring(lifePhase())))
		end
		Wait(WATCH_MS)
	end
	return State.Current(token)
end

--- @author DemiAutomatic
--- @method OpxAppearance.Runtime.BeginRestore
--- @description Restores the stored face on the right body once faceable.
--- @param snapshot {table}
--- @param origin {string}
function OpxAppearance.Runtime.BeginRestore(snapshot, origin)
	State.canonical = snapshot
	local token = State.NextRestore()

	if State.Wearing() then
		State.restoreSettledToken = token
		Open77.log.debug(('restore skipped for %s: already worn'):format(tostring(State.citizenId)))
		return
	end

	Open77.log.debug(('restore token=%d origin=%s'):format(token, origin))

	CreateThread(function()
		if not awaitWorld(token, 'restore') then return end
		if not ensureFamily() then return end

		local ok, reason = applySnapshot(State.canonical, 20, token)
		if not State.Current(token) then return end

		State.restoreSettledToken = token
		if ok then
			State.Wore()
			State.bootstrapQueued = true
			Runtime.Publish({ ok = true, event = 'restored', citizenId = State.citizenId })
			Runtime.Announce()
			return
		end

		Runtime.FinishMutation()
		if tostring(reason) == 'body_gender_switch_requires_reload' and reloadOntoFamily() then
			return
		end

		Runtime.Publish({ ok = false, event = 'restored', error = tostring(reason),
			citizenId = State.citizenId })
		Runtime.Notify('error', 'appearance.restoreFailed', { reason = tostring(reason) })
		Runtime.Announce()
	end)
end

--- @author DemiAutomatic
--- @method OpxAppearance.Runtime.BeginPristine
--- @description Settles a world entry on the default face of the character's body.
--- @param origin {string}
function OpxAppearance.Runtime.BeginPristine(origin)
	local token = State.NextRestore()
	Open77.log.debug(('pristine token=%d origin=%s'):format(token, origin))
	CreateThread(function()
		if not awaitWorld(token, 'pristine') then return end
		if not ensureFamily() then return end
		State.restoreSettledToken = token
		Runtime.Announce()
	end)
end

--- @author DemiAutomatic
--- @method OpxAppearance.Runtime.ResolveBootstrap
--- @description Spends the one-shot character bootstrap on a body family.
--- @param family {any}
--- @returns {boolean}
function OpxAppearance.Runtime.ResolveBootstrap(family)
	if bootstrapResolved then return true end
	if bootstrapPhase() == 'ready' then
		bootstrapResolved = true
		return true
	end
	if not Snapshot.IsFamily(family) then
		Open77.session.failCharacterBootstrap('invalid_body_family')
		return false
	end
	local resolved, reason = Open77.session.resolveCharacterBootstrap(family)
	if not resolved then
		Open77.session.failCharacterBootstrap(tostring(reason or 'character_bootstrap_failed'))
		Runtime.Notify('error', 'appearance.bootstrapFailed', { reason = tostring(reason) })
		return false
	end
	bootstrapResolved = true
	loadedFamily = family
	Open77.log.info(('character bootstrap resolved as %s'):format(family))
	return true
end

--- @author DemiAutomatic
--- @type {table|nil}
--- @description The roster opx77_core last broadcast, nil until one arrives.
local rosterSeen = nil

--- @author DemiAutomatic
--- @event opx77:client:charactersReady
--- @description Keeps the roster opx77_core broadcast for the bootstrap pick.
--- @param roster {table}
AddEventHandler('opx77:client:charactersReady', function(roster)
	if type(roster) == 'table' and type(roster.list) == 'table' then rosterSeen = roster.list end
end)

--- @author DemiAutomatic
--- @method heldRoster
--- @description Answers the roster opx77_core already holds, nil while it holds none.
--- @returns {table|nil}
local function heldRoster()
	if rosterSeen ~= nil then return rosterSeen end
	if GetResourceState(CORE) ~= 'running' then return nil end
	local dispatched, promise = pcall(Open77.exports.call, CORE, 'GetCharacters')
	if not dispatched or not promise then return nil end
	local result, callError = promise:await()
	if callError or type(result) ~= 'table' or type(result.characters) ~= 'table' then
		return nil
	end
	if #result.characters == 0 and (tonumber(result.slots) or 0) <= 0 then return nil end
	return result.characters
end

--- @author DemiAutomatic
--- @method lastPlayedFamily
--- @description Answers the body family of the most recently played character.
--- @param characters {table[]}
--- @returns {string|nil}
local function lastPlayedFamily(characters)
	local family, latest
	for index = 1, #characters do
		local summary = characters[index]
		local at = type(summary) == 'table' and summary.lastLoggedOut or nil
		if at ~= nil and Snapshot.IsFamily(summary.gender) then
			local comparable = type(at) == type(latest) and
				(type(at) == 'string' or type(at) == 'number')
			if latest == nil or (comparable and at > latest) then
				family, latest = summary.gender, at
			end
		end
	end
	return family
end

--- @author DemiAutomatic
--- @method defaultFamily
--- @description Answers BOOTSTRAP.DEFAULT_FAMILY, or female with one log line.
--- @returns {string}
local function defaultFamily()
	local bootstrap = type(Config.BOOTSTRAP) == 'table' and Config.BOOTSTRAP or {}
	if Snapshot.IsFamily(bootstrap.DEFAULT_FAMILY) then return bootstrap.DEFAULT_FAMILY end
	Open77.log.warn(('BOOTSTRAP.DEFAULT_FAMILY %s is not "female" or "male"; loading %q')
		:format(tostring(bootstrap.DEFAULT_FAMILY), DEFAULT_FAMILY))
	return DEFAULT_FAMILY
end

--- @author DemiAutomatic
--- @method rosterWaitMs
--- @description Answers BOOTSTRAP.ROSTER_WAIT_MS, or the shipped value with one log line.
--- @returns {number}
local function rosterWaitMs()
	local bootstrap = type(Config.BOOTSTRAP) == 'table' and Config.BOOTSTRAP or {}
	local wait = tonumber(bootstrap.ROSTER_WAIT_MS)
	if wait == nil or wait ~= wait or wait < 0 or wait >= math.huge then
		Open77.log.warn(('BOOTSTRAP.ROSTER_WAIT_MS %s is not a number of ms; waiting %d')
			:format(tostring(bootstrap.ROSTER_WAIT_MS), ROSTER_WAIT_MS))
		return ROSTER_WAIT_MS
	end
	return wait
end

--- @author DemiAutomatic
--- @method OpxAppearance.Runtime.BeginBootstrap
--- @description Spends the join bootstrap on the last played body or the default.
--- @param origin {string}
function OpxAppearance.Runtime.BeginBootstrap(origin)
	if bootstrapResolved or bootstrapPicking then return end
	if bootstrapPhase() ~= 'waiting' then return end
	bootstrapPicking = true

	CreateThread(function()
		local deadline = nowMs() + rosterWaitMs()
		local roster
		while roster == nil and nowMs() < deadline do
			if bootstrapResolved or bootstrapPhase() ~= 'waiting' then break end
			roster = heldRoster()
			if roster == nil then Wait(ROSTER_POLL_MS) end
		end
		bootstrapPicking = false
		if bootstrapResolved or bootstrapPhase() ~= 'waiting' then return end

		local family = roster ~= nil and lastPlayedFamily(roster) or nil
		local why = family ~= nil and 'the last character played' or
			(roster ~= nil and 'no character played yet' or 'no roster in time')
		family = family or defaultFamily()
		Open77.log.info(('bootstrap (%s): loading the %s body, %s'):format(origin, family, why))
		Runtime.ResolveBootstrap(family)
	end)
end

--- @author DemiAutomatic
--- @method OpxAppearance.Runtime.ResolveCharacter
--- @description Restores, asks for a creation, or settles on the default face.
--- @param origin {string}
function OpxAppearance.Runtime.ResolveCharacter(origin)
	if State.citizenId == nil then return end
	local stored = State.canonical

	if Snapshot.IsFamily(State.family) then Runtime.ResolveBootstrap(State.family) end
	State.settled = true

	if type(stored) == 'table' and not Snapshot.BuildAccepted(stored.gameBuild) then
		Runtime.Publish({ ok = false, event = 'settled', error = 'stored_build_mismatch',
			citizenId = State.citizenId })
		if not State.buildWarned then
			State.buildWarned = true
			Runtime.Notify('warning', 'appearance.buildMismatch')
		end
		Runtime.BeginPristine(origin)
		return
	end

	if type(stored) == 'table' then
		State.restoreAttempts = 0
		Runtime.BeginRestore(stored, origin)
		return
	end

	if State.creating then return end
	if State.creationAskedAtMs ~= 0 then return end

	if not State.creationRefused and not State.creationWarned then
		State.creationAskedAtMs = nowMs()
		Runtime.Publish({ ok = true, event = 'needsCreation', citizenId = State.citizenId,
			family = State.family })
		return
	end

	Runtime.BeginPristine(origin)
end

--- @author DemiAutomatic
--- @method OpxAppearance.Runtime.WarnUnanswered
--- @description Lets the player in on the default face when nobody answered needsCreation.
function OpxAppearance.Runtime.WarnUnanswered()
	if State.creationAskedAtMs == 0 or State.creating or State.creationWarned then return end
	if Runtime.NowMs() - State.creationAskedAtMs < Config.CREATION_WAIT_MS then return end
	State.creationWarned = true
	State.creationAskedAtMs = 0
	Open77.log.warn(('%s has no stored face and nothing called the `openCreator` export')
		:format(tostring(State.citizenId)))
	Open77.log.warn('  the player enters on the default face; a character creator resource is')
	Open77.log.warn('  what opens the editor. See README, "Who opens the creator".')
	Runtime.BeginPristine('creation_unanswered')
end

--- @author DemiAutomatic
--- @event open77:appearance:restore_failed
--- @description Re-dispatches an aborted restore, or reports a face that does not fit.
AddEventHandler('open77:appearance:restore_failed', function()
	Runtime.FinishMutation()

	if State.bootstrapToken == State.restoreToken and State.bootstrapQueued and
		not State.appearanceConfirmed then
		State.Undress()
		State.bootstrapQueued = false
		if type(State.canonical) == 'table' and State.restoreAttempts < Config.RESTORE_RETRIES then
			State.restoreAttempts = State.restoreAttempts + 1
			Open77.log.warn(('bootstrap restore aborted before confirmation; retry %d/%d'):format(
				State.restoreAttempts, Config.RESTORE_RETRIES))
			Runtime.BeginRestore(State.canonical, 'mirror_abort')
			return
		end
		Runtime.Notify('error', 'appearance.mirrorUnconfirmed')
		Runtime.Announce()
		return
	end

	if State.Wearing() then return end
	State.bootstrapQueued = false
	State.appearanceConfirmed = false
	Runtime.Notify('error', 'appearance.catalogueMismatch')
end)

--- @author DemiAutomatic
--- @event open77:playerReset:complete
--- @description Ends a body reload and records the player reset, then announces.
AddEventHandler('open77:playerReset:complete', function()
	Runtime.FinishReload('playerReset')
	State.playerResetDone = true
	Runtime.Announce()
end)

--- @author DemiAutomatic
--- @method adoptCharacter
--- @description Adopts a new live character, its body family, face and clothing.
--- @param playerData {table|nil}
--- @param origin {string}
local function adoptCharacter(playerData, origin)
	if type(playerData) ~= 'table' then return end
	local citizen = playerData.citizenId
	if type(citizen) ~= 'string' or citizen == '' then return end
	if citizen == State.citizenId then return end

	local switching = State.citizenId ~= nil
	State.citizenId = citizen
	State.family = type(playerData.charInfo) == 'table' and playerData.charInfo.gender or nil
	State.canonical = type(playerData.appearance) == 'table' and playerData.appearance or nil
	State.settled = false
	State.creationRefused = false
	State.creationAskedAtMs = 0
	State.creationWarned = false
	State.familyAttempts = 0
	State.buildWarned = false
	State.Undress()
	State.restoreSettledToken = State.NextRestore()
	if OpxAppearance.Clothing then OpxAppearance.Clothing.Adopt(playerData) end
	if switching then
		Open77.log.info(('live character is now %s'):format(citizen))
		Runtime.Publish({ ok = true, event = 'characterChanged', citizenId = citizen })
	end
	Runtime.ResolveCharacter(origin)
end

--- @author DemiAutomatic
--- @event opx77:client:onPlayerLoaded
--- @description Adopts the character opx77_core loaded.
--- @param playerData {table}
AddEventHandler('opx77:client:onPlayerLoaded', function(playerData)
	adoptCharacter(playerData, 'playerLoaded')
end)

--- @author DemiAutomatic
--- @event opx77:client:playerDataChanged
--- @description Adopts the character when PlayerData names another citizen id.
--- @param playerData {table}
AddEventHandler('opx77:client:playerDataChanged', function(playerData)
	adoptCharacter(playerData, 'playerDataChanged')
end)

--- @author DemiAutomatic
--- @event opx77:client:onPlayerUnloaded
--- @description Forgets the character's face and clothing.
AddEventHandler('opx77:client:onPlayerUnloaded', function()
	State.Unload()
	if OpxAppearance.Clothing then OpxAppearance.Clothing.Unload() end
end)

--- @author DemiAutomatic
--- @method catchUp
--- @description Adopts a character already loaded before this resource started.
local function catchUp()
	CreateThread(function()
		local result, failure = Runtime.Call(CORE, 'GetPlayerData')
		if result == nil then return Open77.log.debug('catch-up: ' .. tostring(failure)) end
		adoptCharacter(result.data, 'catchUp')
	end)
end

--- @author DemiAutomatic
--- @event open77:worldReady
--- @description Judges the new world, spends the bootstrap, decides the face.
AddEventHandler('open77:worldReady', function()
	State.EnterWorld()
	markWorldEligibility('worldReady')
	Runtime.BeginBootstrap('worldReady')
	Runtime.ResolveCharacter('worldReady')
end)

--- @author DemiAutomatic
--- @event onClientResourceStart
--- @description Re-establishes the world, the bootstrap and the character.
--- @param name {string}
AddEventHandler('onClientResourceStart', function(name)
	if name ~= RESOURCE then return end
	if type(Open77.appearance) ~= 'table' or type(Open77.session) ~= 'table' or
		type(Open77.character) ~= 'table' then
		Open77.log.error('native appearance API unavailable; no face will be stored or restored')
		return
	end
	State.EnterWorld()
	markWorldEligibility('resourceStart')
	Runtime.BeginBootstrap('resourceStart')
	catchUp()
end)

--- @author DemiAutomatic
--- @event onClientResourceStop
--- @description Releases the native mutation transaction when this resource stops.
--- @param name {string}
AddEventHandler('onClientResourceStop', function(name)
	if name ~= RESOURCE then return end
	Runtime.FinishMutation()
end)
