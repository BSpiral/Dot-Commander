/// Presentation-only coordinates: x points toward the bow (right), y down.
/// No Flutter, voyage references, RNG, damage calculation or outcome selection.
enum TheaterPhase {
  encounter,
  maneuver,
  cannon,
  escape,
  closing,
  boarding,
  complete,
}

enum TheaterEnding { playerVictory, opponentVictory, escaped, draw }

class DeckPose {
  final double x, y, heading;
  const DeckPose(this.x, this.y, [this.heading = 0]);
  static DeckPose lerp(DeckPose a, DeckPose b, double t) => DeckPose(
    a.x + (b.x - a.x) * t,
    a.y + (b.y - a.y) * t,
    a.heading + (b.heading - a.heading) * t,
  );
}

/// Fractions are appearance inputs, never changes to a Vessel.
class TheaterDamage {
  final double hull, sails, smoke, crewFraction;
  const TheaterDamage({
    this.hull = 0,
    this.sails = 0,
    this.smoke = 0,
    this.crewFraction = 1,
  });
  bool get valid => [
    hull,
    sails,
    smoke,
    crewFraction,
  ].every((v) => v.isFinite && v >= 0 && v <= 1);
}

class TheaterKeyframe {
  final double seconds;
  final TheaterPhase phase;
  final DeckPose player, opponent;
  final TheaterDamage playerDamage, opponentDamage;
  final int planks;
  const TheaterKeyframe({
    required this.seconds,
    required this.phase,
    required this.player,
    required this.opponent,
    this.playerDamage = const TheaterDamage(),
    this.opponentDamage = const TheaterDamage(),
    this.planks = 0,
  });
}

/// A cosmetic projectile with explicit timing and endpoints supplied by a script.
class CannonCue {
  final double seconds, duration;
  final DeckPose from, to;
  const CannonCue(this.seconds, this.duration, this.from, this.to);
}

class TheaterSample {
  final TheaterPhase phase;
  final DeckPose player, opponent;
  final TheaterDamage playerDamage, opponentDamage;
  final int planks;
  final bool complete;
  const TheaterSample(
    this.phase,
    this.player,
    this.opponent,
    this.playerDamage,
    this.opponentDamage,
    this.planks,
    this.complete,
  );
}

class BattleScript {
  final String id;
  final TheaterEnding ending;
  final List<TheaterKeyframe> frames;
  final List<CannonCue> cannonCues;
  double get duration => frames.last.seconds;
  BattleScript({
    required this.id,
    required this.ending,
    required List<TheaterKeyframe> frames,
    List<CannonCue> cannonCues = const [],
  }) : frames = List.unmodifiable(frames),
       cannonCues = List.unmodifiable(cannonCues) {
    if (frames.length < 2 ||
        frames.first.seconds != 0 ||
        frames.last.phase != TheaterPhase.complete) {
      throw ArgumentError('A script starts at zero and ends with completion.');
    }
    double previous = -1;
    for (final f in frames) {
      if (!f.seconds.isFinite ||
          f.seconds <= previous ||
          !f.playerDamage.valid ||
          !f.opponentDamage.valid ||
          f.planks < 0 ||
          f.planks > 5 ||
          ![
            f.player.x,
            f.player.y,
            f.player.heading,
            f.opponent.x,
            f.opponent.y,
            f.opponent.heading,
          ].every((v) => v.isFinite)) {
        throw ArgumentError('Invalid theater keyframe.');
      }
      previous = f.seconds;
    }
    for (final cue in cannonCues) {
      if (!cue.seconds.isFinite ||
          !cue.duration.isFinite ||
          cue.seconds < 0 ||
          cue.duration <= 0 ||
          cue.seconds + cue.duration > duration ||
          ![
            cue.from.x,
            cue.from.y,
            cue.to.x,
            cue.to.y,
          ].every((v) => v.isFinite)) {
        throw ArgumentError('Invalid cannon cue.');
      }
    }
  }

  /// Seekable: elapsed time alone determines presentation; no integration drift.
  /// Damage/phase changes occur at keys; poses interpolate between them.
  TheaterSample sample(double seconds) {
    if (!seconds.isFinite) throw ArgumentError.value(seconds);
    final time = seconds.clamp(0.0, duration);
    var a = frames.first, b = frames.last;
    for (var i = 1; i < frames.length; i++) {
      if (time < frames[i].seconds) {
        b = frames[i];
        break;
      }
      a = frames[i];
    }
    final t = a == b ? 0.0 : (time - a.seconds) / (b.seconds - a.seconds);
    return TheaterSample(
      a.phase,
      DeckPose.lerp(a.player, b.player, t),
      DeckPose.lerp(a.opponent, b.opponent, t),
      a.playerDamage,
      a.opponentDamage,
      a.planks,
      time >= duration,
    );
  }
}
