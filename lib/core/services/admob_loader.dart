// lib/core/services/admob_loader.dart
// Real AdMob implementation — used on Android and iOS
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../theme/app_theme.dart';

class AdMobLoader {
  static Future<void> initialize() async {
    await MobileAds.instance.initialize();
  }

  static Future<NativeAd?> loadNativeAd({
    required String adUnitId,
    required VoidCallback onLoaded,
    required VoidCallback onFailed,
  }) async {
    NativeAd? ad;
    ad = NativeAd(
      adUnitId: adUnitId,
      listener: NativeAdListener(
        onAdLoaded: (_) => onLoaded(),
        onAdFailedToLoad: (_, err) {
          debugPrint('AdMob native ad failed: $err');
          ad?.dispose();
          onFailed();
        },
      ),
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: DelightColors.surfaceHigh,
        cornerRadius: 14.0,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: DelightColors.emerald,
          style: NativeTemplateFontStyle.bold,
          size: 14.0),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: DelightColors.textPrimary,
          style: NativeTemplateFontStyle.bold,
          size: 14.0),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: DelightColors.textSecondary,
          style: NativeTemplateFontStyle.normal,
          size: 12.0),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: DelightColors.textMuted,
          style: NativeTemplateFontStyle.normal,
          size: 11.0)),
    )..load();
    return ad;
  }

  static void disposeAd(Object? ad) {
    if (ad is NativeAd) ad.dispose();
  }

  static Widget buildAdWidget(Object ad) {
    return AdWidget(ad: ad as NativeAd);
  }
}
