# HUF - Hivemind Unitframes

Dark, minimalist unit frames for World of Warcraft: Forever (interface 16001), made for
multiboxing teams and built to work with [MMT - Manage My Team](https://github.com/bnetworking/MMT).
Version 0.4.7.

## Install
Download the repository (Code > Download ZIP) and copy the `HUF` folder into
`World of Warcraft/_forever_/Interface/AddOns/`. A new or updated addon with new files needs a
full game restart (not just /reload). Type `/huf` in game for the settings.

## Frames
- **Player, Target, Target of target, Pet**: health and power bar, each with a thin dark border.
  Player / Target 175 x 24, Target of target (health only) and Pet hang off the target and
  player frame. The pet frame shows a hunter pet's happiness (icon or text) on the right of its
  health bar. Incoming heals (yours and others') show as a semi-transparent green bar after
  the filled part and may run past the bar's end (overheal). Every frame can be anchored to the screen or to another HUF frame.
- **Group (party)**: real secure unit frames (SecureGroupHeader), so `[@mouseover]` macros and
  click-casting work on them. Show myself or not, sort by name / Blizzard's party order / class,
  vertical or horizontal in either direction, adjustable padding. Missing health in health-status
  colour (hidden at full health), name, level and power on the power bar, your buffs (HoTs) top
  left, debuffs top right, a cast bar on the line between health and power bar with the spell
  icon at the left edge (red for a moment when someone interrupts it). Offline members: light
  grey bar and "Offline". Hidden alone and in a raid (raid frames are planned). Player, target
  and pet frames can show the same cast bar (off by default).
- **Nameplates**: name only / name + bar / bar only (friendly units separately), level, elite /
  rare star, quest progress ("2/10") left of the bar, cast bar ("Interrupted!" for a moment when
  someone interrupts the cast), your debuffs and buffs with time
  left as numbers. Name above or inside the bar, own NPC colours, darker out of combat. Questie's
  quest icon is moved next to HUF's quest progress.
  In instances the game protects friendly player nameplates (no addon can change their names):
  while names are private, HUF switches them and the names above characters off there and back
  on outside (Nameplates > General).
- **Damage meter**: the game's own meter data (damage, healing, damage taken, interrupts, dispels,
  deaths, and HUF's own threat view: your group's threat on your enemy; current fight, overall,
  earlier fights) in a HUF window with privacy names; hides
  Blizzard's meter window. In combat in instances the game hides the meter's names from addons:
  HUF then recognises you, unique classes and members it learned by class + specialisation, else
  shows the class name until the fight ends; never a hidden real name. Click a row for its
  breakdown (spells, amounts, share; hover a spell for details) inside the window (or in a panel
  beside it). Up to 5 windows, each with its own list,
  fight and place (e.g. damage and threat side by side; + opens one, x closes it). Optionally dimmed
  out of combat (full under the mouse) and threat windows hidden out of combat. `/huf meter` toggles it.
- **Minimap**: square or round, any size and scale, moved in unlock mode. A border (accent colour
  by default) and a soft dark shade outside. Zone name, clock, coordinates and FPS / latency, each
  placed inside or around the map with its own size and colour. The game's icons (tracking,
  calendar, mail, crafting orders, instance difficulty, expansion summary, zoom)
  placed anywhere, each shown always, on mouseover or never; addon buttons the same (all or one by
  one). Or the **addon bar**: one button that opens a small bar with every addon button; it closes
  after a click on one of them or after 10 seconds. Turning it off gives the minimap back to
  Blizzard after /reload.
- **Combo points** (rogues, druids in cat form): a row of points above the target frame and under
  your target's nameplate (on by default; position, size, colour adjustable).
- **Buff bar and debuff bar**: HUF's own instead of Blizzard's icons at the top right (each can
  be turned off): growth direction, most icons, rows, columns, padding, icon size, zoom, border
  (debuffs by type), swipe, time left (an hour or more as h:mm or minutes), stacks, sorting.
  Drawn by the game's own aura containers (like EllesmereUI's), so right-click cancels a buff also
  in combat. Moved in unlock mode.
- **Buffs and debuffs** on every frame, drawn by the game's own aura containers (so they also work
  where addons may not read auras: party, nameplates, combat). Optionally hides Blizzard's buff
  and debuff icons.
- Blizzard's player, target, target of target, pet and party frames are hidden while HUF's are on.

## Look and texts
- Accent colour blue / purple / bronze / custom, dark backgrounds and textures, several bar
  textures, portraits (off by default).
- Fonts: **Barlow Condensed** (default) and **Roboto Condensed** come with HUF; with EllesmereUI
  installed its fonts (Expressway, ...) and textures are in the lists too.
- Bar colours: static, gradient (2 colours), class, status (>75% / >40% / below), type.
- 9 text anchors per bar (top / middle / bottom x left / center / right), each with its own
  template, font, size, outline, colour (incl. health status) and offset. Values like `[name]`,
  `[hp]`, `[hp%]`, `[hp:missing]`, `[mp]`, `[mp%]`, `[level]`, `[levelclass:color]`, `[status]`.

## Settings
`/huf`. A search box (top right) finds any setting by its name; a click opens its page and tab.
The settings close when a fight starts and come back after it.

## Click-cast
General > Click-cast: pick a spell (typed or from the spellbook), press a key or mouse button
(with Shift / Ctrl / Alt, wheel too) and choose when it works: always, in combat, out of combat.
Over a HUF frame it casts on that unit like a `[@mouseover]` macro
(`/cast [@mouseover,combat] Spell`). Bindings belong to the character.

## Names and privacy (MMT)
Characters have a first and a last name. HUF always uses the full real name internally
(targeting, menus, macros, addon messages); what you see follows HUF's name setting
(first name by default, last name, full name, "Class X", "Slot X"). With MMT installed, your
team shows the way MMT > Team > Privacy says ("MMT's privacy for my team": always / only while
MMT hides names outside MMT / never). HUF uses MMT's documented privacy API (top of
`MMT/Privacy.lua`, `MMT.PRIVACY_API`, version 1) and warns if MMT ever moves to a newer one.

## Profiles
Account-wide profiles chosen per character. General > Profiles: create, copy, reset, and
**export / import** a profile as one line of text (copy & paste to another account).
With EllesmereUI installed: **Import from EllesmereUI** (its current settings or a `!EUI_` string)
brings over the look of its player, target, target of target, pet frames and nameplates.

## For addon authors
`_G.HUF`: `HUF.API_VERSION` (1), `HUF.RegisterNameProvider(id, fn)` (`fn(unit, first, last)`
returns the name to show or nil), `HUF.RefreshNames()`, `HUF.Refresh()`, `HUF.ToggleConfig([page])`,
`HUF.Bridge.Status()`.

## Help and debugging
`/huf help`: debug log (also a full report to copy), data recorder (`/huf rec on|off|now`) that
shows what the game hides (secret values) about names, values and auras, and the command list.
Unlock frames (`/huf unlock`) shows made-up characters to place and preview the frames.

## Licence
HUF is released under the GNU General Public License v3.0 (see [LICENSE](LICENSE)).
The fonts in `HUF/Media/Fonts` are under the SIL Open Font License 1.1
(`OFL-BarlowCondensed.txt`, `OFL-RobotoCondensed.txt`).
