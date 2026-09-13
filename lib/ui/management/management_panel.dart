import '../../monetization/billing_service.dart';
import '../../monetization/rewarded_chest_service.dart';
import '../../pirates/encounters/pirates_voyage.dart';
import '../../pirates/progression/fleet_progress.dart';
import '../../pirates/ships/crew_representation.dart';
import '../theater/battle_deck.dart';
import 'package:flutter/foundation.dart';
import '../theater/deck_theater.dart';
import 'package:flutter/material.dart';
import '../../core/simulation/vessel.dart';
import '../../pirates/ships/hull_catalog.dart';
import 'progression_panel.dart';
import 'remove_ads_tile.dart';

const managementLabels = ['Shop', 'Tree', 'Upgrades', 'Deck', 'Settings'];

class ManagementPanel extends StatelessWidget {
  final PiratesVoyage? voyage;
  final VoidCallback? onChanged;
  final VoidCallback? debugReset;
  final EncounterRun? encounter;
  final VoidCallback? dismissEncounter;
  final bool soundEnabled;
  final VoidCallback? toggleSound;
  final int tab;
  final Vessel ship;
  final int fleetSize;
  final String? saveError;
  final bool paused;
  final VoidCallback togglePause;
  final bool hasRemoveAds;
  final RewardedChestService? rewardedChests;
  final BillingService? billing;
  final Future<void> Function(ChestCategory category)? onRewardedChestGranted;
  const ManagementPanel({
    super.key,
    this.encounter,
    this.voyage,
    this.onChanged,
    this.debugReset,
    this.dismissEncounter,
    this.soundEnabled = false,
    this.toggleSound,
    required this.tab,
    required this.ship,
    required this.fleetSize,
    required this.saveError,
    required this.paused,
    required this.togglePause,
    this.hasRemoveAds = false,
    this.rewardedChests,
    this.billing,
    this.onRewardedChestGranted,
  });
  @override
  Widget build(BuildContext context) {
    final hull = hullFor(ship.hullType);
    Widget note(IconData icon, String title, String body) => ListTile(
      leading: Icon(icon, color: const Color(0xffddbe7c)),
      title: Text(title),
      subtitle: Text(body),
    );
    final content = switch (tab) {
      0 || 1 || 2 => [
        if (voyage != null)
          ProgressionPanel(
            voyage: voyage!,
            ship: ship,
            tab: tab,
            changed: onChanged ?? () {},
            rewardedChests: rewardedChests,
            onRewardedChestGranted: onRewardedChestGranted,
          ),
      ],
      3 => [
        if (voyage != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              voyage!.life.status(ship),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Text(
                'Hull ${ship.hullHp.toStringAsFixed(1)} / ${ship.maxHullHp.toStringAsFixed(1)}',
              ),
              LinearProgressIndicator(
                value: (ship.hullHp / ship.maxHullHp).clamp(0, 1),
              ),
              Text('Crew ${ship.crewCount} / ${hull.crew}'),
              LinearProgressIndicator(
                value: (ship.crewCount / hull.crew).clamp(0, 1),
                color: Colors.teal,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: encounter != null
              ? BattleDeck(
                  key: ValueKey(encounter!.result.id),
                  run: encounter!,
                  onDismiss: dismissEncounter,
                  soundEnabled: soundEnabled,
                )
              : DeckTheater(
                  masts: hull.masts,
                  damage: 1 - ship.hullHp / ship.maxHullHp,
                  crewA: vesselRepresentatives(ship),
                ),
        ),
        if (encounter == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Cargo ${ship.cargo}/${hull.holds} • ${ship.hullType} • Captain ${ship.captain}\nHull ${ship.hullHp.toInt()}/${ship.maxHullHp.toInt()} • Crew ${ship.crewCount}',
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ExpansionTile(
          key: PageStorageKey('activity_${ship.id}'),
          title: const Text('Recent activity'),
          children: [
            for (final event in ship.recentActivity)
              ListTile(dense: true, title: Text(event)),
          ],
        ),
        if (kDebugMode)
          TextButton(
            key: const Key('theater_preview'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const TheaterPreview(),
            ),
            child: const Text('Development: theater preview'),
          ),
      ],
      _ => [
        if (kDebugMode && debugReset != null)
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.orange),
            title: const Text('DEBUG: Reset all game progress'),
            subtitle: const Text('Development only. Confirmation required.'),
            trailing: TextButton(
              key: const Key('debug_reset'),
              onPressed: debugReset,
              child: const Text('Reset'),
            ),
          ),
        SwitchListTile(
          title: const Text('Cannon sounds'),
          value: soundEnabled,
          onChanged: toggleSound == null ? null : (_) => toggleSound!(),
        ),
        SwitchListTile(
          title: const Text('Pause voyage'),
          subtitle: const Text('Pause or resume the living map.'),
          value: paused,
          onChanged: (_) => togglePause(),
        ),
        note(
          Icons.save_outlined,
          'Local voyage',
          saveError ??
              'Saved every five seconds. Current offline cap: ${voyage?.progress.offlineCapLabel ?? '4h 0m'}. Battles do not simulate offline.',
        ),
        if (billing != null) RemoveAdsTile(billing: billing!, owned: hasRemoveAds),
        note(
          Icons.info_outline,
          'Dot Commander: Pirates',
          'CrowsNest • Dot Commander: Pirates',
        ),
      ],
    };
    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text(
                  managementLabels[tab],
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xfff0d49a),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    ship.name,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              key: PageStorageKey('management_$tab'),
              padding: EdgeInsets.zero,
              children: content,
            ),
          ),
        ],
      ),
    );
  }
}
