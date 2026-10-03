part of 'fleet_progress.dart';

/// Hull Chest reward-category + per-hull weight tables (balance design
/// lock 2026-10-03). ALL weights in this file are BASIS POINTS (bp): 1 bp
/// = 0.01%, 10000 bp = 100%. Basis points (plain ints) are used instead
/// of doubles so "this table sums to exactly 100%" is an exact integer
/// equality check, never a floating-point near-equality fudge -- see
/// `hull_reward_tables_test.dart`'s own sum assertions.
///
/// Before this pass, a Hull Chest roll picked uniformly among
/// (equipmentContent's hull-family items + 1 hull-swap slot) --
/// `fleet_progress.dart`'s old `roll()`. That meant the Hull swap's own
/// odds were `1 / (pool.length + 1)`: silently different every time an
/// equipment item was added or removed, and WHICH hull came out was
/// decided by an independent rarity roll gating `hullCatalog` by
/// `minRollRarityIndex` (see hull_catalog.dart) -- a hull's relative
/// odds were an indirect side effect of the rarity table, never a
/// directly-tunable number.
///
/// This pass makes Hull an explicit, flat, pool-size-INDEPENDENT 6%
/// category chance, and gives each of the three purchasable/ad-funded
/// Hull Chest sources (RollSource.adCommon/paidCommon/paidRare) its own
/// directly-tunable per-hull weight table once that 6% hits. Nothing
/// here reads `equipmentContent.length` or `hullCatalog.length` --
/// adding or removing an equipment item or a hull can never move these
/// numbers; only editing the tables below can.

/// Hull Chest's five peer reward outcomes. `hull` means "the reward is a
/// new/upgraded ship" (one of the three per-source hull tables below).
/// The other four are the pre-existing Hull Upgrade family members
/// (unchanged roles -- see ChestCategoryContent.accepts/hullSlots).
enum HullChestRewardCategory { hull, cannon, rigging, reinforcement, figurehead }

extension HullChestRewardCategoryKind on HullChestRewardCategory {
  /// The equipmentContent `ItemKind` this category draws from, or `null`
  /// for `hull` (which draws from a hull table, not equipmentContent).
  ItemKind? get itemKind => switch (this) {
    HullChestRewardCategory.hull => null,
    HullChestRewardCategory.cannon => ItemKind.cannon,
    HullChestRewardCategory.rigging => ItemKind.rigging,
    HullChestRewardCategory.reinforcement => ItemKind.reinforcement,
    HullChestRewardCategory.figurehead => ItemKind.figurehead,
  };
}

/// EXPLICIT, LOCKED category weights for a Hull Chest roll. Sums to
/// exactly 10000 bp (100%) -- see `hull_reward_tables_test.dart`.
///
/// `hull: 600` (6.00%) is the real, reviewed design decision -- picked
/// deliberately, not derived from anything else in this file or from
/// equipmentContent.
///
/// The other four are NOT a new balance decision: they are the OLD
/// pool.length-derived odds (equipmentContent has 5 cannon / 3
/// reinforcement / 3 rigging / 3 figurehead items -- 14 total hull-family
/// items under the pre-2026-10-03 scheme), proportionally rescaled to
/// fill the remaining 9400 bp once hull was carved out as a flat 600 --
/// i.e. this translation preserves their relative odds to EACH OTHER
/// exactly as before, and only shrinks their combined total by the same
/// sliver (1/15 -> 6%) hull's own explicit value cost them. If/when
/// these four get a real balance pass of their own, only these four
/// need to change -- hull's 600 is independent of them by construction.
const hullChestCategoryWeightsBp = <HullChestRewardCategory, int>{
  HullChestRewardCategory.hull: 600,
  HullChestRewardCategory.cannon: 3358, // old 5/14 share of the remaining 9400
  HullChestRewardCategory.reinforcement: 2014, // old 3/14 share
  HullChestRewardCategory.rigging: 2014, // old 3/14 share
  HullChestRewardCategory.figurehead: 2014, // old 3/14 share
};

/// Which hull you get, GIVEN that the 600 bp Hull roll above already
/// succeeded. Three independent tables -- one per RollSource -- each
/// summing to exactly 10000 bp. FINALIZED 2026-10-03 (supersedes the
/// 2026-10-03 initial design-review proposal) -- still flat,
/// directly-editable data rather than inside any selection logic, since
/// a further rebalance remains a live possibility.
///
/// Hull progression used to derive relative ordering (weakest ->
/// strongest, from actual hull_catalog.dart stats, not real-world ship
/// reputation): Pirogue, Barque, Sloop, Schooner, Cog, Corbita, Longship,
/// Knarr, Galley, Brig, Fluyt, Caravel, Frigate, Galleon, Man-of-War.
/// Xebec (the only current Legendary) sits above all of them and appears
/// ONLY in the Rare table -- see hullTableAdCommonBp/hullTablePaidCommonBp's
/// own doc comments for why it is simply absent, not excluded by a reroll.

/// Ad/Common (rewarded-ad) Hull table: 15 normal hulls, no Xebec. Xebec
/// is NOT a key in this map at all: there is no reroll/exclusion check
/// anywhere in roll() for it, because it is simply never a candidate
/// here.
const hullTableAdCommonBp = <String, int>{
  'Pirogue': 1000,
  'Barque': 2278,
  'Sloop': 1674,
  'Schooner': 1155,
  'Cog': 819,
  'Corbita': 600,
  'Longship': 457,
  'Knarr': 365,
  'Galley': 305,
  'Brig': 266,
  'Fluyt': 240,
  'Caravel': 224,
  'Frigate': 213,
  'Galleon': 206,
  'Man-of-War': 198,
};

/// 10-gem Common Hull table: same 15 hulls, no Xebec, meaningfully
/// better than Ad/Common for mid/high hulls while Man-of-War remains
/// rare.
const hullTablePaidCommonBp = <String, int>{
  'Pirogue': 1000,
  'Barque': 1658,
  'Sloop': 1410,
  'Schooner': 1144,
  'Cog': 932,
  'Corbita': 762,
  'Longship': 626,
  'Knarr': 518,
  'Galley': 431,
  'Brig': 361,
  'Fluyt': 306,
  'Caravel': 261,
  'Frigate': 225,
  'Galleon': 197,
  'Man-of-War': 169,
};

/// 50-gem Rare Hull table: all 16 hulls, including Xebec -- substantially
/// improves strong-hull odds without guaranteeing a Rare-or-better hull.
/// Xebec is a fixed 100 bp (1.00%) -- the rarest single entry in any
/// table, by design, and (see roll()'s own Xebec rarity-override) always
/// resolves as Legendary when picked. This 100 bp is meant as the
/// LEGENDARY TIER's total share, not "Xebec's personal slot": when more
/// Legendary hulls are added later, split this same 100 bp across all of
/// them rather than giving each new Legendary its own additional slice
/// (which would silently inflate the overall chance of pulling *some*
/// Legendary) -- NOT implemented now; deliberately deferred until a
/// second Legendary hull actually exists.
///
/// Pirogue is 502 bp, not the design brief's literal 500 -- the brief's
/// own 16 percentages summed to 99.98%, not 100.00% (confirmed by exact
/// basis-point arithmetic: 500+1122+1018+925+843+769+704+645+594+548+508
/// +473+442+415+392+100 = 9998). The 2 bp shortfall is added to Pirogue
/// (the floor anchor, least balance-sensitive entry) to hit exactly
/// 10000 -- flagged for confirmation rather than silently resolved.
const hullTableRareBp = <String, int>{
  'Pirogue': 502,
  'Barque': 1122,
  'Sloop': 1018,
  'Schooner': 925,
  'Cog': 843,
  'Corbita': 769,
  'Longship': 704,
  'Knarr': 645,
  'Galley': 594,
  'Brig': 548,
  'Fluyt': 508,
  'Caravel': 473,
  'Frigate': 442,
  'Galleon': 415,
  'Man-of-War': 392,
  'Xebec': 100,
};

/// Picks the right per-hull table for a given RollSource -- the ONLY
/// place that maps RollSource -> hull table, so adding a 4th source
/// later means adding one switch arm here, not touching roll() itself.
Map<String, int> hullTableBpFor(RollSource source) => switch (source) {
  RollSource.adCommon => hullTableAdCommonBp,
  RollSource.paidCommon => hullTablePaidCommonBp,
  RollSource.paidRare => hullTableRareBp,
};

/// Generic weighted pick over a basis-point map (values must sum to
/// 10000). A cumulative walk identical in shape to the pre-existing
/// `FleetProgress._rollRarity` pattern (fleet_progress.dart), including
/// the same defensive last-entry fallback for the top of the range --
/// kept here as one shared, independently-testable primitive instead of
/// being duplicated inline for categories and for hulls.
T pickWeighted<T>(Map<T, int> weightsBp, Random rng) {
  final roll = rng.nextInt(10000);
  var cumulative = 0;
  for (final entry in weightsBp.entries) {
    cumulative += entry.value;
    if (roll < cumulative) return entry.key;
  }
  return weightsBp.keys.last;
}
