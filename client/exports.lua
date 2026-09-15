--- @author DemiAutomatic
--- @file client/exports.lua
--- @description The fourteen client exports, each answering a table carrying ok.

local State = OpxAppearance.State
local Snapshot = OpxAppearance.Snapshot
local Runtime = OpxAppearance.Runtime
local Editor = OpxAppearance.Editor
local Panel = OpxAppearance.Panel

--- @author DemiAutomatic
--- @method response
--- @description Stamps ok onto an export answer.
--- @param ok {boolean}
--- @param values {table|nil}
--- @returns {table}
local function response(ok, values)
	values = values or {}
	values.ok = ok == true
	return values
end

--- @author DemiAutomatic
--- @method caller
--- @description Answers the invoking resource's name when it is a valid one.
--- @returns {string|nil}
local function caller()
	local owner = GetInvokingResource()
	if type(owner) ~= 'string' or owner == '' or #owner > 64 or
		owner:match('^[%w_%-%.]+$') == nil then
		return nil
	end
	return owner
end

--- @author DemiAutomatic
--- @method nobody
--- @description Answers the refusal for a call with no invoking resource.
--- @returns {table|nil}
local function nobody()
	if caller() == nil then return response(false, { error = 'export_call_required' }) end
	return nil
end

--- @author DemiAutomatic
--- @method generation
--- @description Answers the invoking resource's code generation, nil when unknown.
--- @returns {integer|nil}
local function generation()
	local value = GetInvokingResourceGeneration()
	return type(value) == 'number' and value or nil
end

--- @author DemiAutomatic
--- @export getSkin
--- @description Answers the live character's stored face as opx77_core holds it.
--- @returns {AppearanceSkin}
exports('getSkin', function()
	local gone = nobody()
	if gone then return gone end
	if State.citizenId == nil then return response(false, { error = 'no_character' }) end
	return response(true, {
		citizenId = State.citizenId,
		family = State.family,
		snapshot = State.canonical,
	})
end)

--- @author DemiAutomatic
--- @export captureSkin
--- @description Answers what the puppet wears now, ready to hand back.
--- @returns {AppearanceCapture}
exports('captureSkin', function()
	local gone = nobody()
	if gone then return gone end
	local payload, failure = Snapshot.Capture()
	if payload == nil then return response(false, { error = tostring(failure) }) end
	return response(true, { snapshot = payload, citizenId = State.citizenId })
end)

--- @author DemiAutomatic
--- @export getFamily
--- @description Answers the live character's body family.
--- @returns {AppearanceFamily}
exports('getFamily', function()
	local gone = nobody()
	if gone then return gone end
	if State.citizenId == nil then return response(false, { error = 'no_character' }) end
	return response(true, { family = State.family, citizenId = State.citizenId })
end)

--- @author DemiAutomatic
--- @export setSkin
--- @description Asks for a face on the puppet without storing it.
--- @param snapshot {AppearanceSnapshot}
--- @returns {AppearanceQueued}
exports('setSkin', function(snapshot)
	local gone = nobody()
	if gone then return gone end
	if State.citizenId == nil then return response(false, { error = 'no_character' }) end
	if State.editing or State.creating then
		return response(false, { error = 'appearance_busy' })
	end
	local canonical, reason = Snapshot.ForNetwork(snapshot)
	if canonical == nil then return response(false, { error = tostring(reason) }) end
	if not Snapshot.BuildAccepted(canonical.gameBuild) then
		return response(false, { error = 'stored_build_mismatch' })
	end
	CreateThread(function()
		local ok, failure = Runtime.ApplySnapshot(canonical, 8, nil)
		Runtime.Publish({ ok = ok, event = 'applied', citizenId = State.citizenId,
			error = (not ok) and tostring(failure) or nil })
	end)
	return response(true, { queued = true, citizenId = State.citizenId })
end)

--- @author DemiAutomatic
--- @export saveSkin
--- @description Asks opx77_core to store a face, by default a capture.
--- @param snapshot {AppearanceSnapshot|nil}
--- @returns {AppearanceQueued}
exports('saveSkin', function(snapshot)
	local gone = nobody()
	if gone then return gone end
	local ok, reason = Editor.Save(snapshot)
	if not ok then return response(false, { error = reason }) end
	return response(true, { queued = true, citizenId = State.citizenId })
end)

--- @author DemiAutomatic
--- @export openEditor
--- @description Asks for the native face editor on the live character.
--- @param mode {string|nil} Either ripperdoc or hairdresser.
--- @returns {AppearanceQueued}
exports('openEditor', function(mode)
	local gone = nobody()
	if gone then return gone end
	local ok, reason = Editor.Open(mode or 'ripperdoc')
	if not ok then return response(false, { error = reason }) end
	return response(true, { queued = true, citizenId = State.citizenId })
end)

--- @author DemiAutomatic
--- @export openCreator
--- @description Answers needsCreation by opening the creation editor on the character's body.
--- @returns {AppearanceQueued}
exports('openCreator', function()
	local gone = nobody()
	if gone then return gone end
	local ok, reason = Editor.Creator()
	if not ok then return response(false, { error = reason }) end
	return response(true, { queued = true, citizenId = State.citizenId })
end)

--- @author DemiAutomatic
--- @export isOpen
--- @description Answers whether a native modal is on screen, and which.
--- @returns {AppearanceOpenState}
exports('isOpen', function()
	local gone = nobody()
	if gone then return gone end
	return response(true, {
		open = Runtime.ModalOnScreen(),
		editing = State.editing,
		creating = State.creating,
	})
end)

--- @author DemiAutomatic
--- @export openPanel
--- @description Asks for this resource's panel, drawn by opx77_menu, for the caller.
--- @returns {AppearanceQueued}
exports('openPanel', function()
	local gone = nobody()
	if gone then return gone end
	local invoker = caller()
	if Runtime.IsDown() then return response(false, { error = 'player_down' }) end
	local ready, why = Panel.Available()
	if not ready then return response(false, { error = why }) end
	if State.citizenId == nil then return response(false, { error = 'no_character' }) end

	if Panel.NativeUp() then return response(false, { error = 'appearance_busy' }) end
	if Panel.IsOpen() and Panel.Owner() ~= invoker then
		return response(false, { error = 'panel_busy' })
	end

	return Panel.Open(invoker, generation())
end)

--- @author DemiAutomatic
--- @export closePanel
--- @description Takes the caller's own panel down.
--- @returns {AppearanceResponse}
exports('closePanel', function()
	local gone = nobody()
	if gone then return gone end
	if not Panel.IsOpen() then return response(false, { error = 'no_panel_open' }) end
	if Panel.Owner() ~= caller() then return response(false, { error = 'not_owner' }) end
	Panel.Close('caller')
	return response(true, {})
end)

--- @author DemiAutomatic
--- @export beginClothingPreview
--- @description Lends the puppet to the caller's fitting room, answering what it wears.
--- @returns {AppearanceClothingPreview}
exports('beginClothingPreview', function()
	local gone = nobody()
	if gone then return gone end
	if Runtime.IsDown() then return response(false, { error = 'player_down' }) end
	local worn, reason = OpxAppearance.Clothing.BeginPreview(caller())
	if worn == nil then return response(false, { error = reason }) end
	return response(true, {
		clothing = worn,
		family = Runtime.BodyFamily(),
		citizenId = State.citizenId,
	})
end)

--- @author DemiAutomatic
--- @export endClothingPreview
--- @description Takes the puppet back: keep saves what it wears, otherwise the record goes back on.
--- @param keep {boolean|nil}
--- @param records {table|nil} The record names put on, so their TweakDB ids read back by name.
--- @returns {AppearanceResponse}
exports('endClothingPreview', function(keep, records)
	local gone = nobody()
	if gone then return gone end
	local ok, reason = OpxAppearance.Clothing.EndPreview(caller(), keep == true, records)
	if not ok then return response(false, { error = reason }) end
	return response(true, {})
end)

--- @author DemiAutomatic
--- @export isSettled
--- @description Answers whether appearance work finished, and what it waits on.
--- @returns {AppearanceSettled}
exports('isSettled', function()
	local gone = nobody()
	if gone then return gone end
	local waiting = nil
	if State.creating then
		waiting = 'creator'
	elseif State.creationAskedAtMs ~= 0 and State.canonical == nil then
		waiting = 'creation'
	elseif not State.settled then
		waiting = 'server'
	elseif State.bodyReloading then
		waiting = 'body'
	elseif State.restoreToken ~= State.restoreSettledToken then
		waiting = 'restore'
	end
	return response(true, {
		settled = State.AppearanceSettled(),
		announced = State.gameplayAnnounced,
		waiting = waiting,
		citizenId = State.citizenId,
	})
end)

--- @author DemiAutomatic
--- @export state
--- @description Answers what this client knows, for a face that went wrong.
--- @returns {AppearanceClientState}
exports('state', function()
	local gone = nobody()
	if gone then return gone end
	local report = State.Report()
	report.body = Runtime.BodyFamily()
	report.panel = Panel.IsOpen()
	report.clothing = OpxAppearance.Clothing and OpxAppearance.Clothing.Report() or 'idle'
	report.ok = true
	return report
end)
