resource "opx77_appearance"
version "0.9.0"
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
client_script "client/clothing.lua" -- after main.lua: it dresses once the face has settled
client_script "client/presence.lua" -- after main.lua: it reads the state the runtime settles
client_script "client/exports.lua" -- last: publishing the surface claims everything it reads

-- Hands every player's look to everybody else, as the platform's open77_appearance and its
-- equipment and wardrobe relays do: an observer draws another player only from it. Stores
-- nothing.
server_script "server/presence.lua"

permissions {
  -- Both halves: TriggerServerEvent for the face and the look, and the looks the server hands
  -- back to every client. local.events is not needed.
  "network.events",

  -- Reading the catalogue and writing the puppet. `read` alone would let this resource save
  -- a face and never put it back on. `read` is also what captureBody needs.
  "player.appearance.read",
  "player.appearance.edit",

  -- Client: the equipment registry and the wardrobe, for the records observers dress this
  -- player's proxy from, and for the clothing opx77_core stores.
  "player.equipment.read",

  -- Client: Open77.equipment.apply and Open77.wardrobe.outfit().apply / activate, putting the
  -- clothing opx77_core stores back on this player's own puppet. Nobody else's.
  "player.equipment.edit",

  -- Client: Open77.puppets.setBody, setSlot and setWardrobe, putting another player's look on
  -- this client's proxy of it.
  "puppets.present",

  -- The local player's life state, read only: no face and no editor goes on a player behind
  -- the "continue" screen or inside the respawn a body reload replays.
  "players.life.read",

  -- No `webui.*`: this resource draws nothing of its own. The panel is a menu, and
  -- opx77_menu owns that surface.

  -- Deliberately not requested: database.access, the players.life.* writes, world.*,
  -- combat.config. opx77_core owns the face, the clothing and every write to them; this
  -- resource dresses its own puppet, and hands on what the others wear without changing it.
}
