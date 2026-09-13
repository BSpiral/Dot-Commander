import 'package:flutter/material.dart';

import '../../monetization/billing_service.dart';

/// Settings-tab row for the one-time Remove Ads entitlement. Purely a
/// thin UI shell over [BillingService] -- all purchase-flow correctness
/// (exactly-once grant, no duplication, persistence) lives there.
class RemoveAdsTile extends StatefulWidget {
  final BillingService billing;
  final bool owned;
  const RemoveAdsTile({super.key, required this.billing, required this.owned});

  @override
  State<RemoveAdsTile> createState() => _RemoveAdsTileState();
}

class _RemoveAdsTileState extends State<RemoveAdsTile> {
  bool _busy = false;

  Future<void> _buy() async {
    setState(() => _busy = true);
    try {
      await widget.billing.buyRemoveAds();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      await widget.billing.restorePurchases();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.owned) {
      return const ListTile(
        key: Key('remove_ads_owned'),
        leading: Icon(Icons.check_circle_outline, color: Colors.lightGreen),
        title: Text('Remove Ads'),
        subtitle: Text(
          'Purchased. The banner is removed. Rewarded Common Chest ads '
          'remain available whenever you want them.',
        ),
      );
    }
    return ListTile(
      leading: const Icon(Icons.block_outlined),
      title: Text('Remove Ads (${widget.billing.removeAdsPriceLabel})'),
      subtitle: const Text(
        'One-time purchase. Removes the banner and offers no future ads. '
        'Does not affect gameplay progress.',
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          TextButton(
            key: const Key('restore_purchases'),
            onPressed: _busy ? null : _restore,
            child: const Text('Restore'),
          ),
          TextButton(
            key: const Key('buy_remove_ads'),
            onPressed: _busy ? null : _buy,
            child: const Text('Buy'),
          ),
        ],
      ),
    );
  }
}
