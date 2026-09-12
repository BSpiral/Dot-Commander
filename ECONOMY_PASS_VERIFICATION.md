# Economy / port-loop / chest correction pass

Only C:\AI\DotCommander was changed. No monetization, sets, prestige, fleet battles, uploads or publication.

## Offline cap

The fleet-wide Offline Tree controls the shared cap (new command slots do not have independent offline caps). Current minutes = `240 + floor(240 * clamp(level, 0, 1000) / 1000)`: level 0 is 4h, 500 is 6h, 1000 is 8h. Bounds and progression maximum are centralized in Balance. The existing income rate remains 0.001 coin/minute/level, rounded down. Load-time calculation uses the earned cap derived from saved Tree levels; no duplicate persisted cap can drift from the Tree. Tree and Settings show the actual current hours/minutes. No offline battle simulation was added.

## Zero hull and port service

Zero hull ships cannot initiate or be selected for combat. Hull below one point is normalized to zero because the existing integer display would show zero; this also stops asymptotically damaged ships from fighting forever. A disabled ship receives a persistent `recovering` flag and heads toward its nearest port, using the existing obstacle avoidance and damaged movement speed as a simple recovery tow. Standing orders stay intact. Changing orders does not cancel recovery. Legacy/externally disabled active participants abort that encounter without awarding its pending result.

On port arrival, every role is serviced automatically, once per arrival transition:
1. Sell carried cargo.
2. Pay for missing hull.
3. Pay for missing crew.
4. Apply the net coin result and store a receipt.
5. Refill the hold with simple voyage cargo and resume after the normal two-second pause.

NPC service does not spend the player's wallet. Player repairs use cargo proceeds plus the existing wallet. If this cannot cover service, repairs take priority over crew charges; available coins are spent, the shortfall is recorded as port aid, and hull/crew are fully restored and the ship waits through an extended ten-second dock pause. No debt, negative wallet, sinking or permanent disablement. This aid policy is deliberately provisional and exploitable as a generous safety net; later balance should tune it rather than strand a zero-hull command.

Repair quote = `ceil(max(0, maxHP - HP) * 1 coin * repairMultiplier)`. Default multiplier 1: 93/100 costs 7. Recruitment quote = `ceil(max(0, hullCrewCapacity - actualCrew) * 0.25 coin * crewMultiplier)`. Default: 12 missing crew costs 3 coins. Positive fractional charges round up. Separate multiplier inputs reserve straightforward hooks for future Tree/equipment/Port Favor effects; no set or officer discount logic was invented.

## Cargo and ledger

Hull hold capacities: Sloop 4, Schooner 6, Brig 8, Frigate 10, Galley 12, Man-of-War 16. One hold carries one unit. Hull swaps clamp carried cargo to the new hold capacity; saves reject over-capacity cargo.

Sale = `floor(units * 10 * (1 + CargoTreeLevel * .01) * (1 + PortFavorLevel * .001))`. CP is not consulted. A baseline full Sloop voyage sells 4 units for 40 coins. Initial/legacy saves start with zero cargo, then receive a full hold at first port service. Restocking is free prototype voyage cargo, not a simulated commodity purchase. The old flat merchant arrival reward is replaced by cargo proceeds. Exploration/search rewards and every-fifth-qualifying-visit gems remain.

`PortReceipt` records command, port, units, gross sale, quoted repair/crew charges, paid charges, net wallet change and derived aid. Ordering example: +40 cargo, -7 repairs, -3 crew = +30 net. Deck displays the latest selected-command receipt; the current hold count is displayed with ship stats. Only the latest fleet receipt is retained to keep this small.

## Chests

Explicit `ChestCategory` (hull/equipment/crew/cannon) is required by the opening API and reward roll; rarity remains Common/Rare. Shop contains eight choices. Hull -> hull items only; Equipment -> ship equipment only; Crew -> officer items only; Cannon -> cannon items only. Common remains 10 gems and Rare 50. Unique per-copy IDs and duplicates are preserved; existing gear items remain valid inventory/equipment even though these eight chests do not currently generate gear. A reward snackbar gives immediate feedback without requiring scrolling to the last-reward list. No ad API was added; explicit categories can be used by a future caller.

## Save compatibility

Schema 5 adds cargo/recovery ship fields and the optional latest port receipt. Versions 1-4 remain accepted. Command IDs, names, Trees, equipped hulls, inventory copies, balances and combat contributions are preserved. Missing old economy fields default to empty cargo/no recovery; disabled ships are routed to recovery on their next simulation tick. Offline cap is recalculated from the existing fleet Offline level. Chests are opened immediately, so there are no unopened generic chest objects to migrate.

## Files changed

Added:
- lib/pirates/economy/port_economy.dart
- test/economy_test.dart
- test/economy_widget_test.dart
- ECONOMY_PASS_VERIFICATION.md

Updated:
- lib/core/simulation/vessel.dart: cargo and recovery state.
- lib/core/simulation/simulation.dart: excludes disabled/recovering pursuit targets.
- lib/core/persistence/voyage_snapshot.dart: schema 5 and cargo/recovery serialization.
- lib/pirates/ships/hull_catalog.dart: hold capacities.
- lib/pirates/progression/fleet_progress.dart: earned cap, explicit chest categories, cargo clamp on hull swap.
- lib/pirates/encounters/pirates_voyage.dart: recovery routing, combat exclusions/abort, automatic service and ledger.
- lib/pirates/persistence/voyage_store.dart: earned-cap calculation, migration and cargo validation.
- lib/ui/command_screen.dart: recovery tow status.
- lib/ui/management/management_panel.dart: current cap, recovery message, cargo and port receipt.
- lib/ui/management/progression_panel.dart: eight chest buttons, category API, reward feedback, earned-cap text.
- Existing progression/encounter/living-world tests: explicit chest categories, schema 5 and cargo-income expectations.

## Verification

Full Flutter suite: **90 passed** (79 previous tests plus 9 focused economy tests and 2 economy UI tests).
`flutter analyze --no-pub`: **No issues found**, 5.7 seconds.

Coverage includes default/earned/max offline caps and payout reload, 0-hull pursuer and target exclusion, real movement to port and resumed behavior, automatic all-role service, exact quote/net ordering, insufficient-money aid, refill/restock bounds, all eight chest pools/prices/duplicates, current cap UI, reward feedback and progression-save compatibility. Existing battle, world/navigation, phone layouts and progression tests still pass.

Native build and live probe results follow below.

## Native builds and live verification

- Production Android Release: success, 42.9 seconds, **45.9 MB**. `build/app/outputs/flutter-apk/app-release.apk`.
- Production Windows Release: success, 61.4 seconds. `build/windows/x64/runner/Release/dot_commander.exe`. Launched and left running.
- Normal Android APK was preserved before the separate probe build, restored to both standard APK output paths, and its SHA-256 matched the preserved production artifact. The probe is not the deliverable.

Actual Android native verification used the same temporary read-only emulator at 1080x2400/420 dpi. A separate `build/economy_probe.dart` entry point injected a new, non-persisting voyage with 0 hull, 6 crew, empty hold, zero coins and Pirate orders. To make the initial tow leg observable, the fixture temporarily used speed 1 and restored normal speed 66 after 40 seconds. The normal port/combat/economy implementations were used; no player save was modified.

Observed: `recovery tow -> Haven Cay`, no combat during that state, then a Haven Cay ledger showing 0 cargo, 0 paid repair/crew, net 0 and **83 coins port aid** (80 hull + 3 recruitment). Afterwards Sea Lark resumed Pirate activity, entered a new encounter against Salt Finch and continued moving. This demonstrates that normal combat resumed after service, rather than at zero hull. Exact restored HP/crew and service timing also have automated assertions.

Artifacts:
- `build/verification/economy-zero-hull.png`: native recovery tow/message.
- `build/verification/economy-port-recovery.png`: Haven Cay aid receipt and subsequent resumed encounter.
- `build/verification/economy-resumed.png`: resumed activity/result.
- `build/verification/economy-release.apk`: preserved production APK.
- `build/verification/economy-probe.apk`: separately named no-save test fixture APK, not for normal play.

The normal production APK was reinstalled after the fixture. Physical-device performance and final economy tuning remain unverified. Aid generosity, free cargo restocking, hull hold counts, recruitment price, multiplier strength and integer rounding are all beta baselines, not final balance. No monetization or unrelated feature systems were added.


Final production checks after the usage-limit interruption: Android Settings explicitly displayed `Current offline cap: 4h 0m` (`build/verification/economy-production-cap.png`). The normal Shop showed category-specific Hull chests at 10/50 gems (`build/verification/economy-production-shop.png`). The temporary emulator continued sailing during the interruption; its accumulated live-play currency is not an offline reward test. It was stopped after the final screenshot. Windows Release remained responsive. No implementation changes followed the 90-test/clean-analysis/native-build verification.
