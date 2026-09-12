import 'battle_script.dart';

/// Hand-authored visual fixtures, not simulated encounters or balance rules.
BattleScript previewScript({bool escape = false}) {
  const damage = TheaterDamage(
    hull: .65,
    sails: .45,
    smoke: .6,
    crewFraction: .6,
  );
  return BattleScript(
    id: escape ? 'preview_escape' : 'preview_boarding',
    ending: escape ? TheaterEnding.escaped : TheaterEnding.playerVictory,
    frames: [
      const TheaterKeyframe(
        seconds: 0,
        phase: TheaterPhase.encounter,
        player: DeckPose(.28, .70),
        opponent: DeckPose(.72, .24),
      ),
      const TheaterKeyframe(
        seconds: 2,
        phase: TheaterPhase.maneuver,
        player: DeckPose(.38, .68),
        opponent: DeckPose(.63, .26),
      ),
      const TheaterKeyframe(
        seconds: 4,
        phase: TheaterPhase.cannon,
        player: DeckPose(.48, .68),
        opponent: DeckPose(.45, .28),
      ),
      TheaterKeyframe(
        seconds: 7,
        phase: escape ? TheaterPhase.escape : TheaterPhase.closing,
        player: const DeckPose(.55, .68),
        opponent: const DeckPose(.40, .30),
        opponentDamage: damage,
      ),
      TheaterKeyframe(
        seconds: 10,
        phase: escape ? TheaterPhase.escape : TheaterPhase.boarding,
        player: const DeckPose(.5, .68),
        opponent: DeckPose(escape ? 1.4 : .5, .32),
        opponentDamage: damage,
        planks: escape ? 0 : 3,
      ),
      TheaterKeyframe(
        seconds: 13,
        phase: TheaterPhase.complete,
        player: const DeckPose(.5, .68),
        opponent: DeckPose(escape ? 1.6 : .5, .32),
        opponentDamage: damage,
        planks: escape ? 0 : 3,
      ),
    ],
    cannonCues: const [
      CannonCue(4.2, .65, DeckPose(.48, .61), DeckPose(.45, .35)),
      CannonCue(5.4, .65, DeckPose(.42, .35), DeckPose(.51, .61)),
    ],
  );
}
