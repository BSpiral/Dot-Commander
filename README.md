Latest playtest polish: [PLAYTEST_POLISH_VERIFICATION.md](PLAYTEST_POLISH_VERIFICATION.md).

Current progression/economy/world-life implementation: see [WORLD_LIFE_PASS_VERIFICATION.md](WORLD_LIFE_PASS_VERIFICATION.md). Earlier foundation sections below are historical.

## Current pass: economy and port-loop correction

See [economy verification and handoff](ECONOMY_PASS_VERIFICATION.md) for earned 4–8h offline caps, automatic port service, disabled-ship recovery, cargo holds, category chests, schema-5 migration, 90 passing tests and native Release verification.

## Current pass: pre-closed-beta progression

Command slots, independent Trees, hull/equipment inventory, chests, CP and schema-4 persistence are implemented. See [progression verification and handoff](PROGRESSION_PASS_VERIFICATION.md) for formulas, changed files, 79 passing tests, Release builds and actual Android portrait captures.

# Current prototype status

Live hostile encounters now resolve before a two-card Deck reenactment, apply hull/crew losses, and award persistent coins/gems for player victories. See [ENCOUNTER_PASS_VERIFICATION.md](ENCOUNTER_PASS_VERIFICATION.md) for the current implementation and limitations. Earlier foundation notes below describe the preceding passes.

# Dot Commander: Pirates

Standalone Flutter/Flame project at `C:\AI\DotCommander`. The primary game screen extends the accepted
nautical map, deterministic simulation/navigation and local persistence; it does not replace them.
Flutter 3.44.6 / Dart 3.12.2, Flame 1.38.2, shared_preferences 2.5.5. Dependencies remain locked.

## Primary screen

The fleet bar provides five berths with actual owned-ship names. Empty berths are disabled; ship acquisition
is not implemented. Selecting a ship updates inspection/management/orders and pulses its map location.
The whole region stays visible; there is no player zoom or minimap. Gold trim marks player ships and the
selected ship has the strongest ring/pulse. Docked fleet icons leave room for future status treatments.

On portrait phones, the living map sits above a persistent management area occupying 38% of available
screen height (including tabs). A compact icon rail keeps standing orders beside the map. The current
mode is highlighted and included in the map status line; long-press tooltips name the icons.
At 900+ logical pixels, management becomes a 360-pixel side panel so the map is not reduced to a tiny
centered square. All five tabs remain visible. A GlobalKey preserves the Flame instance across layout changes.

- **Shop:** honest placeholder for future ships/supplies; no transactions.
- **Tree:** data-driven long-term tracks for Hull, Speed, Hold, Firepower, Crew Capacity, Rigging,
  Port Relations, Seamanship and Offline Efficiency. Expandable planned milestones: 10/50/100/500/1000.
  No progression levels, costs, purchases or effects exist yet.
- **Upgrades:** vertical owned-category lists for Crew, Ships, Equipment and Cannons/Gear. Existing
  crew/ship information is displayed; future ownership systems are explicitly not active.
- **Deck:** selected vessel stats, captain and a lightweight painted deck. No simulated crew/officers.
- **Settings:** pause/resume voyage and local-save information.

## Living world

The existing nautical style is retained: sandy coasts, shallows, printed navigation marks, piers and compass.
The region now has **22 land envelopes**, **6 ports**, **4 search destinations**, and varied decorative cays,
larger islands and ridges. Destinations use fictional names (Kingsford, Port Mercy, Black Gull Cay, etc.)
while retaining their old IDs for save compatibility. The fixed camera backs out from 960x720 to 1024x768.
Symbols are intentionally oversized; ship scaling and printed labels adapt to small map viewports.
The cached chart is rebuilt only when resize changes label scaling. Labels stay within its frame.

Fresh voyages contain one player and **14 persistent NPCs**: 5 merchants, 3 explorers, 3 pirates and
3 privateers. Restored identities/modes are preserved, so a migrated ecosystem may have a different mix.
Merchants visit different ports; explorers visit search points; pirates approach ships; privateers favor
pirates. After observing a ship, pursuers choose a different target more than 60 units away or a port,
preventing placeholder encounters from leaving a permanent stationary cluster. Port/observation pauses
remain two seconds. No combat or economic outcome is resolved.

## Hulls and speed

`lib/pirates/ships/hull_catalog.dart` centralizes hull stats, visual size/masts, personality and future affinity.
All hulls can use all behavior modes. Affinities are descriptive data, not active hidden bonuses.

| Hull | Base pace | Future affinity |
| --- | ---: | --- |
| Sloop | 66 | Starter progression / economical light work |
| Schooner | 53 | Exploration |
| Brig | 39 | Boarding and loot |
| Frigate | 30 | Pirate hunting |
| Galley | 35 | Merchant routes |
| Man-of-War | 20 | Major combat presence |

Effective pace = base pace × load factor × damage factor × (1 + reserved rigging bonus).
Load factors: Light 1.12, Normal 1.0, Heavy 0.72. Damage factor: 0.45 + 0.55 × remaining HP fraction.
Pace is an abstract world-unit value, not knots or real cargo mass. The rigging bonus defaults to zero and
has no purchasing/upgrading UI. Merchants cycle abstract loads after port stops; explorers alternate load
states after searches. This is a movement personality, not a cargo/economy system. No damage is inflicted.

## Code separation

- `lib/core/movement/`: pure coordinates and deterministic island visibility graph. Conservative land
  clearance is 10 units, with an extra 2-unit corner buffer for fixed-step rendered turns. Segment tests
  avoid per-island axis-list allocations. Static edges/routes are cached; moving targets replan periodically.
- `lib/core/simulation/`: vessel state, standing orders, target choice, route traversal and arrival/departure.
  No Flutter/Flame imports. The Flame adapter advances at 60 Hz with bounded catch-up; no offline simulation.
- `lib/core/persistence/voyage_snapshot.dart`: validated versioned model JSON; no render objects.
- `lib/pirates/world/`: region geometry, seeded identities, initial population and deterministic water relocation.
- `lib/pirates/ships/`: hull content/affinities, independent of behavior policy.
- `lib/pirates/visuals/`: cached chart and selectable ship components.
- `lib/pirates/persistence/`: asynchronous local storage and version-1 migration.
- `lib/ui/command_screen.dart`: fleet/map/order/management composition and lifecycle saves.
- `lib/ui/management/`: scalable progression definitions and separate management panels.

## Persistence and migration

The existing storage key remains `dot_commander.pirates.voyage.v1`; the JSON schema inside is now version 2.
Version 2 adds load/rigging fields and allows one to five owned ships. IDs, names, captains, positions,
destinations, orders, HP/crew and arrival pauses remain saved. Writes are serialized every five seconds,
on order changes and best-effort lifecycle/disposal events. Loading completes before play.

Version-1 voyages are validated against the old land map, retain their identities/orders/stats, adopt the
new catalog's base pace, and gain the missing named NPCs. A ship newly covered by added land is relocated
deterministically to nearby navigable water; ship-target coordinates are refreshed. Unaffected positions
stay unchanged. Renamed static destinations retain IDs. After saving version 2, migration does not repeat.
Unsupported/corrupt saves are preserved with autosave paused, rather than overwritten.

No RNG sequence or route caches are saved, so reload resumes state rather than a bit-identical future.
No cloud saves, accounts or time-away gains. Abrupt termination may lose the autosave interval. Android
still uses development signing; choose a production application ID/signing setup before distribution.

## Future work boundary

No combat, battle director, encounter outcomes, crew dots, boarding, cannon fire, economy, acquisitions,
equipment, active progression, monetization or offline rewards. Stable vessel IDs and render-independent
models remain the handoff for a separate 1–2 minute battle presentation. Pause/suspend the appropriate
models and apply results there; do not put outcome logic in ship components or the cached map.
Navigation is deliberately conservative and ignores dynamic ship collision; symbols may overlap briefly.
For new geography/schema changes, migrate saves instead of silently dropping them.

## Verify / run

```text
flutter test
flutter analyze
flutter build apk --release
flutter build windows --release
flutter run -d windows
```

See `GAME_SCREEN_VERIFICATION.md` for this pass's changed files, acceptance results and live checks.
Previous `WORLD_PASS_VERIFICATION.md` records the earlier accepted world pass.

## Phone-first Deck / theater foundation

The Deck now uses a horizontal broadside convention shared with a presentation-only battle timeline. Development builds offer a scripted preview; release builds do not expose it. The map and voyage remain independent of battle presentation. See [PHONE_THEATER_VERIFICATION.md](PHONE_THEATER_VERIFICATION.md) for the interfaces, coordinate conventions, tests and implementation handoff.





