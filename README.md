# opx77_appearance

> [!WARNING]
> **This project is currently in early development and is not considered production-ready.**
>
> The API, architecture, features, and internal systems are subject to change at any time
> without prior notice. Breaking changes may be introduced as development progresses.
>
> **Do not rely on the current API for production resources yet.**

> [!IMPORTANT]
> **This resource is what opens the platform's readiness gate, and on a stock Opx77 install
> nothing else does.**
>
> Every joining player is held by a hold named `__platform` that no Lua may take or release and
> that has no deadline. It clears on exactly one thing: the client announcing
> `open77:session:gameplayReady`, which this resource sends once the local puppet is attached,
> alive and past the "press any key to continue" screen. Without it, `Open77.ready.isReady` is
> permanently false and `onPlayerReady` never fires for anybody.

Character appearance for **Opx77**. Cyberpunk's own customization mirror, opened for a
character that has no face yet and reopened on demand, captured, and sent to `opx77_core`,
which validates it and stores it on the character row.

**This resource is client-only.** It has no `server/`, no `sql/`, no table and no
`database.access`. The face is `opx77_characters.appearance`, `opx77_core` owns every write to
it, and it travels in `PlayerData` like any other field of the character.

This resource takes no readiness hold of its own — it has no server half to take one from.
What holds a player is the platform's `__platform` hold, and this resource decides when it
falls: the announcement below is withheld for as long as the player is still building a
character — an hour included — and goes out the moment they are done, abandon it, or the face
is otherwise settled.

`opx77_core` is the one thing the gate does not stop. It places the character and releases its
own hold as part of `selectCharacter`, without consulting `Open77.ready`, so on a character
with no stored face the player is placed before the creator opens. That is the core's own
sequence and no appearance resource has ever gated it.

## Features

- One stored face per character, kept by `opx77_core` on the citizen id it issued
- One panel every caller shares — a ripperdoc, a clothes store, a menu — instead of each
  shipping its own
- The panel is `opx77_menu`'s, and optional — a missing menu costs one log line
- The join-time readiness announcement, sent only once the player is genuinely playable
- The vanilla character creator for a character that arrives with no face
- A saved face from an older game build is refused rather than misapplied
- Player-facing text in `locales/`, `en` and `fr`

## Commands

None. A chat command cannot be registered from a client resource on this platform, and this
one has no server half to register one from. The panel is opened through the `openPanel`
export and the native editor through `openEditor` — a menu, a ripperdoc prop or any other
client resource calls them.

## Exports

An appearance service, not a flow. This resource reads, applies, stores and edits the live
character's face; it never decides that a player should be sent to a creator. `opx77_charselector`
and `opx77_charcreator` own that decision and call these.

| Export | Does |
|---|---|
| `getSkin` | the stored face for the live character, as `opx77_core` holds it |
| `captureSkin` | what the puppet is wearing right now, ready to hand back |
| `getFamily` | the character's body family, `"female"` or `"male"` |
| `setSkin(snapshot)` | put a face on the puppet; stores nothing |
| `saveSkin(snapshot?)` | store one through `opx77_core`; defaults to a capture |
| `openEditor(mode?)` | the native mirror, `"ripperdoc"` or `"hairdresser"` |
| `openCreator` | the vanilla character creator, for a character with no face |
| `isOpen` | whether a native modal is on screen, and which |
| `isSettled` | whether this world entry's appearance work has finished |
| `state` | what this client knows, for a face that did not come back |
| `openPanel` | this resource's own panel, as a list drawn by `opx77_menu` |
| `closePanel` | take your own panel back down |

`openPanel` and `closePanel` are new in `0.5.0`; the ten above them are unchanged. `state`
reports one more field, `panel`.

`isSettled` is the gate question — is this world entry's face done, and if not what is it
waiting on. `state` is the diagnostic report behind it. Every export answers a table carrying
`ok`, never raises, and takes its caller from `GetInvokingResource()`.

A write answers that it was **asked for**: the engine schedules an apply through the vanilla
mirror and `opx77_core` validates a save, so the outcome arrives on
`OPX_APPEARANCE_CONFIG.EVENT` rather than in the return value.

```lua
CreateThread(function()
  local promise = Open77.exports.call("opx77_appearance", "captureSkin")
  local result = promise and promise:await()
  if result and result.ok then
    Open77.exports.call("opx77_appearance", "saveSkin", result.snapshot)
  end
end)

AddEventHandler("opx77:appearance", function(payload)
  if payload.event == "saved" and payload.ok then
    -- stored
  end
end)
```

## The panel

One resource owns the appearance panel, so a ripperdoc, a clothes store and a menu all call
the same one instead of each shipping their own page. It is a **list, drawn by `opx77_menu`**:
`openPanel` puts it up, `closePanel` takes it down, and only for the caller that opened it.

The sections are the list's levels, and each root row carries its own summary as a value:

| Level | Rows |
|---|---|
| root | `Looks`, `Body`, `Outfits` |
| `Looks` | the saved look, **Wear it**, and the two ways into the native editor |
| `Body` | the body family, stated and not offered — `opx77_core` owns it |
| `Outfits` | one row saying it is not built |

There is no `section` argument. A level is reached by pressing ENTER on its row, and
`opx77_menu` publishes nothing that opens a menu already inside one. A row that is not
actionable is drawn disabled with the reason as its value — `none`, `other build`, `worn`,
`Not right now.` — rather than greyed out with nothing beside it.

**It is the frame around the face, not the face.** There is no face editor here and there
cannot be one: an option is `{ part, name, value, choices }` where `name` is an opaque 64-bit
catalogue hash with no human label anywhere on the platform, and no camera native is shipped.
Cyberpunk's own modal is the only face editor there is, and the panel's job is to open it.

**`opx77_menu` is optional and is not declared as a dependency.** With it stopped `openPanel`
answers `menu_not_running`, an `open` that fails on the way out costs one `Open77.log.warn`
line, and every other export is unaffected.

**The panel never draws over the native mirror.** `Open77.appearance.isOpen()` is the truth,
and a raise from it counts as "on screen": while the panel is up it is read every 200 ms, and
a modal — this resource's or anybody's — takes the panel down with the reason
`appearance_busy`. `openPanel` is refused with the same code while one is already up.
**Edit face** and **Hair only** take the panel down and wait for `opx77_menu` to answer the
close *before* the mirror is asked for; reopen the panel afterwards.

One panel at a time, keyed on `GetInvokingResource()`. A second resource is refused with
`panel_busy`; the owner calling `openPanel` again redraws its own. The panel closes itself
when its owner stops or reloads, when the character changes or unloads, on Escape and the
pause key, and on BACK at the top of the list.

`panelOpened` and `panelClosed` reach `OPX_APPEARANCE_CONFIG.EVENT` like every other decision
here. `panelClosed` carries a `reason`: `caller`, `player`, `appearance_busy`,
`character_changed`, `no_character`, `owner_stopped`, `owner_reloaded`, or `menu_closed` when
`opx77_menu` took the list down for a reason of its own.

### One saved look, and why

The core stores exactly one face per character — `opx77_characters.appearance`, a single
nullable JSON column, written by `opx77_core/server/appearance.lua` and carried in
`PlayerData`. There is no second row and no slot number, so **a wardrobe of saved looks is not
possible today without core work**: another table, its schema file, and a server half to write
it — none of which a satellite may own. The panel therefore shows the one stored look, says
whether the puppet is wearing it, and puts it back on when it is not.

### Outfits

Not built. The level is drawn so that it is visibly a gap rather than a missing feature.
What it needs first is a clothing catalogue with human labels — item id, name, slot, and what
a character owns — and nothing on this platform publishes one. No data shape is invented here
in advance of it.

## Who opens the creator

Not this resource. When the live character has no stored face it publishes `needsCreation` on
its event channel and waits:

```lua
AddEventHandler("opx77:appearance", function(payload)
  if payload.event ~= "needsCreation" then return end
  -- draw whatever you want, then:
  Open77.exports.call("opx77_appearance", "openCreator")
end)
```

Everything after the player confirms belongs here again — the capture, the check that the body
they built is the body their character is, the save through `opx77_core`, spending the character
bootstrap and letting the world load. The outcome arrives as `created`.

If nothing answers, the player sits in the vanilla menu with no world behind it and nothing on
screen. That is undiagnosable from the outside, so after `CREATION_WAIT_MS` this resource says so
in the log, once, naming the export that was never called.

## What it still owns

Three things a caller cannot do for itself, and the reason this is a resource rather than a
library:

- **The character bootstrap.** `resolveCharacterBootstrap` is one-shot and settles which pristine
  body the world loads with. It is spent here, on `charInfo.gender`.
- **The join-time restore.** A stored face is applied only once the puppet is attached, alive and
  past the "press any key to continue" screen — applying it earlier arms a native watchdog that
  ends in a user-facing error on a correct face.
- **`open77:session:gameplayReady`.** The only thing that clears the platform's `__platform`
  hold, and it goes out exactly when `isSettled` turns true. Without it nobody spawns.

## How a face is stored

The client captures the mirror and sends one net event to the core:

```lua
TriggerServerEvent("opx77:server:saveAppearance", { snapshot = snapshot })
```

The core takes the character from the connection — never from the payload — validates the
snapshot, writes it, and publishes it back. There is a **2000 ms cooldown** on that event, key
`appearance.request`; this resource waits it out rather than tripping it.

| Direction | Channel |
|---|---|
| write | `opx77:server:saveAppearance`, payload `{ snapshot = … }` |
| refusal | `opx77:client:notify` → `OPX.Events.Local.REFUSED`, carrying a code and the request
it answers |
| read | `PlayerData.appearance`, so it arrives with `opx77:client:onPlayerLoaded` |
| read | `opx77_core`'s `GetAppearance` client export |
| change | `opx77:client:appearanceSaved`, whose payload is the snapshot |

A refusal carries the request it answers as well as a code, and only one naming
`saveAppearance` is this resource's: an `error.tooFast` raised by a character selection or a
vehicle spawn is left alone rather than taken for the answer to a capture still in flight.

The six codes that request can be refused with are `appearance.invalid`,
`appearance.tooLarge`, `error.badRequest`, `error.notLoggedIn`, `error.tooFast` and
`error.unavailable`, which is what the core's storage failures are mapped to. This resource's
catalogue carries all six, so every one of them is shown in the player's language.

A confirm that did not change anything is completed on the client: the core writes nothing and
publishes nothing for a face identical to the stored one, so waiting for an answer would time
out on a correct save.

## Who owns the body family

`opx77_core` does. It is `charInfo.gender` on the character row, the player chose it when they
created the character, and it is the value this resource resolves the engine's character
bootstrap with.

So **nothing here can change it**. `openEditor` never passes a gender to the native
editor, and a character creator that comes back on the other body is refused with
`body_family_mismatch` and reopened, `FAMILY_RETRIES` times. Changing a character's body type
means changing the character, in `opx77_core`.

## Why a stored face is refused after a game update

A snapshot is not a mesh. It is a list of positions in the customization catalogue — for each
option, which index the player chose — so it only means anything against the catalogue it was
captured on. `GAME_BUILDS` in `config.lua` names the builds this resource will read one back
into, and a face from any other is **not applied**: applying it would put a different face on
the puppet rather than failing.

The player joins with the pristine one, is told so once, and the next save writes a face
against the catalogue that is actually loaded. Widening `GAME_BUILDS` does not make an old
snapshot fit; it only stops this resource from saying so.

## The deadlines, and the one that is not

| | What it bounds | Shipped |
|---|---|---|
| `COMMIT_MS` | how long the core has to answer a captured face | 20,000 ms |
| `SAVE_COOLDOWN_MS` | the core's own cooldown, waited out before a capture goes out | 2,000 ms |

There is no deadline on building a character: a player deliberating for an hour leaves the
readiness gate closed for an hour, and a player who alt-F4s out of the creator was never
holding anything the server keeps.

## What happens when a character never gets a face

Nobody is ever left unable to enter. Every ending below places the player, and none of them
stores anything.

| Ending | What the player gets |
|---|---|
| The creator is closed or cancelled | the bootstrap fails; there is no world to load |
| Wrong body type, `FAMILY_RETRIES` times | the pristine face of their own body, nothing stored |
| The core refuses the write, or never answers | the same, with the reason on screen |

In the last two, the creator is **not** reopened for that character again this session, or it
would come straight back up on top of somebody standing in Night City. `openEditor` is the way
back: it opens an editor on a character with no stored face and saves the first one like any
other capture.

## Configuration

`config.lua`: the language, the event name, whether to raise toasts, the catalogue builds, the
two deadlines above and the two retry counts. The panel has nothing to configure here: how it
is anchored and how wide it is drawn belong to `opx77_menu`.

## Locales

`LOCALE` in `config.lua` picks the catalogue player-facing text is read from — `"en"` or `"fr"`
as shipped. Each resource carries its own catalogue, so this is set here as well as in
`opx77_core`: the core's `Locale` export is client-only and asynchronous, and a resource that
renders text at load cannot wait on it.

To add a language, copy `locales/en.lua` to `locales/<code>.lua`, change the code in the
`register` call, translate the values, add a `shared_script "locales/<code>.lua"` line to
`open77.lua` beside the others, and set `LOCALE` to it. A key missing from a catalogue falls
back to English, then to the key itself. `Open77.log` lines and console output stay English
whatever the setting.

## Community & Support

Join the Open77 and Opx77 communities to discover the platform, share your projects, and
connect with other developers.

<!-- TODO: replace with the final URLs before publication. -->

* [Open77](#)
* [Open77 GitHub](#)
* [OPX Discord](#)

## License

opx77_appearance is licensed under the [**MIT License**](LICENSE).

Copyright © 2026 **Luis MOUTA**.

<p align="center">
    <sub>opx77_appearance is an independent community project and is not affiliated with
    or endorsed by CD PROJEKT RED.</sub>
</p>
