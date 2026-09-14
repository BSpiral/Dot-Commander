import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'monetization_ids.dart';

/// The permanent ad strip: a fixed-height area, docked at the very top of
/// the screen (directly under the status bar, above the fleet selector).
/// It is always present during ad-supported play -- it never collapses or
/// disappears while an ad is loading, only failed/retrying -- so the
/// layout never jumps around. It shows placeholder text until a real
/// banner creative has loaded, then swaps in the live [AdWidget] in the
/// exact same spot. Formerly a bordered box further down the screen; the
/// decorative border was dropped when it moved to the top so it reads as
/// a normal top ad strip rather than a boxed-in panel wedged under the
/// status bar. Loading/retry/collapse behavior is unchanged.
///
/// The only time this strip goes away is when Remove Ads is owned
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

class _BannerAdBarState extends State<BannerAdBar> with WidgetsBindingObserver {
  BannerAd? _ad;
  bool _loaded = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Safety net for backgrounding while a load was in flight or a
    // failure's 30s retry timer was pending: the OS can suspend the
    // process while backgrounded, which may drop a pending Future.delayed
    // retry along with it, leaving the box stuck on the placeholder
    // indefinitely with nothing left to ever retry it. A resume that
    // still isn't showing a loaded ad (and has no load already in
    // flight) gets one fresh, immediate attempt -- diagnosed as a
    // plausible contributor during the time/progression repair pass,
    // not a confirmed root cause on its own.
    if (state == AppLifecycleState.resumed &&
        widget.showAds &&
        !_loaded &&
        !_loading) {
      _load();
    }
  }

  void _load() {
    if (_loading) return;
    _loading = true;
    final ad = BannerAd(
      adUnitId: MonetizationIds.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          _loading = false;
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          _loading = false;
          ad.dispose();
          if (mounted) setState(() => _loaded = false);
          // The box itself stays put (placeholder text); retry shortly
          // rather than leaving a dead space or removing the container.
          Future.delayed(const Duration(seconds: 30), () {
            if (mounted && widget.showAds && !_loaded && !_loading) _load();
          });
        },
      ),
    );
    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      color: const Color(0xff0b2330),
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
