resource "opx77_appearance"
version "0.7.0"
open77_version ">=0.0.1"
auto_start true

reload_policy "local" -- a reload is a script reload, not a reconnect: the face is re-read
                      -- from PlayerData, the panel is taken down, and nothing survives one

shared_script "config.lua"
shared_script "shared/locale.lua"
shared_script "locales/en.lua" -- registered right after the catalogue, so no file below calls
shared_script "locales/fr.lua" -- locale() against an empty one

client_script "client/snapshot.lua"
client_script "client/state.lua" -- after snapshot.lua: the redundant-restore guard compares
client_script "client/main.lua"
client_script "client/editor.lua" -- after main.lua: it calls into the runtime
client_script "client/panel.lua" -- after editor.lua: a panel row opens the native editor
client_script "client/exports.lua" -- last: publishing the surface claims everything it reads

permissions {
  "network.events", -- TriggerServerEvent; local.events is not needed

  -- Reading the catalogue and writing the puppet. `read` alone would let this resource save
  -- a face and never put it back on.
  "player.appearance.read",
  "player.appearance.edit",

  -- The local player's life state, read only: no face and no editor goes on a player behind
  -- the "continue" screen or inside the respawn a body reload replays.
  "players.life.read",

  -- No `webui.*`: this resource draws nothing of its own. The panel is a menu, and
  -- opx77_menu owns that surface.

  -- Deliberately not requested: database.access, the players.life.* writes, world.*,
  -- combat.config. opx77_core owns the face and every write to it; this resource only dresses
  -- a puppet.
}
