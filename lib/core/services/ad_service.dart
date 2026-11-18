// lib/core/services/ad_service.dart
// Google AdMob Native Ad Service — web-safe implementation
// Native ads only show on Android/iOS. On web: completely invisible.

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// Conditionally import AdMob only on non-web platforms
import 'admob_loader.dart'
  if (dart.library.html) 'admob_loader_web.dart';

class AdService {
  // Google's official test IDs — safe to use during development
  static const testAppId      = 'ca-app-pub-3940256099942544~3347511713';
  static const testNativeAdId = 'ca-app-pub-3940256099942544/2247696110';

  // Your real IDs — replace after AdMob account approved
  // Format: ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX
  static const realNativeAdId = 'ca-app-pub-3940256099942544/2247696110'; // ← replace

  static String get nativeAdUnitId =>
    kDebugMode ? testNativeAdId : realNativeAdId;

  static bool get adsEnabled => !kIsWeb;

  static Future<void> initialize() async {
    if (!adsEnabled) return;
    await AdMobLoader.initialize();
  }
}

// ── Native Ad Card — looks like a Delight post ────────────────────────────────
class DelightNativeAdCard extends StatefulWidget {
  const DelightNativeAdCard({super.key});
  @override State<DelightNativeAdCard> createState() => _DelightNativeAdCardState();
}

class _DelightNativeAdCardState extends State<DelightNativeAdCard> {
  bool _loaded = false;
  Object? _ad; // holds NativeAd on mobile, null on web

  @override
  void initState() {
    super.initState();
    if (AdService.adsEnabled) _loadAd();
  }

  Future<void> _loadAd() async {
    final ad = await AdMobLoader.loadNativeAd(
      adUnitId: AdService.nativeAdUnitId,
      onLoaded: () { if (mounted) setState(() => _loaded = true); },
      onFailed: () { if (mounted) setState(() { _loaded = false; _ad = null; }); },
    );
    _ad = ad;
  }

  @override
  void dispose() {
    AdMobLoader.disposeAd(_ad);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Web or ad not loaded → invisible, zero height
    if (!AdService.adsEnabled || !_loaded || _ad == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Small "Sponsored" label — honest, not pushy
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: DelightColors.surfaceBorder,
              borderRadius: BorderRadius.circular(4)),
            child: const Text('Sponsored', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 9,
              fontWeight: FontWeight.w600,
              color: DelightColors.textMuted,
              letterSpacing: 0.5)))),
        // Native ad widget (height bounded)
        ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: double.infinity, minHeight: 80, maxHeight: 160),
          child: AdMobLoader.buildAdWidget(_ad!)),
      ]));
  }
}
