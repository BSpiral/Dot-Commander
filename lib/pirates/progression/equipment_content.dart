part of 'fleet_progress.dart';

/// Small data table: one shared item-copy/assignment system, no ammunition inventory.
class EquipmentDefinition {
  final String id, name, description;
  final ItemKind kind;
  final Map<String, double> effects;
  final String? shot;
  const EquipmentDefinition(
    this.id,
    this.name,
    this.kind,
    this.description,
    this.effects, {
    this.shot,
  });
}

const equipmentContent = [
  EquipmentDefinition(
    'standard',
    'Standard Shot',
    ItemKind.cannon,
    '+4% firepower; little salvage after sinking.',
    {'fire': .04},
    shot: 'standard',
  ),
  EquipmentDefinition(
    'heavy',
    'Heavy Shot',
    ItemKind.cannon,
    '+12% firepower; favors sinking over prizes.',
    {'fire': .12},
    shot: 'heavy',
  ),
  EquipmentDefinition(
    'grape',
    'Grapeshot',
    ItemKind.cannon,
    'Crew damage and boarding; preserves more prize cargo.',
    {},
    shot: 'grape',
  ),
  EquipmentDefinition(
    'chain',
    'Chain Shot',
    ItemKind.cannon,
    'Survivors lose 55% movement until port service.',
    {},
    shot: 'chain',
  ),
  EquipmentDefinition(
    'fire',
    'Fire Shot',
    ItemKind.cannon,
    '+8% firepower; burns 50% of target cargo.',
    {'fire': .08},
    shot: 'fire',
  ),
  // Reinforcement: protective/support equipment (playability pass
  // 2026-09-18 splits the old single 'equipment' slot into Rigging and
  // Reinforcement -- see fleet_progress.dart's hullSlots/savedKind).
  EquipmentDefinition(
    'keel',
    'Reinforced Keel',
    ItemKind.reinforcement,
    '30% less rigging penalty; +3% Hull protection.',
    {'mitigation': .3, 'defense': .03},
  ),
  EquipmentDefinition(
    'netting',
    'Boarding Netting',
    ItemKind.reinforcement,
    '15% less Crew damage.',
    {'crewDefense': .15},
  ),
  // Live playtest repair pass 2026-09-20 (item 5): the first real
  // consumer of the 'hold' effect key (see FleetProgress.apply) -- a
  // genuine Hull Upgrade cargo/hold capacity bonus, reinforcement-slot
  // like Reinforced Keel/Boarding Netting above. +15% is a reasonable
  // default in line with this game's other single-item percentage
  // bonuses (speed/economy/crewDefense items range roughly 3%-15%), not
  // a value specified by the repair brief itself.
  EquipmentDefinition(
    'cargo_hold',
    'Cargo Hold Extension',
    ItemKind.reinforcement,
    '+15% cargo/hold capacity.',
    {'hold': .15},
  ),
  // Rigging: mobility/structure equipment.
  EquipmentDefinition(
    'sweeps',
    'Auxiliary Sweeps',
    ItemKind.rigging,
    'Movement floor of 65% despite rigging damage.',
    {'minimum': .65},
  ),
  EquipmentDefinition(
    'deck',
    'Flush Deck',
    ItemKind.rigging,
    '+8% sailing speed; -4% firepower.',
    {'speed': .08, 'fire': -.04},
  ),
  EquipmentDefinition(
    'gunports',
    'Concealed Gunports',
    ItemKind.rigging,
    '+10% opening attack strength.',
    {'opening': .1},
  ),
  // Figurehead: one per ship, affects only that ship (see
  // fleet_progress.dart's UpgradeCategory doc comment). Limited to
  // effect keys FleetProgress.apply already understands (speed,
  // economy, opening) rather than inventing morale/aggro/stealth/loot-
  // proc mechanics the effect system doesn't currently support.
  EquipmentDefinition(
    'figurehead_dolphin',
    'Carved Dolphin Figurehead',
    ItemKind.figurehead,
    '+6% sailing speed.',
    {'speed': .06},
  ),
  EquipmentDefinition(
    'figurehead_lion',
    'Golden Lion Figurehead',
    ItemKind.figurehead,
    '+6% trade/port financial bonus.',
    {'economy': .06},
  ),
  EquipmentDefinition(
    'figurehead_skull',
    'Grinning Skull Figurehead',
    ItemKind.figurehead,
    '+5% opening attack strength.',
    {'opening': .05},
  ),
  EquipmentDefinition(
    'cap',
    'Stocking Cap',
    ItemKind.head,
    '+3% Crew effectiveness.',
    {'crew': .03},
  ),
  EquipmentDefinition(
    'hat',
    'Pirate Hat',
    ItemKind.head,
    '+4% boarding effectiveness.',
    {'crew': .04},
  ),
  EquipmentDefinition(
    'eyepatch',
    'Eyepatch',
    ItemKind.head,
    '+3% opening attack strength.',
    {'opening': .03},
  ),
  EquipmentDefinition(
    'head_bandage',
    'Head Bandage',
    ItemKind.head,
    '4% less Crew damage.',
    {'crewDefense': .04},
  ),
  EquipmentDefinition(
    'clothing',
    'Seafarer Clothing',
    ItemKind.body,
    '3% less Crew damage.',
    {'crewDefense': .03},
  ),
  EquipmentDefinition(
    'leathers',
    'Boarding Leathers',
    ItemKind.body,
    '8% less Crew damage.',
    {'crewDefense': .08},
  ),
  EquipmentDefinition(
    'body_bandage',
    'Chest Bandage',
    ItemKind.body,
    '5% Crew protection; 3% fresh-loss recovery.',
    {'crewDefense': .05, 'recovery': .03},
  ),
  EquipmentDefinition(
    'hand_bandage',
    'Arm Bandage',
    ItemKind.hands,
    '+3% fighting; 4% fresh-loss recovery.',
    {'crew': .03, 'recovery': .04},
  ),
  EquipmentDefinition(
    'hook',
    'Hook Hand',
    ItemKind.hands,
    '+6% boarding effectiveness.',
    {'crew': .06},
  ),
  EquipmentDefinition(
    'leg_bandage',
    'Leg Bandage',
    ItemKind.legs,
    '6% fresh-loss recovery.',
    {'recovery': .06},
  ),
  EquipmentDefinition('peg', 'Peg Leg', ItemKind.legs, '5% Crew protection.', {
    'crewDefense': .05,
  }),
  EquipmentDefinition(
    'cutlass',
    'Boarding Cutlass',
    ItemKind.weapon,
    '+8% Crew fighting effectiveness.',
    {'crew': .08},
  ),
  EquipmentDefinition(
    'pistol',
    'Pistol Volley',
    ItemKind.weapon,
    'Opening boarding volley against 4% of enemy Crew.',
    {'volley': .04},
  ),
  EquipmentDefinition(
    'captain',
    'Trading Captain',
    ItemKind.captain,
    '+8% sale value / port financial bonus.',
    {'economy': .08},
  ),
  EquipmentDefinition(
    'quartermaster',
    'Steady Quartermaster',
    ItemKind.quartermaster,
    '+8% Crew effectiveness; 6% protection/recovery.',
    {'crew': .08, 'crewDefense': .06, 'recovery': .06},
  ),
  EquipmentDefinition(
    'bosun',
    'Battle Bosun',
    ItemKind.bosun,
    '+10% firepower; +6% boarding effectiveness.',
    {'fire': .1, 'crew': .06},
  ),
  EquipmentDefinition(
    'carpenter',
    'Ship Carpenter',
    ItemKind.carpenter,
    '8% Hull protection; +1 limited field repair capacity; 5% Post-Battle Hull Repair.',
    // Final corrections pass 2026-09-20: added 'hullRecovery' -- a
    // thematically obvious fit for a ship's own carpenter, and the
    // first real equipment source for FleetProgress.apply's
    // postHullRecovery, matching how quartermaster/bandages already do
    // this for the crew side via 'recovery'.
    {'defense': .08, 'repair': 1, 'hullRecovery': .05},
  ),
  EquipmentDefinition(
    'navigator',
    'Weatherwise Navigator',
    ItemKind.navigator,
    '+8% sailing; 25% less rigging penalty.',
    {'speed': .08, 'mitigation': .25},
  ),
];
