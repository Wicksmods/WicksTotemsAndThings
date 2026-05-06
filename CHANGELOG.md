# Changelog

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
