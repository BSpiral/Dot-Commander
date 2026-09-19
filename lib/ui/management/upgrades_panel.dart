import 'package:flutter/material.dart';

import '../../core/simulation/vessel.dart';
import '../../pirates/encounters/pirates_voyage.dart';
import '../../pirates/progression/fleet_progress.dart';

/// Upgrades tab (playability pass 2026-09-18): relevance-first navigation
/// instead of dumping every owned item into one flat list. Three focused
/// categories (Hull/Officer/Crew Equipment), each showing its currently
/// active combined bonuses; tapping a category shows its five slots;
/// tapping a slot shows ONLY owned items relevant to that exact slot
/// (stacked, with owned/equipped/available counts -- see
/// FleetProgress.stacks). A separate Inventory view is where the player
/// can deliberately browse everything owned, across every category.
class UpgradesPanel extends StatefulWidget {
  final PiratesVoyage voyage;
  final Vessel ship;
  final VoidCallback changed;
  const UpgradesPanel({
    super.key,
    required this.voyage,
    required this.ship,
    required this.changed,
  });

  @override
  State<UpgradesPanel> createState() => _UpgradesPanelState();
}

class _UpgradesPanelState extends State<UpgradesPanel> {
  UpgradeCategory? _category;
  ItemKind? _slot;
  bool _inventory = false;

  void _action(void Function() f) {
    setState(f);
    widget.changed();
  }

  void _back() => setState(() {
    if (_slot != null) {
      _slot = null;
    } else if (_category != null) {
      _category = null;
    } else {
      _inventory = false;
    }
  });

  @override
  Widget build(BuildContext context) {
    final p = widget.voyage.progress, c = p.commands[widget.ship.id];
    if (c == null) {
      return const ListTile(title: Text('Select your command to equip items.'));
    }
    if (_inventory) return _inventoryView(context, p, c);
    if (_slot != null) return _slotView(context, p, c, _slot!);
    if (_category != null) return _categoryView(context, p, c, _category!);
    return _landing(context, p, c);
  }

  Widget _backHeader(String title) => ListTile(
    dense: true,
    leading: IconButton(
      key: const Key('upgrades_back'),
      icon: const Icon(Icons.arrow_back),
      onPressed: _back,
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
  );

  Widget _landing(BuildContext context, FleetProgress p, CommandProgress c) {
    final ship = widget.ship;
    return Column(
      children: [
        ListTile(
          title: Text(
            '${ship.name} • ${ship.hullType} • CP ${p.combatPower(ship).toStringAsFixed(1)}',
          ),
          subtitle: Text(
            widget.voyage.busy(ship.id)
                ? 'Equipment locked during battle.'
                : 'Hull changes preserve damage percentage and Tree.',
          ),
        ),
        for (final category in UpgradeCategory.values)
          ListTile(
            key: Key('upgrade_category_${category.name}'),
            leading: Icon(_categoryIcon(category), color: const Color(0xffddbe7c)),
            title: Text(category.label),
            subtitle: Text(_bonusSummary(p, c, category)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => _category = category),
          ),
        ListTile(
          key: const Key('upgrade_inventory'),
          leading: const Icon(Icons.inventory_2_outlined, color: Color(0xffddbe7c)),
          title: const Text('Inventory'),
          subtitle: Text('${p.inventory.length} item${p.inventory.length == 1 ? '' : 's'} owned'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => setState(() => _inventory = true),
        ),
      ],
    );
  }

  IconData _categoryIcon(UpgradeCategory category) => switch (category) {
    UpgradeCategory.hull => Icons.directions_boat_outlined,
    UpgradeCategory.officer => Icons.military_tech_outlined,
    UpgradeCategory.crewEquipment => Icons.groups_outlined,
  };

  /// Sums equipped items' numeric effects (rarity-multiplied, matching
  /// FleetProgress.apply) across [category]'s slots into a short
  /// human-readable line. An approximation of the final combat numbers
  /// (it does not reproduce apply()'s per-stat clamps), but accurate
  /// enough for "what am I currently getting from this category."
  String _bonusSummary(FleetProgress p, CommandProgress c, UpgradeCategory category) {
    final totals = <String, double>{};
    var equippedCount = 0;
    for (final slot in category.slots) {
      final item = p.item(c.equipped[slot]);
      if (item == null) continue;
      equippedCount++;
      final d = item.definition;
      if (d == null) continue;
      for (final effect in d.effects.entries) {
        totals[effect.key] = (totals[effect.key] ?? 0) + effect.value * item.rarity.multiplier;
      }
    }
    if (equippedCount == 0) return 'Nothing equipped';
    final parts = [
      for (final entry in totals.entries)
        if (entry.value != 0)
          '${_effectLabels[entry.key] ?? entry.key} ${entry.value >= 0 ? '+' : ''}${(entry.value * 100).round()}%',
    ];
    return parts.isEmpty
        ? '$equippedCount equipped'
        : parts.join(', ');
  }

  static const _effectLabels = {
    'speed': 'Speed',
    'fire': 'Firepower',
    'crew': 'Crew',
    'crewDefense': 'Crew Defense',
    'recovery': 'Crew Recovery',
    'defense': 'Hull Defense',
    'repair': 'Field Repair',
    'economy': 'Trade',
    'mitigation': 'Rigging Mitigation',
    'minimum': 'Min Speed Floor',
    'opening': 'Opening Attack',
    'volley': 'Opening Volley',
  };

  Widget _categoryView(
    BuildContext context,
    FleetProgress p,
    CommandProgress c,
    UpgradeCategory category,
  ) => Column(
    children: [
      _backHeader(category.label),
      for (final kind in category.slots)
        Builder(
          builder: (context) {
            final current = p.item(c.equipped[kind]);
            final isDefaultHull = kind == ItemKind.hull && current == null;
            return ListTile(
              key: Key('upgrade_slot_${kind.name}'),
              dense: true,
              leading: Icon(
                current != null || isDefaultHull
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                color: current != null || isDefaultHull
                    ? const Color(0xff8fd19e)
                    : Colors.white38,
                size: 20,
              ),
              title: Text(_slotLabel(kind)),
              subtitle: Text(
                current?.name ??
                    (isDefaultHull
                        ? 'Basic Sloop (default, not an inventory item)'
                        : 'EMPTY — unequipped'),
                style: current == null && !isDefaultHull
                    ? const TextStyle(color: Colors.white38, fontStyle: FontStyle.italic)
                    : null,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => _slot = kind),
            );
          },
        ),
    ],
  );

  Widget _slotView(
    BuildContext context,
    FleetProgress p,
    CommandProgress c,
    ItemKind kind,
  ) {
    final current = p.item(c.equipped[kind]);
    // Relevance-first: ONLY owned items for this exact slot -- no other
    // equipment kind, no unowned store items, ever shown here.
    final ownedStacks = p.stacks(kind: kind);
    return Column(
      children: [
        _backHeader(_slotLabel(kind)),
        if (current != null)
          ListTile(
            dense: true,
            leading: const Icon(Icons.check_circle, color: Color(0xff8fd19e)),
            title: Text('${current.name} (equipped)'),
            subtitle: Text('${current.rarity.label} • ${current.description}'),
            trailing: TextButton(
              key: Key('unequip_${kind.name}'),
              onPressed: !widget.voyage.busy(widget.ship.id)
                  ? () => _action(() => widget.voyage.equip(widget.ship.id, kind, null))
                  : null,
              child: const Text('Unequip'),
            ),
          ),
        if (ownedStacks.isEmpty)
          const ListTile(
            title: Text('No owned items for this slot yet'),
            subtitle: Text('Open a chest in Shop, or check Inventory.'),
          ),
        for (final stack in ownedStacks)
          Builder(
            builder: (context) {
              final rep = stack.representative;
              final currentId = current?.id;
              final equippedHere =
                  currentId != null && stack.items.any((i) => i.id == currentId);
              final availableCopy = stack.items.firstWhere(
                (i) => p.assignedTo(i.id) == null,
                orElse: () => rep,
              );
              final canEquip = !equippedHere &&
                  stack.available > 0 &&
                  !widget.voyage.busy(widget.ship.id);
              return ListTile(
                dense: true,
                title: Text('${rep.name} ×${stack.owned}'),
                subtitle: Text(
                  '${rep.rarity.label} • ${rep.description}\n'
                  '×${stack.owned} owned / ×${stack.equipped} equipped / ×${stack.available} available',
                ),
                isThreeLine: true,
                trailing: TextButton(
                  key: Key('equip_stack_${rep.identityKey}_${rep.rarity.name}'),
                  onPressed: canEquip
                      ? () => _action(
                          () => widget.voyage.equip(widget.ship.id, kind, availableCopy.id),
                        )
                      : null,
                  child: Text(equippedHere ? 'Equipped' : 'Equip'),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _inventoryView(BuildContext context, FleetProgress p, CommandProgress c) {
    final stacks = p.stacks();
    return Column(
      children: [
        _backHeader('Inventory'),
        if (stacks.isEmpty)
          const ListTile(
            title: Text('No equipment yet'),
            subtitle: Text('Open a chest in Shop to obtain your first item.'),
          ),
        for (final stack in stacks)
          Builder(
            builder: (context) {
              final rep = stack.representative;
              final current = p.item(c.equipped[rep.kind]);
              final equippedHere = current != null &&
                  stack.items.any((i) => i.id == current.id);
              final availableCopy = stack.items.firstWhere(
                (i) => p.assignedTo(i.id) == null,
                orElse: () => rep,
              );
              final canEquip = !equippedHere &&
                  stack.available > 0 &&
                  !widget.voyage.busy(widget.ship.id);
              return ListTile(
                dense: true,
                leading: Icon(_categoryIconForKind(rep.kind), color: Colors.white54, size: 18),
                title: Text('${rep.name} ×${stack.owned}'),
                subtitle: Text(
                  '${_slotLabel(rep.kind)} • ${rep.rarity.label}\n'
                  '×${stack.owned} owned / ×${stack.equipped} equipped / ×${stack.available} available',
                ),
                isThreeLine: true,
                trailing: TextButton(
                  onPressed: canEquip
                      ? () => _action(
                          () => widget.voyage.equip(widget.ship.id, rep.kind, availableCopy.id),
                        )
                      : null,
                  child: Text(equippedHere ? 'Equipped' : 'Equip on ${widget.ship.name}'),
                ),
              );
            },
          ),
      ],
    );
  }

  IconData _categoryIconForKind(ItemKind kind) {
    if (hullSlots.contains(kind)) return Icons.directions_boat_outlined;
    if (officerSlots.contains(kind)) return Icons.military_tech_outlined;
    return Icons.groups_outlined;
  }
}

/// Human-readable slot name. "Ship"/"Cannons" (rather than "Hull"/
/// "Ordnance") specifically within the Hull category's own five slots,
/// per the 2026-09-18 design brief, so the slot name doesn't collide
/// with the category name it sits inside.
String _slotLabel(ItemKind kind) => switch (kind) {
  ItemKind.hull => 'Ship',
  ItemKind.cannon => 'Cannons',
  ItemKind.rigging => 'Rigging',
  ItemKind.reinforcement => 'Reinforcement',
  ItemKind.figurehead => 'Figurehead',
  ItemKind.head => 'Head',
  ItemKind.body => 'Body',
  ItemKind.hands => 'Hands',
  ItemKind.legs => 'Legs',
  ItemKind.weapon => 'Weapon',
  ItemKind.captain => 'Captain',
  ItemKind.quartermaster => 'Quartermaster',
  ItemKind.bosun => 'Bosun',
  ItemKind.carpenter => 'Carpenter',
  ItemKind.navigator => 'Navigator',
};
