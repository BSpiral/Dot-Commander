import 'package:flutter/material.dart';

import '../../monetization/rewarded_gold_service.dart';
import '../../pirates/progression/fleet_progress.dart';

/// "Watch an ad for gold" row (playability pass 2026-09-18) -- the reward
/// opportunity freed up by consolidating the old 5 near-identical Common
/// Chest ad rows down to 3 (see RewardedChestTile). [goldPreview] is
/// shown so the player knows roughly what they're watching for before
/// tapping; the actual grant (PiratesVoyage.grantAdGold) always uses the
/// player's CURRENT earning rate at the moment the ad completes, so the
/// preview and the actual grant can differ slightly if progression
/// changed in between.
class RewardedGoldTile extends StatefulWidget {
  final RewardedGoldService service;
  final int goldPreview;
  final Future<void> Function() onGranted;
  const RewardedGoldTile({
    super.key,
    required this.service,
    required this.goldPreview,
    required this.onGranted,
  });

  @override
  State<RewardedGoldTile> createState() => _RewardedGoldTileState();
}

class _RewardedGoldTileState extends State<RewardedGoldTile> {
  bool _busy = false;
  int? _remainingToday;

  @override
  void initState() {
    super.initState();
    _refreshRemaining();
  }

  Future<void> _refreshRemaining() async {
    final remaining = await widget.service.remainingToday();
    if (mounted) setState(() => _remainingToday = remaining);
  }

  Future<void> _watch() async {
    setState(() => _busy = true);
    final outcome = await widget.service.watch();
    if (outcome == RewardedGoldOutcome.granted) {
      await widget.onGranted();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _refreshRemaining();
    if (!mounted) return;
    final message = switch (outcome) {
      RewardedGoldOutcome.granted => null, // onGranted shows its own snackbar
      RewardedGoldOutcome.capReached =>
        "Today's gold ad allowance is used up; more tomorrow",
      RewardedGoldOutcome.notAvailable => 'No ad ready yet; try again soon',
      RewardedGoldOutcome.busy => 'An ad is already showing',
      RewardedGoldOutcome.dismissedWithoutReward => 'Ad closed early; no reward',
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
      leading: const Icon(Icons.monetization_on_outlined, color: Color(0xffddbe7c)),
      title: const Text('Watch an ad for gold'),
      subtitle: Text(
        capped
            ? 'Come back tomorrow for more'
            : '~${widget.goldPreview} coins • ${remaining ?? Balance.rewardedChestDailyCap}/${Balance.rewardedChestDailyCap} remaining today',
      ),
      trailing: TextButton(
        key: const Key('watch_gold_ad'),
        onPressed: _busy || capped ? null : _watch,
        child: const Text('Watch'),
      ),
    );
  }
}
