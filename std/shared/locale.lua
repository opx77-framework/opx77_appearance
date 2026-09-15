---@meta

OpxAppearance.Locale = {}

--- Merges `strings` into the catalogue for `code`. Operators' own `locales/<code>.lua` files call
--- it, so it keeps its lowercase name.
---@param code string
---@param strings table<string, string>
function OpxAppearance.Locale.register(code, strings) end

--- Selects the catalogue player-facing text is read from. An unknown code is accepted and falls
--- back to `en`: catalogues register after the locale module loads.
---@param code string
---@return boolean applied
function OpxAppearance.Locale.Set(code) end

--- The code of the catalogue player-facing text is read from.
---@return string
function OpxAppearance.Locale.Current() end

--- Whether the active catalogue or the `en` fallback carries `key`.
---@param key string
---@return boolean
function OpxAppearance.Locale.Exists(key) end

--- The text for `key` with `{name}` placeholders filled from `params`. Never nil: a missing key
--- falls back to `en`, then to the key itself.
---@param key string
---@param params? table<string, string|number>
---@return string
function OpxAppearance.Locale.Get(key, params) end

--- The shorthand for `OpxAppearance.Locale.Get` every file below the catalogues uses.
---@type fun(key: string, params?: table<string, string|number>): string
locale = nil
