# Changelog

## v0.3.7 - 2026-05-07

Critical fix: ProcAlerts crash from `UnitBuff` signature mismatch.

- `findAura` was reading `count` from position 4 of the `UnitBuff`/`UnitDebuff` return tuple, but TBC 2.5.5 dropped the legacy `rank` slot — `count` lives at position 3 now. With the old indexing, `count` was actually the `debuffType` string ("Magic", "Curse", "" etc.), which made the proc-floater refresh throw `attempt to compare number with string` at `if count > 1 then` and spam BugSack thousands of times per session.
- Fixed the signature in `CooldownTracker.lua`'s shared `findAura` helper. Added `tonumber()` defensive wraps on the return values so a future signature change can't silently break the comparison again.
- Stack-count text on proc floaters (Flurry, Maelstrom, Lightning Shield charge counts, etc.) now displays correctly again.

## v0.3.6 - 2026-05-07

- **Duplicate floater fix.** ProcAlerts now keeps a frame pool keyed by entry short. Init and Rebuild both reuse the existing floater for each entry instead of creating a new one (which left stale orphans visible). Floaters that drop out of the visible set after a respec are hidden via the pool, never re-created.
- **Init/Rebuild ordering** — Rebuild now defers to Init if Init hasn't run yet, preventing a race where PLAYER_TALENT_UPDATE fires before LOGIN.

## v0.3.5 - 2026-05-07

- New `category = "shield"` field on TRACKED entries marks Lightning Shield, Water Shield, and Earth Shield as their own class (always-displayed with the missing-buff pulse), distinct from regular procs.
- **Two scale sliders** in Options → Proc Floaters: "Procs size" sizes the regular floaters (Stormstrike, Flurry, Sated, Clearcasting, etc), "Shields size" sizes the always-on shield floaters independently.
- Per-category global scale (`procs.scale` vs `procs.shieldScale`) still multiplies with each floater's per-entry override saved in `procs.perProc[<short>].scale`.

## v0.3.4 - 2026-05-07

- Main panel height bumped from 420 to 500 so the Options tab content (Proc Floaters + Twist sections) no longer spills out of the chrome.
- New **Proc Floater size slider** in Options (Proc Floaters section). Range 60% to 180%, scales every proc + shield floater uniformly via `host:SetScale`. Per-entry scale is still saved (multiplicative with global) for future per-floater controls.

## v0.3.3 - 2026-05-07

Per-talent filtering replaces the cruder spec-tag filter.

- New `WT.TalentRank(name)` helper scans all talent tabs and returns the player's current rank.
- TRACKED entries now use `talent = "<Name>"` instead of `spec = "<spec>"` for talent-gated procs (Stormstrike, Flurry, Earth Shield, Mana Tide, Clearcasting / Elemental Focus, Elemental Devastation, Eye of the Storm, Lightning Overload).
- Filter precedence is talent (per-ability) > spec (whole-tree) > always-allowed.
- ProcAlerts now rebuilds floaters on `PLAYER_TALENT_UPDATE` / `CHARACTER_POINTS_CHANGED` so respecs immediately re-filter the visible set without `/reload`.
- Combat-locked rebuilds are queued and flushed on `PLAYER_REGEN_ENABLED`.

Result: an Elemental shaman who didn't spec Eye of the Storm no longer sees its floater. A Resto shaman who hasn't taken Earth Shield (yet) won't see that one either.

## v0.3.2 - 2026-05-07

- Slider release fix: dragging the size slider's thumb past the slider's hit area no longer leaves it stuck to the cursor. Release detection now polls `IsMouseButtonDown` every frame instead of relying solely on `OnMouseUp`.
- "Cooldown / Proc Bar" section in Options renamed to "CD Bar" since procs split into their own floaters in v0.3.0.
- Water Shield floater is now Restoration-only. Lightning Shield stays available to all specs (Enhance and Elemental both use it).

## v0.3.1 - 2026-05-07

- **Shield missing-buff pulse.** Lightning Shield, Water Shield, and Earth Shield (target) floaters stay visible when the buff is missing, pulsing subtly between 25% and 55% alpha as a refresh reminder. Snap to full brightness + autocast shine the moment the shield goes back up.
- **Binding label clarified.** "Drop active preset" now reads "Drop active preset (all 4 totems in sequence)" so it's obvious that each press advances `/castsequence` rather than firing all four at once.

## v0.3.0 - 2026-05-07

Big refactor: procs and flashes split out of the cooldown bar into individual draggable floaters.

- **CD bar** now ONLY shows kind=cd / kind=both entries (the long cooldowns + spec talents). No more cluttered mixed-purpose row.
- **ProcAlerts module (new):** every proc/flash entry becomes its own 44x44 framed icon with full Wick chrome (void background, fel-green corner brackets, 1px border). Each is independently draggable.
- **Hidden when not active:** by default the floater is invisible. The frame appears only when the proc/buff/debuff fires, complete with autocast shine for proc-kind entries.
- **Edit mode** in Options forces all floaters visible (greyed) so you can drag them into position without waiting for procs. Toggle via Options or `/wtt procedit`.
- **Default layout:** 4-column grid below center on first run. `/wtt resetprocs` returns floaters to default positions.
- **Per-floater positions** persist in `WicksTotemsDB.procs.perProc[<short>]`.

## v0.2.6 - 2026-05-07

Coverage gaps from common shaman addons.

- **Shock cooldown tracker** — Earth / Frost / Flame Shock share one timer (6s base). Single icon shows the shared CD.
- **Sated / Exhaustion debuff tracker** — 10-min Lust lockout. New `auraAlt` field on TRACKED entries handles the dual-name case (Sated on Bloodlust, Exhaustion on Heroism).
- **Water Shield + Lightning Shield charge trackers** — buff stack count for both shaman shields.
- **Totem destroyed alert** — when an enemy kills a totem more than 5 seconds before its natural expiration, the OOR banner machinery fires `TOTEM DESTROYED: <Totem Name>` plus a `RAID_WARNING` sound. Totemic Call recalls are filtered out via `UNIT_SPELLCAST_SUCCEEDED` watch.

## v0.2.5 - 2026-05-07

Resizable bars.

- Per-bar **Size slider** in the Options panel for the totem icon strip, cooldown / proc bar, and swing timer. Range 60% to 180%, drag-to-set with live percentage readout.
- Scale persists per account via `WicksTotemsDB.{bar,cd,swing}.scale`.
- New `:SetScale(v)` method on each bar module — clamps to [0.5, 2.5] and applies via `host:SetScale`.

## v0.2.4 - 2026-05-07

Performance pass. No feature changes; addressing reported in-combat lag and stutter, especially in 25-man raids.

- **CooldownTracker**: 0.25s poller now early-exits when the bar is hidden. Cuts ~400 UnitBuff calls per second when the user has the bar toggled off.
- **CooldownTracker**: combat-log handler now early-exits when there are no flash-kind entries, uses a cached player GUID, and looks up flash spells via a pre-built spellName table instead of walking every entry. Negligible per-event cost in raid combat for non-Enhance specs.
- **SwingTimer**: text labels (formatted seconds) now refresh at 10Hz instead of every frame, and skip the SetText when the formatted value didn't change. Bar fill remains every-frame for smooth animation.
- **SwingTimer**: OnUpdate fully suspends after the post-combat fade-out completes. Combat-enter and the Show command re-attach it. No background wakeups while idle.
- **RangeWarning**: UNIT_AURA-driven Check is now throttled to 0.2s and skipped entirely when no buff totems are active. Stops a per-aura-tick storm in raids from re-walking 4 totem slots × 40 buff slots.
- **AffectedCount**: poll interval relaxed from 0.5s to 0.75s. Pre-built unit-name pools and a reused buffer eliminate per-poll string concatenation and table allocation, saving ~30 allocations per cycle in 25-mans.

## v0.2.3 - 2026-05-06

CD bar recovery + diagnostic visibility.

- `getActiveSpec` is now wrapped in pcall so a transient `GetTalentTabInfo` throw at PLAYER_LOGIN can't abort Init silently.
- Init prints "init starting" / "init done" markers to chat so it's obvious whether it ran and how many entries it built.
- New slash command `/wtt cdrebuild` — tears down the bar state and re-runs Init from scratch. Recovery for the "bar disappeared" case without a full /reload.

## v0.2.2 - 2026-05-06

Fix: cooldown bar disappearing after spec detection edge cases.

- RebuildForSpec no longer clobbers the bar when `getActiveSpec()` returns nil (talent data still loading after a respec or login).
- Skipped during combat (SecureActionButtonTemplate.SetParent is blocked) and queued for combat-end.
- Force-shows the host after rebuild unless explicitly hidden via Options.
- Init now keeps the host frame alive even when the initial entry list is empty, so the talent-update rebuild has something to populate.
- `/wtt cdtest` now reports active spec and host visibility.

## v0.2.1 - 2026-05-06

Spec-aware filter for the cooldown / proc bar.

- Each spec-specific tracker (Stormstrike, Flurry, Earth Shield, Mana Tide buff, Clearcasting, Elemental Devastation, Eye of the Storm, Lightning Overload) now only shows for the matching spec.
- Spec is detected from highest-points talent tab (Elemental / Enhancement / Restoration).
- Bar rebuilds automatically on respec via PLAYER_TALENT_UPDATE.

## v0.2.0 - 2026-05-06

Resto + Elemental coverage and precise totem range checks.

**Per-totem precise range**

- Embedded LibRangeCheck-3.0 (TBC variant) so the affected-count overlay uses true per-totem distance instead of the 40yd `UnitInRange` upper bound.
- A 20yd Stoneskin Totem now correctly reports zero affected when nobody is inside 20yd, even if multiple party members are within 40yd.
- Falls back to `UnitInRange` if the lib fails to load.

**Resto trackers (CD bar)**

- **Earth Shield (target)** — proc tracker; lights up when the targeted ally has Earth Shield, shows the stack count.
- **Mana Tide buff** — separate from the Mana Tide Totem cooldown tracker; lights up while the buff is pulsing on you so you can time your follow-up casts.

**Elemental trackers (CD bar)**

- **Elemental Focus (Clearcasting)** — 2-stack proc tracker; lights up when your spell crit sets up the next two free-mana casts.
- **Elemental Devastation** — proc tracker for the post-spell-crit melee-crit window.
- **Eye of the Storm** — proc tracker for the pushback-resist buff after taking damage.
- **Lightning Overload** — combat-log flash tracker; the icon swirls every time the talent procs a free Lightning Bolt or Chain Lightning copy.

**Carried over from v0.1**

Slim totem icon strip with secure cast buttons + keybind labels, affected-count overlay (now precise), out-of-range warning, totem twisting with click-now cue, swing timer, ankh reagent counter, editable presets, options panel.

## v0.1.0 - 2026-05-06

Initial release. Enhancement-focused shaman command bar.

- Slim totem icon strip with secure cast buttons + keybind labels
- Affected-count overlay on every totem (party / raid scan, 40yd cap)
- Count badge overlay on Blizzard's totem frame icons
- Out-of-range warning with red banner + screen vignette + sound on transition
- Totem twisting per element with click-now visual + audio cue (default air = Windfury <-> Grace of Air, 5s)
- Cooldown / proc tracker: Reincarnation, Bloodlust / Heroism, Fire and Earth Elemental Totems, Nature's Swiftness, Elemental Mastery, Tidal Force, Mana Tide, Shamanistic Rage, Flurry stack, Windfury Weapon proc flash, Stormstrike target debuff
- Main-hand and off-hand swing timer (combat-only)
- Ankh reagent counter on the totem strip (turns red when empty)
- Multiple named presets per character with editor (Presets tab)
- Options tab toggling every module
- Wick brand chrome (slim 28px header, two-tone title, fel-green L-brackets, multiplication-sign close)
