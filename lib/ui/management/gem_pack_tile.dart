import 'package:flutter/material.dart';

import '../../monetization/billing_service.dart';
import '../../monetization/monetization_ids.dart';

/// "Buy N Gems" Shop row -- one per [MonetizationIds.gemProducts] (the
/// three real Play Billing gem packs), shown directly in the Shop tab
/// rather than only behind the [GemPurchaseDialog] modal (Shop reorder
/// pass 2026-10-03: the three Gem packs are now the first three entries
/// in the Shop itself). Reuses the exact same BillingService calls the
/// modal dialog already uses (buyGems/gemPriceLabel/gemsCredited) --
/// this is a new presentation, not new purchase logic. Mirrors
/// RewardedChestTile's own shape: one small StatefulWidget per row,
/// owning its own busy/price-label state.
class GemPackTile extends StatefulWidget {
  final BillingService billing;
  final GemProductInfo product;
  const GemPackTile({super.key, required this.billing, required this.product});

  @override
  State<GemPackTile> createState() => _GemPackTileState();
}

class _GemPackTileState extends State<GemPackTile> {
  bool _busy = false;

  Future<void> _buy() async {
    setState(() => _busy = true);
    try {
      await widget.billing.buyGems(widget.product.productId);
    } finally {
      // Only clears the spinner -- buyGems merely STARTS the Play
      // purchase sheet; the real credit (and its SnackBar below) only
      // happens via gemsCredited, listened for by the ancestor that owns
      // this tile (see ProgressionPanel's own gemsCredited subscription).
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final priceLabel = widget.billing.gemPriceLabel(widget.product.productId);
    final available = priceLabel != null;
    return ListTile(
      dense: true,
      title: Text('${widget.product.totalGems} Gems'),
      subtitle: Text(
        widget.product.bonusGems > 0
            ? '${widget.product.baseGems} + ${widget.product.bonusGems} bonus'
            : 'Gem pack',
      ),
      trailing: TextButton(
        key: Key('buy_gems_shop_${widget.product.productId}'),
        onPressed: !available || _busy ? null : _buy,
        child: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                priceLabel ?? 'Unavailable',
                key: available
                    ? null
                    : Key('gem_pack_unavailable_${widget.product.productId}'),
              ),
      ),
    );
  }
}
