--- @author DemiAutomatic
--- @file config.lua
--- @description Operator configuration for faces, clothing, looks and the join bootstrap.
--- @field LOCALE {string} Catalogue code player-facing text is read from.
--- @field PRESENT_BODIES {boolean} Hand every look to other players; false when another resource does.
--- @field EVENT {string} Client event raised after every decision.
--- @field NOTIFY {boolean} Raise toasts through opx77_notify; false writes chat lines instead.
--- @field GAME_BUILDS {table<string, boolean>} Builds a stored face may be read back into.
--- @field COMMIT_MS {integer} Milliseconds opx77_core has to answer a face or clothing save.
--- @field SAVE_COOLDOWN_MS {integer} opx77_core's save cooldown in milliseconds, waited out.
--- @field CLOTHING {table} What the character wears, stored by opx77_core.
--- @field CLOTHING.PERSIST {boolean} false leaves clothing alone: nothing put on or saved.
--- @field CLOTHING.SAVE_DEBOUNCE_MS {integer} Milliseconds a change holds before it is saved.
--- @field RESTORE_RETRIES {integer} Re-dispatches of a restore the mirror aborted.
--- @field FAMILY_RETRIES {integer} Body reloads and reopened creation editors per character.
--- @field BODY_RELOAD_SETTLE_MS {integer} Milliseconds waited for the respawn after a body reload.
--- @field CREATION_WAIT_MS {integer} Milliseconds needsCreation waits for openCreator.
--- @field BOOTSTRAP {table} The body the world loads with at join.
--- @field BOOTSTRAP.ROSTER_WAIT_MS {integer} Milliseconds waited for opx77_core's roster.
--- @field BOOTSTRAP.DEFAULT_FAMILY {string} 'female' or 'male'; anything else reads 'female'.

OPX_APPEARANCE_CONFIG = {
	LOCALE = 'en',
	PRESENT_BODIES = true,
	EVENT = 'opx77:appearance',
	NOTIFY = true,
	GAME_BUILDS = { ['2.31'] = true },
	COMMIT_MS = 20000,
	SAVE_COOLDOWN_MS = 2000,
	CLOTHING = {
		PERSIST = true,
		SAVE_DEBOUNCE_MS = 2000,
	},
	RESTORE_RETRIES = 3,
	FAMILY_RETRIES = 2,
	BODY_RELOAD_SETTLE_MS = 10000,
	CREATION_WAIT_MS = 15000,
	BOOTSTRAP = {
		ROSTER_WAIT_MS = 3000,
		DEFAULT_FAMILY = 'female',
	},
}
