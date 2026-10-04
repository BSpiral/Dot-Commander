import 'dart:async';

import 'package:flutter/material.dart';

import '../../monetization/billing_service.dart';
import '../../monetization/monetization_ids.dart';
import '../../pirates/encounters/pirates_voyage.dart';

/// The USER-INITIATED-ONLY "Buy Gems" modal (monetization update pass
/// 2026-09-27). Shows exactly the three configured gem packs with their
/// real, localized Play Billing price -- never a hardcoded currency
/// string (see BillingService.gemPriceLabel) -- plus the player's current
/// balance, which updates live if a purchase completes while this is
/// open.
///
/// This dialog is never shown automatically by anything in this app (not
/// at startup, after a match, on low gems, on an ad failure, on a timer,
/// or as a promotion) -- every call site is a deliberate player action
/// (tapping the "+" by the gem counter, or tapping BUY GEMS from
/// [showNotEnoughGemsDialog]). Keep it that way: do not wire a new
/// automatic call site without updating this comment.
Future<void> showGemPurchaseDialog(
  BuildContext context, {
  required BillingService billing,
  required PiratesVoyage voyage,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => GemPurchaseDialog(billing: billing, voyage: voyage),
  );
}

class GemPurchaseDialog extends StatefulWidget {
  final BillingService billing;
  final PiratesVoyage voyage;
  const GemPurchaseDialog({
    super.key,
    required this.billing,
    required this.voyage,
  });

  @override
  State<GemPurchaseDialog> createState() => _GemPurchaseDialogState();
}

class _GemPurchaseDialogState extends State<GemPurchaseDialog> {
  StreamSubscription<int>? _sub;
  String? _busyProductId;
  int? _lastCreditedAmount;

  @override
  void initState() {
    super.initState();
    _sub = widget.billing.gemsCredited.listen((amount) {
      if (!mounted) return;
      setState(() {
        _busyProductId = null;
        _lastCreditedAmount = amount;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _buy(String productId) async {
    setState(() => _busyProductId = productId);
    try {
      await widget.billing.buyGems(productId);
    } finally {
      // Only clears the spinner -- buyGems merely STARTS the Play
      // purchase sheet; it does not itself confirm the purchase (see
      // gemsCredited, which clears _busyProductId again on success and
      // is the only place a real credit happens).
      if (mounted && _busyProductId == productId) {
        setState(() => _busyProductId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('gem_purchase_dialog'),
      title: const Text('Buy Gems'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '◆ ${widget.voyage.gems} gems',
              key: const Key('gem_purchase_balance'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (_lastCreditedAmount != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Purchase successful: +$_lastCreditedAmount gems',
                  key: const Key('gem_purchase_success'),
                  style: const TextStyle(
                    color: Colors.lightGreen,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            for (final product in MonetizationIds.gemProducts)
              Builder(
                builder: (context) {
                  // BILLING AUDIT FIX: `priceLabel == null` means this
                  // product hasn't resolved with Play (not yet created in
                  // Play Console, offline at startup, store unreachable)
                  // -- the row must show "Unavailable" and disable Buy,
                  // never a guessed/hardcoded price that would make it
                  // look purchasable when it isn't.
                  final priceLabel = widget.billing.gemPriceLabel(
                    product.productId,
                  );
                  final available = priceLabel != null;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${product.totalGems} GEMS'),
                      subtitle: product.bonusGems > 0
                          ? Text('${product.baseGems} + ${product.bonusGems} BONUS')
                          : null,
                      trailing: SizedBox(
                        width: 84,
                        child: ElevatedButton(
                          key: Key('buy_gems_${product.productId}'),
                          onPressed: !available || _busyProductId != null
                              ? null
                              : () => _buy(product.productId),
                          child: _busyProductId == product.productId
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  priceLabel ?? 'Unavailable',
                                  key: available
                                      ? null
                                      : Key('gem_unavailable_${product.productId}'),
                                ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('gem_purchase_close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// "NOT ENOUGH GEMS" prompt shown only when a player attempts something
/// they can't afford -- never automatically. BUY GEMS opens the real
/// purchase modal ([showGemPurchaseDialog]); CANCEL (or dismissing) just
/// returns to the game with nothing changed.
Future<void> showNotEnoughGemsDialog(
  BuildContext context, {
  required int need,
  required BillingService billing,
  required PiratesVoyage voyage,
}) async {
  final wantsToBuy = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('not_enough_gems_dialog'),
      title: const Text('Not enough gems'),
      content: Text('You need $need more gems.'),
      actions: [
        TextButton(
          key: const Key('not_enough_gems_cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('not_enough_gems_buy'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Buy Gems'),
        ),
      ],
    ),
  );
  if (wantsToBuy == true && context.mounted) {
    await showGemPurchaseDialog(context, billing: billing, voyage: voyage);
  }
}
