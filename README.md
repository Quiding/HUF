# HUF - Hivemind Unitframes

Dark, minimalist unit frames for World of Warcraft: Forever (interface 16001), made for
multiboxing teams and built to work with [MMT - Manage My Team](https://github.com/bnetworking/MMT).
Version 0.5.29.

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
  left, debuffs top right, members out of range faded (40%, the game's range check), a cast bar on the line between health and power bar with the spell
  icon at the left edge (red for a moment when someone interrupts it). Offline members: light
  grey bar and "Offline". Hidden alone and in a raid (raid frames are planned). Player, target
  and pet frames can show the same cast bar (off by default).
- **Nameplates**: name only / name + bar / bar only (friendly units separately), level, elite /
  rare star, quest progress ("2/10") left of the bar, threat (your % in threat colours and / or a
  glow when the mob is about to switch to you, or threat colours on the bar for tanks and
  damage / healers), the level even when the game hides it (in the game's difficulty colour),
  cast bar ("Interrupted!" for a moment when
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
  beside it); hover a name for its top spells (optional). Up to 5 windows, each with its own list,
  fight and place (e.g. damage and threat side by side; + opens one, x closes it). Optionally dimmed
  out of combat (full under the mouse) and threat windows hidden out of combat. `/huf meter` toggles it.
- **Minimap**: square or round, any size and scale, moved in unlock mode. A border (accent colour
  by default) and a soft dark shade outside. Zone name, clock, coordinates and FPS / latency, each
  placed inside or around the map with its own size and colour. The game's icons (tracking,
  calendar, mail, crafting orders, instance difficulty, expansion summary, zoom)
  placed anywhere, each shown always, on mouseover or never; addon buttons the same (all or one by
  one). Or the **addon bar**: one button that opens a small bar with every addon button; it closes
  after a click on one of them or after 10 seconds. Behaviour: shown always or only in some
  situations, rotating map, zoom reset after a few seconds, subzone, latency and difficulty texts
  (texts dragged in unlock mode, with their own opacity). Turning it off gives the minimap back to
  Blizzard after /reload.
- **Data bars**: the minimap data bar, a strip as wide as the map under (or over) it with friends
  and guild members online (click: friends list / guild window); icon colour, size and place
  configurable (Frames > Minimap > Data bar). Free data bars anywhere (Frames > Data bars), each
  with its own place, size, look and blocks: FPS, latency, clock, gold, audio, durability,
  combat, friends, guild.
- **Chat**: the game's look or a panel like EllesmereUI's (one panel, flat tabs, button strip, flat
  input line); font, size, outline, window background and opacity; short channel names at the start of
  a line ([1], [2], [S], [Y], [P], [PL], [G], [GO], [R], [RL], [RW], [W], [I], each editable);
  names in class colours; web addresses as links (click: copy box); tooltips over item / spell /
  quest links; chat kept over /reload and logout (up to 2000 lines a window); buttons beside the
  chat: copy chat, guild (members online, hover for who), friends, and the game's chat channel and
  chat menu buttons moved there, fading to 40% after 5 s; the input line below or above; the game's chat
  settings (bubbles, timestamps, style, whispers, filter) and chat colours on one page. Lines the
  game hides from addons (instance chat lockdown) stay as they are.
- **Bags**: all bags in one HUF window (the game's own item buttons, so using / moving / selling
  works as usual, also in combat); a dropdown to your bank (as it was at your last bank visit) and
  one to your other characters' bags and banks (saved when you play them); a search bar that dims
  everything else; the keyring in the same dropdown; the reagent bag's slots in their own colour,
  or the reagent bag in its own small window beside the bags; a sort button (the game's own fast sort; the bank while you're at it); money
  with coin icons, hover it for every character's gold and the total; tooltips show
  "Name: 8 | 12" (bags | bank) for every character; slots per row,
  slot size, spacing, background, border, quality borders, scale. Turns on the game's combined bags
  option. Saved bags are account data, never in a profile export.
- **Combo points** (rogues, druids in cat form): a row of points above the target frame and under
  your target's nameplate (on by default; position, size, colour adjustable).
- **Buff bar and debuff bar**: HUF's own instead of Blizzard's icons at the top right (each can
  be turned off): growth direction (8 ways: icons right > left / left > right / down / up, new rows or columns either side), most icons, rows, columns, padding, icon size, zoom, border
  (debuffs by type), swipe, time left (an hour or more as h:mm or minutes), stacks, sorting.
  Drawn by the game's own aura containers (like EllesmereUI's), so right-click cancels a buff also
  in combat. Moved in unlock mode.
- **Buffs and debuffs** on every frame, drawn by the game's own aura containers (so they also work
  where addons may not read auras: party, nameplates, combat), on their own Debuffs and Buffs
  tabs: filters (all, important, ones I can dispel, ones my group can dispel, crowd control;
  defensives, cancelable), crowd control first, hide Sated / Exhaustion, 9 places inside the frame
  or above / below, debuff edges in their type colour; buff filters for what can be purged or
  stolen (by you or your group), removable buffs marked with an edge or a golden glow (optionally
  bigger), an edge round the frame for a debuff you / your group can dispel (on for the party),
  tooltips on nameplate auras. Optionally hides Blizzard's buff and debuff
  icons.
- **Classic quest log** (Frames > Quest log, off by default): two sides (the quest list on black
  left, the quest's text on parchment right, in the game's window frame) or the original one-column
  window drawn from the game's own classic art; the game's quest fonts: levels in difficulty colours, complete / failed / daily, tracked check,
  objectives with progress, description, rewards; Abandon, Share, Exit, Track, Show on map.
  **Own categories**: right-click a quest to put it into a category of your own (shown above the
  zones); right-click a category to rename, move or delete it. While on, the quest log key and
  clicks on quests in the tracker open it instead of the map + quest window. For addon authors
  (MMT's quest tracker): `HUF.QuestLog` API 1 - GetCategories, GetCategory, SetCategory,
  GetSections, Listen.
- **The game's windows can be moved** (General > Frames & Features, on): character, spellbook, professions,
  quests, map, mail, merchant, bank, friends, guild and more; drag an empty part (optionally only
  with Shift). Places are remembered; Shift + right-click puts one back, or reset them all. Every
  window that opens through the game's panel system is taken, and inner panels covering a window
  drag it too (way learned from ForeverMove, MIT). With ForeverMove enabled, HUF leaves the
  windows to it.
- Blizzard's player, target, target of target, pet and party frames are hidden while HUF's are on,
  and Blizzard's raid / party manager on the left edge (General: can be shown again).

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
The settings close when a fight starts and come back after it. The General page has three tiles:
**Look and Feel** (accent colour, settings background, HUF Global Font, outline, shadow, a button
that puts every unit frame text back on the global font, short numbers, status texts, avoiding
overlapping texts), **Frames & Features** (hiding Blizzard's frames and raid manager, moving the
game's windows with a reset list) and **Addon Support** (MMT interaction, MMT's privacy names or
HUF's own name setting, click-casting addons). A setting that needs a reload asks for one.

## Click-cast
General > Click-cast: pick a spell (typed or from the spellbook), press a key or mouse button
(with Shift / Ctrl / Alt, wheel too) and choose when it works: always, in combat, out of combat.
Over a HUF frame it casts on that unit like a `[@mouseover]` macro
(`/cast [@mouseover,combat] Spell`). Bindings belong to the character.

## Names and privacy (MMT)
Characters have a first and a last name. HUF always uses the full real name internally
(targeting, menus, macros, addon messages); what you see follows HUF's name setting
(first name by default, last name, full name, "Class X", "Slot X"). With MMT installed, your
team shows the way MMT > Team > Privacy says ("Use MMT privacy setting for names"); "Allow MMT
interaction" off makes HUF ignore MMT completely. HUF uses MMT's documented privacy API (top of
`MMT/Privacy.lua`, `MMT.PRIVACY_API`, version 1) and warns if MMT ever moves to a newer one.

## Profiles
Account-wide profiles chosen per character. General > Profiles: create, copy, reset, and
**export / import** a profile as one line of text (copy & paste to another account): every HUF
setting, plus the character's click-cast bindings, the game's chat settings and colours and the
damage number settings (not the kept chat lines).
With EllesmereUI installed: **Import from EllesmereUI** (its current settings or a `!EUI_` string)
brings over the look of its player, target, target of target, pet and group frames, nameplates
(including their stacking and threat colours), party debuffs, the minimap, its data bars and the
damage meter's hover setting, the chat and the data bars. Every import goes into a new profile
(a copy of the active one with only the ticked parts replaced).

## For addon authors
`_G.HUF`: `HUF.API_VERSION` (1), `HUF.RegisterNameProvider(id, fn)` (`fn(unit, first, last)`
returns the name to show or nil), `HUF.RefreshNames()`, `HUF.Refresh()`, `HUF.ToggleConfig([page])`,
`HUF.Bridge.Status()`.

## Help and debugging
`/huf help`: debug log (also a full report to copy), data recorder (`/huf rec on|off|now`) that
shows what the game hides (secret values) about names, values and auras, and the command list.
Unlock frames (`/huf unlock`) shows made-up characters to place and preview the frames. Frames snap
to each other, the screen's middle and an optional grid while dragged (Alt: freely), with guide
lines and distances; a small unlock bar offers Lock, Settings, snapping and the grid. Chat, bags,
quest log and meter windows have boxes too; right-click a box for its settings. Other addons add
their windows with `HUF.RegisterMover(id, spec)` (MMT does).

## Licence
HUF is released under the GNU General Public License v3.0 (see [LICENSE](LICENSE)).
The fonts in `HUF/Media/Fonts` are under the SIL Open Font License 1.1
(`OFL-BarlowCondensed.txt`, `OFL-RobotoCondensed.txt`).
