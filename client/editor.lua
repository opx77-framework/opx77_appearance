--- The two modal transactions: building a character, and editing one.

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

--- Open the vanilla creator for a character that has no stored face.
---@return boolean
local function openCreator()
  -- No deadline while the modal is open; a player deliberating for an hour is not a fault.
  State.creating = true
  local opened, reason = Open77.session.requestCharacterCreator()
  if opened then return true end
  State.creating = false
  Open77.session.failCharacterBootstrap(reason or "character_creator_unavailable")
  Runtime.notify("error", "appearance.creatorUnavailable", { reason = tostring(reason) })
  return false
end

--- End a creation that did not store anything, and let the player into the world on the
--- pristine face. The creator is not reopened for this character again.
---@param reason any
local function enterPristine(reason)
  State.creating = false
  State.commit = nil
  State.creationRefused = true
  Runtime.publish({ ok = false, event = "created", error = tostring(reason),
                    citizenId = State.citizenId })
  Runtime.resolveBootstrap(State.family)
  Runtime.notify("error", "appearance.creationNotSaved", { reason = tostring(reason) })
  Runtime.announce()
end

--- Open the creator for the live character. Called by the runtime when `PlayerData` carries
--- no stored face.
---@return boolean
function Editor.requireCreation()
  if State.creating or State.creationRefused or State.citizenId == nil then return false end
  Runtime.publish({ ok = true, event = "createRequired", citizenId = State.citizenId })
  return openCreator()
end

--- The core stored the face the creator built: spend the bootstrap and let the world load.
function Editor.finishCreation()
  State.creating = false
  State.wore()
  if not Runtime.resolveBootstrap(State.family) then
    Runtime.publish({ ok = false, event = "created", error = "character_bootstrap_failed",
                      citizenId = State.citizenId })
    return
  end
  Runtime.publish({ ok = true, event = "created", citizenId = State.citizenId })
  Runtime.notify("success", "appearance.created")
  Runtime.announce()
end

-- ---------------------------------------------------------------------------
-- Editing a face
-- ---------------------------------------------------------------------------

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
  if not State.editing then
    -- Not ours: either the creator confirmed -- the worker below reads that from
    -- `takeCharacterCreatorResult` -- or a queued restore mirror finalised.
    if State.bootstrapToken == State.restoreToken and State.bootstrapQueued then
      State.appearanceConfirmed = true
      Runtime.announce()
    else
      Runtime.finishMutation()
    end
    return
  end
  State.editing = false

  local capture, captureError = Open77.appearance.capture()
  local payload, payloadError = Snapshot.forNetwork(capture)
  if payload == nil then
    local why = tostring(payloadError or captureError or "capture_failed")
    rollback(why)
    return Runtime.notify("error", "appearance.captureFailed", { reason = why })
  end

  -- The core writes nothing and says nothing when the face did not change, so an unchanged
  -- confirm is completed here rather than waited on.
  if Snapshot.same(payload, State.canonical) then
    State.wore()
    SetTimeout(250, Runtime.finishMutation)
    Runtime.publish({ ok = true, event = "saved", citizenId = State.citizenId })
    return Runtime.notify("success", "appearance.saved")
  end

  send(payload, "edit", function(reason)
    rollback(reason)
    Runtime.notify("error", "appearance.saveFailed", { reason = reason })
  end)
end)

AddEventHandler("open77:appearance:cancelled", function()
  State.editing = false
  Runtime.finishMutation()
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

--- Pick up whatever asked for a body-family transition on the other side of the world reload.
---@return boolean handled
local function resumeFamilyTransition()
  local result = Open77.appearance.takeBodyFamilyTransition()
  if type(result) ~= "string" or result == "" then return false end
  local action, family = result:match("^([^:]+):(.+)$")
  if action == "error" then
    Runtime.notify("error", "appearance.bodyChangeFailed", { reason = tostring(family) })
    return true
  end
  if not Snapshot.isFamily(family) then
    Runtime.notify("error", "appearance.bodyChangeInvalid")
    return true
  end
  State.settled = false
  Runtime.resolveCharacter("body_family_transition")
  return true
end

--- What the creator answered, once the modal has closed.
---@param result string
local function takeCreatorResult(result)
  if result == "cancelled" then
    State.creating = false
    Open77.session.failCharacterBootstrap("character_creation_cancelled")
    return
  end

  local action, family = result:match("^([^:]+):(.+)$")
  if action ~= "confirmed" or not Snapshot.isFamily(family) then
    State.creating = false
    Runtime.finishMutation()
    Open77.session.failCharacterBootstrap("invalid_creator_result")
    return
  end

  -- The body family is the character's, and this resource never changes it: a run that came
  -- back on the other body is refused and reopened.
  if family ~= State.family then
    State.creating = false
    Runtime.finishMutation()
    State.familyAttempts = State.familyAttempts + 1
    if State.familyAttempts > Config.FAMILY_RETRIES then
      return enterPristine("body_family_mismatch")
    end
    Runtime.notify("warning", "appearance.wrongBody",
      { family = Runtime.familyText(State.family) })
    openCreator()
    return
  end

  local capture, captureError = Open77.appearance.capture()
  local payload, payloadError = Snapshot.forNetwork(capture)
  if payload == nil then
    State.creating = false
    Runtime.finishMutation()
    Open77.session.failCharacterBootstrap(
      tostring(payloadError or captureError or "character_capture_failed"))
    return
  end

  -- `creating` stays true until the core answers: the announcement waits on it.
  send(payload, "create", function(reason)
    Runtime.finishMutation()
    enterPristine(reason)
  end)
end

--- One pass of the worker: the modals, and the capture deadline.
local function watch()
  resumeFamilyTransition()

  if State.creating then
    local result = Open77.session.takeCharacterCreatorResult()
    if type(result) == "string" and result ~= "" then takeCreatorResult(result) end
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
    -- a raise from a host call would end this loop for the session: no creator result is ever
    -- read again, and no capture is ever timed out
    local ok, failure = pcall(watch)
    if not ok then Open77.log.error("appearance worker: " .. tostring(failure)) end
  end
end)
