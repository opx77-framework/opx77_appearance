---@meta

OpxAppearance.Clothing = {}

--- The nine equipment slots of a clothing record and of a published look.
---@type string[]
OpxAppearance.Clothing.SLOTS = {}

--- The seven visible slots a wardrobe outfit overrides.
---@type string[]
OpxAppearance.Clothing.OUTFIT_SLOTS = {}

--- The record the platform states for a character it has no row for: every slot empty but
--- `Items.Underwear_Basic_01_Bottom`, no outfit. Shared read-only with client/presence.lua.
---@type AppearanceClothing
OpxAppearance.Clothing.DEFAULT = {}

--- Any clothing-shaped table in opx77_core's canonical form: nine slots stated, outfit keys
--- `"0"` to `"6"`, empty outfits dropped.
---@type fun(value: any): AppearanceClothing|nil
OpxAppearance.Clothing.Normalize = nil

--- Whether two plain values are equal, tables compared by content. Used on normalized clothing
--- records and on published looks.
---@type fun(left: any, right: any): boolean
OpxAppearance.Clothing.Same = nil

--- Whether equipment `info` (from `Open77.equipment.info`) lets `family` wear the item: false
--- only when the record says that family is not supported.
---@param info table
---@param family string|nil
---@return boolean
function OpxAppearance.Clothing.Fits(info, family) end

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
