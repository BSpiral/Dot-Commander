import '../../monetization/billing_service.dart';
import '../../monetization/monetization_ids.dart';
import '../../monetization/rewarded_chest_service.dart';
import '../../pirates/encounters/pirates_voyage.dart';
import '../../pirates/ships/crew_representation.dart';
import '../../pirates/theater/result_script.dart';
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
  final Future<void> Function(RewardedAdGroup group)? onRewardedChestGranted;
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
    // Ship/combat overhaul pass 2026-09-21: crew capacity can now grow
    // past the hull's raw base (see FleetProgress.crewCapacity's own doc
    // comment) -- using hull.crew here would silently re-cap a genuinely
    // developed ship's Crew bar/text at its OLD, un-grown maximum.
    final crewCap = voyage?.progress.crewCapacity(ship) ?? hull.crew;
    // Ship/combat overhaul pass 2026-09-21 (cannon HUD fix): while THIS
    // ship is in an active encounter, the Hull/Crew bars below must
    // track the same already-authoritative, already-decided damage the
    // BattleDeck animation is revealing progressively (see
    // EncounterResult.playerFirst and TheaterSample.playerDamage) --
    // not the raw live Vessel state, which PiratesVoyage._complete only
    // actually mutates once the whole encounter animation finishes (see
    // pirates_voyage.dart). Before this fix, these bars stayed frozen at
    // the PRE-battle value for the entire fight, then snapped instantly
    // to the post-battle value the moment it ended -- cannon fire with
    // no visible consequence until the very end. The underlying numbers
    // were never fabricated (TheaterDamage is derived directly from the
    // real, already-resolved EncounterResult), just not rendered as a
    // legible bar anywhere during the fight itself.
    final liveEncounter = encounter;
    double hullFraction, crewFraction;
    if (liveEncounter != null) {
      final sample = scriptForResult(
        liveEncounter.result.playerFirst(),
      ).sample(liveEncounter.elapsed);
      hullFraction = (1 - sample.playerDamage.hull).clamp(0.0, 1.0);
      crewFraction = sample.playerDamage.crewFraction.clamp(0.0, 1.0);
    } else {
      hullFraction = (ship.hullHp / ship.maxHullHp).clamp(0.0, 1.0);
      crewFraction = (ship.crewCount / crewCap).clamp(0.0, 1.0);
    }
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
        // Compact single status block: name + current activity (the
        // player-visible "what is this ship doing right now" -- kept,
        // per the brief, since watching it is part of the fun), then one
        // line of Hull/Crew/Cargo numbers with two thin bars underneath.
        // Coins/gems (already global, in the top bar) and Destination
        // (the map already shows movement) are deliberately NOT
        // duplicated here. This replaces the old 4-row Hull/Crew block
        // plus a second, redundant Cargo/Hull/Crew text block below the
        // ship art, so the deck art itself can start much higher.
        if (voyage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
            child: Text(
              '${ship.name} • ${voyage!.life.status(ship)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xfff0d49a),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // Live playtest repair pass 2026-09-20: was hull.holds
                // (raw hull base) -- never reflected cargoCeiling or
                // equipment cargo bonuses, so an investment that
                // genuinely raised usable capacity looked like it did
                // nothing here.
                'Hull ${ship.hullHp.toStringAsFixed(0)}/${ship.maxHullHp.toStringAsFixed(0)} • Crew ${ship.crewCount}/$crewCap • Cargo ${ship.cargo}/${voyage?.progress.effectiveHoldCapacity(ship) ?? hull.holds}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: hullFraction,
                        minHeight: 3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: crewFraction,
                        minHeight: 3,
                        color: Colors.teal,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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
                  // No script/battle is running, so this "seconds" only
                  // drives the idle ambient crew wander (see
                  // TheaterPainter._crew) -- ordinary sailing/trading
                  // should still look alive, not frozen.
                  seconds: DateTime.now().millisecondsSinceEpoch / 1000,
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
          // The Deck tab (3) skips this header entirely: the player just
          // tapped the Deck tab (a large "Deck" label would be redundant)
          // and the ship's name already opens its own compact status
          // block below (see the tab==3 content above) -- this reclaims
          // a full header row's worth of height for the ship art itself.
          if (tab != 3)
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
