import '../../monetization/rewarded_chest_service.dart';
import '../../pirates/progression/life_balance.dart';
import 'package:flutter/material.dart';
import '../../pirates/progression/fleet_progress.dart';
import '../../pirates/encounters/pirates_voyage.dart';
import '../../core/simulation/vessel.dart';
import 'rewarded_chest_tile.dart';

class ProgressionPanel extends StatelessWidget {
  final PiratesVoyage voyage;
  final Vessel ship;
  final int tab;
  final VoidCallback changed;
  final RewardedChestService? rewardedChests;
  final Future<void> Function(ChestCategory category)? onRewardedChestGranted;
  const ProgressionPanel({
    super.key,
    required this.voyage,
    required this.ship,
    required this.tab,
    required this.changed,
    this.rewardedChests,
    this.onRewardedChestGranted,
  });
  @override
  Widget build(BuildContext context) {
    final p = voyage.progress, c = voyage.progress.commands[ship.id];
    void action(void Function() f) {
      f();
      changed();
    }

    Widget row(
      String title,
      String detail,
      String button,
      VoidCallback? onTap, {
      Key? key,
    }) => ListTile(
      dense: true,
      title: Text(
        title,
        style: TextStyle(
          color: title.contains('Super Prestige')
              ? Colors.lightBlue
              : title.contains('★')
              ? Colors.amber
              : null,
        ),
      ),
      subtitle: Text(detail),
      trailing: TextButton(key: key, onPressed: onTap, child: Text(button)),
    );
    final widgets = <Widget>[];
    if (tab == 0) {
      final n = p.commands.length;
      widgets.add(
        row(
          'Command berths: $n / 5',
          'New identity, zero Tree, basic Sloop',
          n == 5 ? 'Full' : '${Balance.slotCosts[n]} coins',
          n < 5 && voyage.coins >= Balance.slotCosts[n]
              ? () => action(() {
                  voyage.purchaseSlot();
                })
              : null,
          key: const Key('buy_slot'),
        ),
      );
      for (final category in ChestCategory.values) {
        for (final kind in ChestKind.values) {
          widgets.add(
            row(
              '${kind.name == 'common' ? 'Common' : 'Rare'} ${category.label} Chest',
              '${category.label} only. Duplicate copies are kept.',
              '${Balance.chestCosts[kind]} gems',
              voyage.gems >= Balance.chestCosts[kind]!
                  ? () => action(() {
                      final reward = voyage.openChest(kind, category: category);
                      if (reward != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Received ${reward.name} (${reward.rarity})',
                            ),
                          ),
                        );
                      }
                    })
                  : null,
              key: Key('chest_${category.name}_${kind.name}'),
            ),
          );
          // Common Chests only: an additional, entirely voluntary way to
          // open one -- watch a rewarded ad instead of spending gems.
          // Each category has its own independent 5/day allowance (see
          // RewardedChestService); Rare chests stay gem-only.
          if (kind == ChestKind.common &&
              rewardedChests != null &&
              onRewardedChestGranted != null) {
            widgets.add(
              RewardedChestTile(
                service: rewardedChests!,
                category: category,
                onGranted: onRewardedChestGranted!,
              ),
            );
          }
        }
      }
      for (final id in p.lastRewards) {
        final item = p.item(id)!;
        widgets.add(
          ListTile(
            title: Text('Received: ${item.name}'),
            subtitle: Text(
              '${item.rarity} • ${item.kind.name} • $id\nEquip in Upgrades',
            ),
          ),
        );
      }
    } else if (tab == 1) {
      if (c == null) {
        widgets.add(
          const ListTile(
            title: Text('Select one of your commands to develop its Tree.'),
          ),
        );
      } else {
        widgets.add(
          ListTile(
            title: Text(
              '${ship.name} • CP ${p.combatPower(ship).toStringAsFixed(1)}',
            ),
            subtitle: const Text(
              'Permanent command progression. Hull swaps keep all levels.',
            ),
          ),
        );
        const labels = [
          'Hull',
          'Firepower',
          'Crew',
          'Navigation',
          'Port Relations',
        ];
        for (final t in CommandTrack.values) {
          final level = c.level(t), cost = LifeBalance.cost(c.level(t));
          widgets.add(
            row(
              '${labels[t.index]} ${c.label(t)}',
              c.nextBenefit(t),
              level == LifeBalance.maxLevels ? 'MAXED' : '$cost coins',
              level < LifeBalance.maxLevels &&
                      voyage.coins >= cost &&
                      !voyage.busy(ship.id)
                  ? () => action(() {
                      voyage.buyTree(ship.id, t);
                    })
                  : null,
              key: Key('tree_${t.name}'),
            ),
          );
        }
      }
      widgets.add(
        const ListTile(
          title: Text('Fleet progression'),
          subtitle: Text('Shared by all commands. Does not increase CP.'),
        ),
      );
      for (final t in [FleetTrack.offline]) {
        final level = p.tree[t] ?? 0, cost = Balance.treeCost(p.tree[t] ?? 0);
        widgets.add(
          row(
            '${t == FleetTrack.portFavor ? 'Port Relations' : 'Offline Effectiveness'} $level / 1000',
            t == FleetTrack.portFavor
                ? '+0.1% arrival coins per level'
                : '+0.001 coin/min per level away. Current cap: ${p.offlineCapLabel}; grows from 4h to 8h.',
            level == 1000 ? 'MAXED' : '$cost coins',
            level < 1000 && voyage.coins >= cost
                ? () => action(() {
                    voyage.buyFleetTree(t);
                  })
                : null,
            key: Key('fleet_tree_${t.name}'),
          ),
        );
      }
    } else {
      if (c == null) {
        widgets.add(
          const ListTile(title: Text('Select your command to equip items.')),
        );
      } else {
        widgets.add(
          ListTile(
            title: Text(
              '${ship.name} • ${ship.hullType} • CP ${p.combatPower(ship).toStringAsFixed(1)}',
            ),
            subtitle: Text(
              voyage.busy(ship.id)
                  ? 'Equipment locked during battle.'
                  : 'Hull changes preserve damage percentage and Tree.',
            ),
          ),
        );
        // Grouped by the same five categories the Shop's Common/Rare
        // Chests already use (ChestCategory) -- one clearly-headed section
        // per category, in slot order within it, so equipped/empty state
        // reads at a glance instead of one flat undifferentiated list.
        const sectionOrder = [
          ChestCategory.hull,
          ChestCategory.cannon,
          ChestCategory.equipment,
          ChestCategory.crew,
          ChestCategory.officers,
        ];
        for (final category in sectionOrder) {
          final kinds = ItemKind.values.where(category.accepts);
          widgets.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
              child: Text(
                category.label,
                style: const TextStyle(
                  color: Color(0xffddbe7c),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          );
          for (final kind in kinds) {
            final current = p.item(c.equipped[kind]);
            final isDefaultHull = kind == ItemKind.hull && current == null;
            widgets.add(
              ListTile(
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
                      ? const TextStyle(
                          color: Colors.white38,
                          fontStyle: FontStyle.italic,
                        )
                      : null,
                ),
                trailing: TextButton(
                  key: Key('unequip_${kind.name}'),
                  onPressed: current != null && !voyage.busy(ship.id)
                      ? () => action(() {
                          voyage.equip(ship.id, kind, null);
                        })
                      : null,
                  child: const Text('Unequip'),
                ),
              ),
            );
            for (final item in p.inventory.where((i) => i.kind == kind)) {
              final owner = p.assignedTo(item.id),
                  equipped = current?.id == item.id;
              widgets.add(
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: row(
                    item.name,
                    '${item.description}\n${item.rarity} • ${item.id}${owner == null ? '' : ' • on ${voyage.ships.firstWhere((s) => s.id == owner).name}'}',
                    equipped ? 'Equipped' : 'Equip',
                    !equipped && owner == null && !voyage.busy(ship.id)
                        ? () => action(() {
                            voyage.equip(ship.id, kind, item.id);
                          })
                        : null,
                    key: Key('equip_${item.id}'),
                  ),
                ),
              );
            }
          }
        }
        if (p.inventory.isEmpty) {
          widgets.add(
            const ListTile(
              title: Text('No equipment yet'),
              subtitle: Text('Open a chest in Shop to obtain your first item.'),
            ),
          );
        }
      }
    }
    return Column(children: widgets);
  }
}

/// Human-readable slot name for an equipment section row. Section headers
/// already establish the category (Hull/Ordnance/Equipment/Crew/Officers),
/// so this only needs to name the individual slot within it.
String _slotLabel(ItemKind kind) => switch (kind) {
  ItemKind.hull => 'Hull',
  ItemKind.cannon => 'Ordnance',
  ItemKind.equipment => 'Ship Equipment',
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
