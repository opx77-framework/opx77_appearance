--- @author DemiAutomatic
--- @file client/state.lua
--- @description What this client knows about the live character's face, and its generations.

OpxAppearance = OpxAppearance or {}

local Snapshot = OpxAppearance.Snapshot

OpxAppearance.State = {}
local State = OpxAppearance.State

--- @author DemiAutomatic
--- @type {string|nil}
--- @description The live character's citizen id, nil while none is loaded.
OpxAppearance.State.citizenId = nil

--- @author DemiAutomatic
--- @type {string|nil}
--- @description The live character's body family, its charInfo.gender.
OpxAppearance.State.family = nil

--- @author DemiAutomatic
--- @type {table|nil}
--- @description The stored face, as PlayerData.appearance carries it.
OpxAppearance.State.canonical = nil

--- @author DemiAutomatic
--- @type {string|nil}
--- @description The character whose face was last accepted onto the puppet.
OpxAppearance.State.appliedCitizen = nil

--- @author DemiAutomatic
--- @type {table|nil}
--- @description The face last accepted onto the puppet.
OpxAppearance.State.appliedSnapshot = nil

--- @author DemiAutomatic
--- @type {integer}
--- @description The current restore generation.
OpxAppearance.State.restoreToken = 0

--- @author DemiAutomatic
--- @type {integer}
--- @description The last restore generation that settled.
OpxAppearance.State.restoreSettledToken = 0

--- @author DemiAutomatic
--- @type {integer|nil}
--- @description The restore generation the readiness announcement waits on.
OpxAppearance.State.bootstrapToken = nil

--- @author DemiAutomatic
--- @type {boolean}
--- @description That restore queued the mirror and awaits its confirmation.
OpxAppearance.State.bootstrapQueued = false

--- @author DemiAutomatic
--- @type {boolean}
--- @description The mirror confirmed the queued restore.
OpxAppearance.State.appearanceConfirmed = false

--- @author DemiAutomatic
--- @type {boolean}
--- @description This world entry's pristine player reset has run.
OpxAppearance.State.playerResetDone = false

--- @author DemiAutomatic
--- @type {integer}
--- @description Re-dispatches spent on the current bootstrap restore.
OpxAppearance.State.restoreAttempts = 0

--- @author DemiAutomatic
--- @type {boolean}
--- @description This world is the gameplay one, not the pre-game menu.
OpxAppearance.State.worldEligible = false

--- @author DemiAutomatic
--- @type {boolean}
--- @description open77:session:gameplayReady went out for this world entry.
OpxAppearance.State.gameplayAnnounced = false

--- @author DemiAutomatic
--- @type {boolean}
--- @description This world entry's face has been decided.
OpxAppearance.State.settled = false

--- @author DemiAutomatic
--- @type {boolean}
--- @description This resource's face editor is open.
OpxAppearance.State.editing = false

--- @author DemiAutomatic
--- @type {boolean}
--- @description A creation runs, from openCreator to the core's answer.
OpxAppearance.State.creating = false

--- @author DemiAutomatic
--- @type {boolean}
--- @description The creation editor was opened and not yet closed.
OpxAppearance.State.creatorUp = false

--- @author DemiAutomatic
--- @type {{ kind: string, deadlineMs: integer }|nil}
--- @description A captured face sent to opx77_core and not yet answered.
OpxAppearance.State.commit = nil

--- @author DemiAutomatic
--- @type {integer}
--- @description When the last captured face went out, in milliseconds.
OpxAppearance.State.lastSaveAtMs = 0

--- @author DemiAutomatic
--- @type {boolean}
--- @description This character was told its stored face is from another build.
OpxAppearance.State.buildWarned = false

--- @author DemiAutomatic
--- @type {integer}
--- @description Body-family attempts spent on this character.
OpxAppearance.State.familyAttempts = 0

--- @author DemiAutomatic
--- @type {string|nil}
--- @description The body family this client last loaded the world with.
OpxAppearance.State.bodyFamily = nil

--- @author DemiAutomatic
--- @type {boolean}
--- @description A body reload has not reached its new puppet's reset yet.
OpxAppearance.State.bodyReloading = false

--- @author DemiAutomatic
--- @type {boolean}
--- @description The host's reset projection left complete since the switch.
OpxAppearance.State.reloadResetSeen = false

--- @author DemiAutomatic
--- @type {integer}
--- @description Until when a finished reload holds modals back, 0 when none.
OpxAppearance.State.reloadSettleUntilMs = 0

--- @author DemiAutomatic
--- @type {boolean}
--- @description This character's creation ended without a face.
OpxAppearance.State.creationRefused = false

--- @author DemiAutomatic
--- @type {integer}
--- @description When an unanswered needsCreation went out, 0 when none waits.
OpxAppearance.State.creationAskedAtMs = 0

--- @author DemiAutomatic
--- @type {boolean}
--- @description The wait for an answer to needsCreation ran out.
OpxAppearance.State.creationWarned = false

--- @author DemiAutomatic
--- @type {boolean}
--- @description This client spent the one-shot character bootstrap.
OpxAppearance.State.bootstrapResolved = false

--- @author DemiAutomatic
--- @type {boolean}
--- @description The join-time roster wait that picks the bootstrap body runs.
OpxAppearance.State.bootstrapPicking = false

--- @author DemiAutomatic
--- @method OpxAppearance.State.Adopt
--- @description Adopts a stored face and, when given, the live character.
--- @param snapshot {table|nil}
--- @param citizen {string|nil}
function OpxAppearance.State.Adopt(snapshot, citizen)
	if type(snapshot) == 'table' then State.canonical = snapshot end
	if citizen ~= nil then State.citizenId = citizen end
end

--- @author DemiAutomatic
--- @method OpxAppearance.State.NextRestore
--- @description Starts a restore generation and answers its token.
--- @returns {integer}
function OpxAppearance.State.NextRestore()
	State.restoreToken = State.restoreToken + 1
	State.bootstrapToken = State.restoreToken
	State.bootstrapQueued = false
	State.appearanceConfirmed = false
	return State.restoreToken
end

--- @author DemiAutomatic
--- @method OpxAppearance.State.Current
--- @description Whether a token is still the current restore generation.
--- @param token {integer}
--- @returns {boolean}
function OpxAppearance.State.Current(token)
	return token == State.restoreToken
end

--- @author DemiAutomatic
--- @method OpxAppearance.State.Wearing
--- @description Whether the puppet already wears this character's stored face.
--- @returns {boolean}
function OpxAppearance.State.Wearing()
	return State.appliedCitizen ~= nil and State.appliedCitizen == State.citizenId and
		Snapshot.Same(State.appliedSnapshot, State.canonical)
end

--- @author DemiAutomatic
--- @method OpxAppearance.State.Wore
--- @description Records that the stored face was accepted onto the puppet.
function OpxAppearance.State.Wore()
	State.appliedCitizen = State.citizenId
	State.appliedSnapshot = State.canonical
end

--- @author DemiAutomatic
--- @method OpxAppearance.State.Undress
--- @description Forgets which face is on the puppet.
function OpxAppearance.State.Undress()
	State.appliedCitizen = nil
	State.appliedSnapshot = nil
end

--- @author DemiAutomatic
--- @method OpxAppearance.State.AppearanceSettled
--- @description Whether all appearance work for this world entry has finished.
--- @returns {boolean}
function OpxAppearance.State.AppearanceSettled()
	if State.citizenId == nil then return false end
	if not State.settled or State.creating or State.bodyReloading then return false end
	if State.creationAskedAtMs ~= 0 then return false end
	if State.commit ~= nil and State.commit.kind == 'create' then return false end
	if State.restoreToken ~= State.restoreSettledToken then return false end
	if State.bootstrapToken == State.restoreToken and State.bootstrapQueued then
		return State.appearanceConfirmed and State.playerResetDone
	end
	return true
end

--- @author DemiAutomatic
--- @method OpxAppearance.State.EnterWorld
--- @description Clears what a new world entry invalidates, keeping the character.
function OpxAppearance.State.EnterWorld()
	if OpxAppearance.Clothing then OpxAppearance.Clothing.EnterWorld() end
	State.settled = false
	State.gameplayAnnounced = false
	State.bootstrapToken = nil
	State.bootstrapQueued = false
	State.appearanceConfirmed = false
	State.playerResetDone = false
	State.restoreAttempts = 0
end

--- @author DemiAutomatic
--- @method OpxAppearance.State.Unload
--- @description Forgets the character and everything about its face.
function OpxAppearance.State.Unload()
	State.citizenId = nil
	State.family = nil
	State.canonical = nil
	State.editing = false
	State.creating = false
	State.creatorUp = false
	State.commit = nil
	State.creationRefused = false
	State.creationAskedAtMs = 0
	State.creationWarned = false
	State.familyAttempts = 0
	State.buildWarned = false
	State.settled = false
	State.Undress()
	State.EnterWorld()
end

--- @author DemiAutomatic
--- @method OpxAppearance.State.Report
--- @description Builds the diagnostic fields the state export answers.
--- @returns {table}
function OpxAppearance.State.Report()
	return {
		citizenId = State.citizenId,
		family = State.family,
		stored = State.canonical ~= nil,
		wearing = State.Wearing(),
		decided = State.settled,
		settled = State.AppearanceSettled(),
		restoring = State.restoreToken ~= State.restoreSettledToken,
		committing = State.commit ~= nil,
		creating = State.creating,
		editing = State.editing,
		worldEligible = State.worldEligible,
		announced = State.gameplayAnnounced,
		bodyReloading = State.bodyReloading,
	}
end
