# Continuation notice

The live encounter/currency pass supersedes the foundation-only status below. See [ENCOUNTER_PASS_VERIFICATION.md](ENCOUNTER_PASS_VERIFICATION.md) for current authority boundaries, version-3 saves, card rendering, audio and verification.

# Phone-first / battle theater handoff

## Scope and files

Updated `lib/ui/command_screen.dart`: five compact fleet berths, 48 dp orders in a horizontal map rail on phones, a reserved 60 dp rail strip preventing chart occlusion, full-width fixed chart, management at approximately 38% of the area below the fleet (minimum 170 dp), bottom tabs. Landscape phones adapt to a split layout; desktop retains its wider management column. Selection still pulses the selected ship on the map; the full fixed world is visible, so no camera pan, zoom, minimap or new coordinate system was introduced.

Updated `lib/pirates/visuals/chart_component.dart`: reduced adaptive label enlargement after inspecting the real Android screen; all destinations remain labeled.

Updated `lib/ui/management/management_panel.dart`: horizontal Deck uses the shared theater renderer, with ship information below. Development-only preview entry; no preview controls in release.

Added:
- `lib/pirates/theater/battle_script.dart`: pure Dart presentation contract and seekable sampler.
- `lib/pirates/theater/preview_script.dart`: explicitly fabricated boarding and escape fixtures.
- `lib/ui/theater/deck_theater.dart`: broadside geometry, deck renderer, minimal damage/projectile/smoke demonstration and development preview.
- `test/theater_test.dart`: timeline validation, deterministic sampling, escape, damaged boarding, geometry and preview checks.

Updated `test/widget_test.dart`: 320x568, 360x780, 390x844, 430x932, 844x390 and 1200x800; fleet bounds, minimum control sizes, bottom navigation, broadside aspect, all tabs and resizing. Existing five-ship selection/order and save tests retained.

## Landing point for later combat

The simulator must supply an outcome BEFORE presentation begins. `BattleScript.ending` is supplied, never calculated by the renderer. No damage is applied to voyage vessels. No encounter detector, battle director, combat RNG, draw threshold, balancing or persistence integration was added.

`BattleScript` contains immutable timed `TheaterKeyframe` values and `CannonCue` effects. `sample(elapsedSeconds)` is a pure seek operation: positions/headings interpolate; phases, damage and planks switch at keyframes. Seeking/replay does not repeat side effects. Negative time clamps to the start, time after the end clamps to completion. Invalid durations, non-finite poses and damage fractions are rejected. Scripts can last 60–120 seconds or any other supplied duration; the 13-second fixtures are deliberately short for development, not final battle timing.

`DeckPose`: normalized stage x/y, y down, heading in radians. Ships face right at heading zero. Heading interpolation uses supplied continuous angles (unwrap before supplying a turn across 2*pi). Poses may leave the unit square for an escape. The renderer clips to the stage. Ship-local x follows the horizontal bow/stern axis; local y crosses the deck. `DeckGeometry` uses a 3.8:1 footprint with three shared plank stations. Later actor positions/paths should attach to ship-local deck coordinates and transform with the ship, not use independent screen pixels.

The phases are encounter, maneuver, cannon, escape, closing, boarding and complete. The scripted cannon cues occur while ships move, before boarding alignment. Escapes need not contain a boarding phase. Projectile endpoints/times are supplied cosmetic data, not collision tests. The future director should convert a deterministic result into poses, cues, phase durations and an explicit completion event; resolve voyage effects once outside the renderer, not on every sample or animation rebuild.

`TheaterDamage` carries hull damage, sail damage, smoke and remaining representative-crew fraction in [0,1]. Hull darkening/cracks, shortened sail spars and smoke are demonstrated. Crew fraction is a data hook only; crew actors/casualties are intentionally not rendered. Later use a bounded representative roster (not one actor per actual sailor), stable actor IDs and continuous ship-local paths. Ranged positions, melee crossing, 1–2 rope swings and victor occupation should be scripted atop the same deck geometry. The three plank anchors demonstrate the available inter-deck gap; no boarding combat exists.

Future cannon-type mechanics (regular/grape/chain/explosive/long-range), escape math, draw thresholds, loss/loot calculations, final durations and battle interruption/resume policy belong to the future simulator/director. Do not infer these rules from the visual fixtures. The theater currently renders a shared mast count for both demonstration ships; later asset/actor specifications can provide per-ship hull silhouettes without changing the timeline coordinate convention.

## Preserved systems

No simulation, navigation, hull-catalog, role-affinity or persistence code changed in this pass. The 22 land regions, 10 destinations, 14 NPC ships and player fleet remain. Save schema remains version 2, with the existing version-1 migration and invalid-save preservation. No battle is saved because none is connected to a voyage. Autosave and order changes retain their existing behavior.

## Automated acceptance

- Focused suites: 10 widget tests and 7 theater tests passed.
- Full Flutter suite: 48 passed.
- `flutter analyze --no-pub`: no issues found.

Release build and practical inspection results are recorded below. Physical-device performance, final combat, representative crew, final ship art, progression and economy are deferred. Nothing is published.


## Practical inspection

Android: used the already installed emulator system image in a temporary read-only session (no existing AVD contents changed). The initial windowed instance ended during verification, so the successful check used a headless Android emulator with ADB screenshots and app input. Display: 1080x2400 at 420 dpi, approximately 411x914 dp before system insets.

Installed the local release APK, launched the actual Android activity, inspected the full chart, all five fleet slots, broadside Deck, readable bottom tabs and standing orders. Tapped Explorer and observed the order and search destination change. Opened Tree while the map kept running; tapped the player fleet slot and observed its locate pulse. NPCs moved between captures, including docked anchor indicators at ports; the simulation tests additionally verify repeated docking/departure over ten minutes. Force-stopped only Dot Commander, installed the final APK over it, relaunched, and confirmed Sea Lark's name and Explorer order persisted with all 15 ships. Release UI contains no theater-preview or FPS control. Representative screenshots are under `build/verification/` (generated artifacts, not source).

Windows: launched and visually inspected the release, horizontal Deck, adaptive management column, nautical map and 15 ships. Relaunch restored Sea Lark's saved Privateer order. Left the release executable running and responsive. Phone widths other than the emulator's approximately 411 dp, and landscape, are covered by widget tests; no physical-device performance testing is claimed.

The battle preview is validated by widget/pure-data tests. It is deliberately unavailable in the release app and has not been connected to an actual encounter. Crew fraction is an unrendered hook; no crew-dot combat, outcomes, loot or economy were implemented.

Persistence/schema: unchanged. Dependencies: unchanged. No new migrations, accounts, cloud services or publication. Crownest/Game Shelf source was not accessed or modified during this pass.

## Final build results

- Full `flutter test --no-pub`: **48 passed** (including 10 widget and 7 theater tests).
- `flutter analyze --no-pub`: **No issues found** (8.8 seconds).
- Android `flutter build apk --release --no-pub`: **success**, 58.6 seconds, 44.5 MB. Artifact: `C:\AI\DotCommander\build\app\outputs\flutter-apk\app-release.apk`.
- Windows `flutter build windows --release --no-pub`: **success**, 50.2 seconds. Artifact: `C:\AI\DotCommander\build\windows\x64\runner\Release\dot_commander.exe`.
- Final Android APK was installed and launched again after the rail-clearance safeguard. Screenshot: `build/verification/android-final.png`. Name/order persisted; chart and rail do not overlap.
- Android signing remains the existing development key; no upload/publishing occurred.
- The temporary headless emulator was stopped after verification. Windows release was left running.

