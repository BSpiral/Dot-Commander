# Progression, economy and world-life handoff

This document supersedes provisional economy/progression descriptions in earlier pass reports. Work is confined to DotCommander. No publishing or equipment/chest redesign.

## Systems changed
- `lib/pirates/progression/life_balance.dart`: current world-life tuning and prestige formulas.
- `fleet_progress.dart`: five per-command branches, eleven cycles, gold/blue stars, MAXED, legacy branch mapping; equipment copies remain intact.
- `lib/pirates/world/world_life.dart`: serial timed port work, generic cargo transactions, limited broke recovery, bounded logs, population turnover, pirate respawn and hunters.
- `lib/pirates/encounters/`: parallel Hull/Crew outcomes, fresh-damage-only recovery, merchant attrition, battle reservations and port immunity.
- `lib/core/simulation/` and `core/persistence/`: inactive-world state, reservations and snapshot fields. Renderers do not determine outcomes.
- `lib/pirates/persistence/voyage_store.dart`: schema 6 and migration.
- `lib/pirates/world/caribbean.dart`, `pirates/visuals/`: Pirate Haven and inactive ship rendering.
- `lib/ui/command_screen.dart`, `ui/management/`: tree presentation, separate health bars, timed operational status, activity expansion. Expansion state uses a dedicated per-ship key to avoid collision with scroll state.
- Tests: world_life_test, encounter_test, widget_test and related progression/economy/persistence regressions.

## Balance
- 11 cycles of 100 purchases; 1100 total is MAXED. Cycles 1–5 show gold stars; 6–10 show one through five blue stars.
- Reward per level is original reward times (cycle + 1), never exponential. Hull base +0.1, Firepower +0.02. Secondary progression percentages use rewardUnits * 0.0001, capped at 20%.
- Next purchase cost: (1 + totalLevels + floor(levelInCycle squared / 100)) * (cycle + 1) cubed.
- Command berths: free, 10,000, 50,000, 250,000, 1,000,000 coins. New commands start with empty trees.
- Offline alone remains fleet-wide: 1000 levels, cap 240 to 480 minutes, income level * 0.001 coins/minute. No offline battle simulation.
- Port baseline: up to 10 Hull and 10 Crew per visit, 1 coin each. Cargo buy/sell capacity 10 (also limited by holds and money); buy 1, sell 2. Port progression raises capacity/value and lowers costs/time.
- Service time 0.1 seconds per Hull, Crew and cargo unit, sequential/additive, plus a 0.25-second selling display. Broke service stays capacity-limited and gives exactly one restart cargo.
- Carpenter/Bosun support hooks: at most 2 Hull/Crew per use, twice baseline port price before Port Relations. Specialist item pools are intentionally not added in this pass.
- Active NPC cap 20, excluding player commands; pirate spawning cap 10. Base role weights Merchant/Pirate/Explorer/Privateer = 50/10/5/35, adjusted for scarcity.
- Arrival roll every 60 seconds: 1% if below cap. NPC port departure: 1% per arrival.
- Pirate NPC defeat absence 60 seconds; player recovery delay 5 seconds. Pirate-aligned ships use Pirate Haven.
- Hunters activate at 4/8 total pirates, including players; maximum two. Hunters return to port after victory; at <=2 pirates they retire at port.
- Merchant second attack between port visits forces defeat. Docking resets the counter.
- Recent activity: 12 entries per ship, persisted. Retired NPC history pruned beyond 60 records where safe.

## Combat invariants
Resolver-owned reservations hold both ships until one-time result application. Normal movement skips held participants; port work cannot start/advance during an unresolved battle. Order changes can be recorded while held but cannot change their current destination or release them. Battle presentation/seek cannot resolve or release ships. Docked, servicing, recovering and already engaged ships cannot initiate or receive a new encounter. Survivors resume routing or the required hunter port trip only after resolution.

## Saves
Schema 6 retains ship identities, inventory/equipment, wallets and orders and stores port phase/remaining time, world timers, inactive/respawn states and bounded logs. Old speed/handling/exploration levels merge into Navigation; cargo maps to Port Relations; legacy fleet Port Favor is copied into each existing command's Port Relations. Merged branches cap at 1100. Offline remains shared. Existing active encounter snapshots retain their captured math. Unsupported/corrupt saves retain the existing no-overwrite handling. RNG sequence and route caches are not serialized, so continuation is not a bit-identical replay.

## Provisional boundaries
Tuning still needs closed-beta economy playtesting. Crew currently develops effectiveness/recovery/service performance rather than adding a new scalable crew-capacity system. Equipment modifiers retain their existing behavior; the 20% cap applies to new tree secondary bonuses. Carpenter/Bosun are metadata-backed support hooks awaiting the separate equipment pool design. No grapeshot pool, reload simulation, detailed commodities, monetization or new equipment design was added. Existing banked coins survive defeat; cargo is the working capital at risk.

## Verification
- Full Flutter suite: 105 tests passed (`build/life-tests.log`). Includes prestige boundaries, independent commands, port quantities/timing, broke recovery, pirate/hunter thresholds and respawn, merchant attrition, parallel health, one-time battle resolution, lifecycle battle lock, dock/service exclusions, persistence and responsive widgets.
- Flutter analyze: no issues (`build/life-analyze.log`).
- Windows Release: built successfully (`build/life-windows.log`). Launched and responsive, PID 47132 at final live check.
- Windows live session used the existing saved three-command fleet. Observed independent sailing/docking, a timed Selling cargo state, separate sale and purchase log entries, currency changes, separate Hull/Crew bars, preserved hull equipment and independent Trees with shared Offline. Reopening the app retained the voyage and operational history.
- Live testing found and fixed a gray Deck panel after expanding activity then switching Tree/command/Deck. The repeated sequence passed on the rebuilt release and now has an automated regression.
- Battle lock, no combat in port, prestige extremes, hunter thresholds and defeat timing were verified by automated scenarios, not all manually triggered in the native session.
- An optional additional schema-five synthetic migration test was rejected before execution by approval review due to its service usage limit. It was not added. Existing persistence tests and loading the real saved fleet passed; no claim is made that this additional case ran.
- No publication. No Crownest/Game Shelf changes. Equipment pool design remains deferred.
- Final Android Release APK: built successfully, 46.2 MB (`build/app/outputs/flutter-apk/app-release.apk`; `build/life-android.log`). Final build includes battle-lock, port immunity and Deck state-key fix.
