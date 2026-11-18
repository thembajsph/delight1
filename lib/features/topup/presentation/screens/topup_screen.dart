import 'package:flutter/material.dart';
import '../../../../core/services/location_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/services/xrpl_service.dart';
import '../../../../core/services/supabase_service.dart';

enum _Method { agent, voucher, ussd, eft }

// ─── Agent model ──────────────────────────────────────────────────────────────

class _Agent {
  final String id, name, address, distance, flag;
  final double rating;
  final int reviewCount, txCount;
  final double floatZAR;
  final bool isOpen, isVerified, isTopAgent, isHighFloat;
  final List<_Review> reviews;

  const _Agent({
    required this.id, required this.name, required this.address,
    required this.distance, required this.flag, required this.rating,
    required this.reviewCount, required this.txCount, required this.floatZAR,
    required this.isOpen, this.isVerified = false,
    this.isTopAgent = false, this.isHighFloat = false,
    this.reviews = const [],
  });
}

class _Review {
  final String user, text;
  final double rating;
  final String timeAgo;
  const _Review({required this.user, required this.text,
    required this.rating, required this.timeAgo});
}

// ─── Demo agents ──────────────────────────────────────────────────────────────

const _agents = [
  _Agent(
    id: 'a1', name: 'Mama Tuck Shop', flag: '🏪',
    address: '14 Khumalo Street, Soweto', distance: '0.2 km',
    rating: 4.9, reviewCount: 312, txCount: 2400, floatZAR: 3500,
    isOpen: true, isVerified: true, isTopAgent: true, isHighFloat: true,
    reviews: [
      _Review(user: 'Thabo M.', text: 'Always fast, never had a problem. Mama is very friendly!',
        rating: 5.0, timeAgo: '2 days ago'),
      _Review(user: 'Zanele K.', text: 'Super fast, money arrived instantly. Very reliable.',
        rating: 5.0, timeAgo: '5 days ago'),
      _Review(user: 'Sipho N.', text: 'Quick and reliable. Best agent in the area.',
        rating: 4.5, timeAgo: '1 week ago'),
    ]),
  _Agent(
    id: 'a2', name: 'Flash Spaza', flag: '⚡',
    address: 'Corner Zulu Ave & Dube St', distance: '0.4 km',
    rating: 4.7, reviewCount: 189, txCount: 1800, floatZAR: 2000,
    isOpen: true, isVerified: true, isTopAgent: false, isHighFloat: false,
    reviews: [
      _Review(user: 'Nomsa D.', text: 'Fast service, easy to find.',
        rating: 5.0, timeAgo: '1 day ago'),
      _Review(user: 'Kwame A.', text: 'Good but sometimes runs out of float on weekends.',
        rating: 4.0, timeAgo: '4 days ago'),
      _Review(user: 'Amara T.', text: 'Reliable agent, been using for 3 months.',
        rating: 5.0, timeAgo: '2 weeks ago'),
    ]),
  _Agent(
    id: 'a3', name: 'Kazang Point', flag: '🏬',
    address: 'Shoprite Foyer, Dube Plaza', distance: '0.8 km',
    rating: 4.6, reviewCount: 87, txCount: 920, floatZAR: 5000,
    isOpen: true, isVerified: true, isTopAgent: false, isHighFloat: true,
    reviews: [
      _Review(user: 'Fatima O.', text: 'Never had a problem, always sorted me out quickly.',
        rating: 5.0, timeAgo: '3 days ago'),
      _Review(user: 'Kofi M.', text: 'Inside Shoprite so safe and easy.',
        rating: 4.5, timeAgo: '1 week ago'),
      _Review(user: 'Nia K.', text: 'Good agent but queue can be long.',
        rating: 4.0, timeAgo: '2 weeks ago'),
    ]),
  _Agent(
    id: 'a4', name: 'OTT Vouchers — Pep', flag: '🎟',
    address: 'Pep Stores, Kliptown Mall', distance: '1.1 km',
    rating: 4.2, reviewCount: 43, txCount: 340, floatZAR: 1000,
    isOpen: false, isVerified: false, isTopAgent: false, isHighFloat: false,
    reviews: [
      _Review(user: 'Tunde B.', text: 'Closed early sometimes. Check hours first.',
        rating: 3.5, timeAgo: '5 days ago'),
      _Review(user: 'Zainab O.', text: 'Helpful staff when open.',
        rating: 4.5, timeAgo: '1 week ago'),
      _Review(user: 'David D.', text: 'Handles vouchers well, cash can be limited sometimes.',
        rating: 4.0, timeAgo: '3 weeks ago'),
    ]),
];

// ─── TopUp Screen ─────────────────────────────────────────────────────────────

class TopUpScreen extends ConsumerStatefulWidget {
  const TopUpScreen({super.key});
  @override
  ConsumerState<TopUpScreen> createState() => _TopUpScreenState();
}

class _TopUpScreenState extends ConsumerState<TopUpScreen> {
  _Method _method = _Method.agent;
  final _amountCtrl  = TextEditingController();
  final _voucherCtrl = TextEditingController();
  bool _loading = false;
  static const double _zarRate = 9.50;
  final _quickAmounts = [20.0, 50.0, 100.0, 200.0, 500.0];

  @override
  void dispose() {
    _amountCtrl.dispose();
    _voucherCtrl.dispose();
    super.dispose();
  }

  double get _amount  => double.tryParse(_amountCtrl.text) ?? 0;
  double get _dcValue => _amount / _zarRate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      appBar: AppBar(
        backgroundColor: DelightColors.background,
        title: const Text('Add Money', style: TextStyle(
          fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => context.pop())),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAmountSection(),
              const SizedBox(height: 28),
              _buildMethodSelector(),
              const SizedBox(height: 24),
              _buildMethodPanel(context),
              const SizedBox(height: 24),
              if (_method != _Method.agent && _method != _Method.ussd)
                _buildConfirmButton(context),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAmountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Add Money', style: TextStyle(
          fontFamily: 'Clash', fontSize: 22, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 4),
        Text(DelightCurrency.exchangeRate(), style: const TextStyle(
          fontFamily: 'Satoshi', fontSize: 12, color: DelightColors.textMuted)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: DelightColors.emeraldGlow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
          child: const Row(children: [
            Icon(Icons.bolt, color: DelightColors.emerald, size: 13),
            SizedBox(width: 6),
            Expanded(child: Text(
              'Deposit once — spend everywhere inside Delight at 0.5–1.5%. '
              'Only convert to ZAR when you need cash out.',
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                color: DelightColors.emerald, height: 1.4))),
          ])),
        const SizedBox(height: 14),
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontFamily: 'Clash', color: DelightColors.textPrimary,
            fontSize: 40, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(
            prefixText: 'R ',
            prefixStyle: TextStyle(fontFamily: 'Clash', fontSize: 40,
              fontWeight: FontWeight.w700, color: DelightColors.gold),
            hintText: '0',
            hintStyle: TextStyle(fontFamily: 'Clash', fontSize: 40,
              fontWeight: FontWeight.w700, color: DelightColors.textMuted),
            border: InputBorder.none)),
        if (_amount > 0) ...[
          const SizedBox(height: 4),
          Text('= ${DelightCurrency.dcAmount(_dcValue)} added to wallet',
            style: const TextStyle(fontFamily: 'Satoshi', fontSize: 14,
              color: DelightColors.emerald, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _quickAmounts.map((amt) {
            final sel = _amountCtrl.text == amt.toStringAsFixed(0);
            return GestureDetector(
              onTap: () { _amountCtrl.text = amt.toStringAsFixed(0); setState(() {}); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: sel ? const LinearGradient(colors: DelightColors.goldGradient) : null,
                  color: sel ? null : DelightColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? Colors.transparent : DelightColors.surfaceBorder)),
                child: Text('R${amt.toStringAsFixed(0)}', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 14, fontWeight: FontWeight.w700,
                  color: sel ? DelightColors.textInverse : DelightColors.textMuted))));
          }).toList()),
      ],
    );
  }

  Widget _buildMethodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('How do you want to pay?', style: TextStyle(
          fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('No bank account needed — cash works too',
          style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
            color: DelightColors.emerald)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: DelightColors.goldGlow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DelightColors.gold.withOpacity(0.25))),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text('💡', style: TextStyle(fontSize: 13)),
            SizedBox(width: 8),
            Expanded(child: Text(
              'Deposit once. Spend everything inside at 0.5–3%. '
              'Only cash out when you need it — that\'s when the conversion fee applies.',
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                color: DelightColors.gold, height: 1.45))),
          ])),
        const SizedBox(height: 14),
        _methodCard(_Method.agent,   '🏪', 'Cash at Agent',
          'Nearest spaza, tuck shop or garage', 'No bank needed', DelightColors.emerald),
        const SizedBox(height: 8),
        _methodCard(_Method.voucher, '🎟', 'Voucher Code',
          'Bluevoucher / OTT — buy at Shoprite, Pep, Checkers',
          'Coming soon', DelightColors.textMuted),
        const SizedBox(height: 8),
        _methodCard(_Method.ussd,    '📱', 'USSD *120*DELIGHT#',
          'No internet needed. Any phone, any network.', 'Any phone', DelightColors.gold),
        const SizedBox(height: 8),
        _methodCard(_Method.eft,     '🏦', 'Bank EFT',
          'FNB, Capitec, Standard Bank, ABSA, Nedbank…', 'Bank needed', DelightColors.textMuted),
      ],
    );
  }

  Widget _methodCard(_Method m, String icon, String title, String sub,
      String badge, Color badgeColor) {
    final sel = _method == m;
    return GestureDetector(
      onTap: () => setState(() => _method = m),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sel ? DelightColors.emeraldGlow : DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: sel ? DelightColors.emerald : DelightColors.surfaceBorder,
            width: sel ? 1.5 : 1)),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(
                fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary, fontSize: 14))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6)),
                child: Text(badge, style: TextStyle(fontFamily: 'Satoshi',
                  fontSize: 9, fontWeight: FontWeight.w700, color: badgeColor))),
            ]),
            const SizedBox(height: 3),
            Text(sub, style: const TextStyle(fontFamily: 'Satoshi',
              fontSize: 12, color: DelightColors.textMuted)),
          ])),
          const SizedBox(width: 8),
          Icon(sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: sel ? DelightColors.emerald : DelightColors.textMuted, size: 20),
        ])));
  }

  Widget _buildMethodPanel(BuildContext context) {
    switch (_method) {
      case _Method.agent:   return _AgentPanel(amount: _amount);
      case _Method.voucher: return _VoucherPanel(ctrl: _voucherCtrl);
      case _Method.ussd:    return _USSDPanel(amount: _amount);
      case _Method.eft:     return _EFTPanel(amount: _amount);
    }
  }

  Widget _buildConfirmButton(BuildContext context) {
    return GestureDetector(
      onTap: _amount < 5 ? null : () => _proceed(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 60, width: double.infinity,
        decoration: BoxDecoration(
          gradient: _amount >= 5
            ? const LinearGradient(colors: DelightColors.emeraldGradient) : null,
          color: _amount < 5 ? DelightColors.surfaceHigh : null,
          borderRadius: BorderRadius.circular(18),
          boxShadow: _amount >= 5 ? [BoxShadow(
            color: DelightColors.emerald.withOpacity(0.35),
            blurRadius: 20, offset: const Offset(0, 6))] : []),
        alignment: Alignment.center,
        child: _loading
          ? const SizedBox(width: 24, height: 24,
              child: CircularProgressIndicator(
                color: DelightColors.textInverse, strokeWidth: 2.5))
          : Text(
              _amount >= 5
                ? 'Add ${DelightCurrency.formatZAR(_amount)}'
                : 'Enter amount (min R5)',
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _amount >= 5 ? DelightColors.textInverse : DelightColors.textMuted))));
  }

  Future<void> _proceed(BuildContext context) async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 800));
    ref.read(walletProvider.notifier).addAmount(_dcValue);
    ref.read(analyticsProvider.notifier).track('topup');
    setState(() => _loading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${DelightCurrency.formatZAR(_amount)} added to your wallet!'),
        backgroundColor: DelightColors.emerald));
      context.pop();
    }
  }
}

// ─── Agent Panel — Uber-style trust system ────────────────────────────────────

class _AgentPanel extends StatelessWidget {
  final double amount;
  const _AgentPanel({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // How it works
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DelightColors.emeraldGlow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('How it works', style: TextStyle(
                fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                color: DelightColors.emerald, fontSize: 13)),
              const SizedBox(height: 8),
              ...['1. Choose the nearest open agent below',
                '2. Walk in and tell them you\'re topping up Delight',
                '3. Show them your QR code (below)',
                '4. Hand over your cash',
                '5. Money appears in your wallet instantly',
              ].map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(s, style: const TextStyle(fontFamily: 'Satoshi',
                  fontSize: 12, color: DelightColors.textSecondary)))),
              if (amount > 0) ...[
                const Divider(color: DelightColors.surfaceBorder, height: 16),
                Text('You will hand over: R${amount.toStringAsFixed(0)} cash',
                  style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                    fontWeight: FontWeight.w700, color: DelightColors.emerald)),
              ],
            ])),
        const SizedBox(height: 16),

        // User QR code
        Center(child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(
              color: DelightColors.emerald.withOpacity(0.2), blurRadius: 20)]),
          child: Column(children: [
            QrImageView(
              data: 'delight://pay/rDelightUserWallet?amount=topup',
              version: QrVersions.auto,
              size: 140,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF060F0A)),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF060F0A))),
            const SizedBox(height: 8),
            const Text('Show this QR to your agent',
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                color: Color(0xFF060F0A))),
          ]))),
        const SizedBox(height: 20),

        // Agent programme CTA
        GestureDetector(
          onTap: () => _showBecomeAgent(context),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                DelightColors.gold.withOpacity(0.12), DelightColors.background]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: DelightColors.gold.withOpacity(0.35))),
            child: Row(children: [
              const Text('💰', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Become a Delight Agent', style: TextStyle(
                    fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                    fontSize: 14, color: DelightColors.gold)),
                  const SizedBox(height: 3),
                  const Text(
                    'Basic 1% · Merchant 2% · Super Agent 0.5% on your network. '
                    'Start with R500 float.',
                    style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                      color: DelightColors.textMuted, height: 1.4)),
                ])),
              const Icon(Icons.chevron_right, color: DelightColors.gold, size: 18),
            ]))),
        const SizedBox(height: 16),

        // Agent list header
        Row(children: [
          const Expanded(child: Text('Nearest Agents', style: TextStyle(
            fontFamily: 'Clash', fontSize: 16, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: DelightColors.surfaceHigh,
              borderRadius: BorderRadius.circular(8)),
            child: Row(children: const [
              Icon(Icons.gps_fixed, color: DelightColors.emerald, size: 12),
              SizedBox(width: 4),
              Text('Using location', style: TextStyle(fontFamily: 'Satoshi',
                fontSize: 11, color: DelightColors.textMuted)),
            ])),
        ]),
        const SizedBox(height: 8),

        // Agent cards
        ..._agents.map((agent) => _AgentCard(agent: agent, amount: amount)),
      ],
    );
  }

  void _showBecomeAgent(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _BecomeAgentSheet());
  }
}

// ─── Agent Card — Uber-driver style ──────────────────────────────────────────

class _AgentCard extends StatelessWidget {
  final _Agent agent;
  final double amount;
  const _AgentCard({required this.agent, required this.amount});

  @override
  Widget build(BuildContext context) {
    // R20 minimum per transaction, always show agents
    final effectiveAmount = amount < 20 ? 20.0 : amount;
    final canHandle = agent.floatZAR >= effectiveAmount;
    final borderColor = !agent.isOpen
      ? DelightColors.surfaceBorder
      : canHandle
        ? DelightColors.emerald.withOpacity(0.35)
        : DelightColors.gold.withOpacity(0.35);

    return GestureDetector(
      onTap: () => _showAgentDetail(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor)),
        child: Column(
          children: [
            // Top row — name, distance, open/closed
            Row(children: [
              Text(agent.flag, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(agent.name, style: const TextStyle(
                      fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                      fontSize: 14, color: DelightColors.textPrimary))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: agent.isOpen
                          ? DelightColors.emeraldGlow : DelightColors.surfaceBorder,
                        borderRadius: BorderRadius.circular(6)),
                      child: Text(agent.isOpen ? 'Open' : 'Closed',
                        style: TextStyle(fontFamily: 'Satoshi', fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: agent.isOpen
                            ? DelightColors.emerald : DelightColors.textMuted))),
                  ]),
                  Text(agent.address, style: const TextStyle(
                    fontFamily: 'Satoshi', fontSize: 11,
                    color: DelightColors.textMuted)),
                ])),
              const SizedBox(width: 8),
              Text(agent.distance, style: const TextStyle(
                fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                fontSize: 13, color: DelightColors.textSecondary)),
            ]),
            const SizedBox(height: 10),

            // Stats row — stars, reviews, transactions
            Row(children: [
              // Star rating
              Row(children: [
                ..._buildStars(agent.rating),
                const SizedBox(width: 4),
                Text('${agent.rating}', style: const TextStyle(
                  fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                  fontSize: 12, color: DelightColors.textPrimary)),
                const SizedBox(width: 2),
                Text('(${_formatCount(agent.reviewCount)})',
                  style: const TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                    color: DelightColors.textMuted)),
              ]),
              const SizedBox(width: 12),
              // Transaction count
              Row(children: const [
                Icon(Icons.swap_horiz, size: 12, color: DelightColors.textMuted),
                SizedBox(width: 3),
              ]),
              Text(_formatCount(agent.txCount), style: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 11, color: DelightColors.textMuted)),
              const Text(' txns', style: TextStyle(fontFamily: 'Satoshi',
                fontSize: 11, color: DelightColors.textMuted)),
              const Spacer(),
              // Float
              Flexible(child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.account_balance_wallet_outlined,
                  size: 12, color: DelightColors.textMuted),
                const SizedBox(width: 3),
                Flexible(child: Text(
                  agent.floatZAR >= (amount > 0 ? amount : 50) ? '✅ Can handle your amount' : '⚠️ May not cover this amount',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                    color: canHandle || amount == 0
                      ? DelightColors.textMuted : DelightColors.error))),
              ])),
            ]),
            const SizedBox(height: 8),

            // Badges row
            Row(children: [
              Expanded(child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  if (agent.isVerified) _badge('✓ Verified', const Color(0xFF00C96A)),
                  if (agent.isTopAgent) ...[
                    const SizedBox(width: 6),
                    _badge('🏆 Top Agent', DelightColors.gold),
                  ],
                  if (agent.isHighFloat) ...[
                    const SizedBox(width: 6),
                    _badge('💰 High Float', DelightColors.blue),
                  ],
                  if (!canHandle && amount > 0) ...[
                    const SizedBox(width: 6),
                    _badge('⚠️ May not cover this amount',
                      DelightColors.error),
                  ],
                ]))),
              const SizedBox(width: 8),
              const Text('Tap for details →', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 10,
                color: DelightColors.textMuted)),
            ]),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStars(double rating) {
    final stars = <Widget>[];
    for (int i = 1; i <= 5; i++) {
      final filled = rating >= i;
      final half = !filled && rating >= i - 0.5;
      stars.add(Icon(
        half ? Icons.star_half : (filled ? Icons.star : Icons.star_border),
        color: DelightColors.gold, size: 14));
    }
    return stars;
  }

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.3))),
    child: Text(label, style: TextStyle(fontFamily: 'Satoshi', fontSize: 9,
      fontWeight: FontWeight.w700, color: color)));

  String _formatCount(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  void _showAgentDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: DelightColors.surfaceHigh,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: DelightColors.surfaceBorder,
                  borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),

              // Header
              Row(children: [
                Text(agent.flag, style: const TextStyle(fontSize: 36)),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Text(agent.name, style: const TextStyle(
                    fontFamily: 'Clash', fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: DelightColors.textPrimary)),
                  Text(agent.address, style: const TextStyle(
                    fontFamily: 'Satoshi', fontSize: 13,
                    color: DelightColors.textMuted)),
                ])),
              ]),
              const SizedBox(height: 16),

              // Badges
              Wrap(spacing: 8, runSpacing: 8, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: agent.isOpen
                      ? DelightColors.emeraldGlow : DelightColors.surfaceBorder,
                    borderRadius: BorderRadius.circular(8)),
                  child: Text(agent.isOpen ? '● Open Now' : '● Closed',
                    style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: agent.isOpen
                        ? DelightColors.emerald : DelightColors.textMuted))),
                if (agent.isVerified) _badge('✓ Verified', const Color(0xFF00C96A)),
                if (agent.isTopAgent) _badge('🏆 Top Agent', DelightColors.gold),
                if (agent.isHighFloat) _badge('💰 High Float', DelightColors.blue),
              ]),
              const SizedBox(height: 20),

              // Stats cards
              Row(children: [
                _statCard('${agent.rating}', '★ Rating', DelightColors.gold),
                const SizedBox(width: 8),
                _statCard(_formatCount(agent.reviewCount), 'Reviews', DelightColors.blue),
                const SizedBox(width: 8),
                _statCard(_formatCount(agent.txCount), 'Transactions', DelightColors.emerald),
                const SizedBox(width: 8),
                // Float amount hidden from consumer for security
              ]),
              const SizedBox(height: 24),

              // Distance
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: DelightColors.emeraldGlow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.directions_walk,
                    color: DelightColors.emerald, size: 20),
                  const SizedBox(width: 10),
                  Text('${agent.distance} away',
                    style: const TextStyle(fontFamily: 'Satoshi',
                      fontWeight: FontWeight.w700, fontSize: 14,
                      color: DelightColors.emerald)),
                  const Spacer(),
                  const Text('~3 min walk', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 12,
                    color: DelightColors.textMuted)),
                ])),
              const SizedBox(height: 20),

              // Reviews
              const Text('Recent Reviews', style: TextStyle(
                fontFamily: 'Clash', fontSize: 16, fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary)),
              const SizedBox(height: 10),
              ...agent.reviews.map((r) => _ReviewCard(review: r)),
              const SizedBox(height: 16),

              // Leave a review
              _LeaveReviewSection(agent: agent),
              const SizedBox(height: 16),

              // Actions
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Opening directions...')));
                  },
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: DelightColors.emeraldGradient),
                      borderRadius: BorderRadius.circular(14)),
                    alignment: Alignment.center,
                    child: Text('Go to ${agent.name}',
                      style: const TextStyle(fontFamily: 'Satoshi',
                        fontWeight: FontWeight.w700, fontSize: 14,
                        color: Colors.white))))),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => _reportAgent(context),
                  child: Container(
                    height: 52, width: 52,
                    decoration: BoxDecoration(
                      color: DelightColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: DelightColors.error.withOpacity(0.3))),
                    alignment: Alignment.center,
                    child: const Icon(Icons.flag_outlined,
                      color: DelightColors.error, size: 20))),
              ]),
              const SizedBox(height: 8),
              Center(child: TextButton(
                onPressed: () => _reportAgent(context),
                child: const Text('Report this agent',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                    color: DelightColors.error)))),
            ],
          ))));
  }

  Widget _statCard(String value, String label, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2))),
      child: Column(children: [
        Text(value, style: TextStyle(fontFamily: 'Clash', fontSize: 16,
          fontWeight: FontWeight.w700, color: color)),
        Text(label, style: const TextStyle(fontFamily: 'Satoshi',
          fontSize: 9, color: DelightColors.textMuted)),
      ])));
  }

  void _reportAgent(BuildContext context) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Report Agent', style: TextStyle(
            fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary)),
          const SizedBox(height: 8),
          const Text('Agents with multiple reports are automatically reviewed. '
            'This keeps the network safe for everyone.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
              color: DelightColors.textMuted, height: 1.4)),
          const SizedBox(height: 20),
          ...['Didn\'t credit my wallet',
            'Charged wrong amount',
            'Rude or unhelpful',
            'Closed but listed as open',
            'Suspicious behaviour',
            'Other',
          ].map((reason) => GestureDetector(
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Report submitted. We\'ll review ${agent.name} within 24h.')));
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: DelightColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DelightColors.surfaceBorder)),
              child: Row(children: [
                Expanded(child: Text(reason, style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 14,
                  color: DelightColors.textPrimary))),
                const Icon(Icons.chevron_right,
                  color: DelightColors.textMuted, size: 18),
              ])))),
        ])));
  }
}

// ─── Review card ──────────────────────────────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  final _Review review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DelightColors.emerald.withOpacity(0.1)),
              alignment: Alignment.center,
              child: Text(review.user[0], style: const TextStyle(
                fontFamily: 'Clash', fontWeight: FontWeight.w700,
                fontSize: 14, color: DelightColors.emerald))),
            const SizedBox(width: 8),
            Expanded(child: Text(review.user, style: const TextStyle(
              fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
              fontSize: 13, color: DelightColors.textPrimary))),
            Row(children: List.generate(5, (i) => Icon(
              i < review.rating.floor() ? Icons.star
                : (i < review.rating ? Icons.star_half : Icons.star_border),
              color: DelightColors.gold, size: 13))),
          ]),
          const SizedBox(height: 6),
          Text(review.text, style: const TextStyle(
            fontFamily: 'Satoshi', fontSize: 12,
            color: DelightColors.textSecondary, height: 1.4)),
          const SizedBox(height: 4),
          Text(review.timeAgo, style: const TextStyle(
            fontFamily: 'Satoshi', fontSize: 10,
            color: DelightColors.textMuted)),
        ],
      ),
    );
  }
}

// ─── Voucher panel ────────────────────────────────────────────────────────────

class _VoucherPanel extends StatefulWidget {
  final TextEditingController ctrl;
  const _VoucherPanel({required this.ctrl});
  @override State<_VoucherPanel> createState() => _VoucherPanelState();
}

class _VoucherPanelState extends State<_VoucherPanel> {
  // Which voucher brand is selected
  String _brand = '1Voucher';
  bool _redeeming = false;

  static const _brands = [
    (name: '1Voucher',     emoji: '🟠', color: Color(0xFFFF6B00),
     desc: 'Buy at any till — Shoprite, Pick n Pay, Checkers, USave, Spar'),
    (name: 'Bluevoucher',  emoji: '🔵', color: Color(0xFF0066CC),
     desc: 'Available at Pep, Shoprite, Boxer and 50,000+ retailers'),
    (name: 'OTT Voucher',  emoji: '⚫', color: Color(0xFF333333),
     desc: 'Available at Pep stores, tuck shops and spaza shops'),
  ];

  Future<void> _redeem() async {
    final code = widget.ctrl.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter your voucher code first')));
      return;
    }
    if (code.length < 12) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Voucher code too short — check and try again'),
        backgroundColor: Color(0xFFFF5555)));
      return;
    }

    // ── Not live yet — needs a merchant account ─────────────────────────────
    // Voucher redemption needs a real merchant integration (Kazang for
    // 1Voucher/OTT, or Bluevoucher's own API) that requires signing up for
    // a merchant account and getting API credentials — an operational step,
    // not something that can be faked here. Once that account exists:
    //   1Voucher / OTT → Kazang API: POST https://api.kazang.net/v1/vouchers/redeem
    //     Headers: { Authorization: 'Bearer $KAZANG_API_KEY' }
    //     Body: { voucher_code: code, merchant_ref: uuid }
    //   Bluevoucher → POST https://api.bluevoucher.co.za/redeem
    //     Body: { pin: code, merchant_id: MERCHANT_ID }
    // Wire the call here and credit the real ledger via the same topup path
    // used by EFT/agent top-ups (never credit the wallet client-side).
    // Until then, this is honest about not being able to redeem anything —
    // no fake "processing" delay, no simulated success.
    setState(() => _redeeming = true);
    try {
      if (mounted) {
        widget.ctrl.clear();
        showModalBottomSheet(
          context: context,
          backgroundColor: const Color(0xFF0D1F14),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('⏳', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              const Text('Voucher integration coming soon',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Clash', fontSize: 20,
                  fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 8),
              const Text(
                'We need a merchant account with Kazang or Bluevoucher '
                'to activate real voucher redemption. '
                'Expected live within 5–7 business days.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                  color: Color(0xFF9BBFAA), height: 1.5)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C96A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF00C96A).withOpacity(0.3))),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Icon(Icons.info_outline, color: Color(0xFF00C96A), size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'In the meantime, use the Agent or EFT method to add money.',
                    style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                      color: Color(0xFF00C96A), height: 1.4))),
                ])),
              const SizedBox(height: 20),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    height: 48, width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A3A25),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF00C96A).withOpacity(0.3))),
                    alignment: Alignment.center,
                    child: const Text('Got it',
                      style: TextStyle(fontFamily: 'Satoshi', fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF00C96A)))))),
            ])));
      }
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sel = _brands.firstWhere((b) => b.name == _brand);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // Brand selector tabs
      const Text('Voucher type', style: TextStyle(
        fontFamily: 'Satoshi', fontSize: 12, fontWeight: FontWeight.w700,
        color: DelightColors.textMuted, letterSpacing: 0.5)),
      const SizedBox(height: 8),
      Row(children: _brands.map((b) {
        final active = b.name == _brand;
        return Expanded(child: GestureDetector(
          onTap: () => setState(() => _brand = b.name),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? b.color.withOpacity(0.12) : DelightColors.surfaceHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? b.color : DelightColors.surfaceBorder,
                width: active ? 1.5 : 1)),
            child: Column(children: [
              Text(b.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 3),
              Text(b.name, style: TextStyle(fontFamily: 'Satoshi', fontSize: 9,
                fontWeight: FontWeight.w700,
                color: active ? b.color : DelightColors.textMuted)),
            ]))));
      }).toList()),
      const SizedBox(height: 12),

      // Info strip
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sel.color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: sel.color.withOpacity(0.25))),
        child: Row(children: [
          Text(sel.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(sel.name, style: TextStyle(fontFamily: 'Satoshi',
              fontWeight: FontWeight.w700, fontSize: 13, color: sel.color)),
            Text(sel.desc, style: const TextStyle(fontFamily: 'Satoshi',
              fontSize: 11, color: DelightColors.textMuted, height: 1.4)),
          ])),
        ])),
      const SizedBox(height: 14),

      // Code input
      TextField(
        controller: widget.ctrl,
        style: const TextStyle(fontFamily: 'Satoshi',
          color: DelightColors.textPrimary, fontSize: 20, letterSpacing: 3),
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Enter ${sel.name} code',
          hintStyle: const TextStyle(fontFamily: 'Satoshi', letterSpacing: 0, fontSize: 14),
          filled: true, fillColor: DelightColors.surfaceHigh,
          prefixIcon: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(sel.emoji, style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: sel.color, width: 1.5)))),
      const SizedBox(height: 12),

      // Redeem button
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _redeeming ? null : _redeem,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 52, width: double.infinity,
            decoration: BoxDecoration(
              gradient: widget.ctrl.text.isNotEmpty
                ? LinearGradient(colors: [sel.color, sel.color.withOpacity(0.75)])
                : null,
              color: widget.ctrl.text.isEmpty ? DelightColors.surfaceHigh : null,
              borderRadius: BorderRadius.circular(14),
              border: widget.ctrl.text.isEmpty
                ? Border.all(color: DelightColors.surfaceBorder) : null),
            alignment: Alignment.center,
            child: _redeeming
              ? SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: sel.color, strokeWidth: 2))
              : Text(
                  widget.ctrl.text.isEmpty
                    ? 'Enter code above'
                    : 'Redeem ${sel.name}',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: widget.ctrl.text.isEmpty
                      ? DelightColors.textMuted : Colors.white))))),

      const SizedBox(height: 12),
      // Where to buy
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: DelightColors.surfaceBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Where to buy', style: TextStyle(fontFamily: 'Satoshi',
            fontWeight: FontWeight.w700, fontSize: 12,
            color: DelightColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6,
            children: ['Shoprite', 'Checkers', 'Pep', 'USave',
                       'Pick n Pay', 'Spar', 'OK Foods', 'Boxer', 'Game']
              .map((s) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: DelightColors.emeraldGlow,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
                child: Text(s, style: const TextStyle(fontFamily: 'Satoshi',
                  fontSize: 11, color: DelightColors.emerald,
                  fontWeight: FontWeight.w600)))).toList()),
        ])),
    ]);
  }
}

// ─── USSD panel ───────────────────────────────────────────────────────────────

class _USSDPanel extends StatelessWidget {
  final double amount;
  const _USSDPanel({required this.amount});

  static const _codes = [
    ('🟡', 'MTN',     '*120*DELIGHT#'),
    ('🔴', 'Vodacom', '*120*DELIGHT#'),
    ('🔵', 'Cell C',  '*120*DELIGHT#'),
    ('⚫', 'Telkom',  '*120*DELIGHT#'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DelightColors.goldGlow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: DelightColors.gold.withOpacity(0.3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('No internet or smartphone needed', style: TextStyle(
            fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
            color: DelightColors.gold, fontSize: 13)),
          const SizedBox(height: 8),
          ...['1. Dial the code for your network below',
            '2. Select "Top Up Delight"',
            '3. Enter your Delight account number',
            if (amount > 0) '4. Enter R${amount.toStringAsFixed(0)}',
            '5. Confirm with your PIN',
            '6. Money added instantly',
          ].map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(s, style: const TextStyle(fontFamily: 'Satoshi',
              fontSize: 12, color: DelightColors.textSecondary)))),
        ])),
      const SizedBox(height: 12),
      ..._codes.map((c) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DelightColors.surfaceBorder)),
        child: Row(children: [
          Text(c.$1, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Flexible(child: Text(c.$2, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'Satoshi',
            fontWeight: FontWeight.w700, color: DelightColors.textPrimary, fontSize: 14))),
          const Spacer(),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: c.$3));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${c.$3} copied!')));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: DelightColors.goldGlow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DelightColors.gold.withOpacity(0.3))),
              child: Row(children: [
                Text(c.$3, style: const TextStyle(fontFamily: 'Satoshi',
                  fontSize: 13, fontWeight: FontWeight.w700, color: DelightColors.gold)),
                const SizedBox(width: 6),
                const Icon(Icons.copy, size: 12, color: DelightColors.gold),
              ]))),
        ]))),
    ]);
  }
}

// ─── EFT panel ────────────────────────────────────────────────────────────────

class _EFTPanel extends ConsumerStatefulWidget {
  final double amount;
  const _EFTPanel({required this.amount});
  @override
  ConsumerState<_EFTPanel> createState() => _EFTPanelState();
}

class _EFTPanelState extends ConsumerState<_EFTPanel> {
  Map<String, dynamic>? _details;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(authProvider);
    if (user == null) { setState(() { _loading = false; _failed = true; }); return; }
    // Real bank details + reference come from the topup edge function —
    // no longer duplicated/hardcoded in the client, so whatever account
    // the backend is configured with is what the user actually sees.
    final details = await SupabaseService.getEftDetails(user.id);
    if (!mounted) return;
    setState(() {
      _details = details;
      _loading = false;
      _failed = details == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final amount = widget.amount;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: DelightColors.emerald)));
    }

    if (_failed || _details == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: DelightColors.error.withOpacity(0.3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.error_outline, color: DelightColors.error, size: 18),
            SizedBox(width: 8),
            Text("Couldn't load bank details", style: TextStyle(
              fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
              fontSize: 14, color: DelightColors.textPrimary)),
          ]),
          const SizedBox(height: 8),
          const Text('Check your connection and try again, or use the Agent method instead.',
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
              color: DelightColors.textMuted, height: 1.4)),
          const SizedBox(height: 10),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ]));
    }

    final details = _details!;
    final accountNumber = details['account_number'] as String? ?? '';
    // The backend ships with a placeholder account number until a real
    // business bank account is configured — show that honestly instead of
    // a fabricated number.
    final accountNotConfigured = accountNumber.isEmpty ||
      accountNumber.toUpperCase().contains('YOUR_') ||
      accountNumber.toUpperCase().contains('REPLACE');
    final eftRef = details['reference'] as String? ?? '';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      if (accountNotConfigured)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DelightColors.gold.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DelightColors.gold.withOpacity(0.4))),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, color: DelightColors.gold, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text(
              'Bank EFT isn\'t fully set up yet — Delight\'s business bank '
              'account hasn\'t been configured. Use the Agent method in the '
              'meantime.',
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                color: DelightColors.gold, height: 1.4))),
          ])),

      // How it works
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DelightColors.emeraldGlow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Text('🏦', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text('Bank EFT — free for you', style: TextStyle(
              fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
              fontSize: 14, color: DelightColors.textPrimary)),
          ]),
          const SizedBox(height: 6),
          const Text(
            'Do a normal EFT from your banking app to our account below. '
            'Your Delight balance updates within 1 business day.',
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
              color: DelightColors.textMuted, height: 1.5)),
        ])),
      const SizedBox(height: 12),

      // Bank account details — user copies these
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: DelightColors.surfaceBorder)),
        child: Column(children: [
          _detailRow('Bank',            details['bank_name'] as String? ?? '—'),
          _detailRow('Account name',    details['account_name'] as String? ?? '—'),
          _detailRow('Account number',  accountNotConfigured ? 'Not yet configured' : accountNumber),
          _detailRow('Branch code',     details['branch_code'] as String? ?? '—'),
          _detailRow('Account type',    details['account_type'] as String? ?? '—'),
          const Divider(color: DelightColors.surfaceBorder, height: 20),
          // Reference is the most important — without it we can't match the payment
          _copyRow(context, 'YOUR reference', eftRef, highlight: true),
        ])),
      const SizedBox(height: 10),

      // Warning about reference
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2A1000),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: DelightColors.gold.withOpacity(0.4))),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Icon(Icons.warning_amber_outlined,
            color: DelightColors.gold, size: 16),
          SizedBox(width: 8),
          Expanded(child: Text(
            'You MUST use your reference above. '
            'Without it we cannot match the payment to your account.',
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
              color: DelightColors.gold, height: 1.4))),
        ])),
      const SizedBox(height: 10),

      // Fee breakdown
      if (amount > 0) Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DelightColors.surfaceBorder)),
        child: Column(children: [
          _feeRow('You send',    'R${amount.toStringAsFixed(2)}',
            DelightColors.textPrimary),
          _feeRow('Delight fee (0.5%)',
            '- R${(amount * 0.005).toStringAsFixed(2)}',
            DelightColors.textMuted),
          _feeRow('Exchange fee (0.1%)',
            '- R${(amount * 0.001).toStringAsFixed(2)}',
            DelightColors.textMuted),
          const Divider(color: DelightColors.surfaceBorder, height: 14),
          _feeRow('DC credited to wallet',
            '${((amount * 0.994) / 9.5).toStringAsFixed(2)} DC',
            DelightColors.emerald, bold: true),
          _feeRow('≈ value in Rands',
            'R${(amount * 0.994).toStringAsFixed(2)}',
            DelightColors.textMuted),
        ])),
      const SizedBox(height: 10),

      // Supported banks
      const Text('Works from any SA bank', style: TextStyle(
        fontFamily: 'Satoshi', fontSize: 11,
        color: DelightColors.textMuted)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6,
        children: ['FNB', 'Standard Bank', 'ABSA', 'Nedbank',
          'Capitec', 'TymeBank', 'African Bank', 'Discovery',
          'Investec', 'Bidvest']
          .map((b) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: DelightColors.surfaceBorder,
              borderRadius: BorderRadius.circular(8)),
            child: Text(b, style: const TextStyle(fontFamily: 'Satoshi',
              fontSize: 11, color: DelightColors.textSecondary))))
          .toList()),
    ]);
  }

  Widget _detailRow(String label, String value) =>
    Padding(padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 120, child: Text(label, style: const TextStyle(
          fontFamily: 'Satoshi', fontSize: 12,
          color: DelightColors.textMuted))),
        Expanded(child: Text(value, style: const TextStyle(
          fontFamily: 'Satoshi', fontSize: 12,
          fontWeight: FontWeight.w600,
          color: DelightColors.textPrimary))),
      ]));

  Widget _copyRow(BuildContext ctx, String label, String value,
      {bool highlight = false}) =>
    GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('$label copied: $value'),
          backgroundColor: DelightColors.emerald));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: highlight
            ? DelightColors.emeraldGlow
            : DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: highlight
              ? DelightColors.emerald.withOpacity(0.5)
              : DelightColors.surfaceBorder)),
        child: Row(children: [
          SizedBox(width: 120, child: Text(label, style: TextStyle(
            fontFamily: 'Satoshi', fontSize: 12,
            color: highlight
              ? DelightColors.emerald
              : DelightColors.textMuted,
            fontWeight: FontWeight.w700))),
          Expanded(child: Text(value, style: TextStyle(
            fontFamily: 'Clash', fontSize: 14,
            fontWeight: FontWeight.w800,
            color: highlight
              ? DelightColors.emerald
              : DelightColors.textPrimary))),
          Icon(Icons.copy, size: 14,
            color: highlight
              ? DelightColors.emerald
              : DelightColors.textMuted),
        ])));

  Widget _feeRow(String label, String value, Color color, {bool bold = false}) =>
    Padding(padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(
          fontFamily: 'Satoshi', fontSize: 12,
          color: DelightColors.textSecondary))),
        Text(value, style: TextStyle(fontFamily: 'Satoshi',
          fontSize: 12, color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
      ]));
}

// ─── Leave a Review ───────────────────────────────────────────────────────────

class _LeaveReviewSection extends StatefulWidget {
  final _Agent agent;
  const _LeaveReviewSection({required this.agent});
  @override
  State<_LeaveReviewSection> createState() => _LeaveReviewSectionState();
}

class _LeaveReviewSectionState extends State<_LeaveReviewSection> {
  int _selectedStars = 0;
  bool _submitted = false;
  final _ctrl = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DelightColors.emeraldGlow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
        child: const Row(children: [
          Icon(Icons.check_circle_outline,
            color: DelightColors.emerald, size: 20),
          SizedBox(width: 10),
          Expanded(child: Text(
            'Thank you! Your review helps others in the community.',
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
              color: DelightColors.emerald, height: 1.4))),
        ]));
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Rate this agent', style: TextStyle(
          fontFamily: 'Clash', fontSize: 16, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 4),
        Text('Your rating helps others find reliable agents near them.',
          style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
            color: DelightColors.textMuted, height: 1.4)),
        const SizedBox(height: 14),

        // Star selector
        Row(mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final filled = i < _selectedStars;
            return GestureDetector(
              onTap: () => setState(() => _selectedStars = i + 1),
              child: AnimatedScale(
                scale: filled ? 1.2 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    filled ? Icons.star : Icons.star_border,
                    color: DelightColors.gold,
                    size: 36))),
            );
          })),

        if (_selectedStars > 0) ...[
          const SizedBox(height: 6),
          Center(child: Text(
            ['', 'Poor', 'Fair', 'Good', 'Great', 'Excellent!'][_selectedStars],
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _selectedStars >= 4
                ? DelightColors.emerald : DelightColors.gold))),
          const SizedBox(height: 12),

          // Optional text review
          TextField(
            controller: _ctrl,
            maxLines: 2,
            style: const TextStyle(fontFamily: 'Satoshi',
              color: DelightColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Optional: describe your experience...',
              hintStyle: const TextStyle(
                fontFamily: 'Satoshi', color: DelightColors.textMuted,
                fontSize: 12),
              filled: true, fillColor: DelightColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: DelightColors.surfaceBorder)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: DelightColors.surfaceBorder)),
              contentPadding: const EdgeInsets.all(12))),
          const SizedBox(height: 12),

          GestureDetector(
            onTap: () {
              if (_selectedStars == 0) return;
              setState(() => _submitted = true);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                  '${_selectedStars}-star review submitted for '
                  '${widget.agent.name}. Thank you! 🙏'),
                backgroundColor: DelightColors.emerald));
            },
            child: Container(
              height: 46, width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: DelightColors.goldGradient),
                borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: const Text('Submit Review', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 14,
                fontWeight: FontWeight.w700, color: Colors.black)))),
        ],
      ]));
  }
}

// ─── Become an Agent ──────────────────────────────────────────────────────────

class _BecomeAgentSheet extends StatefulWidget {
  const _BecomeAgentSheet();
  @override
  State<_BecomeAgentSheet> createState() => _BecomeAgentSheetState();
}

class _BecomeAgentSheetState extends State<_BecomeAgentSheet> {
  int _tier = 0; // 0=Basic, 1=Merchant, 2=Super
  bool _submitted = false;
  final _nameCtrl    = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _addressCtrl = TextEditingController();
  bool _loading = false;

  static const _tiers = [
    (
      label: 'Basic Agent',
      emoji: '🧑',
      commission: '1% per top-up',
      float: 'R500 starting float',
      desc: 'Individuals. Earn R1 for every R100 someone tops up at your location.',
      color: Color(0xFF00C96A),
    ),
    (
      label: 'Merchant Agent',
      emoji: '🏪',
      commission: '2% per top-up',
      float: 'R2,000 starting float',
      desc: 'Spaza shops, tuck shops, garages. Get a branded Delight sign. Earn R2 per R100.',
      color: Color(0xFF6C63FF),
    ),
    (
      label: 'Super Agent',
      emoji: '⚡',
      commission: '0.5% on your network',
      float: 'R10,000 starting float',
      desc: 'Recruit and manage basic agents. Earn on every transaction in your network.',
      color: Color(0xFFD4AF37),
    ),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_nameCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in your name and phone')));
      return;
    }
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 1200));
    setState(() { _loading = false; _submitted = true; });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      expand: false,
      builder: (_, ctrl) => SingleChildScrollView(
        controller: ctrl,
        padding: const EdgeInsets.all(24),
        child: _submitted ? _successView() : _formView()));
  }

  Widget _successView() {
    final t = _tiers[_tier];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Center(child: Container(width: 40, height: 4,
        decoration: BoxDecoration(color: DelightColors.surfaceBorder,
          borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 40),
      Text(t.emoji, style: const TextStyle(fontSize: 64)),
      const SizedBox(height: 20),
      Text('Application Submitted!', style: const TextStyle(
        fontFamily: 'Clash', fontSize: 26, fontWeight: FontWeight.w700,
        color: DelightColors.textPrimary)),
      const SizedBox(height: 10),
      Text('Welcome to the Delight Agent Network, ${_nameCtrl.text.trim()}.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontFamily: 'Satoshi', fontSize: 14,
          color: DelightColors.textSecondary, height: 1.5)),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
        child: Column(children: [
          _step('1', 'KYC verification — we\'ll call you within 24h'),
          _step('2', 'Float activation — deposit your starting float'),
          _step('3', 'Go live — appear on the agent map immediately'),
          _step('4', 'Start earning — every top-up, every cashout'),
        ])),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DelightColors.goldGlow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DelightColors.gold.withOpacity(0.3))),
        child: Row(children: [
          const Text('💰', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.label, style: const TextStyle(
              fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
              fontSize: 13, color: DelightColors.gold)),
            Text(t.commission, style: const TextStyle(
              fontFamily: 'Satoshi', fontSize: 12,
              color: DelightColors.textSecondary)),
          ])),
        ])),
      const SizedBox(height: 24),
    ]);
  }

  Widget _step(String n, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 22, height: 22,
        decoration: BoxDecoration(
          color: DelightColors.emeraldGlow, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(n, style: const TextStyle(fontFamily: 'Clash',
          fontSize: 11, fontWeight: FontWeight.w800,
          color: DelightColors.emerald))),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(
        fontFamily: 'Satoshi', fontSize: 13,
        color: DelightColors.textSecondary, height: 1.4))),
    ]));

  Widget _formView() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // Handle
      Center(child: Container(width: 40, height: 4,
        decoration: BoxDecoration(color: DelightColors.surfaceBorder,
          borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 16),

      // Header
      const Text('Become a Delight Agent', style: TextStyle(
        fontFamily: 'Clash', fontSize: 22, fontWeight: FontWeight.w700,
        color: DelightColors.textPrimary)),
      const SizedBox(height: 4),
      const Text(
        'Join 3,840+ agents earning from every top-up and cashout in their area.',
        textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
          color: DelightColors.textMuted, height: 1.4)),
      const SizedBox(height: 20),

      // Tier selector
      const Align(alignment: Alignment.centerLeft,
        child: Text('Choose your tier', style: TextStyle(
          fontFamily: 'Satoshi', fontSize: 12, fontWeight: FontWeight.w700,
          color: DelightColors.textMuted, letterSpacing: 0.5))),
      const SizedBox(height: 10),

      ..._tiers.asMap().entries.map((e) {
        final sel = _tier == e.key;
        final t = e.value;
        return GestureDetector(
          onTap: () => setState(() => _tier = e.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: sel ? t.color.withOpacity(0.08) : DelightColors.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: sel ? t.color : DelightColors.surfaceBorder,
                width: sel ? 1.5 : 1)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(t.label, style: TextStyle(
                    fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: sel ? t.color : DelightColors.textPrimary)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: t.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(5)),
                    child: Text(t.commission, style: TextStyle(
                      fontFamily: 'Satoshi', fontSize: 9,
                      fontWeight: FontWeight.w700, color: t.color))),
                ]),
                const SizedBox(height: 2),
                Text(t.desc, style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 11,
                  color: DelightColors.textMuted, height: 1.4)),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.account_balance_wallet_outlined,
                    size: 11, color: t.color),
                  const SizedBox(width: 4),
                  Text(t.float, style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 11,
                    fontWeight: FontWeight.w600, color: t.color)),
                ]),
              ])),
              Radio<int>(
                value: e.key,
                groupValue: _tier,
                onChanged: (v) => setState(() => _tier = v!),
                activeColor: t.color),
            ])));
      }),

      const SizedBox(height: 8),

      // Form fields
      _field(_nameCtrl, 'Full Name *', Icons.person_outline),
      const SizedBox(height: 10),
      _field(_phoneCtrl, 'Phone Number *', Icons.phone_outlined,
        type: TextInputType.phone),
      const SizedBox(height: 10),
      _field(_addressCtrl, 'Your address / business location',
        Icons.location_on_outlined),
      const SizedBox(height: 20),

      // What happens next
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: DelightColors.goldGlow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DelightColors.gold.withOpacity(0.3))),
        child: const Row(children: [
          Icon(Icons.info_outline, color: DelightColors.gold, size: 16),
          SizedBox(width: 8),
          Expanded(child: Text(
            'After submitting: we verify your ID, activate your float, '
            'and you appear on the agent map immediately. No fees to join.',
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
              color: DelightColors.gold, height: 1.4))),
        ])),
      const SizedBox(height: 20),

      // Submit
      GestureDetector(
        onTap: _loading ? null : _register,
        child: Container(
          height: 56, width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_tiers[_tier].color,
                _tiers[_tier].color.withOpacity(0.75)]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(
              color: _tiers[_tier].color.withOpacity(0.35),
              blurRadius: 16, offset: const Offset(0, 4))]),
          alignment: Alignment.center,
          child: _loading
            ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2))
            : Text('Apply as ${_tiers[_tier].label}',
                style: const TextStyle(fontFamily: 'Satoshi', fontSize: 15,
                  fontWeight: FontWeight.w800, color: Colors.white)))),
    ]);
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {TextInputType type = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(fontFamily: 'Satoshi',
        color: DelightColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Satoshi',
          color: DelightColors.textMuted, fontSize: 12),
        prefixIcon: Icon(icon, color: DelightColors.textMuted, size: 18),
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
            color: DelightColors.gold, width: 1.5))));
  }
}

// ── GPS Agent Finder ───────────────────────────────────────────────────────────
class _AgentFinderList extends StatefulWidget {
  @override State<_AgentFinderList> createState() => _AgentFinderListState();
}

class _AgentFinderListState extends State<_AgentFinderList> {
  List<AgentLocation>? _agents;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final agents = await findNearestAgents();
    if (mounted) setState(() { _agents = agents; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(child: SizedBox(width: 20, height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2, color: DelightColors.emerald))));

    final agents = _agents ?? [];
    return Column(children: agents.map((a) => Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
            'Show your QR code at ${a.name} — they pay you cash'))),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: DelightColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: DelightColors.emerald.withOpacity(0.2))),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Satoshi',
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: DelightColors.textPrimary))),
                const SizedBox(width: 6),
                if (!a.isOpen)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: DelightColors.error.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4)),
                    child: const Text('Closed', style: TextStyle(
                      fontFamily: 'Satoshi', fontSize: 9,
                      color: DelightColors.error))),
              ]),
              Text(a.address, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Satoshi',
                fontSize: 11, color: DelightColors.textMuted)),
            ])),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${a.rating} ⭐', style: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 11, color: DelightColors.gold)),
              Text(a.distanceKm > 0
                ? '${a.distanceKm.toStringAsFixed(1)} km'
                : 'Nearby',
                style: const TextStyle(fontFamily: 'Satoshi',
                  fontSize: 11, color: DelightColors.textMuted)),
            ]),
          ]))))).toList());
  }
}
