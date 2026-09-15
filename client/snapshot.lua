--- @author DemiAutomatic
--- @file client/snapshot.lua
--- @description The shape of a face the client needs: families, builds, network form.

OpxAppearance = OpxAppearance or {}

OpxAppearance.Snapshot = {}
local Snapshot = OpxAppearance.Snapshot

local Config = OPX_APPEARANCE_CONFIG

--- @author DemiAutomatic
--- @type {table<string, boolean>}
--- @description The two body families the engine and charInfo.gender know.
local FAMILIES = { female = true, male = true }

--- @author DemiAutomatic
--- @method OpxAppearance.Snapshot.IsFamily
--- @description Whether a value names one of the two body families.
--- @param value {any}
--- @returns {boolean}
function OpxAppearance.Snapshot.IsFamily(value)
	return type(value) == 'string' and FAMILIES[value] == true
end

--- @author DemiAutomatic
--- @method OpxAppearance.Snapshot.BuildAccepted
--- @description Whether a stored face from this game build may be applied.
--- @param value {any}
--- @returns {boolean}
function OpxAppearance.Snapshot.BuildAccepted(value)
	return type(value) == 'string' and Config.GAME_BUILDS[value] == true
end

--- @author DemiAutomatic
--- @method OpxAppearance.Snapshot.ForNetwork
--- @description Reduces a capture to the four face fields, option names lower-cased.
--- @param capture {any}
--- @returns {table|nil, string|nil}
function OpxAppearance.Snapshot.ForNetwork(capture)
	if type(capture) ~= 'table' or type(capture.options) ~= 'table' then
		return nil, 'invalid_snapshot'
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
		if type(option) ~= 'table' then return nil, 'invalid_option' end
		if type(option.name) ~= 'string' then return nil, 'invalid_option_name' end
		payload.options[index] = {
			part = option.part,
			name = option.name:lower(),
			value = option.value,
			choices = option.choices,
		}
	end
	return payload
end

--- @author DemiAutomatic
--- @method OpxAppearance.Snapshot.Capture
--- @description Captures the puppet's face in network form, answering refusals as codes.
--- @returns {table|nil, string|nil}
function OpxAppearance.Snapshot.Capture()
	local read, capture, failure = pcall(Open77.appearance.capture)
	if not read then return nil, 'capture_failed' end
	if type(capture) ~= 'table' then return nil, tostring(failure or 'capture_failed') end
	local payload, reason = Snapshot.ForNetwork(capture)
	if payload == nil then return nil, tostring(reason) end
	return payload
end

--- @author DemiAutomatic
--- @method OpxAppearance.Snapshot.Same
--- @description Whether two snapshots describe the same face.
--- @param left {table|nil}
--- @param right {table|nil}
--- @returns {boolean}
function OpxAppearance.Snapshot.Same(left, right)
	if type(left) ~= 'table' or type(right) ~= 'table' then return false end
	if left.gameBuild ~= right.gameBuild or left.catalogDigest ~= right.catalogDigest then
		return false
	end
	if left.gender ~= right.gender then return false end
	if type(left.options) ~= 'table' or type(right.options) ~= 'table' then return false end
	local count = #left.options
	if count ~= #right.options then return false end
	for index = 1, count do
		local a, b = left.options[index], right.options[index]
		if a.part ~= b.part or a.name ~= b.name or a.value ~= b.value then return false end
	end
	return true
end
