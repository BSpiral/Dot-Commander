# Playtest polish

Scope: DotCommander only; no equipment/chest redesign, detailed combat rebalance or publishing.

## Service pacing
`LifeBalance.secondsPerUnit` changes from 0.1 to 0.5 seconds. Ten Hull, ten Crew or ten cargo now take 5 seconds each instead of 1 second. Partial amounts scale proportionally. Nonempty stages have a 0.75-second baseline minimum before bonuses. Zero repair/replenishment/loading work adds no timed wait. The previous fixed 0.25-second sale display is now a quantity-scaled unloading/selling stage, with a minimum 0.75-second transaction display. Ten cargo unloading takes 5 seconds. Transactions still apply once, with staged waits between them.

A baseline visit unloading 10, repairing 10 Hull, restoring 10 Crew and loading 10 takes about 20 seconds instead of 3.25 seconds (plus fixed-step transitions). Existing Crew + Port Relations speed reduction remains capped at 20%. Equipped Carpenter/Bosun metadata provides an additional 10% reduction to its corresponding repair/replenishment stage, multiplicatively: 5 seconds becomes 4 seconds with maximum tree bonus, or 3.6 seconds with the matching specialist. No item pools were changed. Saved in-progress remaining timers are preserved; subsequent stages use new tuning.

## Debug reset
Settings includes `DEBUG: Reset all game progress` only under `kDebugMode`. The handler also checks `kDebugMode`; Release/Profile have no reset control. Confirmation explicitly says the operation is irreversible. Cancel/back/dismiss do not reset.

Confirmed reset replaces only the existing DotCommander voyage save using the ordered `VoyageStore.save` queue. Old-screen autosaves are disabled before replacement and disposal, avoiding stale saves overwriting the reset. On successful write a new CommandScreen loads the fresh voyage. On write failure the old in-memory game remains available with an error.

Resets: owned commands to one starter, ship identities/names/orders/positions, Tree and Offline progression, equipped items/inventory/chest reward history, coins/gems, cargo/health, encounter reservations/results/cooldowns, population/service/respawn state, recent logs, and voyage sound preference to its starter default. Starts unpaused with the initial world. Does not clear unrelated preferences/files/projects or change application installation. In-memory injected-store tests verify cancellation and successful reset; no real player save was reset during verification.

## Tree descriptions
`CommandProgress.nextBenefit` takes the difference between current and next formula-derived rewards. Hull increments: initial +0.1; one gold star +0.2; five gold +0.6; first blue +0.7; five blue +1.1. Firepower initially +0.02, one gold +0.04. Navigation initially +0.01% base speed, one gold +0.02%, five gold +0.06%. Capped secondary bonuses explicitly display +0%; MAXED says maximum reached. No description falsely advertises an uncapped prestige gain after the actual 20% secondary cap.

## Representative crew
Full-strength total figures, including the existing captain: Sloop 6, Schooner 8, Brig 12, Frigate 16, Galley 14, Man-of-War 20. Previously ordinary full hulls displayed only 4–6 figures; the renderer hard-capped at 10.

Count = ceil(hull representative cap * sqrt(clamped current crew / hull crew capacity)), bounded by actual crew and hull cap. Zero crew gives zero figures; one gives one. Frigate at 55/90 crew displays 13; at 22/90 displays 8. Catalog crew capacity is 90 for Frigate; 55 is the Brig's full crew. Renderer uses two rows for up to 10 and three rows above that, at most 20 figures per ship. Figures are representative, not one actor per sailor.

Figure zero already was the named captain: gold with a ring and excluded from representative boarding crossings. That convention is preserved; remaining figures are ordinary crew in team colors. Shared counting applies to the ordinary Deck and battle presentation without changing combat outcome math.

## Files
- lib/pirates/progression/life_balance.dart, fleet_progress.dart
- lib/pirates/world/world_life.dart
- lib/pirates/ships/hull_catalog.dart, crew_representation.dart
- lib/ui/management/progression_panel.dart, management_panel.dart
- lib/ui/command_screen.dart, lib/ui/theater/deck_theater.dart
- test/playtest_polish_test.dart; updated world_life_test.dart, encounter_test.dart, living_world_test.dart

## Verification
Full suite: 109 tests passed (`build/polish-tests.log`). Focused tests cover next-level prestige/caps, crew bounds/depletion, timing/bonuses and confirmed/cancelled reset. Existing full lifecycle battle-lock and no-combat-in-port regressions remain green.

Final verification: `flutter analyze --no-pub` reports no issues; Windows Release built successfully (`build/polish-windows.log`). Live Windows check used the existing three-command save and confirmed quantity-scaled unloading and a later loading countdown, separate coin changes, 12-figure Brig and 16-figure Frigate with distinct gold captain, formula-derived Tree text, and no debug reset in Release Settings. Hull/Crew service and specialist timing were exercised by automated tests; the healthy native fleet did not require repair/replenishment during this check. The real save was not reset. Android was not rebuilt in this Windows-only verification pass.
