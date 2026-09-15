---@meta

OpxAppearance.Snapshot = {}

--- Whether `value` is `"female"` or `"male"`, the two body families the engine has and
--- opx77_core's `charInfo.gender` carries.
---@param value any
---@return boolean
function OpxAppearance.Snapshot.IsFamily(value) end

--- Whether a stored face captured on game build `value` may be read back, per `GAME_BUILDS`.
---@param value any
---@return boolean
function OpxAppearance.Snapshot.BuildAccepted(value) end

--- The network form of a capture: the four fields that are the face, option names lower-cased,
--- without the editor-only metadata the runtime's value codec will not carry.
---@param capture any what `Open77.appearance.capture` answered
---@return AppearanceSnapshot|nil payload
---@return string|nil error `invalid_snapshot`, `invalid_option` or `invalid_option_name`
function OpxAppearance.Snapshot.ForNetwork(capture) end

--- What the puppet wears, in network form. Never raises: the engine's refusal is answered as an
--- error code.
---@return AppearanceSnapshot|nil payload
---@return string|nil error
function OpxAppearance.Snapshot.Capture() end

--- Whether two snapshots are the same face: build, catalogue digest, gender hash and every
--- option's part, name and value.
---@param left table|nil
---@param right table|nil
---@return boolean
function OpxAppearance.Snapshot.Same(left, right) end
