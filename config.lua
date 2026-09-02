--- opx77_appearance -- settings shipped to every client. This resource has no server half.

OPX_APPEARANCE_CONFIG = {
  -- Language for player-facing text. Server logs stay in English.
  LOCALE = "en",

  -- Client event raised after every decision this resource reaches.
  EVENT = "opx77:appearance",

  -- Whether to raise toasts through opx77_notify.
  NOTIFY = true,

  -- Which catalogue builds a stored snapshot may be read back into.
  GAME_BUILDS = { ["2.31"] = true },

  -- How often a creator that is still on screen is traced, in ms. It is a trace and never a
  -- deadline: building a character is not timed.
  CREATION_BEAT_MS = 5000,

  -- How long opx77_core has to answer a captured face before it is given up on, in ms.
  COMMIT_MS = 20000,

  -- opx77_core's own cooldown on `appearance.request`. A commit inside it is held back rather
  -- than refused.
  SAVE_COOLDOWN_MS = 2000,

  -- Re-dispatches of a bootstrap restore the native aborted before confirming it.
  RESTORE_RETRIES = 3,

  -- Character creator reopens after the player came back on the wrong body family.
  FAMILY_RETRIES = 2,
}
