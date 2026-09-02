resource "opx77_appearance"
version "0.3.0"
open77_version ">=0.0.1"
auto_start true

reload_policy "local" -- a reload is a script reload, not a reconnect: the face is re-read
                      -- from PlayerData, and nothing here survives one

shared_script "config.lua"
shared_script "shared/locale.lua"
shared_script "locales/en.lua" -- registered right after the catalogue, so no file below calls
shared_script "locales/fr.lua" -- locale() against an empty one

client_script "client/snapshot.lua"
client_script "client/state.lua" -- after snapshot.lua: the redundant-restore guard compares
client_script "client/main.lua"
client_script "client/editor.lua" -- after main.lua: it calls into the runtime
client_script "client/exports.lua" -- last: publishing the surface claims everything it reads

permissions {
  "network.events", -- TriggerServerEvent; local.events is not needed

  -- Reading the catalogue and writing the puppet. `read` alone would let this resource save
  -- a face and never put it back on.
  "player.appearance.read",
  "player.appearance.edit",

  -- Deliberately not requested: database.access, players.life.*, world.*, combat.config.
  -- opx77_core owns the face and every write to it; this resource only dresses a puppet.
}
