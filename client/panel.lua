--- @author DemiAutomatic
--- @file client/panel.lua
--- @description The appearance panel, a list drawn by opx77_menu for one caller.

OpxAppearance = OpxAppearance or {}

local Config = OPX_APPEARANCE_CONFIG
local Snapshot = OpxAppearance.Snapshot
local State = OpxAppearance.State
local Runtime = OpxAppearance.Runtime
local Editor = OpxAppearance.Editor

OpxAppearance.Panel = {}
local Panel = OpxAppearance.Panel

--- @author DemiAutomatic
--- @type {string}
--- @description This resource's own name, which owns the menu events.
local RESOURCE = GetCurrentResourceName()

--- @author DemiAutomatic
--- @type {string}
--- @description The resource that draws the panel.
local MENU = 'opx77_menu'

--- @author DemiAutomatic
--- @type {string}
--- @description The menu id the panel's list carries.
local MENU_ID = 'appearance'

--- @author DemiAutomatic
--- @type {string}
--- @description Local event opx77_menu raises for the panel's rows and closes.
local EVENT = 'opx77_appearance:panel'

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds between two looks at the native modal.
local WATCH_MS = 200

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds between two checks of the panel's owner.
local OWNER_SWEEP_MS = 1000

--- @author DemiAutomatic
--- @type {table<string, boolean>}
--- @description opx77_menu close reasons that mean the player took the list down.
local CLOSED_BY_PLAYER = { pause = true, back = true, item = true, select = true }

--- @author DemiAutomatic
--- @type {string|nil}
--- @description The resource the open panel belongs to.
local owner

--- @author DemiAutomatic
--- @type {integer|nil}
--- @description The generation of the owner's code when it opened the panel.
local ownerGeneration

--- @author DemiAutomatic
--- @type {integer|nil}
--- @description opx77_menu's handle for the open list, once it answered.
local handle

--- @author DemiAutomatic
--- @type {integer}
--- @description Panel session, moved on by every open and every close.
local session = 0

--- @author DemiAutomatic
--- @type {integer}
--- @description When the owner is next checked, in milliseconds.
local nextSweepMs = 0

--- @author DemiAutomatic
--- @method menu
--- @description Calls one opx77_menu export from a coroutine.
--- @param name {string}
--- @returns {table|nil, string|nil}
local function menu(name, ...)
	return Runtime.Call(MENU, name, ...)
end

--- @author DemiAutomatic
--- @method available
--- @description Whether opx77_menu runs to draw the panel.
--- @returns {boolean, string|nil}
local function available()
	if GetResourceState(MENU) ~= 'running' then return false, 'menu_not_running' end
	return true
end
OpxAppearance.Panel.Available = available

--- @author DemiAutomatic
--- @method isOpen
--- @description Whether a panel is up for any caller.
--- @returns {boolean}
local function isOpen()
	return owner ~= nil
end
OpxAppearance.Panel.IsOpen = isOpen

--- @author DemiAutomatic
--- @method OpxAppearance.Panel.Owner
--- @description Answers the resource the open panel belongs to.
--- @returns {string|nil}
function OpxAppearance.Panel.Owner()
	return owner
end

--- @author DemiAutomatic
--- @method nativeUp
--- @description Whether a native modal is on screen, an unreadable answer included.
--- @returns {boolean}
local function nativeUp()
	return State.editing or State.creating or Runtime.ModalOnScreen()
end
OpxAppearance.Panel.NativeUp = nativeUp

--- @author DemiAutomatic
--- @method storedText
--- @description Answers the player-facing condition of the stored face.
--- @returns {string}
local function storedText()
	if type(State.canonical) ~= 'table' then return locale('appearance.panel.none') end
	if State.Wearing() then return locale('appearance.panel.worn') end
	return locale('appearance.panel.stored')
end

--- @author DemiAutomatic
--- @method familyText
--- @description Answers the player-facing body family of the character.
--- @returns {string}
local function familyText()
	return State.family ~= nil and Runtime.FamilyText(State.family) or '-'
end

--- @author DemiAutomatic
--- @method looksItems
--- @description Builds the saved look row and the two native editor rows.
--- @returns {table[]}
local function looksItems()
	local stored = type(State.canonical) == 'table' and State.canonical or nil
	local fits = stored ~= nil and Snapshot.BuildAccepted(stored.gameBuild)
	local busy = State.commit ~= nil or nativeUp()

	local blocked
	if stored == nil then
		blocked = locale('appearance.panel.none')
	elseif not fits then
		blocked = locale('appearance.panel.otherBuild')
	elseif State.Wearing() then
		blocked = locale('appearance.panel.worn')
	elseif busy then
		blocked = locale('appearance.panel.busy')
	end

	return {
		{ separator = true, label = locale('appearance.panel.oneLook') },
		{ id = 'saved', label = locale('appearance.panel.savedLook'), value = storedText(),
			disabled = true },
		{ id = 'wear', label = locale('appearance.panel.wear'), value = blocked,
			disabled = blocked ~= nil },
		{ separator = true },
		{ id = 'editFace', label = locale('appearance.panel.editFace'),
			description = locale('appearance.panel.editNote'),
			value = busy and locale('appearance.panel.busy') or nil, disabled = busy },
		{ id = 'editHair', label = locale('appearance.panel.editHair'),
			value = busy and locale('appearance.panel.busy') or nil, disabled = busy },
	}
end

--- @author DemiAutomatic
--- @method bodyItems
--- @description Builds the body family rows, shown and not offered.
--- @returns {table[]}
local function bodyItems()
	return {
		{ separator = true, label = locale('appearance.panel.bodyNote') },
		{ id = 'family', label = locale('appearance.panel.bodyType'), value = familyText(),
			disabled = true },
	}
end

--- @author DemiAutomatic
--- @method outfitsItems
--- @description Builds the outfits row that says no picker exists yet.
--- @returns {table[]}
local function outfitsItems()
	return {
		{ id = 'soon', label = locale('appearance.panel.outfitsNote'),
			value = locale('appearance.panel.soon'), disabled = true },
	}
end

--- @author DemiAutomatic
--- @method spec
--- @description Builds the whole rendered opx77_menu spec of the panel.
--- @returns {table}
local function spec()
	return {
		id = MENU_ID,
		title = locale('appearance.panel.title'),
		event = EVENT,
		items = {
			{ id = 'looks', label = locale('appearance.panel.looks'), value = storedText(),
				items = looksItems() },
			{ id = 'body', label = locale('appearance.panel.body'), value = familyText(),
				items = bodyItems() },
			{ id = 'outfits', label = locale('appearance.panel.outfits'),
				value = locale('appearance.panel.soon'), items = outfitsItems() },
		},
	}
end

--- @author DemiAutomatic
--- @method OpxAppearance.Panel.Refresh
--- @description Redraws the open panel where the player stands in it.
function OpxAppearance.Panel.Refresh()
	if handle == nil then return end
	local mine = session
	CreateThread(function()
		if session ~= mine then return end
		local _, failure = menu('update', handle, spec())
		if failure ~= nil then Open77.log.debug('the panel was not refreshed: ' .. failure) end
	end)
end

--- @author DemiAutomatic
--- @method status
--- @description Shows a transient status line under the open list.
--- @param text {string}
--- @param ok {boolean}
local function status(text, ok)
	if handle == nil then return end
	local mine = session
	CreateThread(function()
		if session ~= mine then return end
		local _, failure = menu('setStatus', text, ok)
		if failure ~= nil then Open77.log.debug('the panel status line: ' .. failure) end
	end)
end

--- @author DemiAutomatic
--- @method takeDown
--- @description Forgets the open panel, says so, and answers the handle to close.
--- @param reason {AppearancePanelReason}
--- @returns {integer|nil}
local function takeDown(reason)
	if owner == nil then return nil end
	local open = handle
	session = session + 1
	owner, ownerGeneration, handle = nil, nil, nil
	Runtime.Publish({ ok = true, event = 'panelClosed', citizenId = State.citizenId,
		reason = reason })
	return open
end

--- @author DemiAutomatic
--- @method closeMenu
--- @description Takes a list down through opx77_menu from a coroutine.
--- @param open {integer|nil}
local function closeMenu(open)
	if open == nil then return end
	local _, failure = menu('close', open)
	if failure ~= nil then Open77.log.debug('the panel was already down: ' .. failure) end
end

--- @author DemiAutomatic
--- @method OpxAppearance.Panel.Close
--- @description Takes the panel down for a reason of this resource's own.
--- @param reason {AppearancePanelReason}
function OpxAppearance.Panel.Close(reason)
	local open = takeDown(reason)
	if open == nil then return end
	CreateThread(function() closeMenu(open) end)
end

--- @author DemiAutomatic
--- @method tick
--- @description Closes the panel under a native modal or a gone owner.
--- @param atMs {integer}
--- @returns {boolean}
local function tick(atMs)
	if owner == nil then return false end

	if nativeUp() then
		Panel.Close('appearance_busy')
		return false
	end

	if atMs < nextSweepMs then return true end
	nextSweepMs = atMs + OWNER_SWEEP_MS
	if GetResourceState(owner) ~= 'running' then
		Panel.Close('owner_stopped')
		return false
	end
	if ownerGeneration ~= nil and type(Open77.resource) == 'table' and
		type(Open77.resource.generation) == 'function' then
		local generation = Open77.resource.generation(owner)
		if generation ~= nil and generation ~= ownerGeneration then
			Panel.Close('owner_reloaded')
			return false
		end
	end
	return true
end

--- @author DemiAutomatic
--- @method watch
--- @description Watches one open panel session until it ends.
--- @param mine {integer}
local function watch(mine)
	local failing = false
	while session == mine do
		Wait(WATCH_MS)
		if session ~= mine then return end
		local ok, alive = pcall(tick, Runtime.NowMs())
		if not ok then
			if not failing then Open77.log.error('the appearance panel: ' .. tostring(alive)) end
			failing = true
		else
			failing = false
			if not alive then return end
		end
	end
end

--- @author DemiAutomatic
--- @method OpxAppearance.Panel.Open
--- @description Puts the panel up for a caller, or redraws it.
--- @param callerName {string}
--- @param generation {integer|nil}
--- @returns {AppearanceQueued}
function OpxAppearance.Panel.Open(callerName, generation)
	local ready, why = available()
	if not ready then return { ok = false, error = why } end

	if isOpen() then
		Panel.Refresh()
		return { ok = true, queued = true, citizenId = State.citizenId }
	end

	session = session + 1
	local mine = session
	owner, ownerGeneration, handle = callerName, generation, nil
	nextSweepMs = 0
	CreateThread(function()
		local opened, failure = menu('open', spec())
		if session ~= mine then
			if opened ~= nil then closeMenu(opened.handle) end
			return
		end
		if opened == nil then
			owner, ownerGeneration = nil, nil
			Open77.log.warn('the appearance panel did not open: ' .. tostring(failure))
			return
		end
		handle = opened.handle
		Runtime.Publish({ ok = true, event = 'panelOpened', citizenId = State.citizenId })
		watch(mine)
	end)
	return { ok = true, queued = true, citizenId = State.citizenId }
end

--- @author DemiAutomatic
--- @method openNative
--- @description Takes the panel down, then asks for the native editor.
--- @param mode {AppearanceMode}
local function openNative(mode)
	local open = takeDown('caller')
	CreateThread(function()
		closeMenu(open)
		local ok, reason = Editor.Open(mode)
		if ok then return end
		Runtime.Notify('error', 'appearance.editorUnavailable', { reason = tostring(reason) })
	end)
end

--- @author DemiAutomatic
--- @method wearStored
--- @description Puts the stored face back on the puppet from the panel.
local function wearStored()
	if type(State.canonical) ~= 'table' then
		return status(locale('appearance.panel.noLook'), false)
	end
	if not Snapshot.BuildAccepted(State.canonical.gameBuild) then
		return status(locale('appearance.buildMismatch'), false)
	end
	if State.Wearing() then
		return status(locale('appearance.panel.alreadyWorn'), true)
	end
	if State.commit ~= nil or nativeUp() then
		return status(locale('appearance.panel.busy'), false)
	end

	local snapshot, citizen = State.canonical, State.citizenId
	status(locale('appearance.panel.wearing'), true)
	CreateThread(function()
		local ok, failure = Runtime.ApplySnapshot(snapshot, 8, nil)
		if State.citizenId ~= citizen or State.canonical ~= snapshot then return end
		if ok then State.Wore() end
		Runtime.Publish({ ok = ok, event = 'applied', citizenId = citizen,
			error = (not ok) and tostring(failure) or nil })
		if ok then
			status(locale('appearance.panel.wornNow'), true)
		else
			status(locale('appearance.restoreFailed', { reason = tostring(failure) }), false)
		end
	end)
end

--- @author DemiAutomatic
--- @event opx77_appearance:panel
--- @description Runs the panel row the player selected, or records the menu's close.
--- @param payload {table}
AddEventHandler(EVENT, function(payload)
	if type(payload) ~= 'table' or payload.menu ~= MENU_ID then return end
	if payload.owner ~= RESOURCE then return end
	if payload.action == 'close' then
		if payload.reason == 'reopened' then return end
		if handle ~= nil and payload.handle ~= handle then return end
		takeDown(CLOSED_BY_PLAYER[payload.reason] and 'player' or 'menu_closed')
		return
	end
	if payload.action ~= 'select' or payload.handle ~= handle then return end
	local id = payload.itemId
	if id == 'wear' then return wearStored() end
	if id == 'editFace' then return openNative('ripperdoc') end
	if id == 'editHair' then return openNative('hairdresser') end
end)

--- @author DemiAutomatic
--- @event opx77:appearance
--- @description Redraws or closes the panel after a decision about the face.
--- @param payload {AppearanceEvent}
AddEventHandler(Config.EVENT, function(payload)
	if owner == nil or type(payload) ~= 'table' then return end
	local name = payload.event
	if name == 'characterChanged' then return Panel.Close('character_changed') end
	if name == 'saved' or name == 'restored' or name == 'applied' then Panel.Refresh() end
end)

--- @author DemiAutomatic
--- @event opx77:client:onPlayerUnloaded
--- @description Takes the panel down when the character unloads.
AddEventHandler('opx77:client:onPlayerUnloaded', function()
	Panel.Close('no_character')
end)
