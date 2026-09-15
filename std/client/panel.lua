---@meta

OpxAppearance.Panel = {}

--- Whether opx77_menu runs to draw the panel; `menu_not_running` when it does not.
---@type fun(): boolean, string|nil
OpxAppearance.Panel.Available = nil

--- Whether a panel is up for any caller.
---@type fun(): boolean
OpxAppearance.Panel.IsOpen = nil

--- Whether a native modal is on screen; an unreadable answer counts as on screen.
---@type fun(): boolean
OpxAppearance.Panel.NativeUp = nil

--- The resource the open panel belongs to.
---@return string|nil
function OpxAppearance.Panel.Owner() end

--- Redraws the open panel where the player stands in it. Best-effort.
function OpxAppearance.Panel.Refresh() end

--- Takes the panel down and raises `panelClosed` with `reason`.
---@param reason AppearancePanelReason
function OpxAppearance.Panel.Close(reason) end

--- Puts the panel up for `callerName`, or redraws it when already open.
---@param callerName string
---@param generation integer|nil
---@return AppearanceQueued
function OpxAppearance.Panel.Open(callerName, generation) end
