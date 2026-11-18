// lib/core/services/valr_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// VALR Exchange API — South African crypto exchange
// Used for: ZAR → DC (top-up) and DC → ZAR (cash out)
//
// Sign up: https://valr.com
// API docs: https://docs.valr.com
// FSCA registered — legal for SA operations
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../config/env.dart';

class ValrService {
  static const _baseUrl = Env.valrBaseUrl;
  static const _pair = 'XRPZAR';

  /// Single shared source of truth for the DC→ZAR rate.
  /// Every screen that shows a ZAR balance reads this same value,
  /// so Wallet and Cash Out never disagree on how much money you have.
  static double cachedRateZAR = 9.50;

  // ── Public Endpoints (no auth needed) ────────────────────────────────────

  /// Get live DC/ZAR market price from VALR
  static Future<ValrMarketSummary> getMarketSummary() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/v1/public/$_pair/marketsummary'),
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw ValrException('Failed to fetch market data: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ValrMarketSummary(
      lastPrice: double.parse(data['lastTradedPrice'] ?? '9.50'),
      bidPrice: double.parse(data['bidPrice'] ?? '9.48'),
      askPrice: double.parse(data['askPrice'] ?? '9.52'),
      high24h: double.parse(data['highPrice'] ?? '10.00'),
      low24h: double.parse(data['lowPrice'] ?? '9.00'),
      volume24h: double.parse(data['baseVolume'] ?? '0'),
      changePercent: double.tryParse(data['changeFromPrevious'] ?? '0') ?? 0,
    );
  }

  /// Get simple DC price in ZAR. Updates the shared cachedRateZAR so every
  /// screen (Wallet, Cash Out, transaction history) stays in sync.
  static Future<double> getXrpPriceZAR() async {
    try {
      final summary = await getMarketSummary();
      cachedRateZAR = summary.lastPrice;
      return summary.lastPrice;
    } catch (_) {
      return cachedRateZAR; // fallback to last known good rate
    }
  }

  /// Calculate how much DC you get for a ZAR amount
  static Future<ValrQuote> getTopUpQuote({
    required double zarAmount,
    required double platformFeePercent,
  }) async {
    final price = await getXrpPriceZAR();
    final zarAfterFees = zarAmount * (1 - platformFeePercent / 100);
    final xrpAmount = zarAfterFees / price;
    return ValrQuote(
      zarIn: zarAmount,
      xrpOut: xrpAmount,
      xrpPriceZAR: price,
      platformFeeZAR: zarAmount * (platformFeePercent / 100),
      exchangeFeeZAR: zarAfterFees * 0.001, // VALR 0.1% taker fee
    );
  }

  // ── Authenticated Endpoints ───────────────────────────────────────────────
  // NOTE: These are called from YOUR BACKEND (Node.js on Railway), not the app.
  // Your app calls your backend API, which calls VALR with your API keys.
  // NEVER put your VALR API secret in the Flutter app.

  /// Place a market buy order for DC using ZAR
  /// Called by your backend after Ozow confirms ZAR received
  ///
  /// Backend endpoint example (Node.js):
  /// POST /wallet/topup/callback (Ozow webhook)
  ///   → calls this to buy DC
  ///   → then sends DC to user wallet via XRPL
  static Map<String, dynamic> buildMarketBuyPayload({
    required double zarAmount,
    required String customerOrderId,
  }) {
    return {
      'side': 'BUY',
      'quoteAmount': zarAmount.toStringAsFixed(2),
      'pair': _pair,
      'postOnly': false,
      'customerOrderId': customerOrderId,
    };
  }

  /// Generate HMAC-SHA512 signature for VALR API auth
  /// Used in your Node.js backend
  static String generateSignature({
    required String apiSecret,
    required String timestamp,
    required String verb,
    required String path,
    String body = '',
  }) {
    final payload = '$timestamp$verb$path$body';
    final key = utf8.encode(apiSecret);
    final message = utf8.encode(payload);
    final hmac = Hmac(sha512, key);
    final digest = hmac.convert(message);
    return digest.toString();
  }

  // ── Estimated Returns Calculator ─────────────────────────────────────────

  /// Full fee breakdown for a ZAR top-up
  static TopUpBreakdown calculateTopUp({
    required double zarAmount,
    required double xrpPriceZAR,
    required double ozowFeePercent,   // typically 1.5%
  }) {
    final ozowFee = zarAmount * (ozowFeePercent / 100);
    final zarToExchange = zarAmount - ozowFee;
    final valrFee = zarToExchange * 0.001; // VALR 0.1%
    final zarBuying = zarToExchange - valrFee;
    final xrpReceived = zarBuying / xrpPriceZAR;

    return TopUpBreakdown(
      zarIn: zarAmount,
      ozowFeeZAR: ozowFee,
      valrFeeZAR: valrFee,
      xrpReceived: xrpReceived,
      effectiveRate: zarAmount / xrpReceived,
    );
  }
}

// ── Models ────────────────────────────────────────────────────────────────────

class ValrMarketSummary {
  final double lastPrice;
  final double bidPrice;
  final double askPrice;
  final double high24h;
  final double low24h;
  final double volume24h;
  final double changePercent;

  const ValrMarketSummary({
    required this.lastPrice,
    required this.bidPrice,
    required this.askPrice,
    required this.high24h,
    required this.low24h,
    required this.volume24h,
    required this.changePercent,
  });
}

class ValrQuote {
  final double zarIn;
  final double xrpOut;
  final double xrpPriceZAR;
  final double platformFeeZAR;
  final double exchangeFeeZAR;

  const ValrQuote({
    required this.zarIn,
    required this.xrpOut,
    required this.xrpPriceZAR,
    required this.platformFeeZAR,
    required this.exchangeFeeZAR,
  });
}

class TopUpBreakdown {
  final double zarIn;
  final double ozowFeeZAR;
  final double valrFeeZAR;
  final double xrpReceived;
  final double effectiveRate;

  const TopUpBreakdown({
    required this.zarIn,
    required this.ozowFeeZAR,
    required this.valrFeeZAR,
    required this.xrpReceived,
    required this.effectiveRate,
  });
}

class ValrException implements Exception {
  final String message;
  const ValrException(this.message);
  @override String toString() => 'ValrException: $message';
}
