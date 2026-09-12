# Primary game screen / living-world verification

## Changed files

Added:

- `lib/pirates/ships/hull_catalog.dart`
- `lib/ui/management/progression_tracks.dart`
- `lib/ui/management/management_panel.dart`
- `test/living_world_test.dart`
- `GAME_SCREEN_VERIFICATION.md`

Updated:

- `lib/core/simulation/vessel.dart`
- `lib/core/simulation/simulation.dart`
- `lib/core/movement/sea_navigation.dart`
- `lib/core/persistence/voyage_snapshot.dart`
- `lib/pirates/world/caribbean.dart`
- `lib/pirates/persistence/voyage_store.dart`
- `lib/pirates/visuals/pirates_game.dart`
- `lib/pirates/visuals/chart_component.dart`
- `lib/ui/command_screen.dart`
- `test/widget_test.dart`
- `test/simulation_test.dart`
- `test/navigation_test.dart`
- `README.md`

No new dependency, Crownest/Game Shelf work, physics, combat, publishing or monetization.

## Automated acceptance

Final full `flutter test --no-pub`: **38 passed**.

- 11 simulation/model tests.
- 5 navigation tests, including all destination pairs and every movement segment over ten simulated minutes.
- 9 persistence tests covering state, serialization, corruption and write recovery.
- 6 living-world tests covering hull/load/damage pace, all-role usability, ten-minute merchant activity,
  version-1 migration, up-to-five ownership, close-contact departure and no indefinitely stationary NPCs.
- 7 widget tests covering 320x568 / 390x844 / 1200x800 layouts, five owned-ship order selection, all five tabs,
  the portrait management height, save reload/error protection and retaining the live game across resize.

Final `flutter analyze --no-pub`: **No issues found**.

The merchant activity test verifies every merchant sails for more than 65% of the test and that no port
pause exceeds roughly two seconds. The full NPC test checks that nobody remains stationary beyond the
short arrival interval. Damage modifiers are tested without introducing combat or damage events.

## Intentional limitations

Five berths are supported but new voyages still begin with one owned ship; no ship acquisition was added.
Tree milestones, affinities and Upgrades categories are foundations, not active progression/bonus systems.
No real cargo, ship-to-ship collision, combat or offline progression. Hull silhouettes are symbolic scale.
Physical Android-device/performance testing is not claimed; portrait dimensions are covered by widget tests.

## Release builds and live verification

- Windows Release: succeeded in 29.9 seconds; `build/windows/x64/runner/Release/dot_commander.exe`.
- Android Release APK: succeeded in 47.9 seconds, 44.4 MB; `build/app/outputs/flutter-apk/app-release.apk`.
- Android retains the project development signing setup; nothing was uploaded or published.
- Launched the final Windows executable and inspected the nautical map, 15-ship population, fleet bar, hull silhouettes, and desktop management panel.
- Opened Tree and expanded Hull to verify the planned 10 / 50 / 100 / 500 / 1000 milestones; opened Upgrades and checked the separate owned-content categories.
- Observed Sea Lark docking with an anchor indicator and subsequently sailing again while management remained available.
- Changed Sea Lark from Merchant to Explorer through the order rail and observed its destination change to a search location.
- Closed and relaunched the final executable. Sea Lark retained its identity and Explorer order, the map retained 15 ships, and autonomous travel/observation continued.
- Left the final release app running on Deck. Phone layouts were verified by widget tests, not a physical device.
