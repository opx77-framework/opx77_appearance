--- opx77_appearance -- the client half: the link to opx77_core, the bootstrap, and the restore.

OpxAppearance = OpxAppearance or {}

local Config = OPX_APPEARANCE_CONFIG
local Snapshot = OpxAppearance.snapshot
local State = OpxAppearance.state

local Runtime = {}
OpxAppearance.runtime = Runtime

local RESOURCE = GetCurrentResourceName()
local CORE = "opx77_core"
local NOTIFY = "opx77_notify"

--- How often the announcement worker looks at the world, in ms. It polls an engine state
--- nothing raises an event for.
local WATCH_MS = 200

---@return integer
local function nowMs()
  -- `monotonic` is in SECONDS; mixing it with the millisecond scheduler clock gives a timer
  -- that fires a thousand times too early.
  return math.floor(Open77.time.monotonic() * 1000)
end
Runtime.nowMs = nowMs

--- Tell anything that is listening what just happened, on the resource's own public channel.
---@param payload table
function Runtime.publish(payload)
  TriggerEvent(Config.EVENT, payload)
end

--- One call to another resource's client export. Coroutine only.
--- The third return is true when the target actually answered, so a refusal is authoritative.
---@param resource string
---@param name string
---@return table|nil, string|nil, boolean
function Runtime.call(resource, name, ...)
  if GetResourceState(resource) ~= "running" then return nil, "not_running", false end
  local promise, reason = Open77.exports.call(resource, name, ...)
  if not promise then return nil, tostring(reason or "not_dispatched"), false end
  local result, callError = promise:await()
  if callError then return nil, tostring(callError), false end
  if type(result) ~= "table" then return nil, "malformed_answer", true end
  if result.ok == false then return nil, tostring(result.error or "refused"), true end
  return result, nil, true
end

--- A toast, through opx77_notify. Best-effort and never a dependency: a missing or stopped
--- opx77_notify costs one logged line and changes nothing else.
---@param kind "info"|"success"|"warning"|"error"
---@param key string  a locale key; the log line stays English and carries the key
---@param params table<string, string|number>|nil
function Runtime.notify(kind, key, params)
  Open77.log.info(("notify %s: %s"):format(kind, key))
  if Config.NOTIFY ~= true then return end
  if GetResourceState(NOTIFY) ~= "running" then return end
  local message = locale(key, params)
  CreateThread(function()
    local _, failure = Runtime.call(NOTIFY, "show", {
      type = kind,
      title = "APPEARANCE",
      message = message,
    })
    if failure ~= nil then Open77.log.debug("toast refused: " .. failure) end
  end)
end

--- The player-facing name of a body family, for a message that has to say which one.
---@param family any
---@return string
function Runtime.familyText(family)
  if family == "female" then return locale("appearance.familyFemale") end
  if family == "male" then return locale("appearance.familyMale") end
  return tostring(family)
end

-- ---------------------------------------------------------------------------
-- Where the player is
-- ---------------------------------------------------------------------------

--- Whether the player is playing, rather than merely having a puppet. `attached` alone is also
--- true for the creator's preview and for the puppet behind the "continue" screen.
---@return boolean
local function inGameplay()
  local character = Open77.character.state()
  return type(character) == "table" and character.attached == true and
    character.alive == true and (tonumber(character.health) or 0) > 0
end

--- The host's character bootstrap phase, or "unreadable".
---@return string
local function bootstrapPhase()
  local ok, bootstrap = pcall(Open77.session.characterBootstrap)
  return ok and type(bootstrap) == "table" and tostring(bootstrap.phase) or "unreadable"
end

--- Decide whether this world is the gameplay one or the vanilla menu, from the bootstrap
--- phase. Called from the world-entry events only, because polling would read `ready` too early.
---@param reason string
local function markWorldEligibility(reason)
  local phase = bootstrapPhase()
  State.worldEligible = phase == "ready"
  Open77.log.debug(("world entry (%s): bootstrap phase=%s -> %s"):format(reason, phase,
    State.worldEligible and "gameplay world" or "menu, not announcing"))
end

--- Release the native mutation transaction. Opening the restoration mirror while a commit is
--- still pending always answers `appearance_editor_busy`.
function Runtime.finishMutation()
  local ok, reason = Open77.appearance.finishCommit()
  if not ok then Open77.log.debug("finishCommit: " .. tostring(reason)) end
end

-- ---------------------------------------------------------------------------
-- The announcement
-- ---------------------------------------------------------------------------

--- Announce that this player is really in the world, at most once per world entry. It is the
--- only signal that clears the platform's `__platform` readiness hold.
---@return boolean
function Runtime.announce()
  if State.gameplayAnnounced or not State.worldEligible then return false end
  if not State.appearanceSettled() or not inGameplay() then return false end
  local sent, reason = TriggerServerEvent("open77:session:gameplayReady")
  if not sent then
    Open77.log.warn("gameplay-ready not sent: " .. tostring(reason))
    return false
  end
  State.gameplayAnnounced = true
  Runtime.finishMutation()
  Runtime.publish({ ok = true, event = "gameplayReady", citizenId = State.citizenId })
  return true
end

-- ---------------------------------------------------------------------------
-- Putting a face on
-- ---------------------------------------------------------------------------

--- The failures that mean "not yet" rather than "no". Everything else is final on the first
--- answer.
local RETRYABLE = {
  options_unavailable = true,
  player_unavailable = true,
  customization_state_unavailable = true,
}

--- One snapshot onto the puppet. Coroutine only.
---@param snapshot table
---@param attempts integer
---@param token integer|nil  the restore generation, or nil for a call that owns no generation
---@return boolean, string|nil
local function applySnapshot(snapshot, attempts, token)
  if type(snapshot) ~= "table" then return false, "invalid_snapshot" end
  for attempt = 1, attempts do
    if token ~= nil and not State.current(token) then return false, "superseded" end
    local ok, reason = Open77.appearance.apply(snapshot)
    if ok then return true end
    if not RETRYABLE[tostring(reason)] or attempt >= attempts then return false, reason end
    Wait(400)
  end
  return false, "restore_timeout"
end
Runtime.applySnapshot = applySnapshot

--- One restore of the stored face, end to end: take the token, honour the redundant-restore
--- guard, wait for the gameplay world, apply, settle the bootstrap flags.
---@param snapshot table
---@param citizen string|nil
---@param origin string
function Runtime.beginRestore(snapshot, citizen, origin)
  State.adopt(snapshot, citizen)
  local token = State.nextRestore()

  -- Applying a face the puppet already wears arms a native watchdog with nothing to wait for
  -- and ends in a user-facing error on a correct face.
  if State.wearing() then
    State.restoreSettledToken = token
    Open77.log.debug(("restore skipped for %s: already worn"):format(tostring(State.citizenId)))
    return
  end

  Open77.log.debug(("restore token=%d origin=%s"):format(token, origin))

  CreateThread(function()
    -- BOTH conditions: the menu puppet also answers attached, alive and health 100. No time
    -- limit -- this waits for a human to press a key -- but it says one line after a minute.
    local waitedFrom, said = nowMs(), false
    while not (State.worldEligible and inGameplay()) do
      if not State.current(token) then return end
      if not said and nowMs() - waitedFrom > 60000 then
        said = true
        Open77.log.warn(("restore token=%d is still waiting: eligible=%s gameplay=%s"):format(
          token, tostring(State.worldEligible), tostring(inGameplay())))
      end
      Wait(WATCH_MS)
    end

    -- Twenty attempts rather than the eight a mid-session apply gets: this also has to cover
    -- the short world/menu readiness window.
    local ok, reason = applySnapshot(State.canonical, 20, token)
    if not State.current(token) then return end

    -- Settled either way: a restore that FAILED must still let the player in.
    State.restoreSettledToken = token
    if ok then
      State.wore()
      -- `apply` only queued the hidden mirror; the announcement waits for the two events that
      -- follow.
      State.bootstrapQueued = true
      Runtime.publish({ ok = true, event = "restored", citizenId = State.citizenId })
      Runtime.announce()
      return
    end

    Runtime.finishMutation()
    if tostring(reason) == "body_gender_switch_requires_reload" then
      -- Loading the matching pristine puppet is a world transition, so the restore comes back
      -- around on the next world entry.
      local switched, switchReason = Open77.appearance.switchBodyFamily(State.canonical.gender,
        false)
      if switched then
        return Runtime.notify("info", "appearance.bodySwitching")
      end
      if tostring(switchReason) ~= "body_family_already_active" then
        Runtime.notify("error", "appearance.bodyLoadFailed",
          { reason = tostring(switchReason) })
      end
      return
    end

    Runtime.publish({ ok = false, event = "restored", error = tostring(reason),
                      citizenId = State.citizenId })
    Runtime.notify("error", "appearance.restoreFailed", { reason = tostring(reason) })
  end)
end

-- ---------------------------------------------------------------------------
-- The bootstrap, and what this character's face turns out to be
-- ---------------------------------------------------------------------------

--- Spend the one-shot character bootstrap on the character's own body family. A second call
--- for the same entry is normal and does nothing.
---@param family any
---@return boolean
function Runtime.resolveBootstrap(family)
  if State.bootstrapResolved then return true end
  if bootstrapPhase() == "ready" then
    State.bootstrapResolved = true
    return true
  end
  if not Snapshot.isFamily(family) then
    Open77.session.failCharacterBootstrap("invalid_body_family")
    return false
  end
  local resolved, reason = Open77.session.resolveCharacterBootstrap(family)
  if not resolved then
    Open77.session.failCharacterBootstrap(tostring(reason or "character_bootstrap_failed"))
    Runtime.notify("error", "appearance.bootstrapFailed", { reason = tostring(reason) })
    return false
  end
  State.bootstrapResolved = true
  Open77.log.info(("character bootstrap resolved as %s"):format(family))
  return true
end

--- Decide what happens to the live character's face: restore the stored one, send the player
--- to the creator when there is none, or settle honestly when neither is possible.
---@param origin string
function Runtime.resolveCharacter(origin)
  if State.citizenId == nil then return end
  local stored = State.canonical

  if type(stored) == "table" and not Snapshot.buildAccepted(stored.gameBuild) then
    Runtime.resolveBootstrap(State.family)
    State.settled = true
    Runtime.publish({ ok = false, event = "settled", error = "stored_build_mismatch",
                      citizenId = State.citizenId })
    if not State.buildWarned then
      State.buildWarned = true
      Runtime.notify("warning", "appearance.buildMismatch")
    end
    Runtime.announce()
    return
  end

  if type(stored) == "table" then
    Runtime.resolveBootstrap(State.family)
    State.settled = true
    State.restoreAttempts = 0
    Runtime.beginRestore(stored, nil, origin)
    Runtime.announce()
    return
  end

  -- No stored face. The vanilla creator run is part of the character bootstrap, so it is only
  -- opened while that is still unspent: a reload in the gameplay world must not raise one.
  if not State.creating and not State.creationRefused and bootstrapPhase() ~= "ready" then
    State.settled = true
    OpxAppearance.editor.requireCreation()
    return
  end

  Runtime.resolveBootstrap(State.family)
  State.settled = true
  Runtime.announce()
end

-- ---------------------------------------------------------------------------
-- The native's own answers
-- ---------------------------------------------------------------------------

AddEventHandler("open77:appearance:restore_failed", function()
  Runtime.finishMutation()

  -- The abort concerns the restore the announcement waits on: retract the optimistic applied
  -- record and re-dispatch. This event only fires once the bridge is polled, so it cannot spin.
  if State.bootstrapToken == State.restoreToken and State.bootstrapQueued and
    not State.appearanceConfirmed then
    State.undress()
    State.bootstrapQueued = false
    if type(State.canonical) == "table" and State.restoreAttempts < Config.RESTORE_RETRIES then
      State.restoreAttempts = State.restoreAttempts + 1
      Open77.log.warn(("bootstrap restore aborted before confirmation; retry %d/%d"):format(
        State.restoreAttempts, Config.RESTORE_RETRIES))
      Runtime.beginRestore(State.canonical, nil, "mirror_abort")
      return
    end
    Runtime.notify("error", "appearance.mirrorUnconfirmed")
    Runtime.announce()
    return
  end

  -- Return BEFORE clearing the flags: clearing them would strand a player whose face is right.
  if State.wearing() then return end
  State.bootstrapQueued = false
  State.appearanceConfirmed = false
  Runtime.notify("error", "appearance.catalogueMismatch")
end)

AddEventHandler("open77:playerReset:complete", function()
  State.playerResetDone = true
  Runtime.announce()
end)

-- ---------------------------------------------------------------------------
-- The link to opx77_core
-- ---------------------------------------------------------------------------

--- Adopt the live character from a PlayerData payload. The citizen id, the body family
--- (`charInfo.gender`, which this resource never changes) and the stored face all travel in it.
---@param playerData table|nil
---@param origin string
local function adoptCharacter(playerData, origin)
  if type(playerData) ~= "table" then return end
  local citizen = playerData.citizenId
  if type(citizen) ~= "string" or citizen == "" then return end
  if citizen == State.citizenId then return end

  -- A different character is a different face, and the bootstrap has already been spent on the
  -- first one, so everything about the previous character goes.
  local switching = State.citizenId ~= nil
  State.citizenId = citizen
  State.family = type(playerData.charInfo) == "table" and playerData.charInfo.gender or nil
  State.canonical = type(playerData.appearance) == "table" and playerData.appearance or nil
  State.settled = false
  State.creationRefused = false
  State.familyAttempts = 0
  State.buildWarned = false
  State.undress()
  if switching then
    Open77.log.info(("live character is now %s"):format(citizen))
    Runtime.publish({ ok = true, event = "characterChanged", citizenId = citizen })
  end
  Runtime.resolveCharacter(origin)
end

AddEventHandler("opx77:client:onPlayerLoaded", function(playerData)
  adoptCharacter(playerData, "playerLoaded")
end)

AddEventHandler("opx77:client:playerDataChanged", function(playerData)
  -- Money and jobs move through this event constantly; `adoptCharacter` returns immediately
  -- when the citizen id has not changed.
  adoptCharacter(playerData, "playerDataChanged")
end)

AddEventHandler("opx77:client:onPlayerUnloaded", function()
  State.unload()
end)

--- Catch up with a character that was already loaded. A resource reload mid-session misses
--- every emission above, and there is no replay.
local function catchUp()
  CreateThread(function()
    local result = Runtime.call(CORE, "GetPlayerData")
    if result ~= nil then adoptCharacter(result.data, "catchUp") end
  end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

AddEventHandler("open77:worldReady", function()
  State.enterWorld()
  markWorldEligibility("worldReady")
  Runtime.resolveCharacter("worldReady")
end)

AddEventHandler("onClientResourceStart", function(name)
  if name ~= RESOURCE then return end
  if type(Open77.appearance) ~= "table" or type(Open77.session) ~= "table" or
    type(Open77.character) ~= "table" then
    Open77.log.error("native appearance API unavailable; no face will be stored or restored")
    return
  end
  -- No `worldReady` follows a republish into a live world, so eligibility is re-established
  -- here. The same phase test keeps a reload landing in the MENU from announcing.
  State.enterWorld()
  markWorldEligibility("resourceStart")
  catchUp()

  CreateThread(function()
    while true do
      Wait(WATCH_MS)
      Runtime.announce()
    end
  end)
end)

AddEventHandler("onClientResourceStop", function(name)
  if name ~= RESOURCE then return end
  Runtime.finishMutation()
end)
