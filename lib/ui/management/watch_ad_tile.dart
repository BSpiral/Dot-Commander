import 'package:flutter/material.dart';

import '../../monetization/ads_service.dart';

/// "Watch an ad for gems" row: entirely voluntary (nothing else in this
/// screen requires it), capped per real-world day so it can never become
/// the dominant gem source, and reports its outcome via a snackbar rather
/// than silently doing nothing when an ad is not ready/capped.
class WatchAdTile extends StatefulWidget {
  final RewardedAdController controller;
  final int rewardGems;
  final int dailyCap;
  final void Function(int gems) onGranted;
  const WatchAdTile({
    super.key,
    required this.controller,
    required this.rewardGems,
    required this.dailyCap,
    required this.onGranted,
  });

  @override
  State<WatchAdTile> createState() => _WatchAdTileState();
}

class _WatchAdTileState extends State<WatchAdTile> {
  bool _busy = false;
  int? _remainingToday;

  @override
  void initState() {
    super.initState();
    _refreshRemaining();
  }

  Future<void> _refreshRemaining() async {
    final remaining = await widget.controller.store.rewardedAdsRemainingToday(
      widget.dailyCap,
    );
    if (mounted) setState(() => _remainingToday = remaining);
  }

  Future<void> _watch() async {
    setState(() => _busy = true);
    final (outcome, gems) = await widget.controller.watch(
      rewardGems: widget.rewardGems,
      dailyCap: widget.dailyCap,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await _refreshRemaining();
    if (!mounted) return;
    final message = switch (outcome) {
      RewardedWatchOutcome.rewarded => 'Received $gems gems',
      RewardedWatchOutcome.capReached =>
        'Daily rewarded-ad limit reached; more tomorrow',
      RewardedWatchOutcome.notAvailable => 'No ad ready yet; try again soon',
      RewardedWatchOutcome.dismissedWithoutReward => 'Ad closed early; no reward',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    if (outcome == RewardedWatchOutcome.rewarded) widget.onGranted(gems);
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remainingToday;
    final capped = remaining != null && remaining <= 0;
    return ListTile(
      dense: true,
      leading: const Icon(Icons.play_circle_outline, color: Color(0xffddbe7c)),
      title: const Text('Watch an ad for gems'),
      subtitle: Text(
        capped
            ? 'Come back tomorrow for more'
            : 'Optional • +${widget.rewardGems} gems'
                  '${remaining == null ? '' : ' • $remaining/${widget.dailyCap} left today'}',
      ),
      trailing: TextButton(
        key: const Key('watch_rewarded_ad'),
        onPressed: _busy || capped ? null : _watch,
        child: const Text('Watch'),
      ),
    );
  }
}
