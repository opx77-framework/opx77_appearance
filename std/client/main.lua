---@meta

OpxAppearance.Runtime = {}

--- The scheduler clock in milliseconds, from `Open77.time.monotonic` (seconds). A non-finite
--- reading keeps the last finite one.
---@type fun(): integer
OpxAppearance.Runtime.NowMs = nil

--- A configured duration in milliseconds when it is a finite, non-negative number (numeric strings
--- included); nil otherwise, for the caller to fall back to its shipped value.
---@param value any
---@return number|nil
function OpxAppearance.Runtime.ConfigMs(value) end

--- Whether the local puppet is attached, alive and above zero health.
---@type fun(): boolean
OpxAppearance.Runtime.InGameplay = nil

--- The host's pristine player reset phase (`"complete"` once run), nil where none is projected.
---@type fun(): string|nil
OpxAppearance.Runtime.PlayerResetPhase = nil

--- The local life phase; false while the player has none, nil when this client cannot read it.
---@type fun(): string|false|nil
OpxAppearance.Runtime.LifePhase = nil

--- Judges from the bootstrap phase whether this world is the gameplay one. World-entry events only.
---@type fun(reason: string)
OpxAppearance.Runtime.MarkWorldEligibility = nil

--- Applies `snapshot`, retrying transient refusals every 400 ms up to `attempts`, and stops when
--- `token` is superseded. Coroutine only.
---@type fun(snapshot: table, attempts: integer, token: integer|nil): boolean, string|nil
OpxAppearance.Runtime.ApplySnapshot = nil

--- Raises `payload` on `OPX_APPEARANCE_CONFIG.EVENT`.
---@param payload AppearanceEvent
function OpxAppearance.Runtime.Publish(payload) end

--- Calls another resource's client export. Coroutine only. Answers the result, or nil and why:
--- not running, not dispatched, a call error, a malformed answer, or the refusal's code.
---@param resource string
---@param name string
---@return table|nil result
---@return string|nil failure
function OpxAppearance.Runtime.Call(resource, name, ...) end

--- Logs a toast and raises it through opx77_notify when `NOTIFY` is true and it runs.
---@param kind "info"|"success"|"warning"|"error"
---@param key string a locale key
---@param params table<string, string|number>|nil
function OpxAppearance.Runtime.Notify(kind, key, params) end

--- The player-facing name of a body family.
---@param family any
---@return string
function OpxAppearance.Runtime.FamilyText(family) end

--- Whether a face or a native modal may go on the puppet now: gameplay world, no reload, reset
--- complete, a life phase that allows it, and the respawn after a reload over or timed out.
---@return boolean
function OpxAppearance.Runtime.Faceable() end

--- Whether a native appearance modal is on screen. A raise from `Open77.appearance.isOpen` counts
--- as on screen: drawing over the mirror, or dressing under it, costs the player more than waiting.
---@return boolean
function OpxAppearance.Runtime.ModalOnScreen() end

--- Releases the native appearance mutation transaction.
function OpxAppearance.Runtime.FinishMutation() end

--- The body family the puppet is on: the engine's word, else the one this client last loaded,
--- else the one the bootstrap resolved.
---@return BodyFamily|nil
function OpxAppearance.Runtime.BodyFamily() end

--- Asks the engine to reload the player on `family`.
---@param family BodyFamily
---@param edit boolean the reload is for an editor, reopened from the transition
---@return "switching"|"active"|nil outcome
---@return string|nil reason
function OpxAppearance.Runtime.SwitchBody(family, edit) end

--- Ends a body reload once its new puppet has been reset, and decides the face again.
---@param origin string
function OpxAppearance.Runtime.FinishReload(origin) end

--- Ends a body reload whose reset event was missed, through the host's reset projection.
function OpxAppearance.Runtime.WatchReload() end

--- Sends `open77:session:gameplayReady` once per settled gameplay world entry.
---@return boolean sent
function OpxAppearance.Runtime.Announce() end

--- Restores `snapshot` on the character's body once the puppet is faceable, on its own
--- restore generation.
---@param snapshot table
---@param origin string
function OpxAppearance.Runtime.BeginRestore(snapshot, origin) end

--- Settles a world entry on the default face of the character's body, on its own generation.
---@param origin string
function OpxAppearance.Runtime.BeginPristine(origin) end

--- Spends the one-shot character bootstrap on `family`; a second call does nothing.
---@param family any
---@return boolean
function OpxAppearance.Runtime.ResolveBootstrap(family) end

--- Spends the bootstrap at join on the last played character's body, or `DEFAULT_FAMILY`.
---@param origin string
function OpxAppearance.Runtime.BeginBootstrap(origin) end

--- Restores the stored face, publishes `needsCreation`, or settles on the default face.
---@param origin string
function OpxAppearance.Runtime.ResolveCharacter(origin) end

--- Lets the player in on the default face once `needsCreation` went unanswered for
--- `CREATION_WAIT_MS`, with one log warning.
function OpxAppearance.Runtime.WarnUnanswered() end
