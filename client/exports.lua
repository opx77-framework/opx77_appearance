--- The public export surface: everything another resource needs to read, apply, save or edit
--- the live character's face. Every call answers a table carrying `ok` and never raises;
--- `error` is one of the codes in types.lua. Client-side only: the server runtime installs none.
---
--- This resource decides nothing about the join flow. A character with no stored face is
--- announced on the event channel as `needsCreation`; opening the creator is a call somebody
--- else makes. See README, "Who opens the creator".

local State = OpxAppearance.state
local Snapshot = OpxAppearance.snapshot
local Runtime = OpxAppearance.runtime
local Editor = OpxAppearance.editor

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

-- ---------------------------------------------------------------------------
-- Reading a face
-- ---------------------------------------------------------------------------

--- The stored face for the live character, as `PlayerData.appearance` carries it. It is what
--- opx77_core holds, not what the puppet is wearing: `captureSkin` answers that.
---@return AppearanceCurrent
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
  local capture, captureError = Open77.appearance.capture()
  local payload, payloadError = Snapshot.forNetwork(capture)
  if payload == nil then
    return response(false, { error = tostring(payloadError or captureError or "capture_failed") })
  end
  return response(true, { snapshot = payload, citizenId = State.citizenId })
end)

--- The body family of the live character -- "female" or "male". It is `charInfo.gender` on the
--- character row and opx77_core owns it; nothing here can change it.
---@return AppearanceFamily
exports("family", function()
  local gone = nobody()
  if gone then return gone end
  if State.citizenId == nil then return response(false, { error = "no_character" }) end
  return response(true, { family = State.family, citizenId = State.citizenId })
end)

-- ---------------------------------------------------------------------------
-- Writing a face
-- ---------------------------------------------------------------------------

--- Put a snapshot on the puppet. Nothing is stored: this is the preview call, for a UI showing
--- a face before the player commits to it. `saveSkin` is what persists.
---
--- Answers that the apply was ASKED for. The engine schedules it through the vanilla mirror and
--- the outcome arrives on the event channel as `applied`.
---@param snapshot AppearanceSnapshot
---@return AppearanceResponse
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

--- Store a face on the character, through opx77_core. Defaults to a capture of the puppet, so
--- a caller that has just applied one can call this with no argument.
---
--- Answers that the save was ASKED for: opx77_core validates and writes it, and the outcome
--- arrives on the event channel as `saved`. A save that changes nothing is answered there too.
---@param snapshot AppearanceSnapshot|nil  defaults to a capture
---@return AppearanceResponse
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
---@return AppearanceResponse
exports("editor", function(mode)
  local gone = nobody()
  if gone then return gone end
  local ok, reason = Editor.open(mode or "ripperdoc")
  if not ok then return response(false, { error = reason }) end
  return response(true, { queued = true, citizenId = State.citizenId })
end)

--- The hairdresser's chair: the same call with the mode fixed.
---@return AppearanceResponse
exports("barber", function()
  local gone = nobody()
  if gone then return gone end
  local ok, reason = Editor.open("hairdresser")
  if not ok then return response(false, { error = reason }) end
  return response(true, { queued = true, citizenId = State.citizenId })
end)

--- Open the vanilla character creator for a character that has no face yet. This is the call
--- that answers `needsCreation`, and it is the only way one opens.
---
--- Everything after the player confirms is this resource's: the capture, the body-family check
--- against the character, the save through opx77_core, spending the character bootstrap and
--- letting the world load. The outcome arrives on the event channel as `created`.
---@return AppearanceResponse
exports("creator", function()
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
-- Where the session is
-- ---------------------------------------------------------------------------

--- Whether the appearance work for this world entry has finished -- restored, created, or
--- honestly failed. `open77:session:gameplayReady` goes out on the same condition, so a
--- resource waiting to place a player can wait on this instead of guessing.
---
--- `waiting = "creation"` is the one worth branching on: the character has no face and nothing
--- has called `creator` yet.
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
  report.ok = true
  return report
end)
