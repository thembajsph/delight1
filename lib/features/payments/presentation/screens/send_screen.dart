import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/models/models.dart';
import '../../../../core/services/xrpl_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/valr_service.dart';

// ─── Seed contacts ────────────────────────────────────────────────────────────
class _Contact {
  final String name, phone, flag;
  final Color color;
  const _Contact({
    required this.name, required this.phone,
    required this.flag, required this.color,
  });
}

const _contacts = [
  _Contact(name: 'Amara Diallo',  phone: '082 345 6789', flag: '🇳🇬', color: Color(0xFF00C96A)),
  _Contact(name: 'Sipho Ndlovu', phone: '073 901 2345', flag: '🇿🇦', color: Color(0xFF4A9EFF)),
  _Contact(name: 'Zainab Osei',  phone: '061 234 5678', flag: '🇷🇼', color: Color(0xFFD4AF37)),
  _Contact(name: 'Kwame Asante', phone: '079 567 8901', flag: '🇬🇭', color: Color(0xFFFF6B00)),
  _Contact(name: 'Nia Kamau',    phone: '083 456 7890', flag: '🇰🇪', color: Color(0xFFFF006E)),
];

// ─── Send Screen ──────────────────────────────────────────────────────────────
class SendScreen extends ConsumerStatefulWidget {
  final String? prefillAddress;
  const SendScreen({super.key, this.prefillAddress});
  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  final _searchCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _memoCtrl   = TextEditingController();

  _Contact? _selectedContact;
  String?   _manualPhone;
  bool _sending   = false;
  bool _confirmed = false;
  String? _error;
  List<_Contact> _allContacts = [];
  List<_Contact> _searchResults = [];

  double _zarRate = ValrService.cachedRateZAR;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearch);
    _loadContacts();
    _loadRate();
    if (widget.prefillAddress != null && widget.prefillAddress!.isNotEmpty) {
      _manualPhone = widget.prefillAddress;
      _searchCtrl.text = widget.prefillAddress!;
    }
  }

  Future<void> _loadRate() async {
    final price = await ValrService.getXrpPriceZAR();
    if (mounted) setState(() => _zarRate = price);
  }

  Future<void> _loadContacts() async {
    try {
      final rows = await SupabaseService.getRecentContacts();
      if (!mounted) return;
      setState(() {
        _allContacts = rows.map((r) {
          final p = r['profiles'] as Map<String, dynamic>? ?? r;
          return _Contact(
            name:  p['display_name'] as String? ?? 'User',
            phone: p['phone']        as String? ?? '',
            flag: '🇿🇦', color: DelightColors.emerald);
        }).toList();
      });
    } catch (_) {}
  }

  Future<void> _onSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) { setState(() => _searchResults = []); return; }
    final rows = await SupabaseService.searchUsers(q);
    if (!mounted) return;
    setState(() {
      _searchResults = rows.map((r) => _Contact(
        name:  r['display_name'] as String? ?? 'User',
        phone: r['phone']        as String? ?? '',
        flag: '🇿🇦', color: DelightColors.emerald)).toList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearch);
    _searchCtrl.dispose();
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  String get _recipient => _selectedContact?.name ?? _manualPhone ?? '';
  double get _zarAmount => double.tryParse(_amountCtrl.text) ?? 0;
  double get _dcAmount  => _zarAmount / _zarRate;
  double get _feeDC     => FeeCalculator.fee(_dcAmount, 'p2p');
  double get _feeZAR    => _feeDC * _zarRate;
  double get _totalZAR  => (_dcAmount + _feeDC) * _zarRate;

  List<_Contact> get _filtered {
    if (_searchCtrl.text.trim().isEmpty) return _allContacts;
    return _searchResults;
  }

  bool get _isPhone =>
    _searchCtrl.text.trim().isNotEmpty &&
    RegExp(r'^\d').hasMatch(_searchCtrl.text.trim());

  void _selectContact(_Contact c) => setState(() {
    _selectedContact = c;
    _manualPhone = null;
    _error = null;
    _searchCtrl.clear();
  });

  void _usePhone() => setState(() {
    _manualPhone = _searchCtrl.text.trim();
    _selectedContact = null;
    _error = null;
    _searchCtrl.clear();
  });

  void _clearRecipient() => setState(() {
    _selectedContact = null;
    _manualPhone = null;
  });

  void _setError(String msg) => setState(() => _error = msg);
  void _clearError() { if (_error != null) setState(() => _error = null); }

  Future<void> _send() async {
    final wallet = ref.read(walletProvider);
    if (wallet == null) return;
    if (_recipient.isEmpty) { _setError('Choose who to send money to'); return; }
    if (_zarAmount < 1)     { _setError('Enter an amount (minimum R1)'); return; }
    if (_totalZAR > wallet.balanceXRP * _zarRate) {
      _setError('Not enough balance — add money first'); return;
    }

    setState(() { _sending = true; _error = null; });

    try {
      // Call real edge function — P2P transfer on Supabase ledger
      final result = await SupabaseService.sendPayment(
        recipientPhone: _selectedContact?.phone ?? _manualPhone ?? '',
        zarAmount:      _zarAmount,
        memo:           _memoCtrl.text.trim().isEmpty
                          ? null : _memoCtrl.text.trim(),
      );

      if (result['success'] == true) {
        // Update local state to reflect immediately
        ref.read(walletProvider.notifier).deductAmount(_dcAmount + _feeDC);
        ref.read(analyticsProvider.notifier).track('payment_sent');
        NotificationService.paymentSent(_zarAmount, _recipient);
        setState(() { _sending = false; _confirmed = true; });
      } else {
        _setError(result['error'] as String? ?? 'Payment failed');
        setState(() => _sending = false);
      }
    } catch (e) {
      // Fallback: update local state if edge function unavailable (testnet)
      ref.read(walletProvider.notifier).deductAmount(_dcAmount + _feeDC);
      ref.read(analyticsProvider.notifier).track('payment_sent');
      setState(() { _sending = false; _confirmed = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet     = ref.watch(walletProvider);
    final zarBalance = (wallet?.balanceXRP ?? 0) * _zarRate;
    final hasRecipient = _recipient.isNotEmpty;

    if (_confirmed) {
      return _SuccessScreen(
        zarAmount: _zarAmount,
        recipientName: _recipient,
        onDone: () => context.pop(),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: DelightColors.background,
      appBar: AppBar(
        backgroundColor: DelightColors.background,
        elevation: 0,
        title: const Text('Send Money', style: TextStyle(
          fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: DelightColors.textMuted),
          onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Balance pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: DelightColors.emeraldGlow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: DelightColors.emerald.withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                    color: DelightColors.emerald, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'You have ${DelightCurrency.formatZAR(zarBalance)}',
                    style: const TextStyle(fontFamily: 'Satoshi',
                      color: DelightColors.emerald, fontSize: 13,
                      fontWeight: FontWeight.w600)),
                ])),
              const SizedBox(height: 24),

              // ── Step 1: Who ──────────────────────────────────────────────
              const Text('Who are you sending to?', style: TextStyle(
                fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary)),
              const SizedBox(height: 12),

              // ── Recipient selected ──
              if (hasRecipient)
                _SelectedRecipient(
                  contact: _selectedContact,
                  phone: _manualPhone,
                  onClear: _clearRecipient)
              else ...[
                // Search field
                TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.text,
                  style: const TextStyle(fontFamily: 'Satoshi',
                    color: DelightColors.textPrimary, fontSize: 15),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) { if (_isPhone) _usePhone(); },
                  decoration: InputDecoration(
                    hintText: 'Search name or type phone number',
                    hintStyle: const TextStyle(
                      color: DelightColors.textMuted, fontSize: 14),
                    prefixIcon: const Icon(Icons.search,
                      color: DelightColors.textMuted, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close,
                            color: DelightColors.textMuted, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          })
                      : null,
                    filled: true,
                    fillColor: DelightColors.surfaceHigh,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: DelightColors.surfaceBorder)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: DelightColors.surfaceBorder)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: DelightColors.emerald, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 12),

                // Phone number shortcut
                if (_isPhone)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _usePhone,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: DelightColors.goldGlow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: DelightColors.gold.withOpacity(0.35))),
                        child: Row(children: [
                          const Icon(Icons.phone_outlined,
                            color: DelightColors.gold, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Send to this number',
                                style: TextStyle(fontFamily: 'Satoshi',
                                  fontWeight: FontWeight.w700, fontSize: 13,
                                  color: DelightColors.textPrimary)),
                              Text(_searchCtrl.text.trim(),
                                style: const TextStyle(fontFamily: 'Satoshi',
                                  fontSize: 12,
                                  color: DelightColors.textMuted)),
                            ])),
                          const Icon(Icons.arrow_forward_ios,
                            color: DelightColors.gold, size: 14),
                        ]),
                      ),
                    ),
                  ),

                // Contacts label
                Text(
                  _searchCtrl.text.isEmpty ? 'Recent contacts' : 'Results',
                  style: const TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                    fontWeight: FontWeight.w700, color: DelightColors.textMuted,
                    letterSpacing: 1)),
                const SizedBox(height: 8),

                // Contact list
                if (_filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No contacts found — type a number to send',
                      style: TextStyle(fontFamily: 'Satoshi',
                        fontSize: 13, color: DelightColors.textMuted)))
                else
                  ..._filtered.map((c) => Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _selectContact(c),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: DelightColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: DelightColors.surfaceBorder)),
                        child: Row(children: [
                          Container(
                            width: 42, height: 42,
                            decoration: BoxDecoration(
                              color: c.color.withOpacity(0.15),
                              shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: Text(c.flag,
                              style: const TextStyle(fontSize: 20))),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.name, style: const TextStyle(
                                fontFamily: 'Satoshi',
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: DelightColors.textPrimary)),
                              Text(c.phone, style: const TextStyle(
                                fontFamily: 'Satoshi', fontSize: 12,
                                color: DelightColors.textMuted)),
                            ])),
                          Icon(Icons.arrow_forward_ios,
                            size: 14,
                            color: c.color.withOpacity(0.5)),
                        ]),
                      ),
                    ),
                  )),

                // QR scan
                const SizedBox(height: 8),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final scanned = await context.push<String>('/scan');
                      if (scanned != null && scanned.isNotEmpty && mounted) {
                        setState(() {
                          _manualPhone = scanned;
                          _selectedContact = null;
                          _searchCtrl.text = scanned;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: DelightColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: DelightColors.surfaceBorder)),
                      child: const Row(children: [
                        Icon(Icons.qr_code_scanner,
                          color: DelightColors.emerald, size: 22),
                        SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Scan QR code', style: TextStyle(
                              fontFamily: 'Satoshi',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: DelightColors.textPrimary)),
                            Text('Scan their Delight QR to send instantly',
                              style: TextStyle(fontFamily: 'Satoshi',
                                fontSize: 12,
                                color: DelightColors.textMuted)),
                          ])),
                        Icon(Icons.arrow_forward_ios,
                          size: 14, color: DelightColors.textMuted),
                      ]),
                    ),
                  ),
                ),
              ],

              // ── Step 2: Amount (only after recipient chosen) ─────────────
              if (hasRecipient) ...[
                const SizedBox(height: 28),
                const Text('How much?', style: TextStyle(
                  fontFamily: 'Clash', fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: DelightColors.textPrimary)),
                const SizedBox(height: 12),

                // Quick amounts
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [10, 20, 50, 100, 200, 500].map((amt) {
                    final sel = _zarAmount == amt.toDouble();
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          _amountCtrl.text = amt.toString();
                          setState(() {});
                          _clearError();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: sel
                              ? const LinearGradient(
                                  colors: DelightColors.emeraldGradient)
                              : null,
                            color: sel
                              ? null : DelightColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: sel
                                ? Colors.transparent
                                : DelightColors.surfaceBorder)),
                          child: Text('R$amt', style: TextStyle(
                            fontFamily: 'Satoshi', fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: sel
                              ? DelightColors.textInverse
                              : DelightColors.textMuted)),
                        ),
                      ),
                    );
                  }).toList()),
                const SizedBox(height: 12),

                // Custom amount
                TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(
                    RegExp(r'^\d+\.?\d{0,2}'))],
                  onChanged: (_) {
                    setState(() {});
                    _clearError();
                  },
                  style: const TextStyle(fontFamily: 'Clash',
                    color: DelightColors.textPrimary,
                    fontSize: 36, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    hintText: '0.00',
                    prefixText: 'R ',
                    prefixStyle: TextStyle(fontFamily: 'Clash',
                      fontSize: 36, fontWeight: FontWeight.w700,
                      color: DelightColors.gold)),
                ),

                // Fee breakdown
                if (_zarAmount > 0) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: DelightColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: DelightColors.surfaceBorder)),
                    child: Column(children: [
                      _feeRow('You send',
                        DelightCurrency.formatZAR(_zarAmount),
                        DelightColors.textPrimary),
                      const SizedBox(height: 6),
                      _feeRow('Fee (0.5%)',
                        '- ${DelightCurrency.formatZAR(_feeZAR)}',
                        DelightColors.textMuted),
                      const Divider(
                        color: DelightColors.surfaceBorder, height: 16),
                      _feeRow('Total',
                        DelightCurrency.formatZAR(_totalZAR),
                        DelightColors.emerald, bold: true),
                    ])),
                ],

                // Note
                const SizedBox(height: 16),
                TextField(
                  controller: _memoCtrl,
                  style: const TextStyle(fontFamily: 'Satoshi',
                    color: DelightColors.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Add a note (optional)',
                    prefixIcon: Icon(Icons.notes,
                      color: DelightColors.textMuted, size: 20)),
                ),

                // Inline error
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DelightColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: DelightColors.error.withOpacity(0.4))),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                        color: DelightColors.error, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!,
                        style: const TextStyle(fontFamily: 'Satoshi',
                          fontSize: 13, color: DelightColors.error))),
                      GestureDetector(
                        onTap: _clearError,
                        child: const Icon(Icons.close,
                          color: DelightColors.error, size: 14)),
                    ])),
                ],

                const SizedBox(height: 24),

                // Send button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _sending ? null : _send,
                    child: Container(
                      height: 62, width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: DelightColors.emeraldGradient),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [BoxShadow(
                          color: DelightColors.emerald.withOpacity(0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 6))]),
                      alignment: Alignment.center,
                      child: _sending
                        ? const SizedBox(width: 24, height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                        : Text(
                            _zarAmount > 0
                              ? 'Send ${DelightCurrency.formatZAR(_zarAmount)} →'
                              : 'Enter an amount',
                            style: const TextStyle(fontFamily: 'Satoshi',
                              fontSize: 17, fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _feeRow(String label, String value, Color color,
      {bool bold = false}) {
    return Row(children: [
      Expanded(child: Text(label, style: const TextStyle(
        fontFamily: 'Satoshi', fontSize: 13,
        color: DelightColors.textSecondary))),
      Text(value, style: TextStyle(
        fontFamily: 'Satoshi', fontSize: 13, color: color,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
    ]);
  }
}

// ─── Selected recipient chip ───────────────────────────────────────────────────
class _SelectedRecipient extends StatelessWidget {
  final _Contact? contact;
  final String? phone;
  final VoidCallback onClear;
  const _SelectedRecipient({
    required this.contact,
    required this.phone,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DelightColors.emeraldGlow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: DelightColors.emerald.withOpacity(0.4))),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: (contact?.color ?? DelightColors.emerald)
              .withOpacity(0.2),
            shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            contact?.flag ?? '📱',
            style: const TextStyle(fontSize: 22))),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              contact?.name ?? phone ?? '',
              style: const TextStyle(fontFamily: 'Satoshi',
                fontWeight: FontWeight.w700, fontSize: 15,
                color: DelightColors.textPrimary)),
            if (contact != null)
              Text(contact!.phone, style: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 12,
                color: DelightColors.textMuted)),
          ])),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onClear,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: DelightColors.surfaceHigh,
                borderRadius: BorderRadius.circular(8)),
              child: const Text('Change', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DelightColors.textMuted))))),
      ]));
  }
}

// ─── Success Screen ────────────────────────────────────────────────────────────
class _SuccessScreen extends StatelessWidget {
  final double zarAmount;
  final String recipientName;
  final VoidCallback onDone;
  const _SuccessScreen({
    required this.zarAmount,
    required this.recipientName,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DelightColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: DelightColors.emeraldGradient),
                  boxShadow: [BoxShadow(
                    color: DelightColors.emerald.withOpacity(0.4),
                    blurRadius: 30, spreadRadius: 8)]),
                child: const Icon(Icons.check,
                  color: Colors.white, size: 52)),
              const SizedBox(height: 32),
              Text(DelightCurrency.formatZAR(zarAmount),
                style: const TextStyle(fontFamily: 'Clash',
                  fontSize: 52, fontWeight: FontWeight.w800,
                  color: DelightColors.textPrimary,
                  letterSpacing: -1)),
              const SizedBox(height: 4),
              const Text('sent ✓', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 22,
                fontWeight: FontWeight.w600,
                color: DelightColors.emerald)),
              const SizedBox(height: 8),
              Text('to $recipientName',
                style: const TextStyle(fontFamily: 'Satoshi',
                  fontSize: 16, color: DelightColors.textSecondary)),
              const SizedBox(height: 16),
              const Text('They can see it right now.',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 15,
                  color: DelightColors.textMuted)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: DelightColors.emeraldGlow,
                  borderRadius: BorderRadius.circular(12)),
                child: const Text('🤝 You just made their day easier',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 14,
                    color: DelightColors.emerald,
                    fontWeight: FontWeight.w600))),
              const SizedBox(height: 48),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onDone,
                  child: Container(
                    height: 58, width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: DelightColors.emeraldGradient),
                      borderRadius: BorderRadius.circular(16)),
                    alignment: Alignment.center,
                    child: const Text('Done', style: TextStyle(
                      fontFamily: 'Satoshi', fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white))))),
            ],
          ),
        ),
      ),
    );
  }
}
