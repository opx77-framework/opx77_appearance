--- Client-side state: what this client knows, and which generation it belongs to.

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

--- Whether this world is the gameplay one rather than the pre-game menu the join starts in.
State.worldEligible = false

--- Sent exactly once per world entry, once the player is genuinely playable.
State.gameplayAnnounced = false

--- Whether this world entry's face has been decided at all: restored, handed to a creation, or
--- honestly given up on.
State.settled = false

--- Which of this resource's two modals is on screen. `creating` covers the whole creation,
--- from `openCreator` to the core's answer; `creatorUp` only the editor being on screen.
State.editing = false
State.creating = false
State.creatorUp = false

--- A captured face sent to opx77_core and not yet answered.
---@type { kind: "edit"|"create", deadlineMs: integer }|nil
State.commit = nil

--- When the last capture went out, so the core's cooldown is waited out rather than tripped.
State.lastSaveAtMs = 0

--- Whether this character has already been told its stored face is from another build. Said
--- once per character, not once per world entry.
State.buildWarned = false

--- Body-family attempts spent on this character: world reloads onto its body, and creation
--- editors that came back on the other one. Bounded by `FAMILY_RETRIES`.
State.familyAttempts = 0

--- The body family the world was last loaded with by this client, for when the engine will
--- not say. nil until the bootstrap or a switch.
---@type string|nil
State.bodyFamily = nil

--- A body switch went out and its reload has not entered the world yet. The puppet still
--- standing there is the old body, so nothing is applied to it and nothing is announced.
State.bodyReloading = false

--- This character's creation ended without a face, and `openCreator` must not reopen it until
--- the character changes or this resource restarts. `openEditor` still can.
State.creationRefused = false

--- A `needsCreation` that nothing has answered yet: when it went out, and whether the wait for
--- an answer has already run out. 0 means nothing is waiting on `openCreator`; the
--- announcement holds while something is.
State.creationAskedAtMs = 0
State.creationWarned = false

--- The record of having spent the one-shot character bootstrap. Not a cache of the phase: the
--- phase is the host's and is read from the host.
State.bootstrapResolved = false

--- The join-time wait for the roster that picks the bootstrap body is running.
State.bootstrapPicking = false

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
  if State.citizenId == nil then return false end
  if not State.settled or State.creating or State.bodyReloading then return false end
  -- a `needsCreation` still unanswered: the editor may yet come up
  if State.creationAskedAtMs ~= 0 then return false end
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
  State.creatorUp = false
  State.commit = nil
  State.creationRefused = false
  State.creationAskedAtMs = 0
  State.creationWarned = false
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
    decided = State.settled,
    settled = State.appearanceSettled(),
    restoring = State.restoreToken ~= State.restoreSettledToken,
    committing = State.commit ~= nil,
    creating = State.creating,
    editing = State.editing,
    worldEligible = State.worldEligible,
    announced = State.gameplayAnnounced,
  }
end
