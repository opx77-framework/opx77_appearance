--- The appearance panel, drawn by opx77_menu. Optional: a missing menu costs one log line.

OpxAppearance = OpxAppearance or {}

local Config = OPX_APPEARANCE_CONFIG
local Snapshot = OpxAppearance.snapshot
local State = OpxAppearance.state
local Runtime = OpxAppearance.runtime
local Editor = OpxAppearance.editor

local Panel = {}
OpxAppearance.panel = Panel

local RESOURCE = GetCurrentResourceName()

local MENU = "opx77_menu"
local MENU_ID = "appearance"
local EVENT = "opx77_appearance:panel"

--- How often the open panel looks at the native modal, and how often at its owner, in ms.
local WATCH_MS = 200
local OWNER_SWEEP_MS = 1000

--- opx77_menu's own close reasons that mean the player took the list down.
local CLOSED_BY_PLAYER = { pause = true, back = true, item = true, select = true }

--- The resource the open panel belongs to, the generation of its code, and the menu handle.
--- `owner` is set the moment `openPanel` is accepted; `handle` only once opx77_menu answers.
---@type string|nil
local owner
---@type integer|nil
local ownerGeneration
---@type integer|nil  opx77_menu's handle for the open list
local handle

--- Rises on every open and every close, so an `open` still in flight when the panel was
--- taken down finds its session gone and takes the list back down instead of adopting it.
local session = 0

local nextSweepMs = 0

--- One call to opx77_menu. Coroutine only.
---@param name string
---@return table|nil, string|nil
local function menu(name, ...)
  return Runtime.call(MENU, name, ...)
end

--- Whether the panel can be drawn at all right now.
---@return boolean, string|nil
local function available()
  if GetResourceState(MENU) ~= "running" then return false, "menu_not_running" end
  return true
end
Panel.available = available

---@return boolean
local function isOpen()
  return owner ~= nil
end
Panel.isOpen = isOpen

---@return string|nil
function Panel.owner()
  return owner
end

--- Whether a native modal is on screen. An unreadable answer counts as "on screen": drawing
--- over the mirror costs the player their way out of it.
---@return boolean
local function nativeUp()
  if State.editing or State.creating then return true end
  local read, open = pcall(Open77.appearance.isOpen)
  if not read then return true end
  return open == true
end
Panel.nativeUp = nativeUp

-- ---------------------------------------------------------------------------
-- What the menu is handed
-- ---------------------------------------------------------------------------

--- The player-facing name of the stored face's condition.
---@return string
local function storedText()
  if type(State.canonical) ~= "table" then return locale("appearance.panel.none") end
  if State.wearing() then return locale("appearance.panel.worn") end
  return locale("appearance.panel.stored")
end

---@return string
local function familyText()
  return State.family ~= nil and Runtime.familyText(State.family) or "-"
end

--- The saved look, and the two ways into Cyberpunk's own mirror.
---@return table[]  opx77_menu items
local function looksItems()
  local stored = type(State.canonical) == "table" and State.canonical or nil
  local fits = stored ~= nil and Snapshot.buildAccepted(stored.gameBuild)
  local busy = State.commit ~= nil or nativeUp()

  -- the reason is the row's value: a greyed row with nothing beside it reads as broken
  local blocked
  if stored == nil then
    blocked = locale("appearance.panel.none")
  elseif not fits then
    blocked = locale("appearance.panel.otherBuild")
  elseif State.wearing() then
    blocked = locale("appearance.panel.worn")
  elseif busy then
    blocked = locale("appearance.panel.busy")
  end

  return {
    { separator = true, label = locale("appearance.panel.oneLook") },
    { id = "saved", label = locale("appearance.panel.savedLook"), value = storedText(),
      disabled = true },
    { id = "wear", label = locale("appearance.panel.wear"), value = blocked,
      disabled = blocked ~= nil },
    { separator = true },
    { id = "editFace", label = locale("appearance.panel.editFace"),
      description = locale("appearance.panel.editNote"),
      value = busy and locale("appearance.panel.busy") or nil, disabled = busy },
    { id = "editHair", label = locale("appearance.panel.editHair"),
      value = busy and locale("appearance.panel.busy") or nil, disabled = busy },
  }
end

--- The body family, shown and not offered: opx77_core owns it.
---@return table[]  opx77_menu items
local function bodyItems()
  return {
    { separator = true, label = locale("appearance.panel.bodyNote") },
    { id = "family", label = locale("appearance.panel.bodyType"), value = familyText(),
      disabled = true },
  }
end

-- TODO(outfits): needs a clothing catalogue with labels, which no resource publishes today.
---@return table[]  opx77_menu items
local function outfitsItems()
  return {
    { id = "soon", label = locale("appearance.panel.outfitsNote"),
      value = locale("appearance.panel.soon"), disabled = true },
  }
end

--- The whole panel, already rendered: opx77_menu holds no catalogue and no rule of ours.
---@return table  an opx77_menu spec
local function spec()
  return {
    id = MENU_ID,
    title = locale("appearance.panel.title"),
    event = EVENT,
    items = {
      { id = "looks", label = locale("appearance.panel.looks"), value = storedText(),
        items = looksItems() },
      { id = "body", label = locale("appearance.panel.body"), value = familyText(),
        items = bodyItems() },
      { id = "outfits", label = locale("appearance.panel.outfits"),
        value = locale("appearance.panel.soon"), items = outfitsItems() },
    },
  }
end

--- Rebuild the open panel where the player is standing in it. Best-effort.
function Panel.refresh()
  if handle == nil then return end
  local mine = session
  CreateThread(function()
    if session ~= mine then return end
    local _, failure = menu("update", handle, spec())
    if failure ~= nil then Open77.log.debug("the panel was not refreshed: " .. failure) end
  end)
end

--- The transient line under the list. Best-effort: it only reports.
---@param text string
---@param ok boolean
local function status(text, ok)
  if handle == nil then return end
  local mine = session
  CreateThread(function()
    if session ~= mine then return end
    local _, failure = menu("setStatus", text, ok)
    if failure ~= nil then Open77.log.debug("the panel status line: " .. failure) end
  end)
end

-- ---------------------------------------------------------------------------
-- Opening and closing
-- ---------------------------------------------------------------------------

--- Forget the open panel and say so. Answers the menu handle still to be taken down, which
--- the caller closes from a coroutine.
---@param reason AppearancePanelReason
---@return integer|nil  the menu handle still to be taken down
local function takeDown(reason)
  if owner == nil then return nil end
  local open = handle
  session = session + 1
  owner, ownerGeneration, handle = nil, nil, nil
  Runtime.publish({ ok = true, event = "panelClosed", citizenId = State.citizenId,
                    reason = reason })
  return open
end

--- Take a list down through opx77_menu. Coroutine only.
---@param open integer|nil
local function closeMenu(open)
  if open == nil then return end
  local _, failure = menu("close", open)
  if failure ~= nil then Open77.log.debug("the panel was already down: " .. failure) end
end

--- Take the panel down, for a reason of this resource's own.
---@param reason AppearancePanelReason
function Panel.close(reason)
  local open = takeDown(reason)
  if open == nil then return end
  CreateThread(function() closeMenu(open) end)
end

--- opx77_menu took the list down by itself: Escape, BACK at the root, or a sweep of its own.
---@param reason string|nil
local function menuClosed(reason)
  if owner == nil then return end
  session = session + 1
  owner, ownerGeneration, handle = nil, nil, nil
  Runtime.publish({ ok = true, event = "panelClosed", citizenId = State.citizenId,
                    reason = CLOSED_BY_PLAYER[reason] and "player" or "menu_closed" })
end

--- One pass while the panel is up. Answers false once the panel has gone.
---@param atMs integer
---@return boolean
local function tick(atMs)
  if owner == nil then return false end

  -- Cyberpunk's own mirror is the only face editor there is, and a list left drawn over it
  -- takes the arrow keys away from it.
  if nativeUp() then
    Panel.close("appearance_busy")
    return false
  end

  if atMs < nextSweepMs then return true end
  nextSweepMs = atMs + OWNER_SWEEP_MS
  if GetResourceState(owner) ~= "running" then
    Panel.close("owner_stopped")
    return false
  end
  if ownerGeneration ~= nil and type(Open77.resource) == "table" and
    type(Open77.resource.generation) == "function" then
    local generation = Open77.resource.generation(owner)
    if generation ~= nil and generation ~= ownerGeneration then
      Panel.close("owner_reloaded")
      return false
    end
  end
  return true
end

--- Watch one open panel, and end with it. A raise from a host call would otherwise end this
--- loop for the session, so it is logged once per run of failures and the loop carries on.
---@param mine integer
local function watch(mine)
  local failing = false
  while session == mine do
    Wait(WATCH_MS)
    if session ~= mine then return end
    local ok, alive = pcall(tick, Runtime.nowMs())
    if not ok then
      if not failing then Open77.log.error("the appearance panel: " .. tostring(alive)) end
      failing = true
    else
      failing = false
      if not alive then return end
    end
  end
end

--- Put the panel up for one caller. `ok = true` means asked: the list opens on a thread.
---@param callerName string
---@param generation integer|nil
---@return AppearanceQueued
function Panel.open(callerName, generation)
  local ready, why = available()
  if not ready then return { ok = false, error = why } end

  -- already yours: there is no level a caller can ask for, so a reopen is a redraw
  if isOpen() then
    Panel.refresh()
    return { ok = true, queued = true, citizenId = State.citizenId }
  end

  session = session + 1
  local mine = session
  owner, ownerGeneration, handle = callerName, generation, nil
  nextSweepMs = 0
  CreateThread(function()
    local opened, failure = menu("open", spec())
    if session ~= mine then
      if opened ~= nil then closeMenu(opened.handle) end
      return
    end
    if opened == nil then
      owner, ownerGeneration = nil, nil
      Open77.log.warn("the appearance panel did not open: " .. tostring(failure))
      return
    end
    handle = opened.handle
    Runtime.publish({ ok = true, event = "panelOpened", citizenId = State.citizenId })
    watch(mine)
  end)
  return { ok = true, queued = true, citizenId = State.citizenId }
end

-- ---------------------------------------------------------------------------
-- What the rows do
-- ---------------------------------------------------------------------------

--- Open Cyberpunk's own mirror. The panel is taken down and opx77_menu has answered the
--- close BEFORE the modal is asked for: a list left up drives the arrow keys under it.
---@param mode AppearanceMode
local function openNative(mode)
  local open = takeDown("caller")
  CreateThread(function()
    closeMenu(open)
    local ok, reason = Editor.open(mode)
    if ok then return end
    Runtime.notify("error", "appearance.editorUnavailable", { reason = tostring(reason) })
  end)
end

--- Put the stored face back on the puppet. Refused while it is already worn: applying a face
--- the puppet wears arms a native watchdog with nothing to open for.
local function wearStored()
  if type(State.canonical) ~= "table" then
    return status(locale("appearance.panel.noLook"), false)
  end
  if not Snapshot.buildAccepted(State.canonical.gameBuild) then
    return status(locale("appearance.buildMismatch"), false)
  end
  if State.wearing() then
    return status(locale("appearance.panel.alreadyWorn"), true)
  end
  if State.commit ~= nil or nativeUp() then
    return status(locale("appearance.panel.busy"), false)
  end

  -- read before the yield: a character change during the apply is a different face
  local snapshot, citizen = State.canonical, State.citizenId
  status(locale("appearance.panel.wearing"), true)
  CreateThread(function()
    local ok, failure = Runtime.applySnapshot(snapshot, 8, nil)
    if State.citizenId ~= citizen or State.canonical ~= snapshot then return end
    if ok then State.wore() end
    Runtime.publish({ ok = ok, event = "applied", citizenId = citizen,
                      error = (not ok) and tostring(failure) or nil })
    if ok then
      status(locale("appearance.panel.wornNow"), true)
    else
      status(locale("appearance.restoreFailed", { reason = tostring(failure) }), false)
    end
  end)
end

--- A row of this resource's own panel. The close is matched on the owner rather than the
--- handle: opx77_menu can take a list down before its `open` export has answered.
AddEventHandler(EVENT, function(payload)
  if type(payload) ~= "table" or payload.menu ~= MENU_ID then return end
  if payload.owner ~= RESOURCE then return end
  if payload.action == "close" then return menuClosed(payload.reason) end
  if payload.action ~= "select" or payload.handle ~= handle then return end
  local id = payload.itemId
  if id == "wear" then return wearStored() end
  if id == "editFace" then return openNative("ripperdoc") end
  if id == "editHair" then return openNative("hairdresser") end
end)

--- The panel draws one character's face, so it follows every decision about it.
AddEventHandler(Config.EVENT, function(payload)
  if owner == nil or type(payload) ~= "table" then return end
  local name = payload.event
  if name == "characterChanged" then return Panel.close("character_changed") end
  if name == "saved" or name == "restored" or name == "applied" then Panel.refresh() end
end)

AddEventHandler("opx77:client:onPlayerUnloaded", function()
  Panel.close("no_character")
end)
