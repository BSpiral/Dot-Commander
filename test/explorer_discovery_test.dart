import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/core/simulation/vessel.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/pirates/world/discoveries.dart';
import 'package:dot_commander/pirates/progression/fleet_progress.dart';

/// A fully controllable fake Random for deterministic probability tests.
/// [doubles] is consumed in order (cycling) by nextDouble(); [ints]
/// (defaulting to always 0) by nextInt().
class _FakeRandom implements Random {
  final List<double> doubles;
  final int Function(int max) ints;
  int _i = 0;
  _FakeRandom(this.doubles, {int Function(int max)? ints})
    : ints = ints ?? ((max) => 0);

  @override
  double nextDouble() => doubles[_i++ % doubles.length];
  @override
  int nextInt(int max) => ints(max);
  @override
  bool nextBool() => false;
}

void main() {
  test(
    'a failed roll increases probability for the SAME ship; repeated '
    'failures keep increasing it',
    () {
      final v = createCaribbean(rng: _FakeRandom([0.99]));
      final s = v.ships.first..behavior = BehaviorMode.explorer;
      expect(v.life.discoveryProbability[s.id], isNull); // starts at base

      v.life.checkDiscovery(s);
      expect(
        v.life.discoveryProbability[s.id],
        closeTo(
          Balance.discoveryBaseProbability + Balance.discoveryProbabilityStep,
          1e-9,
        ),
      );
      v.life.checkDiscovery(s);
      expect(
        v.life.discoveryProbability[s.id],
        closeTo(
          Balance.discoveryBaseProbability +
              2 * Balance.discoveryProbabilityStep,
          1e-9,
        ),
      );
    },
  );

  test('probability escalation is capped, never exceeding it however long the streak', () {
    final v = createCaribbean(rng: _FakeRandom([0.9999]));
    final s = v.ships.first..behavior = BehaviorMode.explorer;
    for (var i = 0; i < 200; i++) {
      v.life.checkDiscovery(s);
    }
    expect(
      v.life.discoveryProbability[s.id],
      closeTo(Balance.discoveryProbabilityCap, 1e-9),
    );
  });

  test('two different ships build entirely independent streaks', () {
    final v = createCaribbean(rng: _FakeRandom([0.9999]))..coins = 1000000;
    v.purchaseSlot();
    final ships = v.ships.where((s) => s.playerOwned).toList();
    expect(ships.length, greaterThanOrEqualTo(2));
    final a = ships[0]..behavior = BehaviorMode.explorer;
    final b = ships[1]..behavior = BehaviorMode.explorer;

    v.life.checkDiscovery(a);
    v.life.checkDiscovery(a);
    v.life.checkDiscovery(a);
    expect(v.life.discoveryProbability[a.id], isNotNull);
    expect(v.life.discoveryProbability[b.id], isNull);
  });

  test('a successful discovery resets probability to base and grants a reward', () {
    // Call order inside checkDiscovery: [gate roll, tier roll, variant
    // roll]. 0.0 always beats the gate (succeeds); tier roll .5 lands in
    // "small" (< .04 great, < .22 good, else small).
    final v = createCaribbean(rng: _FakeRandom([0.0, 0.5, 0.0]));
    final s = v.ships.first..behavior = BehaviorMode.explorer;
    final coinsBefore = v.coins, gemsBefore = v.gems;

    v.life.checkDiscovery(s);

    expect(v.life.discoveryProbability[s.id], Balance.discoveryBaseProbability);
    expect(v.coins, greaterThan(coinsBefore));
    expect(s.recentActivity, isNotEmpty);
    // The .5 tier roll lands in "small" (gems == 0 for every small
    // variant), so gems are unchanged for THIS specific roll.
    expect(v.gems, gemsBefore);
  });

  test('a tier roll under .04 grants a great (rare, big) reward', () {
    final v = createCaribbean(rng: _FakeRandom([0.0, 0.01, 0.0]));
    final s = v.ships.first..behavior = BehaviorMode.explorer;
    v.life.checkDiscovery(s);
    final great = discoveryContent.where((d) => d.tier == DiscoveryTier.great).first;
    expect(v.gems, greaterThanOrEqualTo(10));
    expect(v.coins, greaterThanOrEqualTo(150));
    expect(great.gems, greaterThanOrEqualTo(10)); // sanity on the table itself
  });

  test('non-explorer behaviors never roll, regardless of chance', () {
    final v = createCaribbean(rng: _FakeRandom([0.0])); // would always succeed if rolled
    final s = v.ships.first..behavior = BehaviorMode.merchant;
    final coinsBefore = v.coins;
    v.life.checkDiscovery(s);
    expect(v.coins, coinsBefore);
    expect(v.life.discoveryProbability, isEmpty);
  });

  test('NPC explorers never grant the player a reward', () {
    final v = createCaribbean(rng: _FakeRandom([0.0]));
    final npc = v.ships.firstWhere((s) => !s.playerOwned)
      ..behavior = BehaviorMode.explorer;
    final coinsBefore = v.coins;
    v.life.checkDiscovery(npc);
    expect(v.coins, coinsBefore);
    expect(v.life.discoveryProbability, isEmpty);
  });

  test('discovery probability round-trips through save/restore', () {
    final v = createCaribbean(rng: _FakeRandom([0.9999]));
    final s = v.ships.first..behavior = BehaviorMode.explorer;
    v.life.checkDiscovery(s);
    final raised = v.life.discoveryProbability[s.id];
    expect(raised, isNot(Balance.discoveryBaseProbability));

    final json = v.life.toJson();
    final restored = createCaribbean();
    restored.life.restore(json);
    expect(restored.life.discoveryProbability[s.id], raised);
  });

  test('restore rejects a discovery probability outside the valid range', () {
    final v = createCaribbean();
    expect(
      () => v.life.restore({
        'clock': 0.0,
        'nextNpc': 1,
        'works': [],
        'discoveryProbability': {'ship-1': 5.0},
      }),
      throwsFormatException,
    );
  });

  test('restore tolerates an old save with no discoveryProbability key at all', () {
    final v = createCaribbean();
    v.life.restore({'clock': 0.0, 'nextNpc': 1, 'works': []});
    expect(v.life.discoveryProbability, isEmpty);
  });

  test('discoveries.dart has multiple variants per tier and embeds the amount in flavor text', () {
    for (final tier in DiscoveryTier.values) {
      final variants = discoveryContent.where((d) => d.tier == tier).toList();
      expect(variants.length, greaterThanOrEqualTo(2), reason: '$tier needs variety');
      for (final d in variants) {
        expect(d.flavor, contains(d.gold.toString()));
        if (d.gems > 0) expect(d.flavor, contains(d.gems.toString()));
      }
    }
    // Small finds stay small; a "jackpot" great find is the rare exception.
    final small = discoveryContent.where((d) => d.tier == DiscoveryTier.small);
    expect(small.every((d) => d.gold <= 20 && d.gems == 0), isTrue);
    final great = discoveryContent.where((d) => d.tier == DiscoveryTier.great);
    expect(great.every((d) => d.gold >= 150 && d.gems >= 10), isTrue);
  });

  test(
    'reaching an observation point during normal play triggers exactly one '
    'discovery roll, not a fixed timer',
    () {
      final v = createCaribbean(rng: _FakeRandom([0.0]));
      final s = v.ships.first
        ..behavior = BehaviorMode.explorer
        ..destination = v.places.firstWhere((p) => p.kind == DestinationKind.search)
        ..activity = Activity.sailing;
      s.position = s.destination!.position; // already there
      final coinsBefore = v.coins;
      v.update(.1); // one simulation tick: arrival transition fires here
      expect(s.activity, Activity.observing);
      expect(v.coins, greaterThan(coinsBefore));
    },
  );
}
