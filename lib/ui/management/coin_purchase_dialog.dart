import 'dart:async';

import 'package:flutter/material.dart';

import '../../monetization/billing_service.dart';
import '../../monetization/monetization_ids.dart';
import '../../pirates/encounters/pirates_voyage.dart';

/// The USER-INITIATED-ONLY "Buy Coins" modal (monetization update pass
/// 2026-09-27) -- the coin-purchase sibling of gem_purchase_dialog.dart's
/// [showGemPurchaseDialog]; see that file's own doc comment for the "never
/// automatic" rule this follows identically (no startup/post-match/
/// low-balance/timer/discount auto-open, ever).
Future<void> showCoinPurchaseDialog(
  BuildContext context, {
  required BillingService billing,
  required PiratesVoyage voyage,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => CoinPurchaseDialog(billing: billing, voyage: voyage),
  );
}

class CoinPurchaseDialog extends StatefulWidget {
  final BillingService billing;
  final PiratesVoyage voyage;
  const CoinPurchaseDialog({
    super.key,
    required this.billing,
    required this.voyage,
  });

  @override
  State<CoinPurchaseDialog> createState() => _CoinPurchaseDialogState();
}

class _CoinPurchaseDialogState extends State<CoinPurchaseDialog> {
  StreamSubscription<int>? _sub;
  bool _busy = false;
  int? _lastCreditedAmount;

  @override
  void initState() {
    super.initState();
    _sub = widget.billing.coinsCredited.listen((amount) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _lastCreditedAmount = amount;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _buy() async {
    setState(() => _busy = true);
    try {
      await widget.billing.buyCoins();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('coin_purchase_dialog'),
      title: const Text('Buy Coins'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '● ${widget.voyage.coins} coins',
            key: const Key('coin_purchase_balance'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          if (_lastCreditedAmount != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Purchase successful: +$_lastCreditedAmount coins',
                key: const Key('coin_purchase_success'),
                style: const TextStyle(color: Colors.lightGreen, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              // BILLING AUDIT FIX: `priceLabel == null` means the coin
              // pack hasn't resolved with Play -- disable Buy and show
              // "Unavailable" rather than a guessed/hardcoded price.
              final priceLabel = widget.billing.coinsPriceLabel;
              final available = priceLabel != null;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('${MonetizationIds.coins5000Amount} COINS'),
                trailing: SizedBox(
                  width: 84,
                  child: ElevatedButton(
                    key: const Key('buy_coins_${MonetizationIds.coins5000ProductId}'),
                    onPressed: !available || _busy ? null : _buy,
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            priceLabel ?? 'Unavailable',
                            key: available ? null : const Key('coins_unavailable'),
                          ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('coin_purchase_close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// "NOT ENOUGH COINS" prompt -- coin-purchase sibling of
/// gem_purchase_dialog.dart's [showNotEnoughGemsDialog]. Shown only when a
/// player attempts something they can't afford, never automatically.
Future<void> showNotEnoughCoinsDialog(
  BuildContext context, {
  required int need,
  required BillingService billing,
  required PiratesVoyage voyage,
}) async {
  final wantsToBuy = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('not_enough_coins_dialog'),
      title: const Text('Not enough coins'),
      content: Text('You need $need more coins.'),
      actions: [
        TextButton(
          key: const Key('not_enough_coins_cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('not_enough_coins_buy'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Buy Coins'),
        ),
      ],
    ),
  );
  if (wantsToBuy == true && context.mounted) {
    await showCoinPurchaseDialog(context, billing: billing, voyage: voyage);
  }
}
