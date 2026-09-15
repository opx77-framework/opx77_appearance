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

--- Whether a fitting room holds the puppet.
---@return boolean
function OpxAppearance.Clothing.Previewing() end

--- Lends the puppet to `owner`'s fitting room once the clothes are worn and no save is out:
--- until it is given back, nothing is saved, restored or published. Answers what it wears.
---@param owner string
---@return AppearanceClothing|nil, string|nil
function OpxAppearance.Clothing.BeginPreview(owner) end

--- Takes the puppet back from `owner`: `keep` saves what it wears now, otherwise the record
--- goes back on.
---@param owner string
---@param keep boolean
---@return boolean, string|nil
function OpxAppearance.Clothing.EndPreview(owner, keep) end

--- One clothing pass: the save deadline, then a put-on, a read-back or a save.
function OpxAppearance.Clothing.Check() end
