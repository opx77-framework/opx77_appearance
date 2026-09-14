--- The client half: the link to opx77_core, the bootstrap, and the restore.

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

--- How often the join-time bootstrap looks at opx77_core's roster, in ms. A read of what the
--- core already holds, never a request: the core cools those at 2000 ms and drops the excess.
local ROSTER_POLL_MS = 250

--- The shipped `BOOTSTRAP` values, for a config that lost them.
local ROSTER_WAIT_MS = 3000
local DEFAULT_FAMILY = "female"

--- The shipped `BODY_RELOAD_SETTLE_MS`, for a config that lost it.
local RELOAD_SETTLE_MS = 10000

--- The life phases a native modal may go up in: the ones the platform's own fitting room hands
--- the player to the native editor from.
local LIFE_OPEN = { alive = true, recovering = true }

--- The scheduler clock in milliseconds; `monotonic` answers SECONDS. A non-finite reading is
--- dropped rather than propagated: a NaN would expire nothing, an infinity everything.
---@return integer
local lastMs = 0
local function nowMs()
  local read, seconds = pcall(Open77.time.monotonic)
  if read and type(seconds) == "number" and seconds == seconds and
    seconds >= 0 and seconds < math.huge then
    lastMs = math.floor(seconds * 1000)
  end
  return lastMs
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
--- true for the pre-game menu's puppet and for the one behind the "continue" screen.
---@return boolean
local function inGameplay()
  local ok, character = pcall(Open77.character.state)
  return ok and type(character) == "table" and character.attached == true and
    character.alive == true and (tonumber(character.health) or 0) > 0
end
Runtime.inGameplay = inGameplay

--- The host's character bootstrap phase, or "unreadable".
---@return string
local function bootstrapPhase()
  local ok, bootstrap = pcall(Open77.session.characterBootstrap)
  return ok and type(bootstrap) == "table" and tostring(bootstrap.phase) or "unreadable"
end
Runtime.bootstrapPhase = bootstrapPhase

--- The host's word on this world entry's pristine player reset -- "complete" once it has run --
--- or nil where the host projects none. Read live: it goes back to "complete" only when a reset
--- finishes, while `open77:playerReset:complete` can be missed by a reload.
---@return string|nil
local function playerResetPhase()
  local ok, bootstrap = pcall(Open77.session.characterBootstrap)
  if not ok or type(bootstrap) ~= "table" or bootstrap.playerReset == nil then return nil end
  return tostring(bootstrap.playerReset)
end
Runtime.playerResetPhase = playerResetPhase

--- Said once, when this client cannot read its own life state at all.
local lifeUnreadable = false

--- The local player's life phase; false while the player has none, which is the case behind
--- the "continue" screen; nil when this client cannot read it, which gates nothing.
---@return string|false|nil
local function lifePhase()
  if lifeUnreadable then return nil end
  local players = Open77.players
  local called, life, reason = false, nil, "Open77.players.getLifeState is not on this client"
  if type(players) == "table" and type(players.getLifeState) == "function" then
    called, life, reason = pcall(players.getLifeState)
  end
  if called and type(life) == "table" then return tostring(life.phase) end
  if called and not tostring(reason or ""):find("permission", 1, true) then return false end
  lifeUnreadable = true
  Open77.log.warn(("the life state cannot be read (%s): faces go on without waiting for it")
    :format(tostring(called and reason or life or reason)))
  return nil
end
Runtime.lifePhase = lifePhase

--- `BODY_RELOAD_SETTLE_MS`, or the shipped value for one that is not a finite number of ms.
---@return number
local function reloadSettleMs()
  local wait = tonumber(Config.BODY_RELOAD_SETTLE_MS)
  if wait == nil or wait ~= wait or wait < 0 or wait >= math.huge then return RELOAD_SETTLE_MS end
  return wait
end

--- Whether a face or a native modal may go on the puppet now: the gameplay world, not a body
--- that is about to be replaced by a reload, a player past the "continue" screen whose pristine
--- reset has run, and -- after a reload -- the respawn the platform replays onto the new puppet
--- over. The same conditions the platform's fitting room waits on before the native editor.
---@return boolean
function Runtime.faceable()
  if not State.worldEligible or State.bodyReloading or not inGameplay() then return false end
  local reset = playerResetPhase()
  if reset ~= nil and reset ~= "complete" then return false end
  local life = lifePhase()
  if life == false or (life ~= nil and not LIFE_OPEN[life]) then return false end
  if State.reloadSettleUntilMs ~= 0 then
    -- The editor the game never consumed was asked for during the reset, with that respawn
    -- about to start; which of the two it minded is not known, so both are waited out. Capped:
    -- a phase that never reads "alive" costs a wait, not a player.
    if life ~= nil and life ~= "alive" and nowMs() < State.reloadSettleUntilMs then
      return false
    end
    State.reloadSettleUntilMs = 0
  end
  return true
end

--- Decide whether this world is the gameplay one or the pre-game menu, from the bootstrap
--- phase. Called from the world-entry events only, because polling would read `ready` too early.
--- It does not end a body reload: a reload attaches the world twice, first for the covered
--- return to the menu and then for the target save, and both read `ready`.
---@param reason string
local function markWorldEligibility(reason)
  local phase = bootstrapPhase()
  State.worldEligible = phase == "ready"
  Open77.log.debug(("world entry (%s): bootstrap phase=%s -> %s"):format(reason, phase,
    State.worldEligible and "gameplay world" or "menu, not announcing"))
end
Runtime.markWorldEligibility = markWorldEligibility

--- Release the native mutation transaction. Opening the restoration mirror while a commit is
--- still pending always answers `appearance_editor_busy`.
function Runtime.finishMutation()
  local ok, reason = Open77.appearance.finishCommit()
  if not ok then Open77.log.debug("finishCommit: " .. tostring(reason)) end
end

-- ---------------------------------------------------------------------------
-- The body family
-- ---------------------------------------------------------------------------

--- The body family the puppet is on: the engine's word, else the one this client last loaded,
--- else the one the bootstrap resolved. `captureBody` can answer nothing -- before the gameplay
--- puppet's reset, on some builds at all -- and a restart of this resource forgets what it
--- loaded: without the bootstrap's word the body would read unknown and be reloaded for nothing.
---@return string|nil
function Runtime.bodyFamily()
  local read, body = pcall(Open77.appearance.captureBody)
  if read and type(body) == "table" and Snapshot.isFamily(body.family) then
    return body.family
  end
  if State.bodyFamily ~= nil then return State.bodyFamily end
  local ok, bootstrap = pcall(Open77.session.characterBootstrap)
  if ok and type(bootstrap) == "table" and bootstrap.phase == "ready" and
    Snapshot.isFamily(bootstrap.family) then
    return bootstrap.family
  end
  return nil
end

--- Ask the engine to reload the player on `family`. Only a reload shows the other body, and the
--- world entry that follows it comes back through `resolveCharacter` on the new puppet.
---@param family string
---@param edit boolean  the reload is for an editor, reopened from `takeBodyFamilyTransition`
---@return "switching"|"active"|nil outcome, string|nil reason
function Runtime.switchBody(family, edit)
  local called, switched, reason = pcall(Open77.appearance.switchBodyFamily, family, edit)
  if not called then return nil, tostring(switched) end
  if switched then
    State.bodyFamily = family
    State.bodyReloading = true
    State.reloadResetSeen = false
    State.reloadSettleUntilMs = 0
    -- the reload brings a pristine puppet: nothing this client put on the old one survives
    State.undress()
    -- and observers drop their proxy of the old body until the new one is published
    if OpxAppearance.presence then OpxAppearance.presence.withdraw() end
    Open77.log.info(("the %s body is reloading (%s)"):format(family,
      edit and "an editor reopens after it" or "for the character"))
    return "switching"
  end
  if tostring(reason) == "body_family_already_active" then
    State.bodyFamily = family
    return "active"
  end
  return nil, tostring(reason or "body_family_switch_failed")
end

--- The body reload has put its new puppet through its pristine reset: from here the world
--- entry is the character's, and its face is decided again on the body it now has. A reload
--- that failed before reaching a world is ended by `takeBodyFamilyTransition` instead.
---@param origin string
function Runtime.finishReload(origin)
  if not State.bodyReloading then return end
  State.bodyReloading = false
  State.reloadResetSeen = false
  State.reloadSettleUntilMs = nowMs() + reloadSettleMs()
  Open77.log.info(("the body reload reached its new puppet (%s)"):format(origin))
  State.enterWorld()
  State.playerResetDone = true
  markWorldEligibility(origin)
  Runtime.resolveCharacter("body_reload")
end

--- Follow a reload through the host's reset projection, for a reload whose
--- `open77:playerReset:complete` never reaches this resource. The projection still reads the
--- old puppet's "complete" right after the switch, so only a return to it counts.
function Runtime.watchReload()
  if not State.bodyReloading then return end
  local reset = playerResetPhase()
  if reset == nil then return end
  if reset ~= "complete" then
    State.reloadResetSeen = true
  elseif State.reloadResetSeen then
    Runtime.finishReload("reset_projection")
  end
end

--- One reload onto the live character's own body family, counted against `FAMILY_RETRIES`.
---@return boolean reloading  true when the reload went out and the caller has to stop
local function reloadOntoFamily()
  if not Snapshot.isFamily(State.family) then return false end
  if State.familyAttempts >= Config.FAMILY_RETRIES then
    -- only said when the engine or this client knows the body is the other one
    if Runtime.bodyFamily() ~= nil then
      Runtime.notify("error", "appearance.bodyLoadFailed", { reason = "body_family_retries" })
    end
    return false
  end
  local outcome, reason = Runtime.switchBody(State.family, false)
  if outcome == "switching" then
    State.familyAttempts = State.familyAttempts + 1
    Runtime.notify("info", "appearance.bodySwitching")
    return true
  end
  if outcome == nil then
    Runtime.notify("error", "appearance.bodyLoadFailed", { reason = tostring(reason) })
  end
  return false
end

--- Put the puppet on `charInfo.gender` before a face goes on it. The bootstrap loaded the body
--- of the last character played, and the one selected need not be that one.
---@return boolean proceed  false when a reload went out
local function ensureFamily()
  if not Snapshot.isFamily(State.family) or Runtime.bodyFamily() == State.family then
    return true
  end
  return not reloadOntoFamily()
end

-- ---------------------------------------------------------------------------
-- The announcement
-- ---------------------------------------------------------------------------

--- Announce that this player is really in the world, at most once per world entry. It is the
--- only signal that clears the platform's `__platform` readiness hold, and it is only ever sent
--- for a loaded character: `appearanceSettled` is false while none is.
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

--- Wait for a puppet a face may go on. Coroutine only. No time limit -- this waits for a human
--- to press a key -- but it says one line after a minute.
---@param token integer
---@param label string
---@return boolean current  false when the generation was superseded meanwhile
local function awaitWorld(token, label)
  -- BOTH conditions: the menu puppet also answers attached, alive and health 100.
  local waitedFrom, said = nowMs(), false
  while not Runtime.faceable() do
    if not State.current(token) then return false end
    if not said and nowMs() - waitedFrom > 60000 then
      said = true
      Open77.log.warn(("%s token=%d is still waiting: eligible=%s reloading=%s gameplay=%s " ..
        "reset=%s life=%s"):format(label, token, tostring(State.worldEligible),
          tostring(State.bodyReloading), tostring(inGameplay()), tostring(playerResetPhase()),
          tostring(lifePhase())))
    end
    Wait(WATCH_MS)
  end
  return State.current(token)
end

--- One restore of the stored face, end to end: take the token, honour the redundant-restore
--- guard, wait for the gameplay world, put the character's body on, apply, settle the flags.
---@param snapshot table
---@param citizen string|nil
---@param origin string
function Runtime.beginRestore(snapshot, citizen, origin)
  State.adopt(snapshot, citizen)
  local token = State.nextRestore()

  -- Applying a face the puppet already wears arms a native watchdog with nothing to wait for
  -- and ends in a user-facing error on a correct face. A body reload undresses the puppet, so
  -- a face worn here is worn on the right body.
  if State.wearing() then
    State.restoreSettledToken = token
    Open77.log.debug(("restore skipped for %s: already worn"):format(tostring(State.citizenId)))
    return
  end

  Open77.log.debug(("restore token=%d origin=%s"):format(token, origin))

  CreateThread(function()
    if not awaitWorld(token, "restore") then return end
    -- a reload went out: the world entry it causes starts the next restore
    if not ensureFamily() then return end

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
    -- The engine could not tell the body apart before the apply. `bodyReloading` holds the
    -- announcement until the reload has entered the world and come back around.
    if tostring(reason) == "body_gender_switch_requires_reload" and reloadOntoFamily() then
      return
    end

    Runtime.publish({ ok = false, event = "restored", error = tostring(reason),
                      citizenId = State.citizenId })
    Runtime.notify("error", "appearance.restoreFailed", { reason = tostring(reason) })
    Runtime.announce()
  end)
end

--- Settle a world entry with no face to put on: the character's own body, on the default face.
--- It takes a restore generation, so the announcement waits on the body as it would on a face.
---@param origin string
function Runtime.beginPristine(origin)
  local token = State.nextRestore()
  Open77.log.debug(("pristine token=%d origin=%s"):format(token, origin))
  CreateThread(function()
    if not awaitWorld(token, "pristine") then return end
    if not ensureFamily() then return end
    State.restoreSettledToken = token
    Runtime.announce()
  end)
end

-- ---------------------------------------------------------------------------
-- The bootstrap, and what this character's face turns out to be
-- ---------------------------------------------------------------------------

--- Spend the one-shot character bootstrap on a body family. A second call for the same entry
--- is normal and does nothing.
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
  State.bodyFamily = family
  Open77.log.info(("character bootstrap resolved as %s"):format(family))
  return true
end

--- The roster opx77_core last broadcast, as `charactersReady` carried it. nil until one does.
---@type table|nil
local rosterSeen = nil

AddEventHandler("opx77:client:charactersReady", function(roster)
  if type(roster) == "table" and type(roster.list) == "table" then rosterSeen = roster.list end
end)

--- The roster opx77_core already holds, or nil while it holds none. Coroutine only. The
--- dispatch is guarded and the await is not: a yield is not safe under a pcall.
---@return table|nil
local function heldRoster()
  if rosterSeen ~= nil then return rosterSeen end
  if GetResourceState(CORE) ~= "running" then return nil end
  local dispatched, promise = pcall(Open77.exports.call, CORE, "GetCharacters")
  if not dispatched or not promise then return nil end
  local result, callError = promise:await()
  if callError or type(result) ~= "table" or type(result.characters) ~= "table" then
    return nil
  end
  -- the core's empty mirror answers no character and no slot; an account that has none still
  -- has a slot to put one in
  if #result.characters == 0 and (tonumber(result.slots) or 0) <= 0 then return nil end
  return result.characters
end

--- The body family of the most recently played character in a roster, or nil when none has
--- been played.
---@param characters table  CharacterSummary[]
---@return string|nil
local function lastPlayedFamily(characters)
  local family, latest
  for index = 1, #characters do
    local summary = characters[index]
    local at = type(summary) == "table" and summary.lastLoggedOut or nil
    if at ~= nil and Snapshot.isFamily(summary.gender) then
      -- the core sends the roster most recently played first; this only guards that order,
      -- and only between two stamps of one comparable type
      local comparable = type(at) == type(latest) and
        (type(at) == "string" or type(at) == "number")
      if latest == nil or (comparable and at > latest) then
        family, latest = summary.gender, at
      end
    end
  end
  return family
end

--- `BOOTSTRAP.DEFAULT_FAMILY`, or "female" with one line saying why.
---@return string
local function defaultFamily()
  local bootstrap = type(Config.BOOTSTRAP) == "table" and Config.BOOTSTRAP or {}
  if Snapshot.isFamily(bootstrap.DEFAULT_FAMILY) then return bootstrap.DEFAULT_FAMILY end
  Open77.log.warn(("BOOTSTRAP.DEFAULT_FAMILY %s is not \"female\" or \"male\"; loading %q")
    :format(tostring(bootstrap.DEFAULT_FAMILY), DEFAULT_FAMILY))
  return DEFAULT_FAMILY
end

--- `BOOTSTRAP.ROSTER_WAIT_MS`, or the shipped value for one that is not a finite, positive
--- number of milliseconds.
---@return number
local function rosterWaitMs()
  local bootstrap = type(Config.BOOTSTRAP) == "table" and Config.BOOTSTRAP or {}
  local wait = tonumber(bootstrap.ROSTER_WAIT_MS)
  if wait == nil or wait ~= wait or wait < 0 or wait >= math.huge then
    Open77.log.warn(("BOOTSTRAP.ROSTER_WAIT_MS %s is not a number of ms; waiting %d")
      :format(tostring(bootstrap.ROSTER_WAIT_MS), ROSTER_WAIT_MS))
    return ROSTER_WAIT_MS
  end
  return wait
end

--- Spend the bootstrap at join, before any character is chosen: the shell keeps its cover up,
--- and every OPX//77 surface under it, until it is. Selection happens in the world afterwards.
--- Once per connection; a second world entry while it runs does nothing.
---@param origin string
function Runtime.beginBootstrap(origin)
  if State.bootstrapResolved or State.bootstrapPicking then return end
  if bootstrapPhase() ~= "waiting" then return end
  State.bootstrapPicking = true

  CreateThread(function()
    local deadline = nowMs() + rosterWaitMs()
    local roster
    while roster == nil and nowMs() < deadline do
      if State.bootstrapResolved or bootstrapPhase() ~= "waiting" then break end
      roster = heldRoster()
      if roster == nil then Wait(ROSTER_POLL_MS) end
    end
    State.bootstrapPicking = false
    if State.bootstrapResolved or bootstrapPhase() ~= "waiting" then return end

    local family = roster ~= nil and lastPlayedFamily(roster) or nil
    local why = family ~= nil and "the last character played" or
      (roster ~= nil and "no character played yet" or "no roster in time")
    family = family or defaultFamily()
    Open77.log.info(("bootstrap (%s): loading the %s body, %s"):format(origin, family, why))
    Runtime.resolveBootstrap(family)
  end)
end

--- Decide what happens to the live character's face on this world entry: restore the stored
--- one, publish `needsCreation` and wait, or settle on the default face. This resource never
--- opens an editor on its own.
---@param origin string
function Runtime.resolveCharacter(origin)
  if State.citizenId == nil then return end
  local stored = State.canonical

  -- Spent at join as a rule. A character loaded before that has the best claim on the body; one
  -- whose family is unreadable leaves it to the join-time pick rather than failing it.
  if Snapshot.isFamily(State.family) then Runtime.resolveBootstrap(State.family) end
  State.settled = true

  if type(stored) == "table" and not Snapshot.buildAccepted(stored.gameBuild) then
    Runtime.publish({ ok = false, event = "settled", error = "stored_build_mismatch",
                      citizenId = State.citizenId })
    if not State.buildWarned then
      State.buildWarned = true
      Runtime.notify("warning", "appearance.buildMismatch")
    end
    Runtime.beginPristine(origin)
    return
  end

  if type(stored) == "table" then
    State.restoreAttempts = 0
    Runtime.beginRestore(stored, nil, origin)
    return
  end

  -- A creation already running owns this world entry: it is the reload its editor asked for,
  -- and `takeBodyFamilyTransition` reopens the editor.
  if State.creating then return end
  -- already asked and not yet answered: once is enough
  if State.creationAskedAtMs ~= 0 then return end

  if not State.creationRefused and not State.creationWarned then
    State.creationAskedAtMs = nowMs()
    Runtime.publish({ ok = true, event = "needsCreation", citizenId = State.citizenId,
                      family = State.family })
    return
  end

  Runtime.beginPristine(origin)
end

--- Says so, once, when nobody answered `needsCreation`, and lets the player in on the default
--- face rather than holding the readiness gate for a creator that is not coming.
function Runtime.warnUnanswered()
  if State.creationAskedAtMs == 0 or State.creating or State.creationWarned then return end
  if Runtime.nowMs() - State.creationAskedAtMs < Config.CREATION_WAIT_MS then return end
  State.creationWarned = true
  State.creationAskedAtMs = 0
  Open77.log.warn(("%s has no stored face and nothing called the `openCreator` export")
    :format(tostring(State.citizenId)))
  Open77.log.warn("  the player enters on the default face; a character creator resource is")
  Open77.log.warn("  what opens the editor. See README, \"Who opens the creator\".")
  Runtime.beginPristine("creation_unanswered")
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
  -- The only world entry of a body reload a face may go on: the covered return to the menu
  -- attaches a world as well, and its puppet never gets a reset.
  Runtime.finishReload("playerReset")
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

  -- A different character is a different face, and the bootstrap has already been spent, so
  -- everything about the previous character goes -- including a restore still on its way.
  local switching = State.citizenId ~= nil
  State.citizenId = citizen
  State.family = type(playerData.charInfo) == "table" and playerData.charInfo.gender or nil
  State.canonical = type(playerData.appearance) == "table" and playerData.appearance or nil
  State.settled = false
  State.creationRefused = false
  State.creationAskedAtMs = 0
  State.creationWarned = false
  State.familyAttempts = 0
  State.buildWarned = false
  State.undress()
  State.restoreSettledToken = State.nextRestore()
  -- what it wears travels in the same PlayerData, and goes on after its face
  if OpxAppearance.clothing then OpxAppearance.clothing.adopt(playerData) end
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
  if OpxAppearance.clothing then OpxAppearance.clothing.unload() end
end)

--- Catch up with a character that was already loaded. A resource reload mid-session misses
--- every emission above, and there is no replay.
local function catchUp()
  CreateThread(function()
    local result, failure = Runtime.call(CORE, "GetPlayerData")
    if result == nil then return Open77.log.debug("catch-up: " .. tostring(failure)) end
    adoptCharacter(result.data, "catchUp")
  end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

AddEventHandler("open77:worldReady", function()
  State.enterWorld()
  markWorldEligibility("worldReady")
  -- the pre-game menu world raises this too, with the bootstrap still waiting on this resource
  Runtime.beginBootstrap("worldReady")
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
  -- here. The same phase test keeps a start landing in the MENU from announcing.
  State.enterWorld()
  markWorldEligibility("resourceStart")
  Runtime.beginBootstrap("resourceStart")
  catchUp()

  CreateThread(function()
    while true do
      Wait(WATCH_MS)
      -- a raise from a host call would end this loop for the session, and this loop is what
      -- ends a reload and clears the platform's readiness hold
      local watched, reason = pcall(Runtime.watchReload)
      if not watched then Open77.log.error("reload watch: " .. tostring(reason)) end
      local ok, failure = pcall(Runtime.announce)
      if not ok then Open77.log.error("announce worker: " .. tostring(failure)) end
    end
  end)
end)

AddEventHandler("onClientResourceStop", function(name)
  if name ~= RESOURCE then return end
  Runtime.finishMutation()
end)
