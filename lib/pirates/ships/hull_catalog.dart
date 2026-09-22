import '../../core/simulation/vessel.dart';

/// Pirates content, not simulation policy. Affinities describe future bonuses only.
///
/// Ship/combat overhaul pass 2026-09-21: [holds]/[plankCapacity]/
/// [representativeCap]/[guns] used to be `switch (name)` getters -- four
/// separate places to remember to touch for every new hull, with a silent
/// `_ => default` fallback if one was missed. Converted to plain stored
/// fields (same values, same call sites everywhere else in the app --
/// `h.holds`, `h.guns`, etc. are all still ordinary property reads) so
/// adding a hull is "one entry in the const list below," not "one entry
/// plus four correct switch-statement edits."
///
/// [cargoCeiling]/[crewCeiling] are NEW this pass: the absolute maximum
/// effective cargo/crew a ship of this hull can ever reach through ANY
/// combination of Command Tree + equipment investment -- see
/// FleetProgress.effectiveHoldCapacity and FleetProgress.apply's crew
/// -count formula. Without a hull-specific ceiling, a single FLEET-WIDE
/// Ship Hold Tree bonus (up to +50, shared identically by every ship
/// regardless of hull) could make a 2-hold Pirogue reach 52+ cargo --
/// the same absolute number as a dedicated cargo hull -- silently erasing
/// hull identity. That fleet-wide term is now retired entirely (see
/// FleetTrack.shipHold's own doc comment) -- cargoCeiling remains as the
/// real per-hull cap on top of equipment alone. The ceiling keeps a
/// small/combat hull "useful, but never a miniature Fluyt/Man-of-War,"
/// while letting a hull whose whole identity IS cargo (Fluyt) or crew
/// (Sloop) grow dramatically within its
/// own lane.
///
/// [minRollRarityIndex] gates which hulls a Hull Chest roll may offer at
/// a given rolled [Rarity] (see fleet_progress.dart's Rarity enum, kept
/// as a plain ordinal int here rather than importing the Rarity type
/// itself -- fleet_progress.dart already imports THIS file, so importing
/// it back here would be a circular dependency; Rarity.index is already
/// used as a raw int elsewhere in this codebase, e.g. the hull bonus-HP
/// formula, so this stays consistent with an existing pattern rather than
/// introducing a new one). 0 (the default, common) means "obtainable at
/// any rarity, exactly like every hull before this pass." Only [Xebec]
/// sets this higher -- see FleetProgress.roll for where it's enforced.
class HullDefinition {
  final String name, personality, affinity;
  final BehaviorMode? favoredRole;
  final double baseSpeed, hp, visualScale, guns;
  final int crew, masts, holds, plankCapacity, representativeCap;
  final int cargoCeiling, crewCeiling;
  final int minRollRarityIndex;
  const HullDefinition({
    required this.name,
    required this.baseSpeed,
    required this.hp,
    required this.crew,
    required this.visualScale,
    required this.masts,
    required this.personality,
    required this.affinity,
    required this.guns,
    required this.holds,
    required this.cargoCeiling,
    required this.crewCeiling,
    this.plankCapacity = 1,
    this.representativeCap = 20,
    this.favoredRole,
    this.minRollRarityIndex = 0,
  });
}

const hullCatalog = [
  // --- Small/utility hulls: mobility and coastal work, never combat or
  // cargo specialists. Ship/combat overhaul pass 2026-09-21: Pirogue's
  // cargoCeiling (10) is the direct fix for the reported "52+ cargo
  // Pirogue" bug -- see HullDefinition's own doc comment.
  HullDefinition(
    name: 'Pirogue',
    baseSpeed: 75,
    hp: 40,
    crew: 8,
    visualScale: .65,
    masts: 1,
    personality:
        'Tiny blockade runner and smuggler; almost no guns or hold -- lives on speed, not cargo',
    affinity: 'Mobility',
    guns: 1,
    holds: 2,
    cargoCeiling: 10,
    crewCeiling: 10,
    representativeCap: 3,
  ),
  HullDefinition(
    name: 'Barque',
    baseSpeed: 69,
    hp: 55,
    crew: 12,
    visualScale: .75,
    masts: 1,
    personality: 'Light coastal patrol/fishing boat; agile and inexpensive to crew',
    affinity: 'Coastal mobility',
    guns: 1.5,
    holds: 3,
    cargoCeiling: 12,
    crewCeiling: 15,
    representativeCap: 4,
  ),
  // --- The "wonder ship": tiny base, by far the largest crew ceiling in
  // the game (see HullDefinition's own doc comment) -- the small hull a
  // player is meant to lovingly develop long-term.
  HullDefinition(
    name: 'Sloop',
    baseSpeed: 66,
    hp: 80,
    crew: 18,
    visualScale: .9,
    masts: 1,
    personality:
        'Fast, light and slippery -- punches above its weight with the right long-term investment',
    affinity: 'Starter progression; the hull worth developing for the long haul',
    guns: 2,
    holds: 4,
    cargoCeiling: 10,
    crewCeiling: 70,
    representativeCap: 6,
  ),
  HullDefinition(
    name: 'Schooner',
    baseSpeed: 58,
    hp: 85,
    crew: 25,
    visualScale: 1.05,
    masts: 2,
    personality: 'Quick, versatile scout -- range and discovery, not a combat upgrade over the Sloop',
    affinity: 'Exploration',
    guns: 3,
    holds: 6,
    cargoCeiling: 14,
    crewCeiling: 35,
    representativeCap: 8,
    favoredRole: BehaviorMode.explorer,
  ),
  // --- Merchant line: a clean cargo staircase (see cargoCeiling below),
  // each hull a real, felt step over the last -- Cog < Corbita < Galley <
  // Fluyt < Caravel.
  HullDefinition(
    name: 'Cog',
    baseSpeed: 38,
    hp: 130,
    crew: 35,
    visualScale: 1.1,
    masts: 1,
    personality: 'Dependable merchant workhorse -- makes money and keeps it',
    affinity: 'Trade',
    guns: 4,
    holds: 15,
    cargoCeiling: 35,
    crewCeiling: 40,
    plankCapacity: 2,
    representativeCap: 9,
    favoredRole: BehaviorMode.merchant,
  ),
  HullDefinition(
    name: 'Corbita',
    baseSpeed: 35,
    hp: 145,
    crew: 40,
    visualScale: 1.15,
    masts: 2,
    personality:
        'Solid intermediate cargo carrier -- not flashy, a clean step between Cog and Galley',
    affinity: 'Trade',
    guns: 3,
    holds: 18,
    cargoCeiling: 38,
    crewCeiling: 48,
    plankCapacity: 2,
    representativeCap: 11,
    favoredRole: BehaviorMode.merchant,
  ),
  HullDefinition(
    name: 'Galley',
    baseSpeed: 32,
    hp: 175,
    crew: 60,
    visualScale: 1.25,
    masts: 2,
    personality: 'Heavier hauler -- a real "I can haul stuff now" step above the Cog',
    affinity: 'Merchant routes',
    guns: 3,
    holds: 22,
    cargoCeiling: 45,
    crewCeiling: 75,
    plankCapacity: 3,
    representativeCap: 14,
    favoredRole: BehaviorMode.merchant,
  ),
  HullDefinition(
    name: 'Fluyt',
    baseSpeed: 32,
    hp: 160,
    crew: 50,
    visualScale: 1.3,
    masts: 3,
    personality: 'Dedicated bulk cargo specialist -- the biggest hold, lightly armed',
    affinity: 'Cargo specialist',
    guns: 2,
    holds: 30,
    cargoCeiling: 55,
    crewCeiling: 55,
    plankCapacity: 2,
    representativeCap: 10,
    favoredRole: BehaviorMode.merchant,
  ),
  HullDefinition(
    name: 'Caravel',
    baseSpeed: 27,
    hp: 250,
    crew: 75,
    visualScale: 1.4,
    masts: 3,
    personality:
        'Late-game ocean-going merchant flagship -- enormous cargo, durable enough to be worth protecting, not the best at anything else',
    affinity: 'Shipping magnate',
    guns: 8,
    holds: 40,
    cargoCeiling: 90,
    crewCeiling: 90,
    plankCapacity: 2,
    representativeCap: 18,
    favoredRole: BehaviorMode.merchant,
  ),
  // --- Boarding/raiding line: crew and cannons, not cargo.
  HullDefinition(
    name: 'Brig',
    baseSpeed: 45,
    hp: 150,
    crew: 70,
    visualScale: 1.2,
    masts: 2,
    personality: 'Sturdy raider -- dangerous at both cannon fire and boarding',
    affinity: 'Boarding and loot',
    guns: 8,
    holds: 8,
    cargoCeiling: 20,
    crewCeiling: 85,
    plankCapacity: 2,
    representativeCap: 12,
    favoredRole: BehaviorMode.pirate,
  ),
  HullDefinition(
    name: 'Longship',
    baseSpeed: 43,
    hp: 150,
    crew: 80,
    visualScale: 1.1,
    masts: 1,
    personality:
        '"We\'re coming over" -- crew and boarding are its whole identity, almost no guns',
    affinity: 'Boarding specialist',
    guns: 2,
    holds: 8,
    cargoCeiling: 16,
    crewCeiling: 100,
    plankCapacity: 3,
    representativeCap: 16,
    favoredRole: BehaviorMode.pirate,
  ),
  HullDefinition(
    name: 'Knarr',
    baseSpeed: 38,
    hp: 170,
    crew: 55,
    visualScale: 1.15,
    masts: 1,
    personality:
        'Merchant-raider -- rugged coastal utility ship, carries real cargo and can defend itself',
    affinity: 'Merchant-raider',
    guns: 4,
    holds: 18,
    cargoCeiling: 32,
    crewCeiling: 65,
    plankCapacity: 2,
    representativeCap: 10,
    favoredRole: BehaviorMode.merchant,
  ),
  // --- Dedicated warships.
  HullDefinition(
    name: 'Frigate',
    baseSpeed: 45,
    hp: 200,
    crew: 90,
    visualScale: 1.4,
    masts: 3,
    personality: 'Heavy pirate hunter/interceptor -- a beast in combat, poor at making money',
    affinity: 'Pirate hunting',
    guns: 15,
    holds: 5,
    cargoCeiling: 12,
    crewCeiling: 100,
    plankCapacity: 2,
    representativeCap: 16,
    favoredRole: BehaviorMode.privateer,
  ),
  HullDefinition(
    name: 'Galleon',
    baseSpeed: 32,
    hp: 300,
    crew: 110,
    visualScale: 1.5,
    masts: 3,
    personality:
        'Heavy "fuck off" all-rounder -- can trade, but has enough teeth that stealing from it is a terrible idea',
    affinity: 'Versatile heavy all-rounder',
    guns: 12,
    holds: 23,
    cargoCeiling: 45,
    crewCeiling: 130,
    plankCapacity: 3,
    representativeCap: 18,
  ),
  HullDefinition(
    name: 'Man-of-War',
    baseSpeed: 20,
    hp: 360,
    crew: 160,
    visualScale: 1.65,
    masts: 4,
    personality:
        'Slow, imposing floating fortress -- terrifying if it catches you, easy to outrun, not an economic ship',
    affinity: 'Major combat presence',
    guns: 20,
    holds: 8,
    cargoCeiling: 20,
    crewCeiling: 180,
    plankCapacity: 5,
    representativeCap: 20,
  ),
  // --- Legendary foundation (see FleetProgress.roll): the first of a
  // small planned family (roughly 3-5 total), NOT built out further this
  // pass. Only obtainable when a Hull Chest roll's OWN rarity lands on
  // Legendary -- see minRollRarityIndex's own doc comment and this
  // file's top-of-class doc comment for why base stats are deliberately
  // constrained (fast/dangerous, never simply "a bigger Man-of-War").
  HullDefinition(
    name: 'Xebec',
    baseSpeed: 52,
    hp: 160,
    crew: 70,
    visualScale: 1.15,
    masts: 3,
    personality:
        'Legendary fast combat predator -- controls the engagement through speed and gunnery, not bulk. Real weaknesses: modest hull, modest cargo, not a boarding specialist',
    affinity: 'Legendary predator',
    guns: 14,
    holds: 6,
    cargoCeiling: 14,
    crewCeiling: 85,
    plankCapacity: 2,
    representativeCap: 14,
    favoredRole: BehaviorMode.pirate,
    minRollRarityIndex: 4, // Rarity.legendary.index
  ),
];
HullDefinition hullFor(String name) => hullCatalog.firstWhere(
  (h) => h.name == name,
  orElse: () => hullCatalog.firstWhere((h) => h.name == 'Sloop'),
);
