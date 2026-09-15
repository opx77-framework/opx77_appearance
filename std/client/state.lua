---@meta

OpxAppearance.State = {}

--- The live character's citizen id; nil between `onPlayerUnloaded` and the next selection.
---@type string|nil
OpxAppearance.State.citizenId = nil

--- The live character's body family, its `charInfo.gender`.
---@type BodyFamily|nil
OpxAppearance.State.family = nil

--- The stored face, as `PlayerData.appearance` carries it; what a failed edit is rolled back to.
---@type AppearanceSnapshot|nil
OpxAppearance.State.canonical = nil

--- The character and face last accepted onto the puppet, for the redundant-restore guard.
---@type string|nil
OpxAppearance.State.appliedCitizen = nil
---@type AppearanceSnapshot|nil
OpxAppearance.State.appliedSnapshot = nil

--- Restore generations: `restoreToken ~= restoreSettledToken` while one is in flight.
---@type integer
OpxAppearance.State.restoreToken = 0
---@type integer
OpxAppearance.State.restoreSettledToken = 0

--- The restore the readiness announcement waits on, whether it queued the mirror, and the two
--- confirmations a queued one needs.
---@type integer|nil
OpxAppearance.State.bootstrapToken = nil
---@type boolean
OpxAppearance.State.bootstrapQueued = false
---@type boolean
OpxAppearance.State.appearanceConfirmed = false
---@type boolean
OpxAppearance.State.playerResetDone = false

--- Re-dispatches spent on the current bootstrap restore, bounded by `RESTORE_RETRIES`.
---@type integer
OpxAppearance.State.restoreAttempts = 0

--- Whether this world is the gameplay one rather than the pre-game menu.
---@type boolean
OpxAppearance.State.worldEligible = false

--- Whether `open77:session:gameplayReady` went out for this world entry.
---@type boolean
OpxAppearance.State.gameplayAnnounced = false

--- Whether this world entry's face has been decided.
---@type boolean
OpxAppearance.State.settled = false

--- The modals: the face editor, a creation from `openCreator` to the core's answer, and the
--- creation editor itself.
---@type boolean
OpxAppearance.State.editing = false
---@type boolean
OpxAppearance.State.creating = false
---@type boolean
OpxAppearance.State.creatorUp = false

--- A captured face sent to opx77_core and not yet answered; `deadlineMs` is 0 until it is out.
---@type { kind: "edit"|"create", deadlineMs: integer }|nil
OpxAppearance.State.commit = nil

--- Whether this character was told its stored face is from another build.
---@type boolean
OpxAppearance.State.buildWarned = false

--- Body-family attempts spent on this character, bounded by `FAMILY_RETRIES`.
---@type integer
OpxAppearance.State.familyAttempts = 0

--- A body reload has not reached its new puppet's reset yet.
---@type boolean
OpxAppearance.State.bodyReloading = false

--- This character's creation ended without a face: `openCreator` refuses until it changes.
---@type boolean
OpxAppearance.State.creationRefused = false

--- When an unanswered `needsCreation` went out (0 when none waits), and whether its wait ran out.
---@type integer
OpxAppearance.State.creationAskedAtMs = 0
---@type boolean
OpxAppearance.State.creationWarned = false

--- Starts a restore generation and answers the token its thread carries; clears the queued-apply
--- confirmations.
---@return integer
function OpxAppearance.State.NextRestore() end

--- Whether `token` is still the current restore generation.
---@param token integer
---@return boolean
function OpxAppearance.State.Current(token) end

--- Whether the puppet already wears this character's stored face.
---@return boolean
function OpxAppearance.State.Wearing() end

--- Records that the stored face was accepted onto the puppet. Called once an apply was accepted.
function OpxAppearance.State.Wore() end

--- Forgets which face is on the puppet.
function OpxAppearance.State.Undress() end

--- Whether every piece of appearance work for this world entry has finished. The readiness
--- announcement waits on this and nothing else.
---@return boolean
function OpxAppearance.State.AppearanceSettled() end

--- Clears what a new world entry invalidates, the clothing phase included; keeps the character.
function OpxAppearance.State.EnterWorld() end

--- Forgets the character and everything about its face. Takes a new restore generation, marked
--- settled, so a restore still under way for the departed character stops at its next check.
function OpxAppearance.State.Unload() end

--- The diagnostic fields the `state` export answers, before `body`, `panel` and `clothing`.
---@return table
function OpxAppearance.State.Report() end
