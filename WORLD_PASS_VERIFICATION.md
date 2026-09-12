# World / visual pass verification

Continued the existing standalone project; no Crownest or Game Shelf files changed.

## Changes

- Irregular sandy islands and shallows, inland relief, port towns/piers/open-water berths,
  restrained search symbols, compass rose, chart grid/rhumb lines and water texture.
- Cached Canvas chart with responsive label scaling for phone/desktop layouts.
- Larger/differentiated hull silhouettes and mast counts, player trim/halo, wakes and dock anchors.
- Deterministic visibility-graph routing around shared conservative island bounds.
- Versioned local JSON snapshots, serialized autosaves, load-before-play and background pause.
- Corrupt/unsupported saves are retained and not automatically overwritten.

## Files / areas

Added:

- `lib/core/movement/sea_navigation.dart`
- `lib/core/persistence/voyage_snapshot.dart`
- `lib/pirates/persistence/voyage_store.dart`
- `lib/pirates/visuals/chart_component.dart`
- `test/navigation_test.dart`
- `test/persistence_test.dart`
- `WORLD_PASS_VERIFICATION.md`

Updated:

- `lib/core/simulation/simulation.dart`
- `lib/pirates/world/caribbean.dart`
- `lib/pirates/visuals/pirates_game.dart`
- `lib/ui/command_screen.dart`
- `lib/main.dart`
- `test/widget_test.dart`
- `pubspec.yaml`, `pubspec.lock`, generated Flutter plugin registration metadata
- `README.md`

## Tests / analysis

`flutter test`: **30 passed** after the final responsive label change.

- 11 existing simulation/model tests.
- 5 navigation tests, including deterministic routes, unreachable goals, every destination pair,
  initial water validity, multi-segment movement and every movement segment during ten simulated minutes.
- 9 persistence tests: model/dock-state round trip, target identity, malformed/future saves,
  local-store reload, write serialization and recovery from a failed write.
- 5 widget tests: 320x568, 390x844, 1200x800 startup/orders, saved identity/order load and
  invalid-save preservation.

`flutter analyze`: **No issues found** after the final responsive label change.

## Live Windows check

Inspected the normal Release chart, selected player/readable ships and nautical map details.
Observed arrived NPCs with anchor indicators at ports and moving ships with wakes. Changed Sea Lark
from Merchant to Explorer; its destination switched to search locations. Closed and relaunched the app;
Explorer order and the saved living fleet resumed, including an observing/search arrival state. No debug
FPS overlay was visible in Release. Ship-to-ship crowding is still expected; no combat/separation was added.

Phone dimensions were checked by widget tests; no physical Android-device play/performance test was run.
The final label-size adjustment was retested and both Release artifacts rebuilt afterward.

## Intentional boundaries

No combat/battle renderer, economy, repair/restocking, ship-to-ship collision, cloud accounts, monetization
or offline progression. Navigation uses conservative island envelopes and symbolic oversized icons, not
precise hull/coast collision. Saves preserve current state but not RNG sequence or route caches. Autosaving
is best effort (up to five seconds of loss on abrupt termination); production save migrations/signing remain
future work. See README for the independent simulation / future battle-presentation handoff.

## Final Release artifacts

- Android: **passed**, `flutter build apk --release --no-pub`, 86.4 seconds, APK 44.5 MB.
  `build/app/outputs/flutter-apk/app-release.apk`
- Windows: **passed**, `flutter build windows --release --no-pub`, 77.7 seconds.
  `build/windows/x64/runner/Release/dot_commander.exe` (retain the entire Release folder).
- These are local builds; Android retains development signing. Nothing was uploaded/published.
