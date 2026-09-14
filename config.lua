-- Configuration for opx77_appearance, shipped to every client. It has no server half.

OPX_APPEARANCE_CONFIG = {
  -- Language for player-facing text. Server logs stay in English.
  LOCALE = "en",

  -- Client event raised after every decision this resource reaches.
  EVENT = "opx77:appearance",

  -- Whether to raise toasts through opx77_notify.
  NOTIFY = true,

  -- Which catalogue builds a stored snapshot may be read back into.
  GAME_BUILDS = { ["2.31"] = true },

  -- How long opx77_core has to answer a captured face before it is given up on, in ms.
  COMMIT_MS = 20000,

  -- opx77_core's own cooldown on `appearance.request`. A commit inside it is held back rather
  -- than refused.
  SAVE_COOLDOWN_MS = 2000,

  -- Re-dispatches of a bootstrap restore the native aborted before confirming it.
  RESTORE_RETRIES = 3,

  -- Body-family attempts per character: world reloads onto `charInfo.gender`, and creation
  -- editors reopened after coming back on the other body. Past it the player keeps the body
  -- they are on.
  FAMILY_RETRIES = 2,

  -- How long a character with no stored face waits for something to answer `needsCreation`,
  -- in ms. Past it this resource says nobody did and lets the player in on the default face.
  -- It never opens the editor itself.
  CREATION_WAIT_MS = 15000,

  -- The body the world first loads with, chosen at join before any character is. The shell
  -- keeps its loading cover up until this is spent, so it is never waited on for long.
  BOOTSTRAP = {
    -- How long to wait for opx77_core's roster, in ms, to load the body of the account's most
    -- recently played character. Past it DEFAULT_FAMILY is loaded.
    ROSTER_WAIT_MS = 3000,

    -- "female" or "male": the body loaded for an account with no played character, or whose
    -- roster did not arrive in time. Anything else is read as "female".
    DEFAULT_FAMILY = "female",
  },
}
