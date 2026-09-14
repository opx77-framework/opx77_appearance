--- The two modal transactions: building a new character's face, and editing one.

OpxAppearance = OpxAppearance or {}

local Config = OPX_APPEARANCE_CONFIG
local Locale = OpxAppearance.Locale
local Snapshot = OpxAppearance.snapshot
local State = OpxAppearance.state
local Runtime = OpxAppearance.runtime

local Editor = {}
OpxAppearance.editor = Editor

--- How often the worker looks at the modals, in ms.
local WATCH_MS = 200

--- `OPX.Operations.SAVE_APPEARANCE`: the request a refusal has to name to be this resource's.
local SAVE_OPERATION = "saveAppearance"

--- Every code opx77_core can answer a `saveAppearance` with. All six are locale keys this
--- catalogue carries: the core maps a storage failure to `error.unavailable` before sending it.
local REFUSALS = {
  ["appearance.invalid"] = true,
  ["appearance.tooLarge"] = true,
  ["error.badRequest"] = true,
  ["error.notLoggedIn"] = true,
  ["error.tooFast"] = true,
  ["error.unavailable"] = true,
}

--- Put the stored face back on the puppet after an edit that did not land. The mutation
--- transaction is released FIRST, or the restoration mirror answers `appearance_editor_busy`.
---@param reason any
local function rollback(reason)
  Runtime.finishMutation()
  if type(State.canonical) ~= "table" then return end
  CreateThread(function()
    local ok, failure = Runtime.applySnapshot(State.canonical, 8, nil)
    if not ok then
      Runtime.notify("error", "appearance.rollbackFailed",
        { reason = tostring(reason), failure = tostring(failure) })
    end
  end)
end

--- Tell the player why a save was refused, in their own language when the code is one the
--- core's refusals carry.
---@param code string
local function refused(code)
  if Locale.exists(code) then return Runtime.notify("error", code) end
  Runtime.notify("error", "appearance.saveFailed", { reason = code })
end

--- Send a captured face to opx77_core. The core's cooldown is waited out rather than tripped:
--- a refusal for going too fast would cost the capture.
---@param payload table
---@param kind "edit"|"create"
---@param onNotSent fun(reason: string)
local function send(payload, kind, onNotSent)
  -- deadline 0 until the event is actually out, so the worker cannot time out the wait below
  State.commit = { kind = kind, deadlineMs = 0 }
  CreateThread(function()
    local idle = Config.SAVE_COOLDOWN_MS - (Runtime.nowMs() - State.lastSaveAtMs)
    if idle > 0 then Wait(idle) end
    if State.commit == nil then return end
    State.lastSaveAtMs = Runtime.nowMs()
    State.commit.deadlineMs = Runtime.nowMs() + Config.COMMIT_MS
    local sent, reason = TriggerServerEvent("opx77:server:saveAppearance",
      { snapshot = payload })
    if sent then return end
    State.commit = nil
    onNotSent(tostring(reason or "not_sent"))
  end)
end

-- ---------------------------------------------------------------------------
-- Building a character
-- ---------------------------------------------------------------------------

--- End a creation that did not store anything, and let the player in on the pristine face of
--- their own body. The creation is not reopened for this character again: `openEditor` is the
--- way back, and it saves the first face like any other capture.
---@param reason any
local function enterPristine(reason)
  State.creating = false
  State.creatorUp = false
  State.commit = nil
  State.creationRefused = true
  Runtime.publish({ ok = false, event = "created", error = tostring(reason),
                    citizenId = State.citizenId })
  Runtime.notify("error", "appearance.creationNotSaved", { reason = tostring(reason) })
  Runtime.beginPristine("creation_ended")
end

--- A creation editor is being waited for or opened, so a second ask does not open two.
local creatorOpening = false

--- When the creation editor was last asked for, and whether it has been on screen since. `open`
--- answers true on a queued request, and the game may never consume it.
local creatorAskedAtMs = 0
local creatorShown = false

--- How long an asked-for creation editor may stay off screen before the log says so, in ms.
local CREATOR_UNSEEN_MS = 30000

--- Open the in-world editor on the character's own body, for a character that has no stored
--- face. The editor for the other body opens on that body's puppet, so a body that differs is
--- reloaded first and the editor is reopened from `takeBodyFamilyTransition` after it.
local function openCreator()
  -- No deadline while the modal is open; a player deliberating for an hour is not a fault.
  State.creating = true
  -- one opening at a time: the transition and the worker can both ask after a reload
  if creatorOpening or State.creatorUp then return end
  creatorOpening = true
  local citizen = State.citizenId
  CreateThread(function()
    -- The editor needs the gameplay puppet, which the character's placement can still be
    -- putting back up. After a body reload that means its reset as well: an editor asked for
    -- before it was acknowledged by the game, then never consumed, however often retried.
    while not Runtime.faceable() do
      if not State.creating or State.citizenId ~= citizen then
        creatorOpening = false
        return
      end
      Wait(WATCH_MS)
    end
    creatorOpening = false
    if not State.creating or State.creatorUp or State.citizenId ~= citizen then return end

    local family = Snapshot.isFamily(State.family) and State.family or nil
    if family ~= nil and Runtime.bodyFamily() ~= family then
      if State.familyAttempts >= Config.FAMILY_RETRIES then
        return enterPristine("body_family_mismatch")
      end
      local outcome, reason = Runtime.switchBody(family, true)
      if outcome == "switching" then
        State.familyAttempts = State.familyAttempts + 1
        return Runtime.notify("info", "appearance.creatorSwitching")
      end
      if outcome == nil then
        Runtime.notify("error", "appearance.bodyChangeFailed", { reason = tostring(reason) })
        return enterPristine("body_family_mismatch")
      end
    end

    local opened, reason = Open77.appearance.open({ mode = "ripperdoc", gender = family })
    if opened then
      State.creatorUp = true
      creatorAskedAtMs, creatorShown = Runtime.nowMs(), false
      Open77.log.info(("creation editor asked for on the %s body"):format(tostring(family)))
      return
    end
    Runtime.notify("error", "appearance.creatorUnavailable", { reason = tostring(reason) })
    enterPristine("character_creator_unavailable")
  end)
end

--- Open the in-world editor for the live character, on the body family it was created with;
--- the caller is answering `needsCreation`. The outcome reaches the event channel as `created`.
---@return boolean, string|nil
function Editor.creator()
  if State.citizenId == nil then return false, "no_character" end
  if State.creating then return false, "appearance_busy" end
  if State.editing or Open77.appearance.isOpen() then return false, "appearance_busy" end
  if State.commit ~= nil then return false, "appearance_busy" end
  if State.creationRefused then return false, "creation_refused" end
  if type(State.canonical) == "table" then return false, "already_has_a_face" end
  State.creationAskedAtMs = 0 -- answered: the unanswered-creation wait must not expire
  openCreator()
  return true
end

--- The core stored the face the editor built.
function Editor.finishCreation()
  State.creating = false
  State.creatorUp = false
  State.wore()
  Runtime.publish({ ok = true, event = "created", citizenId = State.citizenId })
  Runtime.notify("success", "appearance.created")
  Runtime.announce()
end

--- The player confirmed the creation editor: check the body, capture, and send it to the core.
local function confirmCreation()
  State.creatorUp = false

  -- The body family is the character's, and this resource never changes it: an editor that
  -- came back on the other body is refused and reopened.
  local family = Runtime.bodyFamily()
  if Snapshot.isFamily(State.family) and family ~= nil and family ~= State.family then
    Runtime.finishMutation()
    State.familyAttempts = State.familyAttempts + 1
    if State.familyAttempts > Config.FAMILY_RETRIES then
      return enterPristine("body_family_mismatch")
    end
    Runtime.notify("warning", "appearance.wrongBody",
      { family = Runtime.familyText(State.family) })
    return openCreator()
  end

  local payload, why = Snapshot.capture()
  if payload == nil then
    Runtime.finishMutation()
    return enterPristine(tostring(why or "character_capture_failed"))
  end

  -- `creating` stays true until the core answers: the announcement waits on it.
  send(payload, "create", function(reason)
    Runtime.finishMutation()
    enterPristine(reason)
  end)
end

-- ---------------------------------------------------------------------------
-- Editing a face
-- ---------------------------------------------------------------------------

--- Store a face on the live character through opx77_core, defaulting to a capture of the
--- puppet. Answers that the save was asked for; the outcome reaches the channel as `saved`.
---@param snapshot AppearanceSnapshot|nil
---@return boolean, string|nil
function Editor.save(snapshot)
  if State.citizenId == nil then return false, "no_character" end
  if State.commit ~= nil then return false, "appearance_busy" end
  if State.editing or State.creating then return false, "appearance_busy" end

  local payload, reason
  if snapshot == nil then
    payload, reason = Snapshot.capture()
  else
    payload, reason = Snapshot.forNetwork(snapshot)
  end
  if payload == nil then return false, tostring(reason or "capture_failed") end
  if not Snapshot.buildAccepted(payload.gameBuild) then
    return false, "stored_build_mismatch"
  end

  if Snapshot.same(payload, State.canonical) then
    -- after this call has answered, or a caller that starts listening on the answer misses it
    SetTimeout(0, function()
      Runtime.publish({ ok = true, event = "saved", citizenId = State.citizenId,
                        unchanged = true })
    end)
    return true
  end

  send(payload, "edit", function(failure)
    Runtime.publish({ ok = false, event = "saved", error = failure,
                      citizenId = State.citizenId })
    Runtime.notify("error", "appearance.saveFailed", { reason = failure })
  end)
  return true
end

--- Open the appearance editor on the live character. Answers only that the modal was asked
--- for; the save happens when the player confirms it.
---@param mode "ripperdoc"|"hairdresser"
---@return boolean, string|nil
function Editor.open(mode)
  mode = tostring(mode or "ripperdoc"):lower()
  if mode ~= "ripperdoc" and mode ~= "hairdresser" then return false, "invalid_mode" end
  -- before the busy test: the creator counts as a modal on screen, so the general refusal
  -- would otherwise hide the specific one
  if State.creating then return false, "character_creation_in_progress" end
  if State.editing or Open77.appearance.isOpen() then return false, "appearance_busy" end
  -- a captured face still with the core: its answer rolls the puppet back and releases the
  -- mutation transaction, and both would land under an open mirror
  if State.commit ~= nil then return false, "appearance_busy" end
  if State.citizenId == nil then return false, "no_character" end

  -- Said before the mirror is on screen: an editor that silently opens on the default face
  -- reads as a wiped character.
  if type(State.canonical) ~= "table" or
    not Snapshot.buildAccepted(State.canonical.gameBuild) then
    Runtime.notify("warning", "appearance.editorDefaultFace")
  end

  State.editing = true
  CreateThread(function()
    -- No gender is ever passed: the body family is a field of the character and opx77_core
    -- owns it.
    local opened, reason = Open77.appearance.open({ mode = mode })
    if opened then return end
    State.editing = false
    Runtime.notify("error", "appearance.editorUnavailable", { reason = tostring(reason) })
  end)
  return true
end

--- The player confirmed a modal. Which one it was is decided by what is open, not by the
--- event: the native raises the same name for both.
AddEventHandler("open77:appearance:confirmed", function()
  if State.creatorUp then return confirmCreation() end
  if not State.editing then
    -- Not an editor of ours: a queued restore mirror finalised.
    if State.bootstrapToken == State.restoreToken and State.bootstrapQueued then
      State.appearanceConfirmed = true
      Runtime.announce()
    else
      Runtime.finishMutation()
    end
    return
  end
  State.editing = false

  local payload, why = Snapshot.capture()
  if payload == nil then
    why = tostring(why or "capture_failed")
    rollback(why)
    return Runtime.notify("error", "appearance.captureFailed", { reason = why })
  end

  -- The core writes nothing and says nothing when the face did not change, so an unchanged
  -- confirm is completed here rather than waited on.
  if Snapshot.same(payload, State.canonical) then
    State.wore()
    SetTimeout(250, Runtime.finishMutation)
    Runtime.publish({ ok = true, event = "saved", citizenId = State.citizenId,
                      unchanged = true })
    return Runtime.notify("success", "appearance.saved")
  end

  send(payload, "edit", function(reason)
    rollback(reason)
    Runtime.notify("error", "appearance.saveFailed", { reason = reason })
  end)
end)

AddEventHandler("open77:appearance:cancelled", function()
  local creation = State.creatorUp
  State.editing = false
  State.creatorUp = false
  Runtime.finishMutation()
  -- The character exists; only its face does not. It plays on the default one, and does not
  -- fail anything: the world is already loaded.
  if creation then enterPristine("character_creation_cancelled") end
end)

-- ---------------------------------------------------------------------------
-- What opx77_core answers
-- ---------------------------------------------------------------------------

--- The core stored a face for the live character. It is the only confirmation there is: a
--- save that changed nothing is answered with silence and completed by the confirm handler.
AddEventHandler("opx77:client:appearanceSaved", function(snapshot)
  if type(snapshot) ~= "table" then return end
  local pending = State.commit
  State.commit = nil
  State.adopt(snapshot, nil)

  if pending ~= nil and pending.kind == "create" then return Editor.finishCreation() end
  if pending ~= nil then
    State.wore()
    -- ReFinalizeState queues work in the character customization system. One frame budget
    -- before replication is allowed to publish the new look.
    SetTimeout(250, Runtime.finishMutation)
    Runtime.publish({ ok = true, event = "saved", citizenId = State.citizenId })
    Runtime.notify("success", "appearance.saved")
    return
  end

  -- Stored by something other than this client: put it on the puppet.
  Runtime.beginRestore(snapshot, nil, "core")
end)

--- A refusal from the core, carrying a locale key and the request it answers. The operation
--- decides whether it is ours: the core refuses a character selection with the same codes.
AddEventHandler("opx77:client:refused", function(code, _, operation)
  local pending = State.commit
  if pending == nil or operation ~= SAVE_OPERATION then return end
  code = tostring(code)
  if not REFUSALS[code] then
    Open77.log.warn(("save refused with an unlisted code: %s"):format(code))
  end
  State.commit = nil
  if pending.kind == "create" then return enterPristine(code) end
  Runtime.publish({ ok = false, event = "saved", error = code, citizenId = State.citizenId })
  rollback(code)
  refused(code)
end)

-- ---------------------------------------------------------------------------
-- The worker
-- ---------------------------------------------------------------------------

--- Whether a creation is waiting for its editor to be opened, and nothing is opening it.
---@return boolean
local function creationStalled()
  return State.creating and not State.creatorUp and not creatorOpening and State.commit == nil
end

--- Pick up what a body-family reload answered on the other side of it. Only a creation asks
--- for an edit transition here; a restore's reload comes back through the world entry.
---@return boolean handled
local function resumeFamilyTransition()
  local result = Open77.appearance.takeBodyFamilyTransition()
  if type(result) ~= "string" or result == "" then return false end
  local action, family = result:match("^([^:]+):(.+)$")
  if action == "error" then
    Runtime.notify("error", "appearance.bodyChangeFailed", { reason = tostring(family) })
    -- no reload is coming: this world is judged again and the face decided on the body it has
    State.bodyReloading = false
    Runtime.markWorldEligibility("body_family_transition_error")
    if creationStalled() then return enterPristine("body_family_mismatch") end
    State.settled = false
    Runtime.resolveCharacter("body_family_transition_error")
    return true
  end
  if action ~= "edit" then
    Open77.log.debug("body family transition: " .. result)
    return true
  end
  if not Snapshot.isFamily(family) then
    Runtime.notify("error", "appearance.bodyChangeInvalid")
    return true
  end
  -- The editor the creation asked for before the reload. The answer comes with the target
  -- world, before its puppet's reset: `openCreator` waits for the reset and the respawn after it.
  Open77.log.info(("body family transition answered %s"):format(result))
  if creationStalled() then openCreator() end
  return true
end

--- One pass of the worker: the unanswered creation, the body transition, the capture deadline.
local function watch()
  Runtime.warnUnanswered()
  resumeFamilyTransition()

  -- A creation whose reload entered the world without the transition answering: the editor
  -- is reopened all the same, or the readiness gate would wait on it for ever.
  if creationStalled() and Runtime.faceable() then openCreator() end

  -- Said once per ask, and nothing more: there is no call that withdraws a queued editor.
  if State.creatorUp and creatorAskedAtMs ~= 0 and not creatorShown then
    -- a raise counts as on screen, as it does for the panel
    local read, open = pcall(Open77.appearance.isOpen)
    local waited = Runtime.nowMs() - creatorAskedAtMs
    if not read or open == true then
      creatorShown = true
    elseif waited >= CREATOR_UNSEEN_MS then
      creatorShown = true
      Open77.log.warn(("the creation editor asked for %d ms ago is not on screen: reset=%s life=%s")
        :format(waited, tostring(Runtime.playerResetPhase()), tostring(Runtime.lifePhase())))
    end
  end

  -- A capture that went out and was never answered. The modal is already closed, so nothing
  -- is taken away from anybody.
  local pending = State.commit
  if pending ~= nil and pending.deadlineMs > 0 and Runtime.nowMs() >= pending.deadlineMs then
    State.commit = nil
    if pending.kind == "create" then
      Runtime.finishMutation()
      enterPristine("save_timeout")
    else
      rollback("save_timeout")
      Runtime.notify("error", "appearance.saveTimedOut")
    end
  end
end

--- Everything that has to be looked at rather than waited for. One thread, because a client
--- resource is allowed 1024 tasks and a thread per transaction is how that budget goes.
CreateThread(function()
  while true do
    Wait(WATCH_MS)
    -- a raise from a host call would end this loop for the session: no body transition is
    -- ever resumed again, and no capture is ever timed out
    local ok, failure = pcall(watch)
    if not ok then Open77.log.error("appearance worker: " .. tostring(failure)) end
  end
end)
