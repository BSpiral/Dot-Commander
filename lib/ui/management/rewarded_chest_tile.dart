import 'package:flutter/material.dart';

import '../../monetization/monetization_ids.dart';
import '../../monetization/rewarded_chest_service.dart';
import '../../pirates/progression/fleet_progress.dart';

/// "Watch an ad to open a Common Chest" row -- one per [RewardedAdGroup]
/// (three real ad units), each with its own independent 5-per-day
/// allowance. A group covering more than one ChestCategory (Crew &
/// Equipment) grants a roll from a random category within it -- see
/// RewardedAdGroupLabel.chestCategories. Entirely voluntary: nothing else
/// in this screen requires it, gem purchases of any chest remain
/// available regardless of this allowance, and owning Remove Ads never
/// disables it (Remove Ads only suppresses the banner).
class RewardedChestTile extends StatefulWidget {
  final RewardedChestService service;
  final RewardedAdGroup group;
  final Future<void> Function(RewardedAdGroup group) onGranted;
  const RewardedChestTile({
    super.key,
    required this.service,
    required this.group,
    required this.onGranted,
  });

  @override
  State<RewardedChestTile> createState() => _RewardedChestTileState();
}

class _RewardedChestTileState extends State<RewardedChestTile> {
  bool _busy = false;
  int? _remainingToday;

  @override
  void initState() {
    super.initState();
    _refreshRemaining();
  }

  Future<void> _refreshRemaining() async {
    final remaining = await widget.service.remainingToday(widget.group);
    if (mounted) setState(() => _remainingToday = remaining);
  }

  Future<void> _watch() async {
    setState(() => _busy = true);
    final outcome = await widget.service.watch(widget.group);
    if (outcome == RewardedChestOutcome.granted) {
      await widget.onGranted(widget.group);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _refreshRemaining();
    if (!mounted) return;
    final message = switch (outcome) {
      RewardedChestOutcome.granted => null, // onGranted shows its own snackbar
      RewardedChestOutcome.capReached =>
        "Today's ${widget.group.label} chest ad allowance is used up; more tomorrow",
      RewardedChestOutcome.notAvailable => 'No ad ready yet; try again soon',
      RewardedChestOutcome.busy => 'An ad is already showing',
      RewardedChestOutcome.dismissedWithoutReward => 'Ad closed early; no reward',
    };
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remainingToday;
    final capped = remaining != null && remaining <= 0;
    return ListTile(
      dense: true,
      leading: const Icon(Icons.play_circle_outline, color: Color(0xffddbe7c)),
      title: Text('Watch an ad to open a Common ${widget.group.label} Chest'),
      subtitle: Text(
        capped
            ? 'Come back tomorrow for more'
            : remaining == null
                ? 'Optional'
                : '$remaining/${Balance.rewardedChestDailyCap} remaining today',
      ),
      trailing: TextButton(
        key: Key('watch_chest_ad_${widget.group.name}'),
        onPressed: _busy || capped ? null : _watch,
        child: const Text('Watch'),
      ),
    );
  }
}
