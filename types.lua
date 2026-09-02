---@meta
--- Type annotations for opx77_appearance. Never loaded at runtime.

---@alias CitizenId string
---| # opx77_core's character id, "H7K-M4X3". The character this resource is dressing.

---@alias BodyFamily "female"|"male"
---| # opx77_core's `charInfo.gender`, and the engine's two pristine puppets. The core owns it.

---@alias AppearanceMode "ripperdoc"|"hairdresser"

--- Why something was refused. Codes from this resource are hints; the core sends six locale
--- keys, all of which this resource's catalogue carries.
---@alias AppearanceError
---| "export_call_required" no invoking resource, so the call came from inside      (client)
---| "no_character"         opx77_core has no character loaded here                 (client)
---| "appearance_busy"      an editor or a creator is already on screen             (client)
---| "character_creation_in_progress" the character is still being built            (client)
---| "invalid_mode"         not "ripperdoc" or "hairdresser"                        (client)
---| "not_sent"             the net event was not accepted                          (client)
---| "save_timeout"         opx77_core never answered a captured face               (client)
---| "invalid_snapshot"     the native capture is not a snapshot                    (client)
---| "invalid_option"       an entry of the option list is not a table              (client)
---| "invalid_option_name"  an option name is not a string                          (client)
---| "stored_build_mismatch" the stored face is from another game build             (client)
---| "body_family_mismatch" the creator came back on the other body                 (client)
---| "character_bootstrap_failed" the host would not load a world for this body     (client)
---| "appearance.invalid"   opx77_core could not read the snapshot                    (core)
---| "appearance.tooLarge"  the JSON document is over the core's limit                (core)
---| "error.badRequest"     the payload was not a table                               (core)
---| "error.notLoggedIn"    no character loaded on the core for this connection       (core)
---| "error.tooFast"        two saves inside the core's 2000 ms cooldown              (core)
---| "error.unavailable"    the core's storage layer refused the write                (core)

--- One logical customization option: a position in the catalogue, not a mesh.
---@class AppearanceOption
---@field part "head"|"body"|"arms"
---@field name string    an opaque 64-bit catalogue hash, "0x…16 hex", lower-cased
---@field value integer  the chosen index, 0-based
---@field choices integer  how many that option has; 0 means the engine reported none

--- A whole face, in the form opx77_core stores and this resource sends.
---@class AppearanceSnapshot
---@field schemaVersion integer  always 1
---@field gameBuild string       the build it was captured on, "2.31"
---@field catalogDigest string  64 hex, lower-cased: which catalogue those indices index
---@field gender string          the ENGINE's opaque body hash, never "female"/"male"
---@field options AppearanceOption[]

--- Every export answers a table carrying `ok` and never raises.
---@class AppearanceResponse
---@field ok boolean
---@field error AppearanceError|nil

---@class AppearanceOpenResult : AppearanceResponse
---@field queued boolean|nil     true means asked, never "the modal is on screen"
---@field citizenId CitizenId|nil

---@class AppearanceOpenState : AppearanceResponse
---@field open boolean      a native modal is on screen
---@field editing boolean   and it is this resource's editor
---@field creating boolean  and it is this resource's character creator

---@class AppearanceCurrent : AppearanceResponse
---@field citizenId CitizenId|nil
---@field family BodyFamily|nil
---@field snapshot AppearanceSnapshot|nil  what `PlayerData.appearance` carries

--- What `state` answers.
---@class AppearanceClientState : AppearanceResponse
---@field citizenId CitizenId|nil
---@field family BodyFamily|nil
---@field stored boolean        a stored snapshot is held on this client
---@field wearing boolean       the puppet is wearing it
---@field settled boolean       this world entry's face has been decided
---@field restoring boolean     a restore is in flight
---@field committing boolean    a captured face is with the core, unanswered
---@field creating boolean
---@field editing boolean
---@field worldEligible boolean this world attachment is the gameplay one
---@field announced boolean     `open77:session:gameplayReady` has gone out

--- Which of this resource's decisions an event reports.
---@alias AppearanceEventName
---| "gameplayReady"    the readiness announcement went out; the player may be placed
---| "restored"         a stored face was put on the puppet, or could not be
---| "settled"          this world entry's face was decided, and there is none to wear
---| "createRequired"   this character has no face and the creator is opening
---| "created"          a character was built and stored, or was not
---| "saved"            an edit was committed, or was refused
---| "characterChanged" the live character switched underneath this resource

--- What arrives on `OPX_APPEARANCE_CONFIG.EVENT`, with a bare `AddEventHandler`.
---@class AppearanceEvent
---@field ok boolean
---@field event AppearanceEventName
---@field error AppearanceError|nil
---@field citizenId CitizenId|nil
