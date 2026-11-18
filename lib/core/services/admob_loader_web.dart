// lib/core/services/admob_loader_web.dart
// Web stub — AdMob SDK is mobile-only. All no-ops.
import 'package:flutter/material.dart';

class AdMobLoader {
  static Future<void> initialize() async {}

  static Future<Object?> loadNativeAd({
    required String adUnitId,
    required VoidCallback onLoaded,
    required VoidCallback onFailed,
  }) async => null;

  static void disposeAd(Object? ad) {}

  static Widget buildAdWidget(Object ad) => const SizedBox.shrink();
}
