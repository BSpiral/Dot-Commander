import '../../monetization/monetization_ids.dart';
import '../../monetization/rewarded_chest_service.dart';
import '../../pirates/progression/life_balance.dart';
import 'package:flutter/material.dart';
import '../../pirates/progression/fleet_progress.dart';
import '../../pirates/encounters/pirates_voyage.dart';
import '../../core/simulation/vessel.dart';
import 'rewarded_chest_tile.dart';
import 'upgrades_panel.dart';

class ProgressionPanel extends StatelessWidget {
  final PiratesVoyage voyage;
  final Vessel ship;
  final int tab;
  final VoidCallback changed;
  final RewardedChestService? rewardedChests;
  final Future<void> Function(RewardedAdGroup group)? onRewardedChestGranted;
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
              '${category.label} only. Duplicate copies stack and auto-upgrade (5 -> next rarity, up to Rare).',
              '${Balance.chestCosts[kind]} gems',
              voyage.gems >= Balance.chestCosts[kind]!
                  ? () => action(() {
                      final reward = voyage.openChest(kind, category: category);
                      if (reward != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Received ${reward.name} (${reward.rarity.label})',
                            ),
                          ),
                        );
                      }
                    })
                  : null,
              key: Key('chest_${category.name}_${kind.name}'),
            ),
          );
        }
      }
      // Rewarded-ad rows: exactly 3 (one per real ad unit -- see
      // RewardedAdGroup). The Gold reward that used to live here
      // (Saturday repair pass 2026-09-20) is now the map's money ship
      // instead -- see PiratesVoyage.claimMoneyShip.
      if (rewardedChests != null && onRewardedChestGranted != null) {
        for (final group in RewardedAdGroup.values) {
          widgets.add(
            RewardedChestTile(
              service: rewardedChests!,
              group: group,
              onGranted: onRewardedChestGranted!,
            ),
          );
        }
      }
      for (final id in p.lastRewards) {
        final item = p.item(id)!;
        widgets.add(
          ListTile(
            title: Text('Received: ${item.name}'),
            subtitle: Text(
              '${item.rarity.label} • ${item.kind.name} • $id\nEquip in Upgrades',
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
      for (final t in [FleetTrack.offline, FleetTrack.shipHold]) {
        final level = p.tree[t] ?? 0, cost = Balance.treeCost(p.tree[t] ?? 0);
        final title = switch (t) {
          FleetTrack.offline => 'Offline Effectiveness',
          FleetTrack.shipHold => 'Ship Hold',
          FleetTrack.portFavor => 'Port Relations', // unreachable: never in this list
        };
        final detail = switch (t) {
          // Port Relations balance pass 2026-09-20: this track no longer
          // sets the offline coin RATE (see Balance.fleetCoinsPerHour) --
          // only the CAP on how long that rate keeps paying out while away.
          FleetTrack.offline =>
            'Increases how long your fleet keeps earning offline income '
                'while away. Current cap: ${p.offlineCapLabel}; grows from 4h to 8h.',
          FleetTrack.shipHold =>
            '+1 cargo hold on every ship per level, up to +50 total '
                '(absolute cap 100 combined with hull base and equipment). '
                'Current bonus: +${(50 * level / 1000).floor()}.',
          FleetTrack.portFavor => '',
        };
        widgets.add(
          row(
            '$title $level / 1000',
            detail,
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
      // Upgrades (tab 2): relevance-first category/slot navigation (see
      // UpgradesPanel) rather than a flat five-section item dump.
      widgets.add(UpgradesPanel(voyage: voyage, ship: ship, changed: changed));
    }
    return Column(children: widgets);
  }
}
