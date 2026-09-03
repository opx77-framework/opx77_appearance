--- The public export surface: reading, applying, storing and editing the live character's
--- face. Every call answers a table carrying `ok`, never raises, and is client-side only.

local State = OpxAppearance.state
local Snapshot = OpxAppearance.snapshot
local Runtime = OpxAppearance.runtime
local Editor = OpxAppearance.editor
local Panel = OpxAppearance.panel

---@param ok boolean
---@param values table|nil
---@return table
local function response(ok, values)
  values = values or {}
  values.ok = ok == true
  return values
end

--- Who is calling, from the host rather than an argument. Nothing inside this VM should be
--- reaching the public surface, so a call with no invoking resource went somewhere by mistake.
---@return string|nil
local function caller()
  local owner = GetInvokingResource()
  if type(owner) ~= "string" or owner == "" or #owner > 64 or
    owner:match("^[%w_%-%.]+$") == nil then
    return nil
  end
  return owner
end

--- The refusal every export starts with.
---@return table|nil
local function nobody()
  if caller() == nil then return response(false, { error = "export_call_required" }) end
  return nil
end

--- Which generation of the caller's code is asking, so a reloaded caller's panel goes away
--- with it. nil when the host will not say.
---@return integer|nil
local function generation()
  local value = GetInvokingResourceGeneration()
  return type(value) == "number" and value or nil
end

-- ---------------------------------------------------------------------------
-- Reading a face
-- ---------------------------------------------------------------------------

--- The stored face for the live character, as `PlayerData.appearance` carries it. It is what
--- opx77_core holds, not what the puppet is wearing: `captureSkin` answers that.
---@return AppearanceSkin
exports("getSkin", function()
  local gone = nobody()
  if gone then return gone end
  if State.citizenId == nil then return response(false, { error = "no_character" }) end
  return response(true, {
    citizenId = State.citizenId,
    family = State.family,
    snapshot = State.canonical,
  })
end)

--- What the puppet is wearing right now, canonical and ready to hand back to `setSkin` or
--- `saveSkin`. Reads the engine, so it answers nothing useful before the world has loaded.
---@return AppearanceCapture
exports("captureSkin", function()
  local gone = nobody()
  if gone then return gone end
  local payload, failure = Snapshot.capture()
  if payload == nil then return response(false, { error = tostring(failure) }) end
  return response(true, { snapshot = payload, citizenId = State.citizenId })
end)

--- The body family of the live character -- "female" or "male". It is `charInfo.gender` on the
--- character row and opx77_core owns it; nothing here can change it.
---@return AppearanceFamily
exports("getFamily", function()
  local gone = nobody()
  if gone then return gone end
  if State.citizenId == nil then return response(false, { error = "no_character" }) end
  return response(true, { family = State.family, citizenId = State.citizenId })
end)

-- ---------------------------------------------------------------------------
-- Writing a face
-- ---------------------------------------------------------------------------

--- Put a snapshot on the puppet; nothing is stored, `saveSkin` is what persists. Answers that
--- the apply was ASKED for: the outcome arrives on the event channel as `applied`.
---@param snapshot AppearanceSnapshot
---@return AppearanceQueued
exports("setSkin", function(snapshot)
  local gone = nobody()
  if gone then return gone end
  if State.citizenId == nil then return response(false, { error = "no_character" }) end
  if State.editing or State.creating then
    return response(false, { error = "appearance_busy" })
  end
  local canonical, reason = Snapshot.forNetwork(snapshot)
  if canonical == nil then return response(false, { error = tostring(reason) }) end
  if not Snapshot.buildAccepted(canonical.gameBuild) then
    return response(false, { error = "stored_build_mismatch" })
  end
  CreateThread(function()
    local ok, failure = Runtime.applySnapshot(canonical, 8, nil)
    Runtime.publish({ ok = ok, event = "applied", citizenId = State.citizenId,
                      error = (not ok) and tostring(failure) or nil })
  end)
  return response(true, { queued = true, citizenId = State.citizenId })
end)

--- Store a face through opx77_core; defaults to a capture of the puppet. Answers that the save
--- was ASKED for: the outcome arrives on the event channel as `saved`, unchanged saves too.
---@param snapshot AppearanceSnapshot|nil  defaults to a capture
---@return AppearanceQueued
exports("saveSkin", function(snapshot)
  local gone = nobody()
  if gone then return gone end
  local ok, reason = Editor.save(snapshot)
  if not ok then return response(false, { error = reason }) end
  return response(true, { queued = true, citizenId = State.citizenId })
end)

-- ---------------------------------------------------------------------------
-- The native modals
-- ---------------------------------------------------------------------------

--- Open the native appearance editor on the live character. `ok = true` means ASKED: the modal
--- opens a moment later, and it cannot change the body family.
---@param mode "ripperdoc"|"hairdresser"|nil  defaults to "ripperdoc"
---@return AppearanceQueued
exports("openEditor", function(mode)
  local gone = nobody()
  if gone then return gone end
  local ok, reason = Editor.open(mode or "ripperdoc")
  if not ok then return response(false, { error = reason }) end
  return response(true, { queued = true, citizenId = State.citizenId })
end)

--- Open the vanilla character creator for a character that has no face yet. This is the call
--- that answers `needsCreation`; the outcome arrives on the event channel as `created`.
---@return AppearanceQueued
exports("openCreator", function()
  local gone = nobody()
  if gone then return gone end
  local ok, reason = Editor.creator()
  if not ok then return response(false, { error = reason }) end
  return response(true, { queued = true, citizenId = State.citizenId })
end)

--- Whether a native appearance modal is on screen right now, and which one. The call an
--- interaction resource makes before offering a prompt.
---@return AppearanceOpenState
exports("isOpen", function()
  local gone = nobody()
  if gone then return gone end
  return response(true, {
    open = Open77.appearance.isOpen() == true,
    editing = State.editing,
    creating = State.creating,
  })
end)

-- ---------------------------------------------------------------------------
-- This resource's own surface
-- ---------------------------------------------------------------------------

--- Put this resource's panel on screen, drawn by opx77_menu: the saved look, the body family
--- and the two ways into the native editor. `ok = true` means ASKED, as everywhere here.
---@return AppearanceQueued
exports("openPanel", function()
  local gone = nobody()
  if gone then return gone end
  local invoker = caller()
  local ready, why = Panel.available()
  if not ready then return response(false, { error = why }) end
  if State.citizenId == nil then return response(false, { error = "no_character" }) end

  -- the mirror is the only face editor there is, and the panel never draws over it
  if Panel.nativeUp() then return response(false, { error = "appearance_busy" }) end
  if Panel.isOpen() and Panel.owner() ~= invoker then
    return response(false, { error = "panel_busy" })
  end

  return Panel.open(invoker, generation())
end)

--- Take your own panel back down. A caller may not close another resource's.
---@return AppearanceResponse
exports("closePanel", function()
  local gone = nobody()
  if gone then return gone end
  if not Panel.isOpen() then return response(false, { error = "no_panel_open" }) end
  if Panel.owner() ~= caller() then return response(false, { error = "not_owner" }) end
  Panel.close("caller")
  return response(true, {})
end)

-- ---------------------------------------------------------------------------
-- Where the session is
-- ---------------------------------------------------------------------------

--- Whether the appearance work for this world entry has finished -- restored, created, or
--- honestly failed. `open77:session:gameplayReady` goes out on the same condition.
---@return AppearanceSettled
exports("isSettled", function()
  local gone = nobody()
  if gone then return gone end
  local waiting = nil
  if State.creating then
    waiting = "creator"
  elseif State.creationAskedAtMs ~= 0 and State.canonical == nil then
    waiting = "creation"
  elseif not State.settled then
    waiting = "server"
  elseif State.restoreToken ~= State.restoreSettledToken then
    waiting = "restore"
  end
  return response(true, {
    settled = State.appearanceSettled(),
    announced = State.gameplayAnnounced,
    waiting = waiting,
    citizenId = State.citizenId,
  })
end)

--- What this client knows: which character it is dressing, whether the stored face is on the
--- puppet, and which of the two modals is open. For a report on a face that did not come back.
---@return AppearanceClientState
exports("state", function()
  local gone = nobody()
  if gone then return gone end
  local report = State.report()
  report.panel = Panel.isOpen()
  report.ok = true
  return report
end)
