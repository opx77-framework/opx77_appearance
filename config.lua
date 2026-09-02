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

  -- Character creator reopens after the player came back on the wrong body family.
  FAMILY_RETRIES = 2,

  -- How long a character with no stored face waits for something to answer `needsCreation`
  -- before this resource says nobody did, in ms. It never opens a creator itself.
  CREATION_WAIT_MS = 15000,
}
