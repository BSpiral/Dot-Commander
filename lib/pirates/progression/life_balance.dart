/// Central tuning for the world-life pass. Equipment/chest tables stay separate.
abstract final class LifeBalance {
  static const cycleLevels = 100, cycles = 11, maxLevels = cycleLevels * cycles;
  static const commandPrices = [0, 10000, 50000, 250000, 1000000];

  // Final progression/balance corrections pass, 2026-09-20: these are
  // TREE SOFT CAPS -- how far the Command Tree investment ALONE can push
  // a facet, before equipment/officers/figureheads/other legitimate
  // modifiers are added on top. They are deliberately NOT final ceilings
  // -- a well-equipped ship is meant to be able to exceed them. See
  // FleetProgress.apply (Damage Reduction, Boarding Defense, Post-Battle
  // Hull/Crew Recovery) and WorldLife (Field Repair Discount, Port
  // Service Discount, Port Service Speed) for exactly where each is
  // consumed, and finalSafetyCeiling below for the genuinely-necessary
  // final bound that applies AFTER equipment stacks on top.
  static const damageReductionTreeCap = .35,
      crewDefenseTreeCap = .35,
      postHullRecoveryTreeCap = .50,
      postCrewRecoveryTreeCap = .50,
      fieldRepairDiscountTreeCap = .35,
      portServiceDiscountTreeCap = .50,
      portServiceSpeedTreeCap = .50;

  // The one genuinely mathematically-necessary final bound shared by
  // every "(1 - x)" cost/damage-reduction/service-time-shaped formula in
  // the game (Damage Reduction, Boarding Defense, Field Repair Discount,
  // Port Service Discount, Port Service Speed) -- NOT a tree soft cap;
  // equipment/other legitimate modifiers CAN push a stat's real total
  // past its own tree cap above, all the way up to this ceiling. .90
  // (not 100%, and deliberately not reusing any of the .35/.50 tree
  // numbers) leaves a mandatory 10% floor -- damage taken, cost paid, or
  // service time required can shrink a great deal under strong
  // investment, but literal zero (true immunity / free / instant
  // service) is a genuinely broken state, not just a strong one.
  // Post-Battle Hull/Crew Recovery do NOT use this constant -- their own
  // final ceiling is an EXACT 100% (see FleetProgress.apply), since
  // recovering more than what was actually lost is mathematically
  // meaningless rather than merely "very strong."
  static const finalSafetyCeiling = .90;


  static int cycle(int total) => (total ~/ cycleLevels).clamp(0, cycles - 1);
  static int level(int total) => total >= maxLevels ? 100 : total % cycleLevels;
  static double rewardUnits(int total) {
    var left = total.clamp(0, maxLevels), result = 0.0;
    for (var c = 0; c < cycles; c++) {
      final n = left.clamp(0, cycleLevels);
      result += n * (c + 1);
      left -= n;
    }
    return result;
  }

  // Port Relations balance pass 2026-09-20, corrected twice same day:
  // raised from .0001 (0.01% per reward-unit) to .001 (0.1% per
  // reward-unit) -- every percent-style Command Tree facet shares this
  // one formula, so this single change is the "0.01% -> 0.1%" global
  // strength bump, growing across the FULL 1100-level tree with no
  // generic cap.
  //
  // This raw value is the TREE'S OWN contribution only. Facets with a
  // genuine mechanical ceiling apply their OWN tree soft cap (see the
  // *TreeCap constants above) where this is consumed, separately from
  // whatever equipment/other legitimate modifiers add on top, which are
  // bounded only by finalSafetyCeiling (or an exact 100% for the two
  // recovery facets) -- see FleetProgress.apply and WorldLife's
  // individual formulas for exactly how each combines the two.
  static double percent(int total) => rewardUnits(total) * .001;
  static int cost(int total) {
    final c = cycle(total) + 1, l = level(total);
    return (1 + total + l * l ~/ 100) * c * c * c;
  }

  static const hullPerUnit = .1, firePerUnit = .02;
  static const serviceCapacity = 10, cargoPortCapacity = 10;
  static const repairPrice = 1.0, crewPrice = 1.0, secondsPerUnit = .5;
  static const minimumServiceStage = .75, specialistServiceReduction = .10;
  static double serviceSeconds(double units, double multiplier) => units <= 0
      ? 0
      : (units * secondsPerUnit).clamp(minimumServiceStage, double.infinity) *
            multiplier;
  static const cargoBuy = 1,
      cargoSell = 2,
      fieldPriceMultiplier = 2.0,
      fieldLimit = 2;
  static const maxNpcs = 20, maxPirates = 10, maxHunters = 2;
  // Arrival pacing (repaired 2026-09-14: the previous 60s/1% pairing
  // averaged one successful spawn roll per ~100 minutes of active
  // engine time -- far too slow to ever refill toward maxNpcs during a
  // normal session, so a world that dipped to a low population (via
  // departures/defeats) could only keep draining, never recover. At
  // 15s/15%, the expected time to a single success is ~100s (~1.7min);
  // refilling a 13-ship deficit (e.g. 7 -> 20) averages ~22 minutes of
  // continuous play -- noticeably recovering within an ordinary
  // session, never instant (still gated one roll per interval, still
  // capped by npcCount >= maxNpcs before every roll), and still leaves
  // natural fluctuation from the independent, much rarer departure/
  // defeat attrition below.
  static const arrivalInterval = 15.0,
      arrivalChance = .15,
      departureChance = .01;
  // Deterministic population floor (2026-09-14): below this many active
  // NPCs, an arrival roll is GUARANTEED on the next interval instead of
  // only LifeBalance.arrivalChance likely -- discovered cause: combat
  // defeat of a non-pirate, non-hunter NPC (merchant/explorer/regular
  // privateer) is a PERMANENT population loss by existing design
  // (WorldLife.defeat sets respawnRemaining=0 for that case -- see
  // test/lifecycle_persistence_test.dart's own "truly gone, not a
  // respawn candidate" assertion, which this does NOT change). With
  // encounters enabled, that ongoing combat drain -- pirates actively
  // hunt merchants, the largest single arrival-weight role -- can
  // outpace the probabilistic arrival trickle no matter how that
  // trickle alone is tuned, stalling a drained world well below
  // maxNpcs indefinitely (a live report of ~5 NPCs not climbing even
  // after the arrival-rate repair above is what surfaced this). Set to
  // half of maxNpcs, not just barely above the reported stuck point,
  // so a critically low world visibly climbs for a sustained stretch
  // (guaranteed arrivals ~15s apart) rather than gaining one ship and
  // immediately reverting to the gentler probabilistic pace. This
  // floor guarantees forward progress out of a critically low
  // population without forcing the world toward maxNpcs or removing
  // fluctuation above it: once npcCount reaches this floor, arrivals
  // go back to being merely likely, not certain.
  static const criticalNpcFloor = 10;
  // Both population-recovery floors below (criticalNpcFloor and the
  // pirate floor) only act once the world's total roster is at least
  // this large. Real gameplay always starts at 15 ships (createCaribbean)
  // and this total never shrinks below what it started at (defeated/
  // departed ships stay in the list as inactive entries rather than
  // being removed -- see WorldLife.tick's >60 cleanup), so this never
  // excludes a real, live-drained-low-population world. It exists
  // purely to leave small, deliberately hand-built test fixtures (e.g.
  // a 2-ship isolated combat scenario) alone: the floor concept itself
  // is meaningless for a world that was never meant to model the real
  // roster size, and those fixtures should not observe extra ships
  // they never asked for.
  static const minRosterForPopulationFloors = 10;
  static const pirateRespawn = 60.0, playerRespawn = 5.0;
  static const hunterThresholds = [4, 8], hunterRetire = 2, merchantAttacks = 2;
  static const roleWeights = [.50, .10, .05, .35];
  static const logLimit = 12;
}
