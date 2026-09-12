import 'dart:math';
import '../../core/movement/sea_navigation.dart';
import '../../core/movement/point.dart';
import '../encounters/pirates_voyage.dart';
import '../../core/simulation/vessel.dart';
import '../ships/hull_catalog.dart';

const caribbeanPlaces = [
  Destination('haven', 'Haven Cay', Point2(160, 150), DestinationKind.port),
  Destination('royal', 'Kingsford', Point2(780, 180), DestinationKind.port),
  Destination(
    'tortuga',
    'Pirate Haven',
    Point2(660, 580),
    DestinationKind.port,
  ),
  Destination('pearl', 'Port Mercy', Point2(180, 540), DestinationKind.port),
  Destination(
    'reef',
    'Sapphire Reef',
    Point2(470, 290),
    DestinationKind.search,
  ),
  Destination('shoal', 'Lost Shoals', Point2(400, 560), DestinationKind.search),
  Destination('marrow', 'Saint Marrow', Point2(330, 180), DestinationKind.port),
  Destination('copper', 'Copperhook', Point2(890, 450), DestinationKind.port),
  Destination(
    'lantern',
    'Lantern Reef',
    Point2(760, 380),
    DestinationKind.search,
  ),
  Destination(
    'widow',
    "Widow's Reef",
    Point2(110, 365),
    DestinationKind.search,
  ),
];
final legacyCaribbeanLand = List<LandRegion>.unmodifiable([
  for (final place in caribbeanPlaces.take(6))
    LandRegion(
      place.id,
      place.position.x - 88,
      place.position.y - 78,
      place.position.x + 12,
      place.position.y - 18,
    ),
]);
final caribbeanLand = List<LandRegion>.unmodifiable([
  ...legacyCaribbeanLand,
  const LandRegion('marrow', 260, 100, 342, 160),
  const LandRegion('copper', 820, 365, 897, 427),
  const LandRegion('lantern', 702, 320, 772, 354),
  const LandRegion('widow', 42, 285, 122, 347),
  const LandRegion('west_spit', 25, 190, 102, 230),
  const LandRegion('little_cay', 210, 320, 242, 342),
  const LandRegion('tangerinco', 505, 90, 620, 165),
  const LandRegion('needle', 650, 220, 677, 240),
  const LandRegion('east_ridge', 795, 240, 890, 294),
  const LandRegion('green_isle', 505, 345, 590, 405),
  const LandRegion('tern', 290, 420, 315, 440),
  const LandRegion('north_rock', 390, 75, 425, 100),
  const LandRegion('south_cay', 80, 610, 135, 630),
  const LandRegion('long_isle', 220, 610, 310, 663),
  const LandRegion('spice_rock', 495, 620, 524, 640),
  const LandRegion('leeward', 810, 535, 879, 560),
]);

/// Deterministic relocation used only for new spawns and version-1 map migration.
Point2 nearestWater(Point2 point, SeaNavigation navigation) {
  if (navigation.isWater(point)) return point;
  for (var radius = 4.0; radius <= 1200; radius += 4) {
    for (final delta in [
      Point2(radius, 0),
      Point2(0, radius),
      Point2(-radius, 0),
      Point2(0, -radius),
      Point2(radius, radius),
      Point2(-radius, radius),
      Point2(-radius, -radius),
      Point2(radius, -radius),
    ]) {
      final candidate = Point2(point.x + delta.x, point.y + delta.y);
      if (navigation.isWater(candidate)) return candidate;
    }
  }
  throw StateError('No navigable spawn');
}

PiratesVoyage createCaribbean({
  int seed = 73,
  List<Vessel>? restoredShips,
  bool encountersEnabled = false,
}) {
  const names = [
    'Sea Lark',
    'Marigold',
    'Black Kite',
    'North Star',
    'Resolute',
    'Coral Wind',
    'Night Heron',
    'Venture',
    'Amber Bell',
    'Grey Warden',
    'Iron Crown',
    'Juniper',
    'Red Jack',
    'Salt Finch',
    'Sovereign',
  ];
  const captains = [
    'Alex Morgan',
    'Ines Flores',
    'Rowan Flint',
    'Mara Reed',
    'Elias Ward',
    'Lucia Vale',
    'Silas Crow',
    'Nia Drake',
    'Paz Moreno',
    'Theo Pike',
    'Ada Stern',
    'Elin Moss',
    'Rafe Cole',
    'Ona Finch',
    'Jonas Grey',
  ];
  const hulls = [
    'Sloop',
    'Schooner',
    'Brig',
    'Schooner',
    'Frigate',
    'Galley',
    'Brig',
    'Sloop',
    'Galley',
    'Frigate',
    'Man-of-War',
    'Schooner',
    'Brig',
    'Galley',
    'Man-of-War',
  ];
  const modes = [
    BehaviorMode.merchant,
    BehaviorMode.merchant,
    BehaviorMode.pirate,
    BehaviorMode.explorer,
    BehaviorMode.privateer,
    BehaviorMode.merchant,
    BehaviorMode.pirate,
    BehaviorMode.explorer,
    BehaviorMode.merchant,
    BehaviorMode.privateer,
    BehaviorMode.merchant,
    BehaviorMode.explorer,
    BehaviorMode.pirate,
    BehaviorMode.merchant,
    BehaviorMode.privateer,
  ];
  final navigation = SeaNavigation(caribbeanLand);
  return PiratesVoyage(
    encountersEnabled: encountersEnabled,
    places: caribbeanPlaces,
    navigation: navigation,
    rng: Random(seed),
    ships:
        restoredShips ??
        [
          for (var i = 0; i < names.length; i++)
            Vessel(
              id: 'ship-$i',
              name: names[i],
              captain: captains[i],
              hullType: hulls[i],
              position: nearestWater(
                Point2(200 + (i % 5) * 135.0, 240 + (i ~/ 5) * 165.0),
                navigation,
              ),
              speed: hullFor(hulls[i]).baseSpeed,
              maxHullHp: hullFor(hulls[i]).hp,
              crewCount: hullFor(hulls[i]).crew,
              behavior: modes[i],
              playerOwned: i == 0,
              load: LoadState.values[i % 3],
            ),
        ],
  );
}
