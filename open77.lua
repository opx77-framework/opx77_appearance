--- @author DemiAutomatic
--- @file open77.lua
--- @description Resource manifest declaring scripts, permissions and reload policy.

resource "opx77_appearance"
version "0.9.0"
open77_version ">=0.0.1"
auto_start true

reload_policy "local"

shared_script "config.lua"
shared_script "shared/locale.lua"
shared_script "locales/en.lua"
shared_script "locales/fr.lua"

client_script "client/snapshot.lua"
client_script "client/state.lua"
client_script "client/main.lua"
client_script "client/editor.lua"
client_script "client/panel.lua"
client_script "client/clothing.lua"
client_script "client/presence.lua"
client_script "client/exports.lua"

server_script "server/presence.lua"

permissions {
  "network.events",
  "player.appearance.read",
  "player.appearance.edit",
  "player.equipment.read",
  "player.equipment.edit",
  "puppets.present",
  "players.life.read",
}
