---@meta

OpxAppearance.Editor = {}

--- Opens the creation editor for the live character on its own body family, answering
--- `needsCreation`. The outcome reaches the event channel as `created`.
---@return boolean asked
---@return string|nil error
function OpxAppearance.Editor.Creator() end

--- Completes a creation whose face opx77_core stored, and announces.
function OpxAppearance.Editor.FinishCreation() end

--- Asks opx77_core to store `snapshot`, a capture of the puppet when nil. The outcome reaches the
--- event channel as `saved`.
---@param snapshot AppearanceSnapshot|nil
---@return boolean asked
---@return string|nil error
function OpxAppearance.Editor.Save(snapshot) end

--- Asks for the native face editor on the live character. The save happens when the player
--- confirms it.
---@param mode "ripperdoc"|"hairdresser"
---@return boolean asked
---@return string|nil error
function OpxAppearance.Editor.Open(mode) end
