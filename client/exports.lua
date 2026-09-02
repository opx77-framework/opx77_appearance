--- opx77_appearance -- the public surface, client-side only: the server runtime installs none.

local State = OpxAppearance.state
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

--- Open the appearance editor for the live character. `ok = true` means ASKED: the modal
--- opens a moment later, and it cannot change the body family.
---@param mode "ripperdoc"|"hairdresser"|nil  defaults to "ripperdoc"
---@return AppearanceOpenResult
exports("open", function(mode)
  local gone = nobody()
  if gone then return gone end
  local ok, reason = Editor.open(mode or "ripperdoc")
  if not ok then return response(false, { error = reason }) end
  return response(true, { queued = true, citizenId = State.citizenId })
end)

--- The hairdresser's chair: the same call with the mode fixed.
---@return AppearanceOpenResult
exports("barber", function()
  local gone = nobody()
  if gone then return gone end
  local ok, reason = Editor.open("hairdresser")
  if not ok then return response(false, { error = reason }) end
  return response(true, { queued = true, citizenId = State.citizenId })
end)

--- Whether a native appearance modal is on screen right now, and which one.
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

--- The stored face for the live character, as `PlayerData.appearance` carries it. It is what
--- opx77_core holds, not a capture of the puppet.
---@return AppearanceCurrent
exports("current", function()
  local gone = nobody()
  if gone then return gone end
  if State.citizenId == nil then return response(false, { error = "no_character" }) end
  return response(true, {
    citizenId = State.citizenId,
    family = State.family,
    snapshot = State.canonical,
  })
end)

--- What this client knows: which character it is dressing, whether the stored face is on the
--- puppet, and which of the two modals is open.
---@return AppearanceClientState
exports("state", function()
  local gone = nobody()
  if gone then return gone end
  local report = State.report()
  report.ok = true
  return report
end)
