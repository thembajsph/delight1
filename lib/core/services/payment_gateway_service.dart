// lib/core/services/payment_gateway_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// SA Payment Gateways:
//   • Ozow  — SA Instant EFT (all major banks, *120# USSD compatible)
//   • MoonPay — Easy ZAR→XRP widget (handles KYC, great for MVP)
//   • PayShap — via Stitch Money API
//
// USER FLOW:
//   1. User enters ZAR amount in app
//   2. App calls your backend: POST /topup/initiate
//   3. Backend creates Ozow/MoonPay payment URL
//   4. App opens URL in WebView (flutter_inappwebview)
//   5. User pays via their bank (or *120# USSD then confirms in app)
//   6. Gateway fires webhook to your backend
//   7. Backend buys DC on VALR
//   8. Backend sends DC to user wallet on XRPL
//   9. Backend sends push notification: "R200 → 21.0 DC credited"
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../config/env.dart';

class PaymentGatewayService {
  // ── MoonPay (MVP — handles everything) ───────────────────────────────────

  /// Generates a MoonPay widget URL for ZAR → DC conversion.
  /// MoonPay handles: KYC, ZAR payment, DC delivery to wallet.
  /// Open this URL in flutter_inappwebview.
  static String buildMoonPayUrl({
    required String walletAddress,
    required double zarAmount,
    String? email,
  }) {
    final params = {
      'apiKey': Env.moonPayPublishableKey,
      'currencyCode': 'xrp',
      'baseCurrencyCode': 'zar',
      'baseCurrencyAmount': zarAmount.toStringAsFixed(2),
      'walletAddress': walletAddress,
      'colorCode': '%2300C96A',        // Delight emerald
      'theme': 'dark',
      'language': 'en',
      if (email != null) 'email': email,
      'redirectURL': '${Env.apiBaseUrl}/moonpay/callback',
    };

    final queryString = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return '${Env.moonPayBaseUrl}?$queryString';
  }

  // ── Ozow (Production — lower fees, all SA banks) ─────────────────────────

  /// Generates a signed Ozow payment URL.
  /// This should be called on your BACKEND to keep the private key safe.
  /// Included here to show the Flutter side how to receive and use the URL.
  ///
  /// BACKEND code (Node.js) to generate this URL:
  /// ```javascript
  /// const crypto = require('crypto');
  /// function generateOzowUrl(userId, zarAmount) {
  ///   const ref = `DELIGHT_${userId}_${Date.now()}`;
  ///   const params = {
  ///     SiteCode: process.env.OZOW_SITE_CODE,
  ///     CountryCode: 'ZA',
  ///     CurrencyCode: 'ZAR',
  ///     Amount: zarAmount.toFixed(2),
  ///     TransactionReference: ref,
  ///     BankReference: 'Delight Top Up',
  ///     Optional1: userId,
  ///     NotifyUrl: 'https://api.delight.africa/webhooks/ozow',
  ///     SuccessUrl: 'https://api.delight.africa/topup/success',
  ///     ErrorUrl: 'https://api.delight.africa/topup/error',
  ///     CancelUrl: 'https://api.delight.africa/topup/cancel',
  ///     IsTest: false,
  ///   };
  ///   const hashStr = Object.values(params).join('').toLowerCase()
  ///     + process.env.OZOW_PRIVATE_KEY.toLowerCase();
  ///   params.HashCheck = crypto.createHash('sha512').update(hashStr).digest('hex');
  ///   return `https://pay.ozow.com/?${new URLSearchParams(params)}`;
  /// }
  /// ```

  /// Flutter calls backend to get payment URL
  static Future<OzowPaymentSession> initiateTopUp({
    required String userId,
    required double zarAmount,
    required String authToken,
  }) async {
    final response = await http.post(
      Uri.parse('${Env.apiBaseUrl}/wallet/topup/initiate'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode({
        'amount_zar': zarAmount,
        'user_id': userId,
        'gateway': 'ozow',
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw PaymentException(
        'Failed to initiate payment: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    return OzowPaymentSession(
      paymentUrl: data['payment_url'] as String,
      transactionRef: data['transaction_ref'] as String,
      expiresAt: DateTime.parse(data['expires_at'] as String),
    );
  }

  // ── PayShap (via Stitch) ─────────────────────────────────────────────────

  /// PayShap payment using Stitch API.
  /// Users pay via their banking app's PayShap option,
  /// or via USSD (*120#) which generates a PayShap payment.
  ///
  /// Your Delight ShapID: e.g. delight@fnb or 0812345678@capitec
  /// Register your ShapID at your business bank account.
  static Future<PayShapSession> initiatePayShap({
    required String userId,
    required double zarAmount,
    required String authToken,
  }) async {
    final response = await http.post(
      Uri.parse('${Env.apiBaseUrl}/wallet/topup/initiate'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode({
        'amount_zar': zarAmount,
        'user_id': userId,
        'gateway': 'payshap',
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw PaymentException('PayShap init failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    return PayShapSession(
      paymentUrl: data['payment_url'] as String,
      shapId: data['shap_id'] as String,          // e.g. delight@fnb
      reference: data['reference'] as String,
      qrCodeData: data['qr_code'] as String?,
    );
  }

  // ── Cash Out (XRP → ZAR → SA Bank) ──────────────────────────────────────

  /// Initiates a cash-out: user's DC sold on VALR → ZAR → SA bank via PayShap
  static Future<CashOutResult> initiateCashOut({
    required String userId,
    required double xrpAmount,
    required String bankAccountNumber,
    required String bankName,
    required String authToken,
  }) async {
    final response = await http.post(
      Uri.parse('${Env.apiBaseUrl}/wallet/cashout'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode({
        'xrp_amount': xrpAmount,
        'bank_account': bankAccountNumber,
        'bank_name': bankName,
        'user_id': userId,
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw PaymentException('Cash out failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    return CashOutResult(
      zarAmount: double.parse(data['zar_amount'].toString()),
      estimatedArrival: data['estimated_arrival'] as String,
      transactionId: data['transaction_id'] as String,
    );
  }

  // ── Supported SA Banks ────────────────────────────────────────────────────

  static const supportedBanks = [
    SaBank(name: 'FNB', ussdCode: '*120*321#', branchCode: '250655'),
    SaBank(name: 'Standard Bank', ussdCode: '*120*2345#', branchCode: '051001'),
    SaBank(name: 'ABSA', ussdCode: '*120*2272#', branchCode: '632005'),
    SaBank(name: 'Nedbank', ussdCode: '*120*001#', branchCode: '198765'),
    SaBank(name: 'Capitec', ussdCode: '*120*3279#', branchCode: '470010'),
    SaBank(name: 'TymeBank', ussdCode: '*120*33#', branchCode: '678910'),
    SaBank(name: 'African Bank', ussdCode: '*120*225#', branchCode: '430000'),
    SaBank(name: 'Discovery Bank', ussdCode: '*120*3279#', branchCode: '679000'),
    SaBank(name: 'Investec', ussdCode: '', branchCode: '580105'),
  ];
}

// ── Models ────────────────────────────────────────────────────────────────────

class OzowPaymentSession {
  final String paymentUrl;
  final String transactionRef;
  final DateTime expiresAt;
  const OzowPaymentSession({
    required this.paymentUrl,
    required this.transactionRef,
    required this.expiresAt,
  });
}

class PayShapSession {
  final String paymentUrl;
  final String shapId;
  final String reference;
  final String? qrCodeData;
  const PayShapSession({
    required this.paymentUrl,
    required this.shapId,
    required this.reference,
    this.qrCodeData,
  });
}

class CashOutResult {
  final double zarAmount;
  final String estimatedArrival;
  final String transactionId;
  const CashOutResult({
    required this.zarAmount,
    required this.estimatedArrival,
    required this.transactionId,
  });
}

class SaBank {
  final String name;
  final String ussdCode;
  final String branchCode;
  const SaBank({required this.name, required this.ussdCode, required this.branchCode});
}

class PaymentException implements Exception {
  final String message;
  const PaymentException(this.message);
  @override String toString() => 'PaymentException: $message';
}
