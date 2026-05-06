---
name: project_wickstotems_description
description: CurseForge description for Wick's Totems and Things. Update when shipping new versions. Copy/paste into the CurseForge web UI.
type: project
originSessionId: eb43377d-970e-4f3b-a8b8-20b70f151dfe
---
This is the master CurseForge description for **Wick's Totems and Things**. Update when shipping new versions. Copy/paste into the CurseForge project description (web UI only, no API endpoint for descriptions).

Changelogs (separate upload field) must be HTML, not markdown. See `feedback_curseforge_html.md`.

No em-dashes in shipped copy. See `feedback_no_em_dashes.md`.

The in-repo source of truth lives at `WicksTotemsAndThings/curseforge-page.md`. Keep this memory and that file in sync.

**Spec scope at v0.1:** Enhancement-focused. Twist macros, swing timer, Windfury proc flash, Flurry stack, and Stormstrike target debuff are Enhance-leaning. Resto and Elemental cooldown trackers (Mana Tide, Tidal Force, Nature's Swiftness, Elemental Mastery) are wired but the headline UX targets Enhancement. Resto / Elemental flows expand in v0.2.

---

## One-liner (suite tables, taglines)

> Enhancement shaman command bar for TBC Classic — totem twist, proc tracker, swing timer.

---

## Short summary (CurseForge Summary field, 256-char limit)

> Enhancement shaman command bar for TBC. Totem twist on one keybind, swing timer, Windfury and Stormstrike proc flashes, range warnings, ankh count, and a cooldown bar that auto-hides what your spec doesn't have.

---

## Long description (CurseForge body)

**Wick's Totems and Things** is the all-in-one shaman command bar for TBC Classic Anniversary (2.5.5). Drop totem sets, twist Windfury and Grace of Air on a single keybind, watch who's actually getting buffed, and never miss a proc.

**Currently focused on Enhancement.** v0.1 ships with the Enhance toolkit dialed in (twist, swing timer, Windfury proc flash, Flurry stack, Stormstrike debuff). Resto and Elemental cooldown trackers are present but the spec-specific UX for those is on the v0.2 list.

**Slim icon strip**

Four element buttons (Fire, Earth, Water, Air) sit on a draggable strip. Each button is a secure cast button bound to your active preset's totem for that element. Left-click casts. Right-click opens a totem picker for the active preset. Keybind labels show in the top-right corner of each icon, action-bar style.

A dedicated "drop all four" keybind cycles your full preset on press, one totem per global cooldown.

**Affected count on every totem**

Each active totem shows a count of how many party or raid members are inside its buff radius. The count also overlays on Blizzard's totem icons (the small ones next to your minimap). Tick-effect totems (Healing Stream, Mana Spring, Mana Tide) and self-only totems are flagged correctly.

**Out-of-range warning**

Step out of range of a buff totem you cast and the addon flashes a red banner across the top of the screen with the totem name, paints a subtle red vignette at the screen edges, plays a single sound, and tints that element's icon border red. Walk back into range and the warning clears instantly.

Tick totems (Healing Stream, Mana Spring) are excluded since they have no detectable aura. Caster totems whose buff doesn't apply to non-melee (Windfury Totem) are also excluded.

**Totem twisting**

Toggle twist for any element from the Options panel. The element's button switches from a single `/cast` to a `/castsequence` between two totems. The icon shows the next totem to cast (it visibly flips on every press), and a center countdown counts down to the refresh window. When the window opens, the icon brightens, a red `!` appears, and a soft chime fires once.

Default air twist: Windfury Totem and Grace of Air Totem on a 5-second rhythm.

**Cooldown and proc tracker**

A second slim bar tracks shaman cooldowns and procs that are easy to forget mid-fight:

- **Reincarnation** (Ankh) with a bag-count box on the totem strip
- **Bloodlust** (Horde) or **Heroism** (Alliance), auto-faction filtered
- **Fire Elemental Totem** and **Earth Elemental Totem**
- **Nature's Swiftness**, **Elemental Mastery**, **Tidal Force**, **Mana Tide Totem**
- **Shamanistic Rage** (talent CD plus active buff)
- **Flurry** (3-stack proc tracker with stack count)
- **Windfury Weapon** (combat-log flash on every Windfury Attack proc)
- **Stormstrike** (target debuff tracker)

Each entry auto-hides when your spec doesn't have the talent. Cooldown spells dim with a Blizzard-style spiral while recharging. Procs grey out when inactive and burst to full color with a swirling autocast shine when they fire.

**Swing timer**

Main-hand and off-hand swing progress bars surface only in combat and fade after combat ends. Off-hand bar auto-hides when not dual-wielding.

**Presets and bindings**

Multiple named presets per character. Click a preset to make it active. Click any element pill to pick a different totem from a popup. Inline rename, delete, and add new presets from the Presets tab.

Eight Blizzard keybinding slots: drop active preset, four per-element casts, toggle main panel, toggle icon strip, cycle to next preset. Set them in Esc to Key Bindings to AddOns.

**Options**

A dedicated Options tab in the main panel toggles every module:

- Show, lock, and reset position for the icon strip, cooldown bar, and swing timer
- Out-of-range warning with separate toggles for sound, top banner, and screen vignette
- Totem-frame count badge overlay on Blizzard's icons
- Per-element twist toggles with default totem pairs

**Slash commands**

- `/wtt` toggles the main panel
- `/wtt bar`, `/wtt cd`, `/wtt swing` toggle the slim bars
- `/wtt twist <element> on|off` enables totem twisting per element
- `/wtt status`, `/wtt range`, `/wtt cdtest` print diagnostics
- `/wtt resetbar`, `/wtt resetcd`, `/wtt resetswing` recover lost positions
- `/wtt resetpresets` wipes presets and re-seeds defaults

**UI**

Wick brand chrome throughout: void background, fel-green L-bracket corner accents, two-tone "Wick's" title, slim 28px header, multiplication-sign close glyph. Drag any bar to position. Lock toggles freeze positions during play.

**Per-character settings**

Presets, twist configuration, and bindings save per character. Bar positions, range-warning toggles, and overlay options save account-wide.

**Requirements**

TBC Classic Anniversary (2.5.5). Pure Lua, no library dependencies. Auto-hides shaman-only modules for non-shaman characters (panel still loads in viewer mode).

**Roadmap**

- v0.2: Resto-focused tracker (Earth Shield ICD, Mana Tide window cue, healing-target frames)
- v0.2: Elemental-focused tracker (Lightning Overload visualizer, Totem of Wrath uptime)
- v0.2: Per-totem precise range checks (currently uses 40yd UnitInRange as an upper bound)
