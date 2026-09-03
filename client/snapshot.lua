--- What the client still has to know about the shape of a face. opx77_core validates and
--- stores it; nothing here decides whether a snapshot may be written.

OpxAppearance = OpxAppearance or {}

local Snapshot = {}
OpxAppearance.snapshot = Snapshot

local Config = OPX_APPEARANCE_CONFIG

--- The two body families the engine has, and the two opx77_core's `charInfo.gender` carries.
local FAMILIES = { female = true, male = true }

---@param value any
---@return boolean
function Snapshot.isFamily(value)
  return type(value) == "string" and FAMILIES[value] == true
end

--- Whether a game build is one this resource will read a stored face back into.
---@param value any
---@return boolean
function Snapshot.buildAccepted(value)
  return type(value) == "string" and Config.GAME_BUILDS[value] == true
end

--- The network form of a fresh capture: the four fields that ARE the face, without the
--- editor-only metadata the runtime's value codec will not carry.
---@param capture any  what `Open77.appearance.capture` answered
---@return table|nil payload, string|nil error
function Snapshot.forNetwork(capture)
  if type(capture) ~= "table" or type(capture.options) ~= "table" then
    return nil, "invalid_snapshot"
  end
  local payload = {
    schemaVersion = capture.schemaVersion,
    gameBuild = capture.gameBuild,
    catalogDigest = capture.catalogDigest,
    gender = capture.gender,
    options = {},
  }
  for index = 1, #capture.options do
    local option = capture.options[index]
    if type(option) ~= "table" then return nil, "invalid_option" end
    if type(option.name) ~= "string" then return nil, "invalid_option_name" end
    -- lower-cased here as well as in the core, so `same` can compare a capture with a face
    -- the core has already canonicalised
    payload.options[index] = {
      part = option.part,
      name = option.name:lower(),
      value = option.value,
      choices = option.choices,
    }
  end
  return payload
end

--- What the puppet is wearing, in network form. Never raises: the engine's own refusal is
--- answered as an error code.
---@return table|nil payload, string|nil error
function Snapshot.capture()
  local read, capture, failure = pcall(Open77.appearance.capture)
  if not read then return nil, "capture_failed" end
  if type(capture) ~= "table" then return nil, tostring(failure or "capture_failed") end
  local payload, reason = Snapshot.forNetwork(capture)
  if payload == nil then return nil, tostring(reason) end
  return payload
end

--- Whether two snapshots are the same face. Used to skip an apply the puppet does not need
--- and a save the core would answer with silence.
---@param left table|nil
---@param right table|nil
---@return boolean
function Snapshot.same(left, right)
  if type(left) ~= "table" or type(right) ~= "table" then return false end
  if left.gameBuild ~= right.gameBuild or left.catalogDigest ~= right.catalogDigest then
    return false
  end
  if left.gender ~= right.gender then return false end
  if type(left.options) ~= "table" or type(right.options) ~= "table" then return false end
  local count = #left.options
  if count ~= #right.options then return false end
  for index = 1, count do
    local a, b = left.options[index], right.options[index]
    if a.part ~= b.part or a.name ~= b.name or a.value ~= b.value then return false end
  end
  return true
end
