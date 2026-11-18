// lib/core/services/xrpl_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Real DC Ledger integration using xrpl_dart (^7.6.0)
//
// API usage here was verified directly against xrpl_dart 7.6.0's published
// pub.dev class documentation (XRPPrivateKey, XRPPublicKey, XRPClassicAddress,
// Payment, NFTokenMint, SubmittableTransaction) — fetched page by page, not
// guessed from search snippets. Confirmed signing flow:
//   1. toSigningBlobBytes(senderAddress) -> List<int>
//   2. wallet.sign(bytes) -> XRPLSignature
//   3. tx.setSignature(signature)
//   4. tx.toTransactionBlob() -> String to submit
//
// SECURITY NOTE: Before ANY mainnet use with real funds, an engineer must
// run this against XRPL Testnet and verify: (1) generateWallet() produces
// an address that's valid/fundable on testnet, (2) sendPayment() produces
// a transaction visible on a testnet explorer, (3) mintNFTTicket() produces
// a real NFToken visible via account_nfts. Treat "compiles" as a necessary
// but not sufficient condition — this needs a real signed-transaction test.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:xrpl_dart/xrpl_dart.dart';
import '../config/env.dart';

class XrplService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ── Wallet Generation ────────────────────────────────────────────────────

  /// Generates a real cryptographic XRPL keypair. The private key never
  /// leaves the device — only the public address is returned to callers.
  static Future<WalletResult> generateWallet() async {
    final wallet = XRPPrivateKey.random();
    final address = wallet.getPublic().toClassicAddress().address;
    final privateKeyHex = wallet.toHex();

    await _storage.write(key: 'xrp_pk_$address', value: privateKeyHex);

    return WalletResult(address: address);
  }

  /// Import an existing wallet using its secret key (as hex).
  static Future<WalletResult> importWallet(String secretKey) async {
    final wallet = XRPPrivateKey.fromHex(secretKey);
    final address = wallet.getPublic().toClassicAddress().address;

    await _storage.write(key: 'xrp_pk_$address', value: secretKey);
    return WalletResult(address: address);
  }

  // ── Balance ──────────────────────────────────────────────────────────────

  static Future<double> getBalance(String address) async {
    try {
      final response = await http.post(
        Uri.parse(Env.xrplRpcEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'method': 'account_info',
          'params': [{
            'account': address,
            'ledger_index': 'current',
            'strict': true,
          }],
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (data['result']?['status'] == 'error') {
        return 0.0; // Account not yet funded/activated
      }

      final drops = data['result']['account_data']['Balance'] as String;
      return double.parse(drops) / 1000000;
    } catch (e) {
      throw XrplException('Failed to fetch balance: $e');
    }
  }

  static Future<int> _getSequence(String address) async {
    final response = await http.post(
      Uri.parse(Env.xrplRpcEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'method': 'account_info',
        'params': [{'account': address, 'ledger_index': 'current'}],
      }),
    ).timeout(const Duration(seconds: 10));

    final data = jsonDecode(response.body);
    if (data['result']?['status'] == 'error') {
      throw XrplException('Account not found or not funded');
    }
    return data['result']['account_data']['Sequence'] as int;
  }

  static Future<Map<String, dynamic>> _submitBlob(String txBlob) async {
    final response = await http.post(
      Uri.parse(Env.xrplRpcEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'method': 'submit',
        'params': [{'tx_blob': txBlob}],
      }),
    ).timeout(const Duration(seconds: 15));

    final data = jsonDecode(response.body);
    final result = data['result'];
    final engineResult = result?['engine_result'] as String?;

    if (engineResult == null || !engineResult.startsWith('tes')) {
      throw XrplException(
        'Transaction failed: ${result?['engine_result_message'] ?? engineResult ?? 'unknown error'}');
    }
    return result as Map<String, dynamic>;
  }

  // ── Send Payment ─────────────────────────────────────────────────────────

  static Future<String> sendPayment({
    required String fromAddress,
    required String toAddress,
    required double amountXRP,
    String? memo,
  }) async {
    if (!isValidAddress(toAddress)) {
      throw XrplException('Invalid destination address');
    }
    if (amountXRP < 0.000001) {
      throw XrplException('Amount too small');
    }

    final privateKeyHex = await _storage.read(key: 'xrp_pk_$fromAddress');
    if (privateKeyHex == null) throw XrplException('Wallet key not found on device');

    final wallet = XRPPrivateKey.fromHex(privateKeyHex);
    final senderAddress = wallet.getPublic().toClassicAddress();
    final sequence = await _getSequence(fromAddress);

    final payment = Payment(
      account: fromAddress,
      destination: toAddress,
      amount: XRPAmount(BigInt.from((amountXRP * 1000000).round())),
      sequence: sequence,
      fee: BigInt.from(12),
      memos: memo != null && memo.isNotEmpty
        ? [XRPLMemo(memoData: memo.codeUnits
            .map((c) => c.toRadixString(16).padLeft(2, '0')).join().toUpperCase())]
        : null,
    );

    final signingBlobBytes = payment.toSigningBlobBytes(senderAddress);
    final signature = wallet.sign(signingBlobBytes);
    payment.setSignature(signature);

    final finalBlob = payment.toTransactionBlob();
    final result = await _submitBlob(finalBlob);

    return result['tx_json']?['hash'] as String? ?? payment.getHash();
  }

  // ── NFT Ticket Minting ───────────────────────────────────────────────────

  /// Mints an NFT ticket on the DC Ledger using NFTokenMint.
  /// transferFee = 300 means 3% royalty on all resales (1/10 basis points).
  static Future<String> mintNFTTicket({
    required String organizerAddress,
    required String eventId,
    required String tierId,
    required String metadataUrl,
  }) async {
    final privateKeyHex = await _storage.read(key: 'xrp_pk_$organizerAddress');
    if (privateKeyHex == null) throw XrplException('Organizer key not found');

    final wallet = XRPPrivateKey.fromHex(privateKeyHex);
    final senderAddress = wallet.getPublic().toClassicAddress();
    final sequence = await _getSequence(organizerAddress);

    final uriHex = metadataUrl.codeUnits
      .map((e) => e.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

    final mint = NFTokenMint(
      account: organizerAddress,
      sequence: sequence,
      fee: BigInt.from(12),
      nftokenTaxon: 1, // all Delight tickets share this taxon
      transferFee: 300, // 3% resale royalty
      uri: uriHex,
      flags: [NFTokenMintFlag.tfTransferable.value],
    );

    final signingBlobBytes = mint.toSigningBlobBytes(senderAddress);
    final signature = wallet.sign(signingBlobBytes);
    mint.setSignature(signature);

    final finalBlob = mint.toTransactionBlob();
    final result = await _submitBlob(finalBlob);

    return result['engine_result'] as String? ?? 'tesSUCCESS';
  }

  // ── Transaction History ──────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getTransactionHistory(
    String address, {int limit = 20}
  ) async {
    try {
      final response = await http.post(
        Uri.parse(Env.xrplRpcEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'method': 'account_tx',
          'params': [{'account': address, 'limit': limit, 'binary': false}],
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      final txList = data['result']['transactions'] as List? ?? [];
      return txList.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  // ── DC Price ────────────────────────────────────────────────────────────

  static Future<XrpPrice> fetchPrice() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.valr.com/v1/public/XRPZAR/marketsummary'),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final zarRate = double.tryParse(data['lastTradedPrice']?.toString() ?? '') ?? 9.50;

        double usdRate = 0.52;
        try {
          final usdResponse = await http.get(
            Uri.parse('https://api.valr.com/v1/public/XRPUSDT/marketsummary'),
          ).timeout(const Duration(seconds: 8));
          if (usdResponse.statusCode == 200) {
            final usdData = jsonDecode(usdResponse.body);
            usdRate = double.tryParse(usdData['lastTradedPrice']?.toString() ?? '') ?? 0.52;
          }
        } catch (_) {}

        return XrpPrice(zarRate: zarRate, usdRate: usdRate);
      }
    } catch (_) {}
    return const XrpPrice(zarRate: 9.50, usdRate: 0.52);
  }

  // ── Validation ───────────────────────────────────────────────────────────

  static bool isValidAddress(String address) {
    return RegExp(r'^r[1-9A-HJ-NP-Za-km-z]{24,34}$').hasMatch(address);
  }

  static String maskAddress(String address, {int visible = 4}) {
    if (address.length < 12) return address;
    return '${address.substring(0, visible + 1)}...${address.substring(address.length - visible)}';
  }
}

// ── Models ────────────────────────────────────────────────────────────────────

class WalletResult {
  final String address;
  const WalletResult({required this.address});
}

class XrpPrice {
  final double zarRate;
  final double usdRate;
  const XrpPrice({required this.zarRate, required this.usdRate});
}

class XrplException implements Exception {
  final String message;
  const XrplException(this.message);
  @override String toString() => 'XrplException: $message';
}

class DelightCurrency {
  static const String coinName    = 'Delight Coins';
  static const String coinSymbol  = 'DC';
  static const String coinEmoji   = '💚';

  static double _xrpPriceZAR = 9.50;
  static double get xrpPriceZAR => _xrpPriceZAR;
  static void updatePrice(double price) => _xrpPriceZAR = price;

  static String zarBalance(double dc) => formatZAR(dc * _xrpPriceZAR);

  static String formatZAR(double amount) {
    if (amount >= 1000000) return 'R${(amount/1000000).toStringAsFixed(2)}M';
    if (amount >= 1000) {
      final parts = amount.toStringAsFixed(2).split('.');
      final withCommas = parts[0].replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
      return 'R$withCommas.${parts[1]}';
    }
    return 'R${amount.toStringAsFixed(2)}';
  }

  static String txZAR(double dc) => formatZAR(dc * _xrpPriceZAR);
  static String feeZAR(double dc) => formatZAR(dc * _xrpPriceZAR);

  static String dcAmount(double amount) {
    if (amount == 0) return '0 $coinSymbol';
    if (amount >= 1000) return '${(amount/1000).toStringAsFixed(1)}K $coinSymbol';
    if (amount < 0.01) return '${amount.toStringAsFixed(4)} $coinSymbol';
    return '${amount.toStringAsFixed(2)} $coinSymbol';
  }

  static String exchangeRate() => '1 $coinSymbol = ${formatZAR(_xrpPriceZAR)}';
  static double zarToDC(double zar) => zar / _xrpPriceZAR;
  static double dcToZAR(double dc) => dc * _xrpPriceZAR;
}

class XrpFormatter {
  static String formatZAR(double amount) => DelightCurrency.formatZAR(amount);
  static String formatXRP(double amount, {int decimals = 2}) =>
      DelightCurrency.dcAmount(amount);
  static String formatUSD(double amount) => '\$${amount.toStringAsFixed(2)}';
  static String maskAddress(String address, {int visible = 4}) =>
      XrplService.maskAddress(address, visible: visible);
  static String transactionLabel(dynamic type) {
    final t = type.toString();
    if (t.contains('send'))    return 'Sent';
    if (t.contains('receive')) return 'Received';
    if (t.contains('ticket'))  return 'Ticket';
    if (t.contains('topup'))   return 'Money Added';
    if (t.contains('event'))   return 'Event Purchase';
    return 'Transaction';
  }
}

class FeeCalculator {
  static const double valrMakerRebate = 0.0005;
  static const double valrTakerFee    = 0.0010;
  static const double xrpNetworkFlat  = 0.05;

  static double fee(double amount, String type) {
    final rates = {
      'p2p':               0.005,
      'consumer_business': 0.010,
      'business_business': 0.010,
      'ticket':            0.030,
    };
    return amount * (rates[type] ?? 0.005);
  }

  static double net(double amount, String type) => amount - fee(amount, type);

  static double delightEarns(double amount, String type, {bool makerStrategy = true}) {
    return fee(amount, type);
  }

  static String feeLabel(String type) {
    final labels = {
      'p2p':               '0.5% — internal transfer, no conversion',
      'consumer_business': '1.0% — internal transfer, no conversion',
      'business_business': '1.0% — internal transfer',
      'ticket':            '3.0% + R0.05 NFT mint',
    };
    return labels[type] ?? '0.5%';
  }

  static String feePct(String type) {
    final pcts = {
      'p2p':               '0.5%',
      'consumer_business': '1.0%',
      'business_business': '1.0%',
      'ticket':            '1.5%',
    };
    return pcts[type] ?? '0.5%';
  }
}
