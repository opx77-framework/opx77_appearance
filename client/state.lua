--- opx77_appearance -- what this client knows, and which generation it belongs to.

OpxAppearance = OpxAppearance or {}

local Snapshot = OpxAppearance.snapshot

local State = {}
OpxAppearance.state = State

--- The live character, and its body family. Both come from opx77_core's PlayerData and are
--- nil between `onPlayerUnloaded` and the next selection.
---@type string|nil
State.citizenId = nil
---@type string|nil
State.family = nil

--- The stored face, as `PlayerData.appearance` carries it. What a cancelled or refused edit
--- is rolled back to.
---@type table|nil
State.canonical = nil

--- What is on the puppet, and which face it is. Re-applying a face the puppet already wears
--- arms the native watchdog with nothing to open for, so it is guarded against.
---@type string|nil
State.appliedCitizen = nil
---@type table|nil
State.appliedSnapshot = nil

--- Restore generations. `restoreToken ~= restoreSettledToken` means one is still in flight,
--- and a thread holding an older token has been superseded and stops.
State.restoreToken = 0
State.restoreSettledToken = 0

--- The join-time restore, and the two confirmations the readiness announcement waits on. A
--- successful `apply` only QUEUES the vanilla mirror; the two arrive later as separate events.
---@type integer|nil
State.bootstrapToken = nil
State.bootstrapQueued = false
State.appearanceConfirmed = false
State.playerResetDone = false

--- How many times the CURRENT bootstrap restore has been re-dispatched. Renewed by every
--- adopted face and by every world entry, so it is never a per-session budget.
State.restoreAttempts = 0

--- Whether this world is the gameplay one rather than the menu the creator runs inside.
State.worldEligible = false

--- Sent exactly once per world entry, once the player is genuinely playable.
State.gameplayAnnounced = false

--- Whether this world entry's face has been decided at all: restored, sent to the creator, or
--- honestly given up on.
State.settled = false

--- Which of this resource's two modals is on screen.
State.editing = false
State.creating = false

--- A captured face sent to opx77_core and not yet answered.
---@type { kind: "edit"|"create", deadlineMs: integer }|nil
State.commit = nil

--- When the last capture went out, so the core's cooldown is waited out rather than tripped.
State.lastSaveAtMs = 0

--- When this client last traced a creator that is still on screen. It grants no time and is
--- never checked against a deadline.
State.creationBeatAtMs = 0

--- Whether this character has already been told its stored face is from another build. Said
--- once per character, not once per world entry.
State.buildWarned = false

--- Creator runs spent on this character coming back on the wrong body family.
State.familyAttempts = 0

--- This character's creator ran, was refused for good, and must not be reopened until the
--- character changes or this resource restarts.
State.creationRefused = false

--- The record of having spent the one-shot character bootstrap. Not a cache of the phase: the
--- phase is the host's and is read from the host.
State.bootstrapResolved = false

--- Adopt the stored face for the live character.
---@param snapshot table|nil
---@param citizen string|nil
function State.adopt(snapshot, citizen)
  if type(snapshot) == "table" then State.canonical = snapshot end
  if citizen ~= nil then State.citizenId = citizen end
end

--- A new restore generation. Answers the token the caller has to carry.
---@return integer
function State.nextRestore()
  State.restoreToken = State.restoreToken + 1
  State.bootstrapToken = State.restoreToken
  State.bootstrapQueued = false
  State.appearanceConfirmed = false
  return State.restoreToken
end

--- Whether `token` is still the current restore.
---@param token integer
---@return boolean
function State.current(token)
  return token == State.restoreToken
end

--- Whether the puppet is already wearing this character's stored face.
---@return boolean
function State.wearing()
  return State.appliedCitizen ~= nil and State.appliedCitizen == State.citizenId and
    Snapshot.same(State.appliedSnapshot, State.canonical)
end

--- Record that it is. Called only once an apply has been accepted, never when one is queued.
function State.wore()
  State.appliedCitizen = State.citizenId
  State.appliedSnapshot = State.canonical
end

--- Forget what is on the puppet. A different character is a different face.
function State.undress()
  State.appliedCitizen = nil
  State.appliedSnapshot = nil
end

--- Whether every piece of appearance work for this world entry has finished -- committed,
--- restored, or honestly failed. The gameplay announcement waits on this and nothing else.
---@return boolean
function State.appearanceSettled()
  if not State.settled or State.creating then return false end
  if State.commit ~= nil and State.commit.kind == "create" then return false end
  if State.restoreToken ~= State.restoreSettledToken then return false end
  -- A queued apply additionally waits on the mirror confirmation and the player reset; a
  -- FAILED apply is an honest settled state and must not strand the player behind the gate.
  if State.bootstrapToken == State.restoreToken and State.bootstrapQueued then
    return State.appearanceConfirmed and State.playerResetDone
  end
  return true
end

--- Everything a new world entry invalidates. The character itself survives it.
function State.enterWorld()
  State.settled = false
  State.gameplayAnnounced = false
  State.bootstrapToken = nil
  State.bootstrapQueued = false
  State.appearanceConfirmed = false
  State.playerResetDone = false
  State.restoreAttempts = 0
end

--- The character went. Everything about a face belongs to a character, so all of it goes.
function State.unload()
  State.citizenId = nil
  State.family = nil
  State.canonical = nil
  State.editing = false
  State.creating = false
  State.commit = nil
  State.creationBeatAtMs = 0
  State.creationRefused = false
  State.familyAttempts = 0
  State.buildWarned = false
  State.settled = false
  State.undress()
  State.enterWorld()
end

--- What `report` publishes: enough to debug a face that did not come back, and nothing a
--- caller could mistake for authority.
---@return table
function State.report()
  return {
    citizenId = State.citizenId,
    family = State.family,
    stored = State.canonical ~= nil,
    wearing = State.wearing(),
    settled = State.settled,
    restoring = State.restoreToken ~= State.restoreSettledToken,
    committing = State.commit ~= nil,
    creating = State.creating,
    editing = State.editing,
    worldEligible = State.worldEligible,
    announced = State.gameplayAnnounced,
  }
end
