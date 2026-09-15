--- @author DemiAutomatic
--- @file client/keys.lua
--- @description Validates configured keys and declares rebindable key mappings.

OpxAppearance = OpxAppearance or {}

OpxAppearance.Keys = {}

--- @author DemiAutomatic
--- @method OpxAppearance.Keys.Setting
--- @description Answers a configured key name, false, or the default with a warning.
--- @param path {string} Config path the warning names.
--- @param value {any}
--- @param default {string}
--- @returns {string|false}
function OpxAppearance.Keys.Setting(path, value, default)
	if value == false then return false end
	if value == nil then return default end
	if type(value) == 'string' and #value > 0 and #value <= 32 and not value:find('[%s%c]') then
		return value
	end
	Open77.log.warn(('config: %s must be a key name or false; using %q'):format(path, default))
	return default
end

--- @author DemiAutomatic
--- @method captured
--- @description Whether another surface holds the keyboard right now.
--- @returns {boolean}
local function captured()
	local read, answer = pcall(Open77.input.isCaptured)
	return read and answer == true
end

--- @author DemiAutomatic
--- @method OpxAppearance.Keys.Register
--- @description Declares one key mapping, logging a refusal once.
--- @param id {string} Stable mapping id a rebind is stored under.
--- @param nameKey {string} Catalogue key of the pause menu name.
--- @param key {string|false}
--- @param onPressed {fun()}
--- @returns {boolean}
function OpxAppearance.Keys.Register(id, nameKey, key, onPressed)
	if key == false then return false end
	local function pressed()
		if captured() then return end
		local ran, failure = pcall(onPressed)
		if not ran then Open77.log.error(('key %s: %s'):format(id, tostring(failure))) end
	end
	local called, ok, answer = pcall(RegisterKeyMapping, id, locale(nameKey), key, pressed)
	local effective = type(ok) == 'string' and ok ~= '' and ok or
		(ok == true and type(answer) == 'string' and answer ~= '' and answer) or nil
	if not called or (ok ~= true and effective == nil) then
		Open77.log.warn(('key mapping %s (%s) not registered: %s'):format(id, key,
			tostring(called and answer or ok)))
		return false
	end
	return true
end
