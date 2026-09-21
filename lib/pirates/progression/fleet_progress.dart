import 'life_balance.dart';
import 'dart:math';
import '../../core/simulation/vessel.dart';
import '../ships/hull_catalog.dart';
part 'equipment_content.dart';

enum CommandTrack { hull, firepower, crew, navigation, portRelations }

// shipHold added 2026-09-20 (Port Relations balance pass): fleet-wide
// (shared by every player ship, like offline) +1-per-step cargo hold
// progression, up to +50 total at max level -- see
// FleetProgress.effectiveHoldCapacity and buyFleetTree. portFavor
// remains the pre-2026-09-14 deprecated/migrated-away slot (see
// VoyageStore's legacy-save migration below); shipHold is a genuinely
// new, unrelated slot, not a repurposing of it.
enum FleetTrack { portFavor, offline, shipHold }

enum ItemKind {
  hull,
  cannon,
  rigging,
  reinforcement,
  figurehead,
  head,
  body,
  hands,
  legs,
  weapon,
  captain,
  quartermaster,
  bosun,
  carpenter,
  navigator,
}

const crewSlots = [
  ItemKind.head,
  ItemKind.body,
  ItemKind.hands,
  ItemKind.legs,
  ItemKind.weapon,
];
const officerSlots = [
  ItemKind.captain,
  ItemKind.quartermaster,
  ItemKind.bosun,
  ItemKind.carpenter,
  ItemKind.navigator,
];
// Hull's five upgrade slots (playability pass 2026-09-18): the ship
// itself, its cannons, and three new equipment slots that used to be
// one undifferentiated 'equipment' ItemKind -- see savedKind's legacy
// mapping below for how existing saves carry forward.
const hullSlots = [
  ItemKind.hull,
  ItemKind.cannon,
  ItemKind.rigging,
  ItemKind.reinforcement,
  ItemKind.figurehead,
];
ItemKind savedKind(String name, [String? specialist]) => switch (name) {
  'gear' => ItemKind.body,
  // Pre-2026-09-18 saves store the old undifferentiated ship-equipment
  // slot as 'equipment'. Every existing item under it (Reinforced Keel,
  // Auxiliary Sweeps, Boarding Netting, Flush Deck, Concealed Gunports)
  // is reclassified into either Rigging or Reinforcement going forward
  // (see equipment_content.dart) -- but an old item object itself only
  // carries the slot name, not which new bucket it belongs in, so this
  // maps it to Rigging as a safe default; ItemKind is purely a slot tag
  // (compatibility/equip-eligibility), never gameplay math, so an old
  // save landing an already-owned Boarding Netting under Rigging instead
  // of Reinforcement costs the player nothing beyond a relabeled slot.
  'equipment' => ItemKind.rigging,
  'officer' =>
    specialist == 'carpenter'
        ? ItemKind.carpenter
        : specialist == 'bosun'
        ? ItemKind.bosun
        : ItemKind.quartermaster,
  _ => ItemKind.values.byName(name),
};

enum ChestKind { common, rare }

enum ChestCategory { hull, equipment, crew, cannon, officers }

extension ChestCategoryContent on ChestCategory {
  /// Live playtest repair pass 2026-09-20: [hull] used to accept ONLY
  /// ItemKind.hull (a brand-new ship), making a "Hull Chest" a pure ship
  /// dispenser -- never a cannon/rigging/reinforcement/figurehead, even
  /// though those are just as much a Hull Upgrade (see UpgradeCategory.
  /// hull's own slots, which [hullSlots] mirrors exactly). Widened to the
  /// full family so "Hull Chest -> Hull upgrades only" is actually true
  /// of everything it can award, not just its narrowest member.
  /// ChestCategory.equipment and ChestCategory.cannon are UNCHANGED and
  /// still independently reachable (narrower gem-purchase-only slices of
  /// this same wider family) -- see roll()'s own doc comment for how the
  /// overlap is handled.
  bool accepts(ItemKind kind) => switch (this) {
    ChestCategory.hull => hullSlots.contains(kind),
    // Rigging/Reinforcement/Figurehead are new sub-slots of what used to
    // be the single 'equipment' ItemKind; they all still come from the
    // same "Equipment" paid/ad chest category as before, so the Shop's
    // chest-buying UI keeps exactly the same 5 categories/10 rows it had
    // -- this pass reorganizes the UPGRADES page (see UpgradeCategory
    // below), not chest purchasing, which is out of scope.
    ChestCategory.equipment =>
      kind == ItemKind.rigging ||
          kind == ItemKind.reinforcement ||
          kind == ItemKind.figurehead,
    ChestCategory.cannon => kind == ItemKind.cannon,
    ChestCategory.crew => crewSlots.contains(kind),
    ChestCategory.officers => officerSlots.contains(kind),
  };
  // Live playtest repair pass 2026-09-20: crew/officers relabeled to
  // match the game's three standardized upgrade family names (Hull
  // Upgrade / Crew Equipment / Officer -- see UpgradeCategory) exactly,
  // so a gem-purchased "Crew Equipment Chest"/"Officer Chest" and the
  // identically-named rewarded-ad chest always describe the same thing.
  String get label => switch (this) {
    ChestCategory.hull => 'Hull',
    ChestCategory.equipment => 'Equipment',
    ChestCategory.crew => 'Crew Equipment',
    ChestCategory.cannon => 'Ordnance',
    ChestCategory.officers => 'Officer',
  };
}

/// The Upgrades page's three top-level equipment categories (playability
/// pass 2026-09-18) -- deliberately a SEPARATE, smaller grouping from
/// ChestCategory above: chest purchasing is unchanged/out of scope, but
/// the Upgrades screen itself should show three focused categories plus
/// a distinct Inventory browse, not a flat five-section item dump.
enum UpgradeCategory { hull, officer, crewEquipment }

extension UpgradeCategorySlots on UpgradeCategory {
  List<ItemKind> get slots => switch (this) {
    UpgradeCategory.hull => hullSlots,
    UpgradeCategory.officer => officerSlots,
    UpgradeCategory.crewEquipment => crewSlots,
  };
  String get label => switch (this) {
    UpgradeCategory.hull => 'Hull',
    UpgradeCategory.officer => 'Officer',
    UpgradeCategory.crewEquipment => 'Crew Equipment',
  };
}

/// Five rarity tiers, ordered common -> legendary. Pre-2026-09-18 saves
/// only ever used 'common'/'rare' string literals for EquipmentItem.rarity
/// (see EquipmentItem.fromJson for the compatibility parse); this enum
/// replaces that raw String going forward.
enum Rarity { common, uncommon, rare, epic, legendary }

extension RarityBonus on Rarity {
  /// Flat multiplier applied to an equipped item's numeric effects in
  /// FleetProgress.apply -- common items are unchanged (1.0, matching
  /// pre-rework behavior exactly); rare is still exactly the old 1.5x.
  double get multiplier => switch (this) {
    Rarity.common => 1.0,
    Rarity.uncommon => 1.2,
    Rarity.rare => 1.5,
    Rarity.epic => 1.85,
    Rarity.legendary => 2.25,
  };
  String get label => switch (this) {
    Rarity.common => 'Common',
    Rarity.uncommon => 'Uncommon',
    Rarity.rare => 'Rare',
    Rarity.epic => 'Epic',
    Rarity.legendary => 'Legendary',
  };
  String get namePrefix => switch (this) {
    Rarity.common => 'Fitted',
    Rarity.uncommon => 'Reinforced',
    Rarity.rare => 'Fine',
    Rarity.epic => 'Masterwork',
    Rarity.legendary => 'Legendary',
  };
}

/// Which reward path a chest/roll came from -- each has its own target
/// rarity distribution (see FleetProgress._rarityWeights). Separate from
/// ChestKind: ChestKind is the player-facing gem cost tier (still exactly
/// two, common/rare, matching the existing Shop UI); RollSource is the
/// finer-grained "how was this actually obtained" used only to pick the
/// odds table, per the 2026-09-18 chest-rarity investigation (ad-funded
/// Common Chests had a strictly worse table than the 10-gem purchase of
/// the same nominal ChestKind.common, by design, to keep paying
/// meaningfully better than watching ads without making ads worthless).
enum RollSource { adCommon, paidCommon, paidRare }

/// Exact target rarity distributions per RollSource, per the 2026-09-18
/// design brief -- "Normal/Common chest" = RollSource.adCommon,
/// "Common gem pack" = RollSource.paidCommon (the 10-gem purchase of a
/// ChestKind.common chest), "Rare gem pack" = RollSource.paidRare (the
/// 50-gem purchase of a ChestKind.rare chest). Entries must sum to 1.0;
/// FleetProgress._rollRarity walks them in this (insertion) order as a
/// cumulative distribution.
const rollRarityWeights = {
  RollSource.adCommon: {
    Rarity.common: .70,
    Rarity.uncommon: .20,
    Rarity.rare: .08,
    Rarity.epic: .02,
  },
  RollSource.paidCommon: {
    Rarity.common: .60,
    Rarity.uncommon: .20,
    Rarity.rare: .15,
    Rarity.epic: .05,
  },
  RollSource.paidRare: {Rarity.rare: .60, Rarity.epic: .30, Rarity.legendary: .10},
};

/// All provisional prices and increments live here, never in widgets.
abstract final class Balance {
  static const maxLevel = 1000;
  static const portCoins = 2,
      searchCoins = 1,
      visitsPerGem = 5,
      offlineBaseMinutes = 240,
      offlineMaxMinutes = 480,
      // Common Chests may also be opened by watching a rewarded ad, up to
      // this many times per day PER CHEST TYPE (ChestCategory) -- five
      // independent daily allowances, not one shared pool. This is the
      // deliberate anti-farming control: watching ads cannot outpace or
      // replace normal gem-earning progression, only supplement one
      // category's worth of Common Chests per day per type.
      rewardedChestDailyCap = 5,
      // A merchant-specific gem trickle (revised 2026-09-14 from a
      // sale-VALUE basis to a trade-COMPLETION-count basis, per
      // feedback that reliable long-term merchant gem progression
      // should track successful dock/trade activity, not cargo value):
      // every this many successful merchant trade completions -- a
      // dock where behavior was Merchant AND actual cargo was sold
      // (sold > 0) -- earns +1 gem. Idle docking with nothing to sell,
      // a canceled trip, or any non-merchant behavior never advances
      // this counter (see WorldLife.startPort), so it can't be farmed
      // by looping empty dock visits; each qualifying completion is
      // also bounded by real travel time between ports. Independent of
      // (and additional to) the universal every-Nth-port-visit trickle
      // every behavior already gets.
      merchantDocksPerGem = 5,
      // Explorer discoveries: each qualifying observation (arriving at
      // and completing a look at a search-kind destination) rolls
      // against a per-ship probability that starts at this base...
      discoveryBaseProbability = .12,
      // ...and increases by this much after every failed roll (reset to
      // base the moment a discovery succeeds) -- see
      // WorldLife.checkDiscovery. Randomness in real elapsed time
      // between finds comes naturally from travel time between search
      // points; this only controls the PER-OBSERVATION odds.
      discoveryProbabilityStep = .06,
      // Upper bound on the escalating probability, so a long unlucky
      // streak eventually plateaus instead of approaching certainty.
      discoveryProbabilityCap = .75;
  static int offlineCapMinutes(int level) =>
      offlineBaseMinutes +
      ((offlineMaxMinutes - offlineBaseMinutes) *
          level.clamp(0, maxLevel) ~/
          maxLevel);

  /// Saturday repair pass 2026-09-20: the OLD formula (`treeLevel * .001
  /// coin/min`) was completely disconnected from real earning potential --
  /// it paid literally $0/hour for every player who hadn't specifically
  /// spent Fleet coins on the "Offline Effectiveness" track (the default
  /// for every new save), which is what live play reported as "offline
  /// money is not being awarded." Replaced with a rate built from the
  /// SAME per-ship stats that already scale trade income during active
  /// play (Vessel.speed, Vessel.economyBonus -- see FleetProgress.apply
  /// and WorldLife.startPort), anchored to a calibrated baseline: a
  /// neutral 1.0-throughput ship earns [neutralShipCoinsPerHour] (540
  /// gold/hour, ~9/min, matching a live-measured Merchant-behavior
  /// baseline). A ship's own throughput factor is its (speed x cargo
  /// hold) relative to the Galley -- the hull the game's own content
  /// already designates as the dedicated Merchant/trading hull (see
  /// HullDefinition's favoredRole in hull_catalog.dart) -- so a fresh
  /// starting Sloop (speed 66, hold 4) computes to ~339/hour, closely
  /// matching the ~324/hour ("-40%") starting-ship estimate from the
  /// 2026-09-20 economy audit. offlineCapMinutes (still keyed off the
  /// Offline Effectiveness Fleet Tree, 4h-8h) is UNCHANGED -- only the
  /// RATE was broken, not the cap.
  static const neutralShipCoinsPerHour = 540.0;
  static const _referenceThroughputSpeed = 35.0, _referenceThroughputHolds = 12;

  /// A single ship's own (speed x cargo hold) throughput relative to the
  /// Galley reference -- 1.0 for a Galley with no bonuses, less for a
  /// smaller/slower hull, more for Navigation Tree/equipment speed gains.
  static double shipThroughputFactor(Vessel s) =>
      (s.speed * hullFor(s.hullType).holds) /
      (_referenceThroughputSpeed * _referenceThroughputHolds);

  /// A single ship's real coins/hour at its CURRENT stats -- throughput
  /// (speed x hold, see [shipThroughputFactor]) times its existing trade
  /// bonus (Vessel.economyBonus: portRelations Tree + equipped economy
  /// gear, already 0-0.2, the exact same field WorldLife.startPort uses
  /// for the live sale-price bonus).
  static double shipCoinsPerHour(Vessel s) =>
      neutralShipCoinsPerHour * shipThroughputFactor(s) * (1 + s.economyBonus);

  /// The player's whole fleet's combined coins/hour -- every productive
  /// ship contributes its own [shipCoinsPerHour] independently, so a
  /// larger or better-invested fleet earns proportionally more (both
  /// offline and as the basis for future related tuning).
  static double fleetCoinsPerHour(Iterable<Vessel> ships) => ships
      .where((s) => s.playerOwned && !s.isMoneyShip)
      .fold(0.0, (sum, s) => sum + shipCoinsPerHour(s));

  /// Coins earned for being away for [elapsedMinutes] real-world minutes,
  /// at the fleet's combined [fleetCoinsPerHour] and fleet-offline-tree
  /// [offlineTreeLevel] (governs only the CAP -- see offlineCapMinutes).
  /// The single source of truth for this formula, shared by
  /// VoyageStore.load (a true cold start) AND CommandScreen's
  /// app-lifecycle resume handler (returning from the background) --
  /// backgrounding the app is by far the most common way a phone game is
  /// "closed" without actually terminating the process, so both paths
  /// must compute this identically.
  static int offlineRewardCoins({
    required int offlineTreeLevel,
    required int elapsedMinutes,
    required double fleetCoinsPerHour,
  }) {
    final minutes = elapsedMinutes.clamp(0, offlineCapMinutes(offlineTreeLevel));
    return (fleetCoinsPerHour / 60 * minutes).floor();
  }

  // Live playtest repair pass 2026-09-20: the flat 540 reward is GONE --
  // the old design brief's own "roughly one neutral ship-hour" intent is
  // now computed for real, at claim time, from [fleetCoinsPerHour] (the
  // exact same canonical earning formula offline income already uses),
  // reusing the player's ACTUAL current fleet rather than a fixed
  // stand-in number -- see PiratesVoyage.claimMoneyShip.
  //
  // Pacing also repaired: the OLD scheme (a flat 900s/15min cooldown,
  // THEN an independent 30s-interval/12%-chance re-roll to actually
  // spawn) averaged roughly 19 real minutes per cycle end to end --
  // observably under the intended "roughly one every 10 minutes,
  // approximately 6/hour" target (confirmed live: a normal play session
  // could easily see zero). Replaced with a single deterministic
  // cooldown plus a small random jitter -- no separate chance-to-spawn
  // gate at all -- so a money ship appears reliably close to every 10
  // minutes (9-11 min range) rather than following a bursty/droughty
  // random-retry distribution with the same long-run average. Despawning
  // an unclaimed ship after 90 sim-seconds (unchanged) still keeps one
  // from lingering on the map indefinitely; the player still has to
  // notice and reach it before then.
  static const moneyShipCooldownSimSeconds = 540.0,
      moneyShipCooldownJitterSimSeconds = 120.0,
      moneyShipDespawnSimSeconds = 90.0;

  /// Port Relations balance pass 2026-09-20: how a ship's hull base
  /// hold, its share of the fleet-wide Ship Hold tree (0-50, see
  /// FleetTrack.shipHold), and equipment's own hold percentage combine
  /// into one effective capacity -- absolute-capped at 100 regardless of
  /// source. Deliberately hull-independent/pure (takes plain numbers,
  /// not a Vessel) so it's directly testable against the design's own
  /// worked examples without needing a real hull of that exact base
  /// hold; see FleetProgress.effectiveHoldCapacity for the real,
  /// hull-driven entry point every gameplay call site actually uses.
  static int combinedHoldCapacity({
    required int baseHold,
    required int shipHoldTreeLevel,
    double equipmentBonus = 0,
  }) {
    final treeBonus = 50 * shipHoldTreeLevel ~/ maxLevel;
    return min(100, ((baseHold + treeBonus) * (1 + equipmentBonus)).round());
  }

  static const slotCosts = LifeBalance.commandPrices;
  static const chestCosts = {ChestKind.common: 10, ChestKind.rare: 50};
  static int treeCost(int level) => 1 + level + (level * level ~/ 100);
  static const hullPerLevel = 1.0,
      firePerLevel = .1,
      crewPerLevel = .002,
      speedPerLevel = .0005,
      handlingPerLevel = .0005;
}

/// Each physical copy has its own ID. Set IDs are reserved metadata, not
/// bonuses. Stacking (identical-item counts, e.g. "Sloop x10") is a pure
/// display-layer grouping over these individual instances -- see
/// FleetProgress.stacks -- not a change to how items are stored, so
/// equip/merge/save logic below is untouched by it.
class EquipmentItem {
  final String id, name;
  final ItemKind kind;
  final String? hullType, setId;
  final Rarity rarity;
  final String? specialist, contentId;
  final double bonus;
  const EquipmentItem(
    this.id,
    this.name,
    this.kind, {
    this.hullType,
    this.rarity = Rarity.common,
    this.bonus = 1,
    this.setId,
    this.specialist,
    this.contentId,
  });
  EquipmentDefinition? get definition => contentId == null
      ? null
      : equipmentContent.firstWhere((d) => d.id == contentId);
  /// Same identity regardless of rarity -- what "stacks" (Trade Captain
  /// vs Combat Captain never combine even though both are Officer/
  /// captain items) and what an auto-merge groups by, together with
  /// rarity (see FleetProgress.mergeDuplicates/stacks).
  String get identityKey =>
      '${kind.name}|${kind == ItemKind.hull ? hullType : contentId}';
  String get description {
    final d = definition;
    if (d != null) {
      final pct = ((rarity.multiplier - 1) * 100).round();
      return '${d.description}${pct > 0 ? ' $pct% bonus.' : ''}';
    }
    return kind == ItemKind.hull
        ? hullFor(hullType!).personality
        : 'Legacy item: existing bonus preserved';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'hull': hullType,
    'rarity': rarity.name,
    'bonus': bonus,
    'set': setId,
    'specialist': specialist,
    'content': contentId,
  };
  factory EquipmentItem.fromJson(Map<String, dynamic> j) {
    // Pre-2026-09-18 saves only ever wrote the String 'common' or 'rare'
    // for rarity (there was no wider tier system yet) -- map those two
    // literals onto the new enum's equivalent tiers, and otherwise parse
    // the enum name directly for saves written by this version onward.
    final rawRarity = j['rarity'];
    final rarity = switch (rawRarity) {
      'common' => Rarity.common,
      'rare' => Rarity.rare,
      _ =>
        Rarity.values.asNameMap()[rawRarity] ??
            (throw const FormatException('Invalid rarity')),
    };
    // savedKind's blanket 'equipment' -> Rigging default is only a safe
    // guess for legacy items with no other information. When a content
    // id IS present, resolve the item's real current kind from
    // equipmentContent instead -- otherwise an item that was
    // reclassified to Reinforcement (Reinforced Keel, Boarding Netting)
    // fails the integrity check below (its resolved kind wouldn't match
    // its own definition's kind) and throws, taking down the entire
    // load/autosave with it.
    final legacyContentId = j['kind'] == 'equipment' ? j['content'] : null;
    EquipmentDefinition? legacyDefinition;
    if (legacyContentId != null) {
      for (final d in equipmentContent) {
        if (d.id == legacyContentId) {
          legacyDefinition = d;
          break;
        }
      }
    }
    final item = EquipmentItem(
      j['id'],
      j['name'],
      legacyDefinition?.kind ?? savedKind(j['kind'], j['specialist']),
      hullType: j['hull'],
      rarity: rarity,
      bonus: (j['bonus'] as num).toDouble(),
      setId: j['set'],
      specialist: j['specialist'],
      contentId: j['content'],
    );
    if ((item.contentId != null &&
            (!equipmentContent.any(
              (d) => d.id == item.contentId && d.kind == item.kind,
            ))) ||
        item.id.isEmpty ||
        item.name.isEmpty ||
        !item.bonus.isFinite ||
        item.bonus < 0 ||
        item.bonus > 100 ||
        (item.kind == ItemKind.hull &&
            !hullCatalog.any((h) => h.name == item.hullType))) {
      throw const FormatException('Invalid equipment');
    }
    return item;
  }
}

/// A display-only grouping of identical-identity, identical-rarity owned
/// copies -- see FleetProgress.stacks. [equipped] is how many of
/// [items] are currently assigned to some ship; [available] is the rest
/// (the count auto-merge and the relevance-filtered equip picker both
/// care about).
class InventoryStack {
  final List<EquipmentItem> items;
  final int equipped;
  InventoryStack(this.items, this.equipped);
  EquipmentItem get representative => items.first;
  int get owned => items.length;
  int get available => owned - equipped;
}

class CommandProgress {
  final String shipId;
  final Map<CommandTrack, int> tree = {};
  final Map<ItemKind, String> equipped = {};
  CommandProgress(this.shipId);
  int level(CommandTrack t) => tree[t] ?? 0;
  double units(CommandTrack t) => LifeBalance.rewardUnits(level(t));
  double percent(CommandTrack t) => LifeBalance.percent(level(t));

  /// Port Relations balance pass 2026-09-20: two NEW, explicit integer
  /// benefits of the SAME portRelations track the percent-based Port
  /// Service Discount/Trade Profit Bonus already use -- how much cargo
  /// (portCargoSupply) or hull damage (portRepairSupply) a port can
  /// service in one visit for THIS ship. Both climb linearly from their
  /// existing flat base (LifeBalance.cargoPortCapacity/serviceCapacity,
  /// currently 10 each) to 100 across the FULL portRelations level range
  /// (0-1100) -- deliberately NOT gated behind the same 20%-of-the-way
  /// point where the percent facets saturate (see LifeBalance.percent),
  /// so the long remainder of the tree past that point still delivers
  /// real, growing benefit instead of generating wasted reward-units.
  /// Independent of ChestCategory/UpgradeCategory 100% integer, never a
  /// percentage -- see the "keep these concepts separate" design note.
  int get portCargoSupply =>
      (LifeBalance.cargoPortCapacity +
              (100 - LifeBalance.cargoPortCapacity) *
                  level(CommandTrack.portRelations) ~/
                  LifeBalance.maxLevels)
          .clamp(LifeBalance.cargoPortCapacity, 100);
  int get portRepairSupply =>
      (LifeBalance.serviceCapacity +
              (100 - LifeBalance.serviceCapacity) *
                  level(CommandTrack.portRelations) ~/
                  LifeBalance.maxLevels)
          .clamp(LifeBalance.serviceCapacity, 100);
  /// Every purchase on a track grows ALL of that track's linked stats at
  /// once (see FleetProgress.apply -- e.g. a Hull level always adds both
  /// capacity and Damage Reduction and Post-Battle Repair together). The
  /// headline below rotates through those linked facets so repeated
  /// purchases read as varied, honestly-described payoffs of the same
  /// investment instead of one stat name forever. Core (uncapped) stats
  /// always show their real numeric delta; percent-based secondary/
  /// utility facets say so plainly once the shared 20% cap is reached.
  String nextBenefit(CommandTrack track) {
    final current = level(track);
    if (current >= LifeBalance.maxLevels) return 'Maximum level reached';
    final unitsDelta =
        LifeBalance.rewardUnits(current + 1) - LifeBalance.rewardUnits(current);
    String number(double value) =>
        value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    // Correction, Port Relations balance pass 2026-09-20: LifeBalance.
    // percent() itself is uncapped now (see its own doc comment), but
    // FleetProgress.apply STILL clamps a few specific fields at their
    // own mechanically-necessary ceiling (damageReduction/crewDefense at
    // .35, postHullRecovery/postCrewRecovery at 1.0). Without [ceiling]
    // here, this UI text would keep promising "+0.1% more" forever for
    // those facets even after they stop having ANY real effect in
    // apply() -- a dishonest, misleading kind of dead progression this
    // pass is specifically trying to avoid. Facets with no [ceiling]
    // (Sailing Speed, Crew Effectiveness, Trade Profit Bonus, Opening
    // Attack, Handling, Port/Boarding facets that are self-protected at
    // their OWN use site rather than via a field clamp -- see
    // WorldLife's embedded `min(...)` calls) correctly keep growing.
    String percentLine(String benefit, {double? ceiling}) {
      final before = ceiling == null
          ? LifeBalance.percent(current)
          : LifeBalance.percent(current).clamp(0, ceiling).toDouble();
      final after = ceiling == null
          ? LifeBalance.percent(current + 1)
          : LifeBalance.percent(current + 1).clamp(0, ceiling).toDouble();
      final delta = (after - before) * 100;
      return delta <= 0
          ? 'Next level: +0% $benefit (cap reached)'
          : 'Next level: +${number(delta)}% $benefit';
    }

    switch (track) {
      case CommandTrack.hull:
        const pattern = [
          'Hull capacity',
          'Damage Reduction',
          'Hull capacity',
          'Post-Battle Hull Repair',
          'Port Repair Discount',
        ];
        final step = pattern[current % pattern.length];
        return switch (step) {
          'Hull capacity' =>
            'Next level: +${number(unitsDelta * LifeBalance.hullPerUnit)} Hull capacity',
          'Damage Reduction' => percentLine(step, ceiling: LifeBalance.damageReductionTreeCap),
          'Post-Battle Hull Repair' => percentLine(step, ceiling: LifeBalance.postHullRecoveryTreeCap),
          _ => percentLine(step),
        };
      case CommandTrack.firepower:
        const pattern = ['Firepower', 'Opening Attack Strength'];
        final step = pattern[current % pattern.length];
        return step == 'Firepower'
            ? 'Next level: +${number(unitsDelta * LifeBalance.firePerUnit)} firepower'
            : percentLine(step);
      case CommandTrack.crew:
        const pattern = [
          'Crew Effectiveness',
          'Crew Recovery',
          'Crew Effectiveness',
          'Boarding Defense',
        ];
        final step = pattern[current % pattern.length];
        return switch (step) {
          'Crew Recovery' => percentLine(step, ceiling: LifeBalance.postCrewRecoveryTreeCap),
          'Boarding Defense' => percentLine(step, ceiling: LifeBalance.crewDefenseTreeCap),
          _ => percentLine(step),
        };
      case CommandTrack.navigation:
        const pattern = [
          'Sailing Speed',
          'Handling',
          'Sailing Speed',
          'Rigging-Damage Mitigation',
        ];
        return percentLine(pattern[current % pattern.length]);
      case CommandTrack.portRelations:
        const pattern = ['Port Service Discount', 'Trade Profit Bonus'];
        return percentLine(pattern[current % pattern.length]);
    }
  }

  String label(CommandTrack t) {
    final total = level(t);
    if (total >= LifeBalance.maxLevels) return 'MAXED';
    final c = LifeBalance.cycle(total), stars = c > 5 ? c - 5 : c;
    return '${LifeBalance.level(total)} / 100 ${'★' * stars}${c > 5 ? ' Super Prestige' : ''}';
  }

  Map<String, dynamic> toJson() => {
    'id': shipId,
    'tree': tree.map((k, v) => MapEntry(k.name, v)),
    'equipped': equipped.map((k, v) => MapEntry(k.name, v)),
  };
}

class FleetProgress {
  final Map<String, CommandProgress> commands = {};
  final Map<FleetTrack, int> tree = {};
  final List<EquipmentItem> inventory = [];
  final List<String> lastRewards = [];
  // Count of successful merchant trade completions (dock + actual sale)
  // since the last gem was awarded -- the merchant-specific gem trickle
  // (Balance.merchantDocksPerGem) resets this to 0 on every award. See
  // WorldLife.startPort.
  int nextItem = 1, visits = 0, merchantDockStreak = 0;
  FleetProgress(List<Vessel> ships) {
    for (final s in ships.where((s) => s.playerOwned)) {
      commands[s.id] = CommandProgress(s.id);
      s.firepower = hullFor(s.hullType).guns;
      // Preserve an older non-default hull as real assigned equipment.
      if (s.hullType != 'Sloop') {
        final item = EquipmentItem(
          'item-${nextItem++}',
          'Legacy ${s.hullType}',
          ItemKind.hull,
          hullType: s.hullType,
          bonus: 0,
        );
        inventory.add(item);
        commands[s.id]!.equipped[ItemKind.hull] = item.id;
      }
    }
  }
  int get offlineCapMinutes =>
      Balance.offlineCapMinutes(tree[FleetTrack.offline] ?? 0);
  String get offlineCapLabel =>
      '${offlineCapMinutes ~/ 60}h ${offlineCapMinutes % 60}m';
  EquipmentItem? item(String? id) {
    for (final i in inventory) {
      if (i.id == id) return i;
    }
    return null;
  }

  String? assignedTo(String id) {
    for (final c in commands.values) {
      if (c.equipped.containsValue(id)) return c.shipId;
    }
    return null;
  }

  double bonus(CommandProgress c, ItemKind k) =>
      item(c.equipped[k])?.bonus ?? 0;

  /// CP is a display estimate. The resolver consumes actual stats, never CP.
  double combatPower(Vessel s) =>
      (s.maxHullHp +
      s.firepower * 5 +
      s.crewCount * 1.5 * s.crewEffectiveness +
      s.speed * .2 +
      s.handling * 20);
  void apply(Vessel s, {bool preserveDamage = true}) {
    final c = commands[s.id];
    if (c == null) return;
    final equippedHull = item(c.equipped[ItemKind.hull]);
    final h = hullFor(equippedHull?.hullType ?? 'Sloop');
    final hpFraction = (s.hullHp / s.maxHullHp).clamp(0.0, 1.0);
    final oldCrew = hullFor(s.hullType).crew;
    final crewFraction = (s.crewCount / oldCrew).clamp(0.0, 1.0);
    s.hullType = h.name;
    s.maxHullHp =
        h.hp +
        c.units(CommandTrack.hull) * LifeBalance.hullPerUnit +
        (equippedHull?.bonus ?? 0) * 5;
    s.hullHp = s.maxHullHp * (preserveDamage ? hpFraction : 1);
    s.crewCount = max(0, (h.crew * crewFraction).round());
    s.speed = h.baseSpeed * (1 + c.percent(CommandTrack.navigation));
    s.firepower =
        h.guns +
        c.units(CommandTrack.firepower) * LifeBalance.firePerUnit +
        bonus(c, ItemKind.cannon) * 2;
    s.crewEffectiveness =
        1 +
        c.percent(CommandTrack.crew) +
        bonus(c, ItemKind.quartermaster) * .05 +
        bonus(c, ItemKind.body) * .03;
    s.handling = c.percent(CommandTrack.navigation);
    // Final corrections pass 2026-09-20: these four are TREE SOFT CAPS
    // (see LifeBalance's *TreeCap constants) -- the Command Tree
    // investment alone stops contributing past this point, but
    // equipment/other legitimate modifiers (added below) are NOT capped
    // here; only a genuinely mechanically-necessary FINAL ceiling
    // (finalSafetyCeiling, or an exact 100% for the two recovery
    // facets) applies once, after everything is summed -- see the
    // final-clamp block below the equipment loop.
    s.damageReduction = c.percent(CommandTrack.hull).clamp(0, LifeBalance.damageReductionTreeCap);
    s.postHullRecovery = c.percent(CommandTrack.hull).clamp(0, LifeBalance.postHullRecoveryTreeCap);
    s.postCrewRecovery = c.percent(CommandTrack.crew).clamp(0, LifeBalance.postCrewRecoveryTreeCap);
    s.ordnance = 'standard';
    // Tree-sourced secondary bonuses (each track's own base value, before
    // equipment's own += on top of it below) -- gives every Command Tree
    // track a second, thematically-related payoff instead of a single
    // repeated stat, using fields this game already resolves in combat/
    // port logic. See CommandProgress.nextBenefit for the matching
    // player-facing description of each.
    s.crewDefense = c.percent(CommandTrack.crew).clamp(0, LifeBalance.crewDefenseTreeCap);
    s.openingVolley = 0;
    s.penaltyMitigation = c.percent(CommandTrack.navigation);
    s.minimumMovement = 0;
    s.economyBonus = c.percent(CommandTrack.portRelations);
    s.fieldRepairBonus = 0;
    s.holdBonus = 0;
    s.openingAttack = c.percent(CommandTrack.firepower);
    for (final id in c.equipped.values) {
      final i = item(id)!;
      final d = i.definition;
      if (d == null) continue;
      final multiplier = i.rarity.multiplier;
      for (final effect in d.effects.entries) {
        final n = effect.value * multiplier;
        switch (effect.key) {
          case 'speed':
            s.speed *= 1 + n;
          case 'fire':
            s.firepower *= 1 + n;
          case 'crew':
            s.crewEffectiveness += n;
          case 'crewDefense':
            s.crewDefense += n;
          case 'recovery':
            s.postCrewRecovery += n;
          case 'hullRecovery':
            // Final corrections pass 2026-09-20: no equipment uses this
            // key yet, but it exists so a future hull-repair item can
            // push Post-Battle Hull Repair past its tree soft cap, the
            // same way 'recovery' already does for the crew side.
            s.postHullRecovery += n;
          case 'defense':
            s.damageReduction += n;
          case 'repair':
            s.fieldRepairBonus += n;
          case 'economy':
            s.economyBonus += n;
          case 'mitigation':
            s.penaltyMitigation += n;
          case 'minimum':
            s.minimumMovement = max(s.minimumMovement, n);
          case 'opening':
            s.openingAttack += n;
          case 'volley':
            s.openingVolley += n;
          case 'hold':
            // Live playtest repair pass 2026-09-20: first real consumer
            // is the Reinforcement-slot Cargo Hold Extension (see
            // equipment_content.dart) -- a genuine Hull Upgrade cargo
            // bonus, per item 5 of the repair brief. See
            // effectiveHoldCapacity's own doc comment for how this
            // combines with the Fleet Tree's flat +50.
            s.holdBonus += n;
        }
      }
      if (d.shot != null) {
        s.ordnance = d.shot!;
        // Generalizes the old rare-only "+4% firepower" (index 2 * 2% =
        // 4%, unchanged) across all five tiers.
        s.firepower *= 1 + i.rarity.index * .02;
      }
    }
    // Final corrections pass 2026-09-20: damageReduction/crewDefense
    // were assigned their TREE soft cap earlier (before the equipment
    // loop); equipment has since stacked on top, uncapped. NOW, after
    // everything is summed, apply the one genuinely mechanically-
    // necessary FINAL ceiling (finalSafetyCeiling, .90 -- not the .35
    // tree cap, which would silently waste any equipment investment
    // past it). Both are read as `(1 - x)` multipliers directly in
    // combat math (see encounter_result.dart, which independently
    // re-clamps damageReduction at this SAME final ceiling), and both
    // are referenced by the in-progress-encounter persistence
    // validation in pirates_voyage.dart -- also updated to this ceiling.
    s.crewDefense = s.crewDefense.clamp(0, LifeBalance.finalSafetyCeiling);
    s.damageReduction = s.damageReduction.clamp(0, LifeBalance.finalSafetyCeiling);
    // postCrewRecovery/postHullRecovery: tree soft-capped at 50% above;
    // equipment ('recovery'/'hullRecovery') can push either past that,
    // up to an EXACT 100% here -- not finalSafetyCeiling's .90, since
    // these are read as a flat multiplier against damage/crew actually
    // LOST this battle (pirates_voyage.dart): recovering more than
    // 100% of what was lost is mathematically meaningless, not just
    // "very strong", so 100% is this pair's true, exact natural
    // ceiling rather than an arbitrary safety margin.
    s.postCrewRecovery = s.postCrewRecovery.clamp(0, 1.0);
    s.postHullRecovery = s.postHullRecovery.clamp(0, 1.0);
    // economyBonus (Trade Profit Bonus): genuinely uncapped -- see Fix
    // for Port Relations trade-profit double counting: WorldLife no
    // longer re-adds bonus(portRelations) on top of this (which already
    // contains it once), and its consumers (sale-price/prize-reward
    // multipliers, cost-discount formulas) either have no ceiling or
    // self-protect independently at their own use site.
    // Cargo actually on board can never exceed the ship's real effective
    // capacity (hull base + Fleet Tree + equipment, absolute-capped at
    // 100 -- see effectiveHoldCapacity). Computed last, after holdBonus
    // is finalized above.
    s.cargo = min(s.cargo, effectiveHoldCapacity(s));
  }

  /// A ship's real effective cargo-hold capacity: hull base (fixed per
  /// hull, preserving hull identity -- a Fluyt stays a better cargo ship
  /// than a Sloop) plus the Fleet Tree's flat +1-per-step bonus (shared
  /// by every player ship, 0-50 total, see FleetTrack.shipHold), then
  /// equipment's own percentage bonus (Vessel.holdBonus) on top -- with
  /// an absolute hard cap of 100 regardless of how those combine (Port
  /// Relations balance pass 2026-09-20). NPCs (no CommandProgress entry)
  /// get their unmodified hull base only -- this bonus is explicitly
  /// fleet-wide for the PLAYER's own ships, never NPCs.
  int effectiveHoldCapacity(Vessel s) {
    final base = hullFor(s.hullType).holds;
    final c = commands[s.id];
    if (c == null) return min(100, base);
    return Balance.combinedHoldCapacity(
      baseHold: base,
      shipHoldTreeLevel: tree[FleetTrack.shipHold] ?? 0,
      equipmentBonus: s.holdBonus,
    );
  }

  /// Picks a rarity for a roll from [source]'s exact target distribution
  /// (rollRarityWeights). A cumulative walk over the table in its
  /// (insertion) order; the tables are const and always sum to 1.0, but a
  /// defensive last-entry fallback guards float rounding at the very top
  /// of the range.
  Rarity _rollRarity(RollSource source, Random rng) {
    final weights = rollRarityWeights[source]!;
    final roll = rng.nextDouble();
    var cumulative = 0.0;
    for (final entry in weights.entries) {
      cumulative += entry.value;
      if (roll < cumulative) return entry.key;
    }
    return weights.keys.last;
  }

  /// Live playtest repair pass 2026-09-20: ChestCategory.hull's pool now
  /// spans the whole Hull Upgrade family (see ChestCategoryContent.accepts)
  /// -- a genuine ship-hull swap (no equipmentContent entry; drawn from
  /// hullCatalog, same as before) is treated as one more roll OPTION
  /// alongside every cannon/rigging/reinforcement/figurehead definition in
  /// the pool, each equally likely, rather than the only possible outcome.
  /// Every other category is completely unchanged: [pool] alone decides
  /// the roll, exactly as before this pass.
  EquipmentItem roll(
    ChestKind chest,
    Random rng, {
    required ChestCategory category,
    required RollSource source,
  }) {
    final pool = equipmentContent
        .where((d) => category.accepts(d.kind))
        .toList();
    final includesHullSwap = category == ChestCategory.hull;
    final options = pool.length + (includesHullSwap ? 1 : 0);
    final pick = rng.nextInt(options);
    final definition = includesHullSwap && pick == pool.length ? null : pool[pick];
    final kind = definition?.kind ?? ItemKind.hull;
    final h = hullCatalog[rng.nextInt(hullCatalog.length)];
    final rarity = _rollRarity(source, rng);
    final result = EquipmentItem(
      'item-${nextItem++}',
      kind == ItemKind.hull
          ? '${rarity.namePrefix} ${h.name}'
          : '${rarity.namePrefix} ${definition!.name}',
      kind,
      hullType: kind == ItemKind.hull ? h.name : null,
      rarity: rarity,
      bonus: definition == null ? (1 + rarity.index).toDouble() : 0.0,
      contentId: definition?.id,
    );
    inventory.add(result);
    // Auto-merge may immediately consume this very item if it happens to
    // be the 5th available identical copy (see mergeDuplicates) -- if
    // so, report whatever it became instead of a now-nonexistent id.
    mergeDuplicates();
    final finalResult = item(result.id) ?? _mergeDescendantOf(result);
    lastRewards
      ..clear()
      ..add(finalResult.id);
    return finalResult;
  }

  int _idNumber(String id) => int.parse(id.substring(5));

  /// After mergeDuplicates runs, finds the highest-id item sharing
  /// [original]'s identity that's newer than it -- i.e. what it was
  /// folded into (possibly several tiers up, if a cascade happened).
  /// Only called when [original]'s own id no longer exists in inventory.
  EquipmentItem _mergeDescendantOf(EquipmentItem original) {
    final n = _idNumber(original.id);
    final descendants = inventory.where(
      (i) => i.identityKey == original.identityKey && _idNumber(i.id) > n,
    );
    return descendants.isEmpty
        ? original
        : descendants.reduce(
            (a, b) => _idNumber(a.id) > _idNumber(b.id) ? a : b,
          );
  }

  /// Automatic 5:1 duplicate upgrading: five AVAILABLE (unequipped)
  /// identical-identity Common copies merge into one Uncommon; five
  /// AVAILABLE Uncommon merge into one Rare. Stops at Rare -- ordinary
  /// duplicate merging never produces Epic or Legendary on its own.
  /// EQUIPPED copies are never counted or consumed (assignedTo check
  /// below), so equipping some copies of a stack protects exactly those
  /// copies from being folded into the next tier, per the design brief's
  /// "two equipped Common Fluytes remain equipped and untouched" example.
  /// Runs as a cascade (merging can itself produce a fifth Uncommon,
  /// which merges again into Rare) in one call.
  void mergeDuplicates() {
    var mergedAny = true;
    while (mergedAny) {
      mergedAny = false;
      final groups = <String, List<EquipmentItem>>{};
      for (final item in inventory) {
        if (item.rarity != Rarity.common && item.rarity != Rarity.uncommon) {
          continue;
        }
        if (assignedTo(item.id) != null) continue; // equipped: protected
        groups.putIfAbsent('${item.identityKey}|${item.rarity.name}', () => []).add(item);
      }
      for (final group in groups.values) {
        if (group.length < 5) continue;
        final five = group.take(5).toList();
        final sample = five.first;
        final nextRarity = Rarity.values[sample.rarity.index + 1];
        for (final consumed in five) {
          inventory.remove(consumed);
        }
        inventory.add(
          EquipmentItem(
            'item-${nextItem++}',
            sample.kind == ItemKind.hull
                ? '${nextRarity.namePrefix} ${hullFor(sample.hullType!).name}'
                : '${nextRarity.namePrefix} ${sample.definition!.name}',
            sample.kind,
            hullType: sample.hullType,
            rarity: nextRarity,
            bonus: sample.definition == null
                ? (1 + nextRarity.index).toDouble()
                : 0.0,
            contentId: sample.contentId,
          ),
        );
        mergedAny = true;
        break; // restart the scan: group membership has shifted
      }
    }
    // A merge can consume the very item lastRewards was pointing at.
    lastRewards.removeWhere((id) => item(id) == null);
  }

  /// A read-only display grouping of [inventory] by identical identity +
  /// rarity -- "Sloop x10", "Trade Captain x3 owned / x2 equipped / x1
  /// available" -- WITHOUT changing how items are stored (each owned
  /// copy remains its own EquipmentItem instance with its own id; see
  /// the class doc comment on EquipmentItem). Trade Captain and Combat
  /// Captain never combine since they have different identityKeys.
  List<InventoryStack> stacks({ItemKind? kind}) {
    final groups = <String, List<EquipmentItem>>{};
    for (final item in inventory) {
      if (kind != null && item.kind != kind) continue;
      groups
          .putIfAbsent('${item.identityKey}|${item.rarity.name}', () => [])
          .add(item);
    }
    return [
      for (final entry in groups.values)
        InventoryStack(entry, entry.where((i) => assignedTo(i.id) != null).length),
    ]..sort((a, b) {
      final kindCompare = a.representative.kind.index.compareTo(
        b.representative.kind.index,
      );
      if (kindCompare != 0) return kindCompare;
      final rarityCompare = b.representative.rarity.index.compareTo(
        a.representative.rarity.index,
      );
      return rarityCompare != 0
          ? rarityCompare
          : a.representative.name.compareTo(b.representative.name);
    });
  }

  Map<String, dynamic> toJson() => {
    'commands': commands.values.map((c) => c.toJson()).toList(),
    'tree': tree.map((k, v) => MapEntry(k.name, v)),
    'inventory': inventory.map((i) => i.toJson()).toList(),
    'nextItem': nextItem,
    'visits': visits,
    'merchantDockStreak': merchantDockStreak,
    'lastRewards': lastRewards,
  };
  void restore(Map<String, dynamic> j, List<Vessel> ships) {
    int level(dynamic v) {
      if (v is! int || v < 0 || v > LifeBalance.maxLevels) {
        throw const FormatException('Invalid Tree level');
      }
      return v;
    }

    commands.clear();
    inventory.clear();
    tree.clear();
    lastRewards.clear();
    for (final row in j['inventory'] as List) {
      inventory.add(EquipmentItem.fromJson(row));
    }
    if (inventory.map((i) => i.id).toSet().length != inventory.length) {
      throw const FormatException('Duplicate item ID');
    }
    nextItem = j['nextItem'] as int;
    visits = j['visits'] as int? ?? 0;
    if (visits < 0) throw const FormatException('Invalid visit count');
    // Old saves carry a 'merchantSales' key from the prior sale-value
    // mechanic; it's intentionally not read here (a different counter
    // under different semantics -- see the field comment above) and is
    // simply dropped, starting every existing save's dock streak at 0.
    merchantDockStreak = j['merchantDockStreak'] as int? ?? 0;
    if (merchantDockStreak < 0) {
      throw const FormatException('Invalid merchant dock streak');
    }
    if (nextItem < 1 ||
        inventory.any(
          (i) =>
              !i.id.startsWith('item-') ||
              (int.tryParse(i.id.substring(5)) ?? nextItem) >= nextItem,
        )) {
      throw const FormatException('Invalid item sequence');
    }
    final assigned = <String>{};
    for (final row in j['commands'] as List) {
      final c = CommandProgress(row['id']);
      if (commands.containsKey(c.shipId) ||
          !ships.any((s) => s.id == c.shipId && s.playerOwned)) {
        throw const FormatException('Invalid command');
      }
      for (final e in (row['tree'] as Map<String, dynamic>).entries) {
        final track = switch (e.key) {
          'speed' || 'handling' || 'exploration' => CommandTrack.navigation,
          _ => CommandTrack.values.byName(e.key),
        };
        c.tree[track] = ((c.tree[track] ?? 0) + level(e.value)).clamp(
          0,
          LifeBalance.maxLevels,
        );
      }
      for (final e in (row['equipped'] as Map<String, dynamic>).entries) {
        final kind = savedKind(e.key, item(e.value)?.specialist);
        if (item(e.value)?.kind != kind || !assigned.add(e.value)) {
          throw const FormatException('Invalid assignment');
        }
        c.equipped[kind] = e.value;
      }
      commands[c.shipId] = c;
    }
    if (commands.length != ships.where((s) => s.playerOwned).length) {
      throw const FormatException('Missing command');
    }
    for (final e in (j['tree'] as Map<String, dynamic>).entries) {
      tree[FleetTrack.values.byName(e.key)] = level(e.value);
    }
    for (final id in j['lastRewards'] as List) {
      if (item(id) == null) throw const FormatException('Missing reward');
      lastRewards.add(id);
    }
  }
}
