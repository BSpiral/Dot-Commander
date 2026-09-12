# Dot Commander: Pirates — pre-closed-beta progression pass

All work is confined to C:\AI\DotCommander. Nothing published or uploaded.

## Layout and identity

Portrait is canonical: product header, five compact numbered command selectors, currency strip, full-width upper map, then a lower management area with Shop / Tree / Upgrades / Deck / Settings above its scrollable content. The map receives about 62% of the usable map/management area. Landscape uses the adaptive side layout. Orientation is checked explicitly rather than selecting a side layout solely because a display reports a large width.

Settings identifies CrowsNest as the studio and Dot Commander: Pirates as the product. Windward Reach stays on the actual map as a region.

## Commands, hulls and inventory

`FleetProgress.commands` is keyed by persistent vessel ID; the vessel retains name and captain. Every command has its own levels and item assignments. Hull changes mutate hull stats on that same vessel, not its identity or Tree. Five-command limit; sequential slot prices are 100, 750, 4,000 and 20,000 coins. Each purchase adds a unique name/captain, an empty Tree and a basic Sloop. New ships receive Flame components automatically and sail under standing orders. Player commands do not target one another.

The basic Sloop is an implicit fallback, not an inventory object. An obtained Sloop is a separate item with a unique ID and bonus stats. Every item copy has ID, kind, name, rarity, bonus and optional set ID. Supported kinds: hull, officer, equipment, cannon, gear. Duplicates remain distinct; a physical item can be assigned to only one command at a time. Unequip releases it. There are no set effects or final rarity mechanics.

Equipment changes preserve hull-health and crew-capacity proportions rather than granting a fresh full repair. Equipment and command Tree purchases are locked during an active battle. Reconfiguring a ship dismisses its old outcome card, preventing obsolete hull snapshots from invalidating later saves.

Shop buys a command or opens a chest immediately. Common costs 10 gems; Rare costs 50. Both give one equally selected item kind; hull rewards select among six hull classes. Common uses bonus strength 1 and Rare 3. The latest reward is shown in Shop and all copies are listed in Upgrades with assignment and equip/unequip controls. These are prototype tables, not final rarity odds.

## Tree and stat formulas

All tracks cap at 1,000. Next-level price from current level L is `1 + L + floor(L² / 100)` coins (first level 1 coin). No skill-point pool, respec or prestige.

Per-command tracks:
- Hull: +1 maximum HP per level.
- Firepower: +0.1 per level.
- Crew: +0.002 effectiveness per level, not extra sailors.
- Speed: +0.0005 × base hull speed per level.
- Handling: +0.0005 per level.
- Cargo: +1% to merchant arrival coins per level.
- Exploration: +1% to search arrival coins per level.

Fleet-only tracks:
- Port Relations: +0.1% to arrival coin rewards per level.
- Offline Effectiveness: 0.001 coin/minute/level while away, capped at 480 minutes and rounded down. No away battles or movement; rewards are saved before load returns. At very low levels a short absence may yield zero coins. Clock rollback gives no reward. Device-clock manipulation is not prevented by a backend.

Small beta income loop: merchant port arrival gives base 2 coins; explorer search arrival base 1. Arrival reward is multiplied by its relevant command track and Port Relations, rounded up. Every fifth qualifying fleet arrival gives a gem. Rewards apply only on the sailing-to-arrival transition, not every paused frame. This deliberately small loop makes peaceful progression possible. Rounding and prices need real-play balance tuning.

Derived stats live in `FleetProgress.apply`. Hull item strength adds 5 HP/unit; equipment adds 3 HP/unit; cannon adds 2 firepower/unit; officer and gear add 0.05 and 0.03 crew effectiveness/unit. Hull base firepower is 2 per mast. Crew upgrades never inflate literal crew counts.

CP (display estimate, decimal precision): `maxHullHP + 5×firepower + 1.5×actualCrew×crewEffectiveness + 0.2×baseSpeed + 20×handling`. Economic, exploration, port and offline levels do not affect it. The encounter resolver uses captured actual current HP, firepower, crew effectiveness, handling and speed; it does not read CP. Existing deterministic result-first battle/theater separation remains intact. Combat remains provisional.

## Save migration

Same existing local save key, schema 4 envelope. It contains ships/damage/destinations, encounters, wallet, all command and fleet levels, equipment assignments, inventory copies, last chest reward, visit count, item sequence and save time. Legacy v1-v3 saves gain independent zero-level command records; old non-Sloop hulls become assigned legacy hull items. Invalid progression or assignments fail loading without overwriting the original save. Schema-4 derived hull/speed stats are cross-checked against equipment. Active encounters resume their immutable results and cannot award twice.

## Changed files

Added:
- lib/pirates/progression/fleet_progress.dart
- lib/ui/management/progression_panel.dart
- test/progression_test.dart
- test/progression_income_test.dart
- test/progression_widget_test.dart
- PROGRESSION_PASS_VERIFICATION.md

Updated:
- lib/core/simulation/vessel.dart — mutable equipped hull stats and combat contributions.
- lib/core/simulation/simulation.dart — growable roster, excludes owned allies from pursuit.
- lib/core/persistence/voyage_snapshot.dart — accepts schema 4.
- lib/pirates/encounters/pirates_voyage.dart — transactions, command purchase, Tree/equip/chests, arrival income.
- lib/pirates/encounters/encounter_result.dart — captures effective combat contributions with legacy defaults.
- lib/pirates/persistence/voyage_store.dart — migration, full save envelope, capped offline claim.
- lib/pirates/visuals/pirates_game.dart — newly purchased ship rendering.
- lib/ui/command_screen.dart — explicit portrait, numbered selector, top management tabs, purchase saves.
- lib/ui/management/management_panel.dart — functional progression panels and studio branding.
- test/widget_test.dart — portrait above/below and landscape side geometry, unlocked Shop entry.
- test/encounter_test.dart, test/living_world_test.dart — schema 4 expectations.

## Automated verification

79 tests passed: previous 64 plus 9 progression model tests, 5 income/migration tests, and 1 actual phone purchase/equip widget test. Includes 320/360/390/430 portrait layouts, landscape/desktop, independent commands, max Tree, escalating costs, hull swap/save/reload, CP exclusions, duplicates, default vs obtained Sloop, equipment exclusivity, battle locks, currency persistence, offline cap/no duplicate claim/clock rollback, old-save migration, corruption preservation, and all previous encounter/navigation tests.

Final analyzer, native build and Android screenshot results are appended after verification.

## Deliberately deferred

No final economy/rarity/set balance, prestige, billing, ads, paid items, cloud saves, fleet/co-op battles, repair/recruitment economy, realistic physics or offline combat. The existing nonlethal encounter policy still accumulates damage; recovery and balance remain important before broad testing. Gear and officer items currently contribute simple stats, not detailed named-officer abilities. Inventory is intentionally a small scrolling list rather than a full RPG bag interface.

## Final results and actual Android inspection

- Full Flutter tests: **79 passed** (`build/progression-tests.log`).
- `flutter analyze --no-pub`: **No issues found**, 79.4 seconds (`build/progression-analyze.log`).
- Android Release: **success**, Gradle 77.4 seconds, APK **45.6 MB** (`build/progression-android-build.log`). Artifact: `build/app/outputs/flutter-apk/app-release.apk`.
- Windows Release: **success**, 54.2 seconds (`build/progression-windows-build.log`). Artifact: `build/windows/x64/runner/Release/dot_commander.exe`. Launched and verified responding; left running.

Installed the final APK into a temporary read-only emulator (1080x2400, 420 dpi, portrait). Inspected the actual native release, not a browser approximation. Confirmed full-width upper map, management below, tabs above management content, numbered five-command selector and readable Shop/Tree/Deck/Settings. No debug overlay is visible in release.

Observed natural port arrival/departure and coin/gem earnings. Bought Hull level 1 using earned coins; CP changed 130.2 -> 131.2, next cost became 2 coins. Force-stopped/relaunched only DotCommander, reopened Tree and confirmed level 1 and CP 131.2 persisted. Confirmed Settings shows `CrowsNest • Dot Commander: Pirates` while the map retains Windward Reach. The temporary emulator was stopped after capture, leaving its base image unchanged.

Actual Android artifacts:
- `build/verification/progression-portrait.png` — canonical upper map and lower Deck.
- `build/verification/progression-tree.png` — per-command Tree before purchase.
- `build/verification/progression-tree-purchase.png` — level 1 and increased CP.
- `build/verification/progression-relaunch.png` — saved level/CP after relaunch.
- `build/verification/progression-shop.png` — 100-coin next command and 10/50-gem chests.
- `build/verification/progression-settings.png` — CrowsNest branding and local save description.

Command purchase, chest opening and hull equip were additionally exercised through real Flutter widget controls with a funded test fixture; the native emulator check used naturally earned coins for the Tree purchase. Offline cap, reward nonduplication, duplicate items and large Tree/hull migration scenarios were automated tests rather than multi-hour live observations. Physical-device testing and final Android distribution signing remain outside this local build verification.
