import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../pirates/encounters/pirates_voyage.dart';
import '../../pirates/encounters/encounter_result.dart';
import '../../pirates/theater/result_script.dart';
import '../../pirates/theater/battle_script.dart';
import '../../pirates/ships/hull_catalog.dart';
import '../../pirates/ships/crew_representation.dart';
import '../audio/cannon_audio.dart';
import 'deck_theater.dart';

class BattleDeck extends StatefulWidget {
  final EncounterRun run;
  final VoidCallback? onDismiss;
  final bool soundEnabled;
  const BattleDeck({
    super.key,
    required this.run,
    this.onDismiss,
    required this.soundEnabled,
  });
  @override
  State<BattleDeck> createState() => _BattleDeckState();
}

class _BattleDeckState extends State<BattleDeck>
    with SingleTickerProviderStateMixin {
  late final Ticker ticker;
  final audio = CannonAudio();
  late BattleScript script;
  late EncounterResult result;
  double last = 0;
  void prepare() {
    final r = widget.run.result;
    result = !r.a.owned && r.b.owned
        ? EncounterResult(
            id: r.id,
            a: r.b,
            b: r.a,
            kind: r.kind,
            winnerId: r.winnerId,
            escapedId: r.escapedId,
            damageA: r.damageB,
            damageB: r.damageA,
            crewLossA: r.crewLossB,
            crewLossB: r.crewLossA,
            coins: r.coins,
            gems: r.gems,
            chainA: r.chainB,
            chainB: r.chainA,
            burnedA: r.burnedB,
            burnedB: r.burnedA,
            loot: r.loot,
            effectsVersion: r.effectsVersion,
          )
        : r;
    script = scriptForResult(result);
    last = widget.run.elapsed;
  }

  @override
  void initState() {
    super.initState();
    prepare();
    ticker = createTicker((_) {
      final now = widget.run.elapsed;
      if (now == last) return;
      if (widget.soundEnabled &&
          script.cannonCues.any((c) => c.seconds > last && c.seconds <= now)) {
        audio.play();
      }
      last = now;
      setState(() {});
    })..start();
  }

  @override
  void didUpdateWidget(BattleDeck old) {
    super.didUpdateWidget(old);
    if (old.run.result.id != widget.run.result.id) prepare();
  }

  @override
  void dispose() {
    ticker.dispose();
    audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sample = script.sample(widget.run.elapsed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${result.a.name}  ⚔  ${result.b.name}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: Color(0xffe3ca98)),
        ),
        Text(
          sample.complete ? result.summary : sample.phase.name,
          style: const TextStyle(fontSize: 13, color: Color(0xffffd58a)),
        ),
        DeckTheater(
          masts: hullFor(result.a.hullType).masts,
          script: script,
          seconds: widget.run.elapsed,
          crewA: representativeCount(result.a.hullType, result.a.crew),
          crewB: representativeCount(result.b.hullType, result.b.crew),
        ),
        if (sample.complete)
          Text(
            'Hull −${result.damageA.toStringAsFixed(0)} / −${result.damageB.toStringAsFixed(0)}  •  Crew −${result.crewLossA} / −${result.crewLossB}\n+${result.coins} coins  •  +${result.gems} gems',
            style: const TextStyle(fontSize: 12),
          ),
        if (sample.complete && widget.onDismiss != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: widget.onDismiss,
              child: const Text('Return to deck'),
            ),
          ),
      ],
    );
  }
}
