import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'monetization_ids.dart';

/// The permanent ad container. This box (brown border, fixed height) is
/// always present during ad-supported play -- it never collapses or
/// disappears while an ad is loading, only failed/retrying -- so the
/// layout never jumps around. It shows placeholder text until a real
/// banner creative has loaded, then swaps in the live [AdWidget] in the
/// exact same spot, same border. It is never moved elsewhere.
///
/// The only time this box goes away is when Remove Ads is owned
/// ([showAds] false), which fully collapses it to zero height.
class BannerAdBar extends StatefulWidget {
  /// The container's fixed height, whether showing the placeholder or a
  /// loaded ad. Exposed so layout code that reserves space for this bar
  /// (see CommandScreen) has one source of truth instead of a duplicated
  /// magic number.
  static const double height = 56;

  final bool showAds;
  const BannerAdBar({super.key, required this.showAds});

  @override
  State<BannerAdBar> createState() => _BannerAdBarState();
}

class _BannerAdBarState extends State<BannerAdBar> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.showAds) _load();
  }

  @override
  void didUpdateWidget(covariant BannerAdBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showAds && !oldWidget.showAds) {
      _load();
    } else if (!widget.showAds && oldWidget.showAds) {
      _ad?.dispose();
      _ad = null;
      if (mounted) setState(() => _loaded = false);
    }
  }

  void _load() {
    final ad = BannerAd(
      adUnitId: MonetizationIds.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _loaded = false);
          // The box itself stays put (placeholder text); retry shortly
          // rather than leaving a dead space or removing the container.
          Future.delayed(const Duration(seconds: 30), () {
            if (mounted && widget.showAds && !_loaded) _load();
          });
        },
      ),
    );
    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showAds) return const SizedBox.shrink();
    final ad = _ad;
    return Container(
      key: const Key('banner_ad_bar'),
      width: double.infinity,
      height: BannerAdBar.height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xff1c130d),
        border: Border.all(color: const Color(0xff8a6a4a), width: 1.5),
      ),
      child: _loaded && ad != null
          ? SizedBox(
              width: ad.size.width.toDouble(),
              height: ad.size.height.toDouble(),
              child: AdWidget(ad: ad),
            )
          : const Text(
              'Dot Commander needs ad support',
              key: Key('banner_ad_placeholder'),
              style: TextStyle(color: Color(0xffcaa87a), fontSize: 12),
            ),
    );
  }
}
