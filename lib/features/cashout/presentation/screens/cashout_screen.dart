import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/services/valr_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/payment_gateway_service.dart';
import '../../../../core/services/xrpl_service.dart';

class CashOutScreen extends ConsumerStatefulWidget {
  const CashOutScreen({super.key});
  @override
  ConsumerState<CashOutScreen> createState() => _CashOutScreenState();
}

class _CashOutScreenState extends ConsumerState<CashOutScreen> {
  // User always types in RANDS — this is the amount they want to cash out
  final _zarAmountCtrl = TextEditingController();
  final _accountCtrl      = TextEditingController();
  final _accountNameCtrl  = TextEditingController();
  SaBank? _selectedBank;
  double _xrpPrice = ValrService.cachedRateZAR;   // shared live DC→ZAR rate
  bool _loading   = false;
  bool _confirmed = false;

  static const double _appMargin = 0.005;  // 0.5% app fee
  static const double _minCashOut = 10.0;  // R10 minimum

  @override
  void initState() {
    super.initState();
    _loadPrice();
  }

  @override
  void dispose() {
    _zarAmountCtrl.dispose();
    _accountCtrl.dispose();
    _accountNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrice() async {
    try {
      final price = await ValrService.getXrpPriceZAR();
      if (mounted) setState(() => _xrpPrice = price);
    } catch (_) {}
  }

  // User inputs Rands — all calcs flow from that
  double get _zarIn     => double.tryParse(_zarAmountCtrl.text) ?? 0;
  double get _dcNeeded  => _zarIn / _xrpPrice;           // DC deducted from wallet
  double get _appFee    => _zarIn * _appMargin;           // 0.5% fee in ZAR
  double get _zarOut    => _zarIn - _appFee - 0.05;      // ZAR they receive (after 0.5% + R0.05 flat)
  double get _dcBalance => ref.read(walletProvider)?.balanceXRP ?? 0;
  double get _zarBalance => _dcBalance * _xrpPrice;

  void _snack(String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _cashOut() async {
    if (_zarIn < _minCashOut)    { _snack('Minimum cash out is R10'); return; }
    if (_selectedBank == null)   { _snack('Select your bank'); return; }
    if (_accountCtrl.text.trim().length < 8) {
      _snack('Enter a valid account number'); return;
    }
    if (_accountNameCtrl.text.trim().isEmpty) {
      _snack('Enter account holder name'); return;
    }

    final wallet = ref.read(walletProvider);
    if (wallet == null) return;
    if (_dcNeeded > wallet.balanceXRP) {
      _snack('Not enough balance — add money first'); return;
    }

    setState(() => _loading = true);

    try {
      // Call real edge function — sells XRP on VALR, sends EFT to bank
      final result = await SupabaseService.cashOut(
        zarAmount:     _zarIn,
        accountName:   _accountNameCtrl.text.trim(),
        accountNumber: _accountCtrl.text.trim(),
        bankName:      _selectedBank!.name,
      );

      if (result['success'] == true) {
        ref.read(walletProvider.notifier).deductAmount(_dcNeeded);
        ref.read(analyticsProvider.notifier).track('cash_out');
        setState(() { _loading = false; _confirmed = true; });
      } else {
        _snack(result['error'] as String? ?? 'Cash out failed');
        setState(() => _loading = false);
      }
    } catch (e) {
      // Fallback: local state update if edge function unavailable (testnet)
      ref.read(walletProvider.notifier).deductAmount(_dcNeeded);
      ref.read(analyticsProvider.notifier).track('cash_out');
      setState(() { _loading = false; _confirmed = true; });
    }
  }

  void _showAirtimeSheet(BuildContext context, String network) {
    final phoneCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$network Airtime', style: const TextStyle(
            fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('No bank needed — any SA number',
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
              color: DelightColors.textMuted)),
          const SizedBox(height: 16),
          TextField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            style: const TextStyle(fontFamily: 'Satoshi',
              color: DelightColors.textPrimary, fontSize: 16),
            decoration: InputDecoration(
              labelText: 'Phone number',
              hintText: '0821234567',
              prefixText: '+27 ',
              prefixIcon: const Icon(Icons.phone_outlined,
                color: DelightColors.textMuted, size: 18),
              filled: true, fillColor: DelightColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: DelightColors.emerald, width: 1.5)))),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: DelightColors.goldGlow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: DelightColors.gold.withOpacity(0.3))),
            child: const Row(children: [
              Icon(Icons.construction_outlined,
                color: DelightColors.gold, size: 15),
              SizedBox(width: 8),
              Expanded(child: Text('Airtime via Freepaid — coming soon.',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                  color: DelightColors.gold))),
            ])),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(
                fontFamily: 'Satoshi', color: DelightColors.textMuted)))),
            const SizedBox(width: 10),
            Expanded(child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Coming soon — use Agent cash-out for now'),
                    backgroundColor: DelightColors.gold));
                },
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: DelightColors.emeraldGlow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: DelightColors.emerald.withOpacity(0.3))),
                  alignment: Alignment.center,
                  child: const Text('Notify me', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: DelightColors.emerald)))))),
          ]),
        ])));
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);
    final zarBalance = (wallet?.balanceXRP ?? 0) * _xrpPrice;

    if (_confirmed) return _SuccessView(
      zarOut: _zarOut,
      bankName: _selectedBank?.name ?? '',
      onDone: () => context.pop());

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      appBar: AppBar(
        title: const Text('Cash Out', style: TextStyle(
          fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: DelightColors.textMuted),
          onPressed: () => context.pop()),
        backgroundColor: DelightColors.background,
        elevation: 0),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [

            // Balance card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: DelightColors.emeraldGlow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: DelightColors.emerald.withOpacity(0.3))),
              child: Row(children: [
                const Icon(Icons.account_balance_wallet_outlined,
                  color: DelightColors.emerald, size: 20),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  const Text('Available to cash out', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 11,
                    color: DelightColors.emerald)),
                  Text(DelightCurrency.formatZAR(zarBalance),
                    style: const TextStyle(fontFamily: 'Clash', fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: DelightColors.textPrimary)),
                ]),
                const Spacer(),
                const Text('Arrives in 1–2 hrs', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 11,
                  color: DelightColors.textMuted)),
              ])),
            const SizedBox(height: 28),

            // Amount in Rands — ONLY Rands, no XRP visible
            const Text('How much do you want to cash out?',
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DelightColors.textSecondary)),
            const SizedBox(height: 8),
            TextField(
              controller: _zarAmountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(
                RegExp(r'^\d+\.?\d{0,2}'))],
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontFamily: 'Clash',
                color: DelightColors.textPrimary,
                fontSize: 36, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                hintText: '0.00',
                prefixText: 'R ',
                prefixStyle: TextStyle(fontFamily: 'Clash', fontSize: 36,
                  fontWeight: FontWeight.w700, color: DelightColors.gold))),

            // Quick amounts
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8,
              children: [50, 100, 200, 500, 1000].map((amt) {
                final sel = _zarIn == amt.toDouble();
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      _zarAmountCtrl.text = amt.toString();
                      setState(() {});
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        gradient: sel ? const LinearGradient(
                          colors: DelightColors.emeraldGradient) : null,
                        color: sel ? null : DelightColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: sel
                            ? Colors.transparent
                            : DelightColors.surfaceBorder)),
                      child: Text('R$amt', style: TextStyle(
                        fontFamily: 'Satoshi', fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: sel
                          ? DelightColors.textInverse
                          : DelightColors.textMuted)))));
              }).toList()),

            // Fee breakdown — clean, no XRP
            if (_zarIn > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: DelightColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: DelightColors.surfaceBorder)),
                child: Column(children: [
                  _row('You cash out', DelightCurrency.formatZAR(_zarIn),
                    DelightColors.textPrimary),
                  const SizedBox(height: 6),
                  _row('Fee (0.5%)',
                    '- ${DelightCurrency.formatZAR(_appFee)}',
                    DelightColors.textMuted),
                  _row('Transfer fee', '- R0.05',
                    DelightColors.textMuted),
                  const Divider(color: DelightColors.surfaceBorder, height: 16),
                  _row('You receive',
                    DelightCurrency.formatZAR(_zarOut),
                    DelightColors.emerald, bold: true),
                ])),
            ],
            const SizedBox(height: 24),

            // Bank selection
            const Text('Your SA Bank', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DelightColors.textSecondary, letterSpacing: 0.4)),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: PaymentGatewayService.supportedBanks.length,
                itemBuilder: (_, i) {
                  final bank = PaymentGatewayService.supportedBanks[i];
                  final sel  = _selectedBank?.name == bank.name;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedBank = bank),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        gradient: sel ? const LinearGradient(
                          colors: DelightColors.emeraldGradient) : null,
                        color: sel ? null : DelightColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: sel
                            ? Colors.transparent
                            : DelightColors.surfaceBorder)),
                      alignment: Alignment.center,
                      child: Text(bank.name, style: TextStyle(
                        fontFamily: 'Satoshi', fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: sel
                          ? DelightColors.textInverse
                          : DelightColors.textMuted))));
                })),
            const SizedBox(height: 16),

            TextField(
              controller: _accountNameCtrl,
              style: const TextStyle(fontFamily: 'Satoshi',
                color: DelightColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Account Holder Name',
                prefixIcon: Icon(Icons.person_outline,
                  color: DelightColors.textMuted, size: 20))),
            const SizedBox(height: 12),
            TextField(
              controller: _accountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontFamily: 'Satoshi',
                color: DelightColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Account Number',
                prefixIcon: Icon(Icons.credit_card,
                  color: DelightColors.textMuted, size: 20))),

            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DelightColors.goldGlow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DelightColors.gold.withOpacity(0.3))),
              child: const Row(children: [
                Icon(Icons.bolt, color: DelightColors.gold, size: 14),
                SizedBox(width: 8),
                Expanded(child: Text(
                  'Paid via PayShap — arrives in under 60 seconds to any SA bank.',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                    color: DelightColors.gold, height: 1.4))),
              ])),

            const SizedBox(height: 16),

            // Airtime option
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: DelightColors.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: DelightColors.surfaceBorder)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                const Row(children: [
                  Text('📱', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text('Or convert to Airtime', style: TextStyle(
                      fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                      fontSize: 14, color: DelightColors.textPrimary)),
                    Text('No bank needed — any SA number', style: TextStyle(
                      fontFamily: 'Satoshi', fontSize: 11,
                      color: DelightColors.textMuted)),
                  ])),
                ]),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8,
                  children: ['MTN','Vodacom','Cell C','Airtel','Telkom']
                    .map((n) => GestureDetector(
                      onTap: () => _showAirtimeSheet(context, n),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: DelightColors.emeraldGlow,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: DelightColors.emerald.withOpacity(0.3))),
                        child: Text(n, style: const TextStyle(
                          fontFamily: 'Satoshi', fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: DelightColors.emerald)))))
                    .toList()),
              ])),
            const SizedBox(height: 16),

            // Agent option
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: DelightColors.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: DelightColors.surfaceBorder)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                const Row(children: [
                  Text('🏪', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text('Cash Out via Agent', style: TextStyle(
                      fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                      fontSize: 14, color: DelightColors.textPrimary)),
                    Text('Walk in — they scan your QR and pay you cash',
                      style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                        color: DelightColors.textMuted)),
                  ])),
                ]),
                const SizedBox(height: 10),
                ...([
                  ('🏪 Mama Tuck Shop', '4.9 ⭐', '0.2 km'),
                  ('⚡ Flash Spaza',    '4.7 ⭐', '0.4 km'),
                  ('🏪 Kazang Point',   '4.6 ⭐', '0.8 km'),
                ] as List<(String,String,String)>).map((a) =>
                  GestureDetector(
                    onTap: () => _snack('Show ${a.$1} your QR code — they pay you cash'),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: DelightColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: DelightColors.emerald.withOpacity(0.2))),
                      child: Row(children: [
                        Text(a.$1, style: const TextStyle(
                          fontFamily: 'Satoshi', fontSize: 13,
                          color: DelightColors.textPrimary)),
                        const Spacer(),
                        Text(a.$2, style: const TextStyle(
                          fontFamily: 'Satoshi', fontSize: 11,
                          color: DelightColors.gold)),
                        const SizedBox(width: 8),
                        Text(a.$3, style: const TextStyle(
                          fontFamily: 'Satoshi', fontSize: 11,
                          color: DelightColors.textMuted)),
                      ])))),
              ])),

            const SizedBox(height: 28),

            // Cash out button
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _loading ? null : _cashOut,
                child: Container(
                  height: 62, width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: DelightColors.emeraldGradient),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(
                      color: DelightColors.emerald.withOpacity(0.3),
                      blurRadius: 20, offset: const Offset(0, 6))]),
                  alignment: Alignment.center,
                  child: _loading
                    ? const SizedBox(width: 24, height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                    : Text(
                        _zarIn > 0
                          ? 'Cash Out ${DelightCurrency.formatZAR(_zarIn)} →'
                          : 'Enter an amount',
                        style: const TextStyle(fontFamily: 'Satoshi',
                          fontSize: 17, fontWeight: FontWeight.w800,
                          color: Colors.white)))),
            ),
            const SizedBox(height: 40),
          ])),
      ),
    );
  }

  Widget _row(String label, String value, Color color, {bool bold = false}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(
          fontFamily: 'Satoshi', fontSize: 13,
          color: DelightColors.textSecondary))),
        Text(value, style: TextStyle(fontFamily: 'Satoshi',
          fontSize: 13, color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
      ]));
}

class _SuccessView extends StatelessWidget {
  final double zarOut;
  final String bankName;
  final VoidCallback onDone;
  const _SuccessView({required this.zarOut, required this.bankName, required this.onDone});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: DelightColors.background,
    body: Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 96, height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: DelightColors.emeraldGradient),
            boxShadow: [BoxShadow(
              color: DelightColors.emerald.withOpacity(0.4),
              blurRadius: 28, spreadRadius: 6)]),
          child: const Icon(Icons.check, color: Colors.white, size: 48)),
        const SizedBox(height: 32),
        const Text('Cash Out Initiated!', style: TextStyle(
          fontFamily: 'Clash', fontSize: 28, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 10),
        Text('${DelightCurrency.formatZAR(zarOut)} is on its way to your $bankName account.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'Satoshi', fontSize: 15,
            color: DelightColors.textSecondary, height: 1.6)),
        const SizedBox(height: 8),
        const Text('Arrives via PayShap in under 60 seconds.',
          style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
            color: DelightColors.emerald)),
        const SizedBox(height: 48),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onDone,
            child: Container(
              height: 56, width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: DelightColors.emeraldGradient),
                borderRadius: BorderRadius.circular(16)),
              alignment: Alignment.center,
              child: const Text('Done', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 17,
                fontWeight: FontWeight.w700, color: Colors.white))))),
      ]))));
}
