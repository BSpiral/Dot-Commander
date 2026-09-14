import 'life_balance.dart';
import 'dart:math';
import '../../core/simulation/vessel.dart';
import '../ships/hull_catalog.dart';
part 'equipment_content.dart';

enum CommandTrack { hull, firepower, crew, navigation, portRelations }

enum FleetTrack { portFavor, offline }

enum ItemKind {
  hull,
  equipment,
  cannon,
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
ItemKind savedKind(String name, [String? specialist]) => switch (name) {
  'gear' => ItemKind.body,
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
  bool accepts(ItemKind kind) => switch (this) {
    ChestCategory.hull => kind == ItemKind.hull,
    ChestCategory.equipment => kind == ItemKind.equipment,
    ChestCategory.cannon => kind == ItemKind.cannon,
    ChestCategory.crew => crewSlots.contains(kind),
    ChestCategory.officers => officerSlots.contains(kind),
  };
  String get label => switch (this) {
    ChestCategory.hull => 'Hull',
    ChestCategory.equipment => 'Equipment',
    ChestCategory.crew => 'Crew',
    ChestCategory.cannon => 'Ordnance',
    ChestCategory.officers => 'Officers',
  };
}

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
      rewardedChestDailyCap = 5;
  static int offlineCapMinutes(int level) =>
      offlineBaseMinutes +
      ((offlineMaxMinutes - offlineBaseMinutes) *
          level.clamp(0, maxLevel) ~/
          maxLevel);
  static const slotCosts = LifeBalance.commandPrices;
  static const chestCosts = {ChestKind.common: 10, ChestKind.rare: 50};
  static int treeCost(int level) => 1 + level + (level * level ~/ 100);
  static const hullPerLevel = 1.0,
      firePerLevel = .1,
      crewPerLevel = .002,
      speedPerLevel = .0005,
      handlingPerLevel = .0005;
}

/// Each physical copy has its own ID. Set IDs are reserved metadata, not bonuses.
class EquipmentItem {
  final String id, name;
  final ItemKind kind;
  final String? hullType, setId;
  final String rarity;
  final String? specialist, contentId;
  final double bonus;
  const EquipmentItem(
    this.id,
    this.name,
    this.kind, {
    this.hullType,
    this.rarity = 'common',
    this.bonus = 1,
    this.setId,
    this.specialist,
    this.contentId,
  });
  EquipmentDefinition? get definition => contentId == null
      ? null
      : equipmentContent.firstWhere((d) => d.id == contentId);
  String get description {
    final d = definition;
    if (d != null) {
      return '${d.description}${rarity == "rare" ? " Rare: numeric gear bonuses ×1.5; ordnance also +4% firepower." : ""}';
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
    'rarity': rarity,
    'bonus': bonus,
    'set': setId,
    'specialist': specialist,
    'content': contentId,
  };
  factory EquipmentItem.fromJson(Map<String, dynamic> j) {
    final item = EquipmentItem(
      j['id'],
      j['name'],
      savedKind(j['kind'], j['specialist']),
      hullType: j['hull'],
      rarity: j['rarity'],
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

class CommandProgress {
  final String shipId;
  final Map<CommandTrack, int> tree = {};
  final Map<ItemKind, String> equipped = {};
  CommandProgress(this.shipId);
  int level(CommandTrack t) => tree[t] ?? 0;
  double units(CommandTrack t) => LifeBalance.rewardUnits(level(t));
  double percent(CommandTrack t) => LifeBalance.percent(level(t));
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
    final percentDelta =
        (LifeBalance.percent(current + 1) - LifeBalance.percent(current)) * 100;
    String number(double value) =>
        value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    String percentLine(String benefit) => percentDelta <= 0
        ? 'Next level: +0% $benefit (cap reached)'
        : 'Next level: +${number(percentDelta)}% $benefit';
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
        return step == 'Hull capacity'
            ? 'Next level: +${number(unitsDelta * LifeBalance.hullPerUnit)} Hull capacity'
            : percentLine(step);
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
        return percentLine(pattern[current % pattern.length]);
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
  int nextItem = 1, visits = 0;
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
    s.cargo = min(s.cargo, h.holds);
    s.maxHullHp =
        h.hp +
        c.units(CommandTrack.hull) * LifeBalance.hullPerUnit +
        (equippedHull?.bonus ?? 0) * 5 +
        bonus(c, ItemKind.equipment) * 3;
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
    s.damageReduction = c.percent(CommandTrack.hull);
    s.postHullRecovery = c.percent(CommandTrack.hull);
    s.postCrewRecovery = c.percent(CommandTrack.crew);
    s.ordnance = 'standard';
    // Tree-sourced secondary bonuses (each track's own base value, before
    // equipment's own += on top of it below) -- gives every Command Tree
    // track a second, thematically-related payoff instead of a single
    // repeated stat, using fields this game already resolves in combat/
    // port logic. See CommandProgress.nextBenefit for the matching
    // player-facing description of each.
    s.crewDefense = c.percent(CommandTrack.crew);
    s.openingVolley = 0;
    s.penaltyMitigation = c.percent(CommandTrack.navigation);
    s.minimumMovement = 0;
    s.economyBonus = c.percent(CommandTrack.portRelations);
    s.fieldRepairBonus = 0;
    s.openingAttack = c.percent(CommandTrack.firepower);
    for (final id in c.equipped.values) {
      final i = item(id)!;
      final d = i.definition;
      if (d == null) continue;
      final multiplier = i.rarity == 'rare' ? 1.5 : 1.0;
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
        }
      }
      if (d.shot != null) {
        s.ordnance = d.shot!;
        if (i.rarity == 'rare') s.firepower *= 1.04;
      }
    }
    s.crewDefense = s.crewDefense.clamp(0, .35);
    s.damageReduction = s.damageReduction.clamp(0, .35);
    s.postCrewRecovery = s.postCrewRecovery.clamp(0, .35);
    s.economyBonus = s.economyBonus.clamp(0, .2);
  }

  EquipmentItem roll(
    ChestKind chest,
    Random rng, {
    required ChestCategory category,
  }) {
    final pool = equipmentContent
        .where((d) => category.accepts(d.kind))
        .toList();
    final definition = category == ChestCategory.hull
        ? null
        : pool[rng.nextInt(pool.length)];
    final kind = definition?.kind ?? ItemKind.hull;
    final h = hullCatalog[rng.nextInt(hullCatalog.length)];
    final rare = chest == ChestKind.rare;
    final result = EquipmentItem(
      'item-${nextItem++}',
      kind == ItemKind.hull
          ? '${rare ? 'Fine' : 'Fitted'} ${h.name}'
          : '${rare ? 'Fine ' : ''}${definition!.name}',
      kind,
      hullType: kind == ItemKind.hull ? h.name : null,
      rarity: rare ? 'rare' : 'common',
      bonus: definition == null ? (rare ? 3 : 1) : 0,
      contentId: definition?.id,
    );
    inventory.add(result);
    lastRewards
      ..clear()
      ..add(result.id);
    return result;
  }

  Map<String, dynamic> toJson() => {
    'commands': commands.values.map((c) => c.toJson()).toList(),
    'tree': tree.map((k, v) => MapEntry(k.name, v)),
    'inventory': inventory.map((i) => i.toJson()).toList(),
    'nextItem': nextItem,
    'visits': visits,
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
          'cargo' => CommandTrack.portRelations,
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
