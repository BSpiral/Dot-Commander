# Encounters, mobile Deck cards and currency — continuation handoff

## Current behavior

The production voyage now detects hostile ship meetings. Pirates pursue other ships; Privateers initiate against Pirates; Merchants and Explorers do not initiate attacks but can defend or escape. Two owned ships cannot fight each other. A clear water segment and distance <=22 world units are required. Stable ID ordering resolves simultaneous candidates. Both participants are reserved and held while the rest of the map continues. A ship cannot participate in two encounters. A 45-second per-ship cooldown prevents immediate rematches.

A player-involved encounter opens Deck once when first noticed, without preventing later tab changes. The map and fleet show battle indicators. At completion ships resume their standing orders, keeping hull and crew losses. The latest player result remains readable until dismissed with Return to deck or replaced by a later result. Coins/gems are visible under the fleet bar.

## Authority boundaries

- `Combatant` captures immutable before-state; `EncounterResult` holds identity, kind, winner/draw/escaped identity, exact hull and crew losses, and rewards.
- `EncounterResolver` is the replaceable interface. `PrototypeResolver` resolves BEFORE any animation. Its deterministic prototype policy compares hull HP + crew*1.5, uses a 5% draw band, lets sufficiently faster peaceful defenders escape, and uses a large strength difference for cannon defeat; otherwise boarding. These are placeholders, NOT final balance.
- `PiratesVoyage` extends the existing reusable `Simulation`: detects, reserves participants, advances time, applies the result once, grants rewards, releases participants and records cooldowns. Applying/removing the active run is synchronous. Rendering and seeking cannot apply consequences.
- `scriptForResult` translates the immutable result into the existing immutable/seekable `BattleScript`. `BattleDeck` reads elapsed simulation time. It swaps presentation order when necessary so the owned ship is above the enemy, preserving the explicit escaping identity.
- `createCaribbean()` retains sailing-only defaults for focused movement fixtures. Production `VoyageStore.load()` always enables encounters. New gameplay callers should use `createCaribbean(encountersEnabled: true)` or load the store.

## Deliberately small rules

Victory by an owned ship currently grants 25 coins and 1 gem. Draws, defeats and escapes grant none. No spending/store balance or progression has been added. Defeats are non-lethal in this pass: ships remain in the 15-ship world and sail with reduced stats. There is no sinking, capture, repair, recruitment or respawn loop. Damage accumulates and the starter Sloop can lose repeatedly; balance/recovery is intentionally future work, not a finished gameplay loop.

Hull plank capacities: Sloop/Schooner 1; Brig/Frigate 2; Galley 3; Man-of-War 5. Connections use min(A,B), including five-lane support in `BattleScript` validation. Lanes are visual only.

Representative count begins at importantCrew + 1 + floor(actualCrew/100), then clamps to the hull's readability range: minimum 4/5/6 for small/medium/large hulls; maximum 5/7/10, always <= actual surviving crew. Only the existing captain is currently named/important; other dots are generic representatives, not invented officers. The helper accepts a future assigned-important-crew count. The losing side's supplied crew fraction removes representatives at completion; a few melee representatives interpolate across planks while the captain/ranged stand-ins remain. No actor decides damage or victory.

## Presentation and phone UI

The existing portrait composition remains canonical at 320/360/390/430 dp: compact five-ship fleet, full-width chart with a separate touch-friendly order rail, bottom management and five tabs. The currency strip uses flexible text and a compact battle icon. Management remains approximately 38% of the useful area below fleet/currency. Landscape/Windows adapt side by side. Narrow panels scroll vertically rather than shrink text or cover the map.

Decks are broadside rectangular place-cards with a small bow silhouette, about 90% stage width, a few crew dots and simple cannons. In battle, two parallel cards close/separate; they are independent of world-map geometry. The compact stage caps each deck's height to preserve an inter-card gap. Phase/result text is above the cards. Damage darkening/cracks, sail spars, smoke, cannon flashes and a winner flag demonstrate the supplied story. Precise naval trajectories and physics are absent.

One original synthetic 0.5-second cannon WAV is included, played quietly through audioplayers 6.8.1 while the visible theater crosses a cannon cue. Replay/seek does not apply gameplay effects. Sound can be disabled in Settings and is saved. Audio failure does not affect battle completion. Asset is locally generated, with no third-party artwork/audio licensing dependency. Package reference: https://pub.dev/packages/audioplayers

## Persistence

Production snapshots are version 3. Existing v1 land/population migration and v2 ships remain supported. The storage key is intentionally unchanged. One JSON write contains ships, coins/gems, sound preference, next encounter ID, active immutable results plus elapsed time, recent result receipt and cooldowns. On reload an active result resumes without rerolling; on completion its rewards are applied once. An already completed result is only a receipt, never reapplied. Identity/damage/reservation validation rejects malformed encounter state and the existing UI preserves invalid source data with autosave paused. No offline simulation was introduced.

`VoyageSnapshot` remains the reusable ship serializer; `VoyageStore` adds the Pirates envelope. Do not save only `simulation.ships` for gameplay sessions, because that omits active encounters and currency.

## Changed files

Added:
- `lib/pirates/encounters/encounter_result.dart`
- `lib/pirates/encounters/pirates_voyage.dart`
- `lib/pirates/ships/crew_representation.dart`
- `lib/pirates/theater/result_script.dart`
- `lib/ui/theater/battle_deck.dart`
- `lib/ui/audio/cannon_audio.dart`
- `assets/audio/cannon.wav`
- `test/encounter_test.dart`
- `test/battle_widget_test.dart`
- `ENCOUNTER_PASS_VERIFICATION.md`

Updated:
- `lib/core/simulation/vessel.dart`: engaged activity, mutable crew count.
- `lib/core/simulation/simulation.dart`: generic held-ship support; excludes held pursuit targets.
- `lib/core/persistence/voyage_snapshot.dart`: accepts v3 envelope/engaged ships.
- `lib/pirates/world/caribbean.dart`: constructs PiratesVoyage over unchanged world/navigation content.
- `lib/pirates/ships/hull_catalog.dart`: plank capacities and representative caps.
- `lib/pirates/persistence/voyage_store.dart`: v3 atomic session envelope and old-save support.
- `lib/pirates/theater/battle_script.dart`: up to five visual planks.
- `lib/pirates/visuals/pirates_game.dart`: engaged map indicator.
- `lib/ui/theater/deck_theater.dart`: simplified cards, bounded crew and plank crossing.
- `lib/ui/management/management_panel.dart`: actual encounter view and sound setting.
- `lib/ui/command_screen.dart`: currency, battle status, event saves and Deck selection.
- `test/widget_test.dart`, `test/persistence_test.dart`, `test/living_world_test.dart`: useful-area layout assertion and v3 expectations.
- `pubspec.yaml`, `pubspec.lock` plus generated Android/Windows plugin/dependency metadata from adding audioplayers.
- `README.md`, `PHONE_THEATER_VERIFICATION.md`: point to this continuation.

## Automated verification

Full `flutter test --no-pub`: 64 passed. Includes the previous 48 tests, 10 encounter tests and 6 active-battle widget tests. Tests cover every requested phone width plus landscape/desktop, portrait management placement, readable card geometry, all hull pair plank minima, crew caps, cannon/boarding/escape/draw resolution, role restrictions, busy/allied ship exclusion, rendering non-authority, in-battle save/resume, completed-result/reward reload, corruption rejection, world navigation and identity persistence.

`flutter analyze --no-pub`: no issues found (12.2 seconds).

Final build and live inspection details are appended below. No final combat balance, progression, Shop, paid systems, ads, cloud features, co-op battles, 1:1 crew simulation or realistic physics were added. Crownest/Game Shelf were not modified. Nothing was uploaded or published.

## Final native builds and practical checks

- Full tests: **64 passed**. Final analysis: **No issues found** (12.2 seconds).
- Android Release: **success**, 74.5 seconds, **45.6 MB**. `C:\AI\DotCommander\build\app\outputs\flutter-apk\app-release.apk`.
- Windows Release: **success**, 61.4 seconds. `C:\AI\DotCommander\build\windows\x64\runner\Release\dot_commander.exe`.
- Android still uses the project's existing development signing configuration; nothing was uploaded.

Actual Android portrait inspection used the available emulator in a temporary read-only, headless session, with ADB screenshots/input. Display was 1080x2400 at 420 dpi (approximately 411x914 dp before insets). The base emulator contents were not modified. Inspected fleet, coin/gem strip, full chart, order controls, normal four-dot Sloop deck and persistent bottom tabs. Changed Sea Lark to Pirate and observed natural encounters with Coral Wind and Venture, battle indicators/held ships, two-card damage and victory presentation, followed by resumed sailing. The final build also showed Juniper's escape and the enemy card leaving the theater.

Force-stopped only Dot Commander, installed the final APK over the existing app and relaunched. Sea Lark's Pirate order, accumulated damage and latest encounter result survived; all 15 ships remained. The observed live defeats/escape granted no rewards, as designed. Positive coin/gem reward persistence and no-duplicate application are proven by automated battle/save tests, not claimed as a live victory observation. Boarding/plank/crew-crossing behavior is covered by the pure/widget tests; the captured live cases were non-boarding/escape. Physical Android hardware performance and independent auditory assessment were not performed.

Windows final release launched successfully, restored the existing voyage, and showed a natural player-involved cannon encounter in the adaptive layout with currency and both cards. App remained responsive. The temporary Android emulator was stopped after verification; Windows release was left running.

Local Android artifacts:
- `build/verification/encounter-portrait.png`: normal Deck, currency and map.
- `build/verification/encounter-orders.png`: Pirate standing order.
- `build/verification/encounter-progress.png`: engaged player and two-card theater.
- `build/verification/encounter-live.png`, `encounter-board-or-result.png`: completed non-boarding outcomes/damage and continued movement.
- `build/verification/encounter-final-android.png`: final release after save/relaunch, readable escape outcome.

No unresolved test/analyzer/build failure remains. The principal next-design concern is deliberate: persistent attrition has no recovery/repair system yet, and the starter Sloop is weak against larger hulls. Replace/tune `PrototypeResolver` and define recovery/sinking/economy policy before treating this as balanced combat. Keep result application and save transactions outside the theater when doing so.
