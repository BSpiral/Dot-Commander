import '../encounters/encounter_result.dart';
import 'battle_script.dart';

/// Converts an already decided result into inexpensive parallel card movement.
BattleScript scriptForResult(EncounterResult r) {
  final end = r.winnerId == null
      ? (r.kind == EncounterKind.escape
            ? TheaterEnding.escaped
            : TheaterEnding.draw)
      : r.winnerId == r.a.id
      ? TheaterEnding.playerVictory
      : TheaterEnding.opponentVictory;
  TheaterDamage state(
    Combatant c,
    double damage,
    int loss, {
    bool crew = false,
  }) => TheaterDamage(
    hull: (1 - (c.hullHp - damage) / c.maxHullHp).clamp(0, 1),
    sails: (damage / c.maxHullHp).clamp(0, 1),
    smoke: damage > 0 ? 0.5 : 0,
    crewFraction: crew && c.crew > 0 ? (c.crew - loss) / c.crew : 1,
  );
  final da = state(r.a, r.damageA, r.crewLossA),
      db = state(r.b, r.damageB, r.crewLossB);
  final fa = state(r.a, r.damageA, r.crewLossA, crew: true),
      fb = state(r.b, r.damageB, r.crewLossB, crew: true);
  final boarding = r.kind == EncounterKind.boarding;
  return BattleScript(
    id: r.id,
    ending: end,
    frames: [
      TheaterKeyframe(
        seconds: 0,
        phase: TheaterPhase.encounter,
        player: const DeckPose(.5, .23),
        opponent: const DeckPose(.5, .77),
        playerDamage: state(r.a, 0, 0),
        opponentDamage: state(r.b, 0, 0),
      ),
      TheaterKeyframe(
        seconds: 2,
        phase: TheaterPhase.maneuver,
        player: const DeckPose(.5, .25),
        opponent: const DeckPose(.5, .75),
        playerDamage: state(r.a, 0, 0),
        opponentDamage: state(r.b, 0, 0),
      ),
      TheaterKeyframe(
        seconds: 4,
        phase: TheaterPhase.cannon,
        player: const DeckPose(.5, .26),
        opponent: const DeckPose(.5, .74),
        playerDamage: state(r.a, 0, 0),
        opponentDamage: state(r.b, 0, 0),
      ),
      TheaterKeyframe(
        seconds: 10,
        phase: boarding
            ? TheaterPhase.closing
            : r.kind == EncounterKind.escape
            ? TheaterPhase.escape
            : TheaterPhase.cannon,
        player: const DeckPose(.5, .28),
        opponent: const DeckPose(.5, .72),
        playerDamage: da,
        opponentDamage: db,
      ),
      if (boarding)
        TheaterKeyframe(
          seconds: 14,
          phase: TheaterPhase.boarding,
          player: DeckPose(.5, r.escapedId == r.a.id ? -.4 : .32),
          opponent: const DeckPose(.5, .68),
          playerDamage: da,
          opponentDamage: db,
          planks: r.planks,
        ),
      TheaterKeyframe(
        seconds: r.duration,
        phase: TheaterPhase.complete,
        player: DeckPose(.5, r.escapedId == r.a.id ? -.4 : .32),
        opponent: DeckPose(
          .5,
          r.kind == EncounterKind.escape && r.escapedId != r.a.id ? 1.4 : .68,
        ),
        playerDamage: fa,
        opponentDamage: fb,
        planks: r.planks,
      ),
    ],
    cannonCues: const [
      CannonCue(4.5, .7, DeckPose(.35, .35), DeckPose(.6, .65)),
      CannonCue(6.5, .7, DeckPose(.6, .65), DeckPose(.35, .35)),
      CannonCue(8.5, .7, DeckPose(.65, .35), DeckPose(.4, .65)),
    ],
  );
}
