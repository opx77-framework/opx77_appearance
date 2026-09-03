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
---| "appearance_busy"      a modal is on screen, or a capture is with the core     (client)
---| "character_creation_in_progress" the character is still being built            (client)
---| "invalid_mode"         not "ripperdoc" or "hairdresser"                        (client)
---| "capture_failed"       the engine would not answer what the puppet wears       (client)
---| "already_has_a_face"   `openCreator` on a character that has a stored one      (client)
---| "bootstrap_already_spent" `openCreator` after the world has already loaded     (client)
---| "creation_refused"     this character's creator run ended for good             (client)
---| "character_creator_unavailable" the engine would not open the creator          (client)
---| "not_sent"             the net event was not accepted                          (client)
---| "menu_not_running"     the panel is opx77_menu's, and it is not running        (client)
---| "panel_busy"           another resource owns the open panel                    (client)
---| "no_panel_open"        `closePanel` with nothing on screen                     (client)
---| "not_owner"            `closePanel` on another resource's panel                (client)
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

--- What `captureSkin` answers: the puppet as it is right now, canonical and ready to hand
--- straight back to `setSkin` or `saveSkin`.
---@class AppearanceCapture : AppearanceResponse
---@field snapshot AppearanceSnapshot|nil
---@field citizenId CitizenId|nil

--- What `getFamily` answers. The value is opx77_core's `charInfo.gender` and nothing here
--- can change it.
---@class AppearanceFamily : AppearanceResponse
---@field family BodyFamily|nil
---@field citizenId CitizenId|nil

--- What `isSettled` answers. `waiting` names what the session is short of; `"creation"` means
--- the character has no face and nothing has called `openCreator`.
---@class AppearanceSettled : AppearanceResponse
---@field settled boolean    the appearance work for this world entry has finished
---@field announced boolean  `open77:session:gameplayReady` has gone out
---@field waiting "server"|"restore"|"creation"|"creator"|nil
---@field citizenId CitizenId|nil

--- What a write or a modal call answers: that it was asked for, never that it has happened.
---@class AppearanceQueued : AppearanceResponse
---@field queued boolean|nil     true means asked, never "it is done"
---@field citizenId CitizenId|nil

---@class AppearanceOpenState : AppearanceResponse
---@field open boolean      a native modal is on screen
---@field editing boolean   and it is this resource's editor
---@field creating boolean  and it is this resource's character creator

--- What `getSkin` answers.
---@class AppearanceSkin : AppearanceResponse
---@field citizenId CitizenId|nil
---@field family BodyFamily|nil
---@field snapshot AppearanceSnapshot|nil  what `PlayerData.appearance` carries

--- What `state` answers.
---@class AppearanceClientState : AppearanceResponse
---@field citizenId CitizenId|nil
---@field family BodyFamily|nil
---@field stored boolean        a stored snapshot is held on this client
---@field wearing boolean       the puppet is wearing it
---@field decided boolean       this world entry's face has been decided
---@field settled boolean       and every piece of work behind that decision has finished
---@field restoring boolean     a restore is in flight
---@field committing boolean    a captured face is with the core, unanswered
---@field creating boolean
---@field editing boolean
---@field worldEligible boolean this world attachment is the gameplay one
---@field announced boolean     `open77:session:gameplayReady` has gone out
---@field panel boolean         this resource's own panel is on screen

--- Which of this resource's decisions an event reports.
---@alias AppearanceEventName
---| "gameplayReady"    the readiness announcement went out; the player may be placed
---| "restored"         a stored face was put on the puppet, or could not be
---| "settled"          this world entry's face was decided, and there is none to wear
---| "needsCreation"    this character has no face; call `openCreator` to open one
---| "applied"          `setSkin` reached the puppet, or could not
---| "created"          a character was built and stored, or was not
---| "saved"            an edit was committed, or was refused
---| "characterChanged" the live character switched underneath this resource
---| "panelOpened"      this resource's own panel came up
---| "panelClosed"      it went down; `reason` says what took it down

--- What arrives on `OPX_APPEARANCE_CONFIG.EVENT`, with a bare `AddEventHandler`.
---@class AppearanceEvent
---@field ok boolean
---@field event AppearanceEventName
---@field error AppearanceError|nil
---@field citizenId CitizenId|nil
---@field family BodyFamily|nil    on `needsCreation`: the body the creator must build
---@field unchanged boolean|nil    on `saved`: the face matched the stored one, nothing written
---@field reason AppearancePanelReason|nil  on `panelClosed`: what took the panel down

--- Why a panel closed.
---@alias AppearancePanelReason
---| "caller"            `closePanel`, or a row that opens the native editor
---| "player"            Escape, the pause key, or BACK at the top of the list
---| "appearance_busy"   a native modal came up, and the panel never draws over one
---| "character_changed" the live character switched underneath the panel
---| "no_character"      the character unloaded
---| "owner_stopped"     the resource that opened it is no longer running
---| "owner_reloaded"    the resource that opened it reloaded
---| "menu_closed"       opx77_menu took the list down for a reason of its own
