import 'dart:math' as math;
import '../../core/simulation/vessel.dart';
import '../ships/hull_catalog.dart';

/// Only the existing captain is named. Remaining dots are generic representatives,
/// not invented officers or one actor per sailor.
int representativeCount(String hull, int crew, {int importantCrew = 1}) {
  if (crew <= 0) return 0;
  final info = hullFor(hull);
  final strength = (crew / info.crew).clamp(0.0, 1.0);
  return math
      .max(importantCrew, (info.representativeCap * math.sqrt(strength)).ceil())
      .clamp(1, info.representativeCap)
      .clamp(0, crew);
}

int vesselRepresentatives(Vessel ship) =>
    representativeCount(ship.hullType, ship.crewCount);
