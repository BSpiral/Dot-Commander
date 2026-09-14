/// Content table for Explorer discoveries -- what an Explorer command
/// can find while observing (see WorldLife.checkDiscovery). Kept
/// separate from WorldLife's own orchestration logic, matching the
/// project's existing convention of separating content tables
/// (equipment_content.dart) from the behavior that consumes them.
library;

enum DiscoveryTier { small, good, great }

class DiscoveryDefinition {
  final DiscoveryTier tier;
  final int gold, gems;
  final String flavor;
  const DiscoveryDefinition(this.tier, this.gold, this.gems, this.flavor);
}

/// Most discoveries are `small` (no gems, modest gold) -- a discovery is
/// meant to make exploring feel active, not to be a jackpot machine.
/// `good` finds are an occasional real find. `great` finds are a rare,
/// flavorful jackpot (see WorldLife.checkDiscovery for the tier odds).
const discoveryContent = [
  DiscoveryDefinition(
    DiscoveryTier.small,
    8,
    0,
    'Spotted a handful of sea-worn coins caught in a tide pool: 8 gold.',
  ),
  DiscoveryDefinition(
    DiscoveryTier.small,
    10,
    0,
    'Found a small trinket box with 10 gold inside.',
  ),
  DiscoveryDefinition(
    DiscoveryTier.small,
    10,
    0,
    'Turned up an old purse holding 10 gold.',
  ),
  DiscoveryDefinition(
    DiscoveryTier.small,
    12,
    0,
    'Uncovered a buried tin with 12 gold pieces.',
  ),
  DiscoveryDefinition(
    DiscoveryTier.small,
    12,
    0,
    'Fished a waterlogged strongbox out of the shallows: 12 gold.',
  ),
  DiscoveryDefinition(
    DiscoveryTier.small,
    15,
    0,
    "Found a merchant's dropped satchel with 15 gold.",
  ),
  DiscoveryDefinition(
    DiscoveryTier.small,
    15,
    0,
    'Spotted glinting coins wedged in the rocks: 15 gold.',
  ),
  DiscoveryDefinition(
    DiscoveryTier.small,
    9,
    0,
    'A gull led the way to 9 gold scattered in the sand.',
  ),
  DiscoveryDefinition(
    DiscoveryTier.small,
    11,
    0,
    'Picked over a wreck\'s remains for 11 gold in loose coin.',
  ),
  DiscoveryDefinition(
    DiscoveryTier.small,
    14,
    0,
    'Traded a few trinkets with islanders for 14 gold.',
  ),
  DiscoveryDefinition(
    DiscoveryTier.good,
    50,
    5,
    'Uncovered a chest holding 5 uncut gems atop 50 gold in coin.',
  ),
  DiscoveryDefinition(
    DiscoveryTier.good,
    45,
    4,
    "Found a smuggler's cache: 45 gold and 4 loose gems.",
  ),
  DiscoveryDefinition(
    DiscoveryTier.good,
    55,
    6,
    'Pried open a sea chest with 55 gold and 6 gems inside.',
  ),
  DiscoveryDefinition(
    DiscoveryTier.great,
    200,
    15,
    'Found a treasure box with 3 gold cups worth 200 gold total, plus 15 loose gems.',
  ),
  DiscoveryDefinition(
    DiscoveryTier.great,
    180,
    12,
    "Unearthed a captain's hoard: 180 gold and 12 gems beneath a rotted hull.",
  ),
];
