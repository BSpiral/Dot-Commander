/// Central tuning for the world-life pass. Equipment/chest tables stay separate.
abstract final class LifeBalance {
  static const cycleLevels = 100, cycles = 11, maxLevels = cycleLevels * cycles;
  static const percentCap = .20;
  static const commandPrices = [0, 10000, 50000, 250000, 1000000];
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

  static double percent(int total) =>
      (rewardUnits(total) * .0001).clamp(0, percentCap);
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
  static const arrivalInterval = 60.0,
      arrivalChance = .01,
      departureChance = .01;
  static const pirateRespawn = 60.0, playerRespawn = 5.0;
  static const hunterThresholds = [4, 8], hunterRetire = 2, merchantAttacks = 2;
  static const roleWeights = [.50, .10, .05, .35];
  static const logLimit = 12;
}
