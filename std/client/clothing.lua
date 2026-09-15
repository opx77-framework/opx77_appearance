---@meta

OpxAppearance.Clothing = {}

--- Any clothing-shaped table in opx77_core's canonical form: nine slots stated, outfit keys
--- `"0"` to `"6"`, empty outfits dropped.
---@type fun(value: any): AppearanceClothing|nil
OpxAppearance.Clothing.Normalize = nil

--- Whether two normalized records are the same clothing.
---@type fun(left: table|nil, right: table|nil): boolean
OpxAppearance.Clothing.Same = nil

--- Starts a world entry: the pristine puppet is dressed again. What was last sent survives.
function OpxAppearance.Clothing.EnterWorld() end

--- Adopts the new live character's clothing from `PlayerData.clothing`: a record, false when
--- none is stored, nil when absent.
---@param playerData table
function OpxAppearance.Clothing.Adopt(playerData) end

--- Forgets the unloaded character's clothing.
function OpxAppearance.Clothing.Unload() end

--- Whether the published look may go out: the clothes are on, given up on, or waited for 15 s.
---@return boolean
function OpxAppearance.Clothing.Settled() end

--- The clothing phase the `state` export reports.
---@return AppearanceClothingPhase
function OpxAppearance.Clothing.Report() end

--- One clothing pass: the save deadline, then a put-on, a read-back or a save.
function OpxAppearance.Clothing.Check() end
