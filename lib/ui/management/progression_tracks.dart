/// Future progression data is separate from owned-item categories and transactions.
class ProgressionTrack {
  final String id, title, purpose;
  final List<int> milestones;
  const ProgressionTrack(
    this.id,
    this.title,
    this.purpose, {
    this.milestones = const [10, 50, 100, 500, 1000],
  });
}

const progressionTracks = [
  ProgressionTrack('hull', 'Hull', 'Long-term hull resilience'),
  ProgressionTrack('speed', 'Speed', 'Cruising pace'),
  ProgressionTrack('hold', 'Hold', 'Capacity for future cargo systems'),
  ProgressionTrack('firepower', 'Firepower', 'Future offensive capability'),
  ProgressionTrack('crew', 'Crew capacity', 'Room for a growing crew'),
  ProgressionTrack('rigging', 'Rigging', 'Sails and handling'),
  ProgressionTrack('ports', 'Port relations', 'Future harbor connections'),
  ProgressionTrack('seamanship', 'Seamanship', 'Navigation experience'),
  ProgressionTrack(
    'offline',
    'Offline efficiency',
    'Future time-away progression',
  ),
];
