import '../../monetization/billing_service.dart';
import '../../monetization/monetization_ids.dart';
import '../../monetization/rewarded_chest_service.dart';
import '../../pirates/progression/life_balance.dart';
import 'package:flutter/material.dart';
import '../../pirates/progression/fleet_progress.dart';
import '../../pirates/encounters/pirates_voyage.dart';
import '../../core/simulation/vessel.dart';
import 'coin_purchase_dialog.dart';
import 'gem_purchase_dialog.dart';
import 'rewarded_chest_tile.dart';
import 'upgrades_panel.dart';

class ProgressionPanel extends StatelessWidget {
  final PiratesVoyage voyage;
  final Vessel ship;
  final int tab;
  final VoidCallback changed;
  final RewardedChestService? rewardedChests;
  final Future<void> Function(RewardedAdGroup group)? onRewardedChestGranted;
  final BillingService? billing;
  const ProgressionPanel({
    super.key,
    required this.voyage,
    required this.ship,
    required this.tab,
    required this.changed,
    this.rewardedChests,
    this.onRewardedChestGranted,
    this.billing,
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
          n == 5
              ? null
              : () {
                  final cost = Balance.slotCosts[n];
                  if (voyage.coins < cost) {
                    final billingService = billing;
                    if (billingService != null) {
                      showNotEnoughCoinsDialog(
                        context,
                        need: cost - voyage.coins,
                        billing: billingService,
                        voyage: voyage,
                      );
                    }
                    return;
                  }
                  action(() => voyage.purchaseSlot());
                },
          key: const Key('buy_slot'),
        ),
      );
      // Shop cleanup pass 2026-09-22: ChestCategory.equipment (the plain
      // "Common/Rare Equipment Chest" gem purchase) is deliberately
      // skipped here -- redundant with the wider ChestCategory.hull
      // family, which already independently covers the same
      // rigging/reinforcement/figurehead pool (see
      // ChestCategoryContent.accepts's own doc comment). This removes
      // only the Shop's two gem-purchase ROWS; the enum value, openChest,
      // and equipment already owned/dropped elsewhere are all untouched
      // -- ChestCategory.crew ("Crew Equipment") and ChestCategory.hull/
      // officers keep their own rows exactly as before.
      for (final category in ChestCategory.values) {
        if (category == ChestCategory.equipment) continue;
        for (final kind in ChestKind.values) {
          final cost = Balance.chestCosts[kind]!;
          final affordable = voyage.gems >= cost;
          widgets.add(
            row(
              '${kind.name == 'common' ? 'Common' : 'Rare'} ${category.label} Chest',
              '${category.label} only. Duplicate copies stack and auto-upgrade (5 -> next rarity, up to Rare).',
              '$cost gems',
              () {
                if (!affordable) {
                  final billingService = billing;
                  if (billingService != null) {
                    showNotEnoughGemsDialog(
                      context,
                      need: cost - voyage.gems,
                      billing: billingService,
                      voyage: voyage,
                    );
                  }
                  return;
                }
                action(() {
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
                });
              },
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
          final maxed = level == LifeBalance.maxLevels;
          final busy = voyage.busy(ship.id);
          widgets.add(
            row(
              '${labels[t.index]} ${c.label(t)}',
              c.nextBenefit(t),
              maxed ? 'MAXED' : '$cost coins',
              maxed || busy
                  ? null
                  : () {
                      if (voyage.coins < cost) {
                        final billingService = billing;
                        if (billingService != null) {
                          showNotEnoughCoinsDialog(
                            context,
                            need: cost - voyage.coins,
                            billing: billingService,
                            voyage: voyage,
                          );
                        }
                        return;
                      }
                      action(() => voyage.buyTree(ship.id, t));
                    },
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
      // Ship/combat overhaul clarification pass 2026-09-21: FleetTrack.
      // shipHold ("Ship Hold 0/1000 -- +1 cargo hold on every ship per
      // level") is retired -- removed from this row list entirely, so
      // it's no longer purchasable or even visible. Cargo capacity is
      // now governed entirely by hull identity (HullDefinition.
      // cargoCeiling) + legitimate equipment -- see FleetProgress.
      // effectiveHoldCapacity. Offline Effectiveness remains the only
      // Fleet-wide progression row.
      for (final t in [FleetTrack.offline]) {
        final level = p.tree[t] ?? 0, cost = Balance.treeCost(p.tree[t] ?? 0);
        final title = switch (t) {
          FleetTrack.offline => 'Offline Effectiveness',
          FleetTrack.shipHold => 'Ship Hold', // unreachable: retired, never in this list
          FleetTrack.portFavor => 'Port Relations', // unreachable: never in this list
        };
        final detail = switch (t) {
          // Port Relations balance pass 2026-09-20: this track no longer
          // sets the offline coin RATE (see Balance.fleetCoinsPerHour) --
          // only the CAP on how long that rate keeps paying out while away.
          FleetTrack.offline =>
            'Increases how long your fleet keeps earning offline income '
                'while away. Current cap: ${p.offlineCapLabel}; grows from 4h to 8h.',
          FleetTrack.shipHold => '', // unreachable: retired, never in this list
          FleetTrack.portFavor => '',
        };
        widgets.add(
          row(
            '$title $level / 1000',
            detail,
            level == 1000 ? 'MAXED' : '$cost coins',
            level == 1000
                ? null
                : () {
                    if (voyage.coins < cost) {
                      final billingService = billing;
                      if (billingService != null) {
                        showNotEnoughCoinsDialog(
                          context,
                          need: cost - voyage.coins,
                          billing: billingService,
                          voyage: voyage,
                        );
                      }
                      return;
                    }
                    action(() => voyage.buyFleetTree(t));
                  },
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
