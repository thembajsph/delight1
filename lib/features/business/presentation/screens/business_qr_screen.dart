import '../../../../core/config/env.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/services/supabase_service.dart';

/// Real, per-business link: opens the item-picking pay screen for this user.
String get _paymentUrl =>
  'https://${Env.linkHost}/pay/${SupabaseService.currentUser?.id ?? ''}';

enum _PrintSize { a4, a5, receipt, sticker }
extension _PS on _PrintSize {
  String get label { switch(this) { case _PrintSize.a4: return 'A4 Page'; case _PrintSize.a5: return 'A5 Half Page'; case _PrintSize.receipt: return 'Till Receipt'; case _PrintSize.sticker: return 'Sticker 10x10cm'; } }
  String get desc { switch(this) { case _PrintSize.a4: return 'Stick on wall or counter'; case _PrintSize.a5: return 'Smaller surfaces'; case _PrintSize.receipt: return 'Narrow strip for door or till'; case _PrintSize.sticker: return 'Tables or packaging'; } }
  String get icon { switch(this) { case _PrintSize.a4: return '📄'; case _PrintSize.a5: return '📋'; case _PrintSize.receipt: return '🧾'; case _PrintSize.sticker: return '🏷️'; } }
  double get qrSize { switch(this) { case _PrintSize.a4: return 200; case _PrintSize.a5: return 170; case _PrintSize.receipt: return 130; case _PrintSize.sticker: return 120; } }
}

class _Lang {
  final String code, name, flag, headline, sub, instruction, footer, tap;
  const _Lang({required this.code, required this.name, required this.flag,
    required this.headline, required this.sub, required this.instruction,
    required this.footer, required this.tap});
}

const _langs = [
  _Lang(code:'en', name:'English', flag:'🇿🇦', headline:'SCAN TO PAY', sub:'Pay with Delight',
    instruction:'Open Delight and scan this code to pay instantly.',
    footer:'Powered by Delight · delight.africa', tap:'Tap · Scan · Pay'),
  _Lang(code:'zu', name:'isiZulu', flag:'🇿🇦', headline:'SKENA UKUKHOKHA', sub:'Khokha nge-Delight',
    instruction:'Vula i-Delight bese uskena le khodi ukukhokha ngokuphazima kweso.',
    footer:'Inikwa amandla yi-Delight · delight.africa', tap:'Thepha · Skena · Khokha'),
  _Lang(code:'xh', name:'isiXhosa', flag:'🇿🇦', headline:'SKENA UKHOKHE', sub:'Khokha nge-Delight',
    instruction:'Vula i-Delight uskene le khowudi ukukhokha ngoko nangoko.',
    footer:'Ixhaswa yi-Delight · delight.africa', tap:'Cofa · Skena · Khokha'),
  _Lang(code:'st', name:'Sesotho', flag:'🇿🇦', headline:'SKENA HO LEFA', sub:'Lefa ka Delight',
    instruction:'Bula Delight mme u skene khoutu ena ho lefa hang-hang.',
    footer:'E thehilwe ke Delight · delight.africa', tap:'Tobetsa · Skena · Lefa'),
  _Lang(code:'sw', name:'Kiswahili', flag:'🇰🇪', headline:'SCAN KULIPA', sub:'Lipa na Delight',
    instruction:'Fungua Delight na upige picha msimbo huu kulipa mara moja.',
    footer:'Inayoendeshwa na Delight · delight.africa', tap:'Gusa · Skani · Lipa'),
  _Lang(code:'fr', name:'Français', flag:'🇨🇩', headline:'SCANNER POUR PAYER', sub:'Payez avec Delight',
    instruction:"Ouvrez Delight et scannez ce code pour payer instantanément.",
    footer:'Propulsé par Delight · delight.africa', tap:'Appuyez · Scannez · Payez'),
  _Lang(code:'pt', name:'Português', flag:'🇲🇿', headline:'DIGITALIZAR PARA PAGAR', sub:'Pague com Delight',
    instruction:'Abra o Delight e digitalize este código para pagar.',
    footer:'Desenvolvido por Delight · delight.africa', tap:'Toque · Digitalize · Pague'),
];


// ── Menu item model ───────────────────────────────────────────────────────────

class MenuItem {
  final String id;
  String name, emoji, category;
  double price;
  bool available;

  MenuItem({
    required this.id,
    required this.name,
    required this.emoji,
    required this.category,
    required this.price,
    this.available = true,
  });

  String get itemUrl =>
    _paymentUrl;
}

class BusinessQRScreen extends ConsumerStatefulWidget {
  const BusinessQRScreen({super.key});
  @override
  ConsumerState<BusinessQRScreen> createState() => _BusinessQRScreenState();
}

class _BusinessQRScreenState extends ConsumerState<BusinessQRScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _nameCtrl = TextEditingController(text: 'My Business');
  _PrintSize _size = _PrintSize.a4;
  _Lang _lang      = _langs[0];
  bool _showLogo   = true;
  bool _showAmount = true;
  bool _showInstructions = true;

  // Menu items — optional, payment always works without them
  final List<MenuItem> _menuItems = [];

  @override
  void initState() { super.initState(); _tab = TabController(length: 3, vsync: this); }
  @override
  void dispose() { _tab.dispose(); _nameCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      appBar: AppBar(
        backgroundColor: DelightColors.background,
        title: const Text('Payment QR Code', style: TextStyle(
          fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
          controller: _tab,
          indicatorColor: DelightColors.emerald,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: DelightColors.textPrimary,
          unselectedLabelColor: DelightColors.textMuted,
          labelStyle: const TextStyle(fontFamily: 'Satoshi', fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.phone_android, size: 16), text: 'Phone'),
            Tab(icon: Icon(Icons.print_outlined, size: 16), text: 'Print'),
            Tab(icon: Icon(Icons.restaurant_menu_outlined, size: 16), text: 'Menu'),
          ])),
      body: TabBarView(
        controller: _tab,
        children: [
          _PhoneTab(nameCtrl: _nameCtrl, lang: _lang,
            menuItems: _menuItems,
            onLangChange: (l) => setState(() => _lang = l),
            onNameChange: () => setState(() {}),
            onItemTap: (item) {}),
          _PrintTab(nameCtrl: _nameCtrl, size: _size, lang: _lang,
            showLogo: _showLogo, showAmount: _showAmount, showInstructions: _showInstructions,
            onSizeChange: (s) => setState(() => _size = s),
            onLangChange: (l) => setState(() => _lang = l),
            onLogoChange: (v) => setState(() => _showLogo = v),
            onAmountChange: (v) => setState(() => _showAmount = v),
            onInstructionsChange: (v) => setState(() => _showInstructions = v),
            onNameChange: () => setState(() {})),
          Center(child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('🛍', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              const Text('Your products live in My Products',
                style: TextStyle(fontFamily: 'Clash', fontSize: 18,
                  fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
              const SizedBox(height: 8),
              const Text('Customers who scan your QR pick items from your '
                'product list and pay. Every sale then shows up in Product '
                'Insights.', textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                  color: DelightColors.textMuted, height: 1.5)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.push('/my-products'),
                child: const Text('Manage products')),
            ]))),
        ]));
  }
}

// ── Phone Tab ─────────────────────────────────────────────────────────────────

class _PhoneTab extends StatefulWidget {
  final TextEditingController nameCtrl;
  final _Lang lang;
  final List<MenuItem> menuItems;
  final Function(_Lang) onLangChange;
  final VoidCallback onNameChange;
  final Function(MenuItem) onItemTap;
  const _PhoneTab({required this.nameCtrl, required this.lang,
    required this.menuItems, required this.onLangChange,
    required this.onNameChange, required this.onItemTap});
  @override State<_PhoneTab> createState() => _PhoneTabState();
}

class _PhoneTabState extends State<_PhoneTab> {
  bool _fullscreen = false;
  double _amount = 0;
  final _amtCtrl = TextEditingController();
  @override void dispose() { _amtCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_fullscreen) {
      return _FullscreenQR(
        businessName: widget.nameCtrl.text,
        lang: widget.lang,
        amount: _amount,
        onExit: () => setState(() => _fullscreen = false));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Explainer banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DelightColors.emeraldGlow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📱', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Phone Mode', style: TextStyle(
                      fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                      fontSize: 14, color: DelightColors.emerald)),
                    const SizedBox(height: 3),
                    const Text('Keep your phone open — customer scans your screen.',
                      style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                        color: DelightColors.textSecondary, height: 1.4)),
                  ])),
              ])),
          const SizedBox(height: 20),

          // ── Quick items — only shown if menu has items ──────────────────
          if (widget.menuItems.isNotEmpty) ...[
            Row(children: [
              const Expanded(child: Text('Quick Items', style: TextStyle(
                fontFamily: 'Clash', fontSize: 16, fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary))),
              Text('Tap to set amount', style: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 11, color: DelightColors.textMuted)),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8,
              children: widget.menuItems.where((i) => i.available).map((item) {
                final sel = _amount == item.price;
                return GestureDetector(
                  onTap: () {
                    _amtCtrl.text = item.price.toStringAsFixed(0);
                    setState(() => _amount = item.price);
                    widget.onItemTap(item);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 130),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: sel ? DelightColors.emeraldGlow : DelightColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: sel ? DelightColors.emerald : DelightColors.surfaceBorder,
                        width: sel ? 1.5 : 1)),
                    child: Column(children: [
                      Text(item.emoji, style: const TextStyle(fontSize: 22)),
                      const SizedBox(height: 3),
                      Text(item.name, style: TextStyle(fontFamily: 'Satoshi',
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: sel ? DelightColors.emerald : DelightColors.textPrimary),
                        overflow: TextOverflow.ellipsis),
                      Text('R${item.price.toStringAsFixed(0)}', style: TextStyle(
                        fontFamily: 'Satoshi', fontSize: 10,
                        color: sel ? DelightColors.emerald : DelightColors.textMuted)),
                    ])));
              }).toList()),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: DelightColors.surfaceHigh,
                borderRadius: BorderRadius.circular(8)),
              child: const Row(children: [
                Icon(Icons.info_outline, size: 12, color: DelightColors.textMuted),
                SizedBox(width: 6),
                Expanded(child: Text(
                  'Or enter any amount below — payment always works without selecting an item.',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                    color: DelightColors.textMuted, height: 1.3))),
              ])),
            const SizedBox(height: 16),
          ],

          // QR preview
          GestureDetector(
            onTap: () => setState(() => _fullscreen = true),
            child: _QRCard(
              businessName: widget.nameCtrl.text,
              lang: widget.lang,
              amount: _amount,
              compact: false,
              showTapHint: true)),
          const SizedBox(height: 20),
          // Amount
          const Text('Request a Specific Amount', style: TextStyle(
            fontFamily: 'Clash', fontSize: 16, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary)),
          const SizedBox(height: 8),
          TextField(
            controller: _amtCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontFamily: 'Clash', color: DelightColors.textPrimary,
              fontSize: 32, fontWeight: FontWeight.w700),
            onChanged: (v) => setState(() => _amount = double.tryParse(v) ?? 0),
            decoration: const InputDecoration(
              prefixText: 'R ', prefixStyle: TextStyle(fontFamily: 'Clash', fontSize: 32,
                fontWeight: FontWeight.w700, color: DelightColors.gold),
              hintText: '0.00', border: InputBorder.none)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8,
            children: [10.0, 20.0, 50.0, 100.0, 200.0].map((amt) {
              final sel = _amount == amt;
              return GestureDetector(
                onTap: () { _amtCtrl.text = amt.toStringAsFixed(0); setState(() => _amount = amt); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel ? DelightColors.emeraldGlow : DelightColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: sel ? DelightColors.emerald : DelightColors.surfaceBorder)),
                  child: Text('R${amt.toStringAsFixed(0)}', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 13, fontWeight: FontWeight.w700,
                    color: sel ? DelightColors.emerald : DelightColors.textMuted))));
            }).toList()),
          const SizedBox(height: 20),
          // Language
          const Text('Language', style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
            fontWeight: FontWeight.w700, color: DelightColors.textMuted, letterSpacing: 1)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8,
            children: _langs.map((l) {
              final sel = l.code == widget.lang.code;
              return GestureDetector(
                onTap: () => widget.onLangChange(l),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel ? DelightColors.emeraldGlow : DelightColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel ? DelightColors.emerald : DelightColors.surfaceBorder)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(l.flag, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 5),
                    Text(l.name, style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: sel ? DelightColors.emerald : DelightColors.textMuted)),
                  ])));
            }).toList()),
          const SizedBox(height: 24),
          // Go fullscreen
          GestureDetector(
            onTap: () => setState(() => _fullscreen = true),
            child: Container(
              height: 56, width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: DelightColors.emeraldGradient),
                borderRadius: BorderRadius.circular(16)),
              alignment: Alignment.center,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.fullscreen, color: Colors.white, size: 22),
                  SizedBox(width: 10),
                  Text('Show Fullscreen QR', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 17,
                    fontWeight: FontWeight.w700, color: Colors.white)),
                ]))),
          const SizedBox(height: 8),
          // Copy link
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: _paymentUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Payment link copied!')));
            },
            child: Container(
              height: 50, width: double.infinity,
              decoration: BoxDecoration(
                color: DelightColors.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: DelightColors.surfaceBorder)),
              alignment: Alignment.center,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.link, color: DelightColors.textMuted, size: 18),
                  SizedBox(width: 8),
                  Text('Copy Payment Link', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 14,
                    fontWeight: FontWeight.w600, color: DelightColors.textSecondary)),
                ]))),
          const SizedBox(height: 32),
        ]));
  }
}

// ── Fullscreen QR ─────────────────────────────────────────────────────────────

class _FullscreenQR extends StatelessWidget {
  final String businessName;
  final _Lang lang;
  final double amount;
  final VoidCallback onExit;
  const _FullscreenQR({required this.businessName, required this.lang,
    required this.amount, required this.onExit});

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFF00C96A),
      body: GestureDetector(
        onTap: onExit,
        child: SafeArea(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: screenH * 0.85),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20)),
                        child: const Text('Tap to exit', style: TextStyle(
                          fontFamily: 'Satoshi', fontSize: 11, color: Colors.white70)))),
                    const SizedBox(height: 8),
                    Text(lang.headline, style: const TextStyle(
                      fontFamily: 'Satoshi', fontSize: 11, color: Colors.white70, letterSpacing: 2)),
                    const SizedBox(height: 4),
                    Text(businessName, style: const TextStyle(
                      fontFamily: 'Clash', fontSize: 28, fontWeight: FontWeight.w700,
                      color: Colors.white, letterSpacing: -0.8)),
                    if (amount > 0) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(30)),
                        child: Text('R${amount.toStringAsFixed(2)}', style: const TextStyle(
                          fontFamily: 'Clash', fontSize: 32, fontWeight: FontWeight.w700,
                          color: Colors.white))),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 24, offset: const Offset(0, 8))]),
                      child: Stack(alignment: Alignment.center, children: [
                        QrImageView(
                          data: _paymentUrl,
                          version: QrVersions.auto,
                          size: 190,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square, color: Color(0xFF060F0A)),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Color(0xFF060F0A))),
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00C96A),
                            borderRadius: BorderRadius.circular(8)),
                          alignment: Alignment.center,
                          child: const Text('D', style: TextStyle(
                            fontFamily: 'Clash', fontSize: 20,
                            fontWeight: FontWeight.w800, color: Colors.white))),
                      ])),
                    const SizedBox(height: 12),
                    Text(lang.instruction, textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                        color: Colors.white, height: 1.5)),
                    const SizedBox(height: 4),
                    Text(lang.footer, style: const TextStyle(
                      fontFamily: 'Satoshi', fontSize: 11, color: Colors.white54)),
                  ])))))));
  }
}

// ── Print Tab ─────────────────────────────────────────────────────────────────

class _PrintTab extends StatefulWidget {
  final TextEditingController nameCtrl;
  final _PrintSize size;
  final _Lang lang;
  final bool showLogo, showAmount, showInstructions;
  final Function(_PrintSize) onSizeChange;
  final Function(_Lang) onLangChange;
  final Function(bool) onLogoChange;
  final Function(bool) onAmountChange;
  final Function(bool) onInstructionsChange;
  final VoidCallback onNameChange;
  const _PrintTab({required this.nameCtrl, required this.size, required this.lang,
    required this.showLogo, required this.showAmount, required this.showInstructions,
    required this.onSizeChange, required this.onLangChange, required this.onLogoChange,
    required this.onAmountChange, required this.onInstructionsChange, required this.onNameChange});
  @override State<_PrintTab> createState() => _PrintTabState();
}

class _PrintTabState extends State<_PrintTab> {
  bool _showSettings = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DelightColors.goldGlow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DelightColors.gold.withOpacity(0.3))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🖨️', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                const Expanded(child: Text(
                  'Print once, accept payments all day. '
                  'Works like M-Pesa tills across Africa.',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                    color: DelightColors.textSecondary, height: 1.4))),
              ])),
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(child: Text('Preview', style: TextStyle(
              fontFamily: 'Clash', fontSize: 16, fontWeight: FontWeight.w700,
              color: DelightColors.textPrimary))),
            GestureDetector(
              onTap: () => setState(() => _showSettings = !_showSettings),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: DelightColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DelightColors.surfaceBorder)),
                child: Text(_showSettings ? 'Hide' : 'Customise',
                  style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                    color: DelightColors.textMuted)))),
          ]),
          const SizedBox(height: 12),
          Center(child: _PrintCard(
            businessName: widget.nameCtrl.text,
            size: widget.size,
            lang: widget.lang,
            showLogo: widget.showLogo,
            showAmount: widget.showAmount,
            showInstructions: widget.showInstructions)),
          if (_showSettings) ...[
            const SizedBox(height: 20),
            TextField(
              controller: widget.nameCtrl,
              onChanged: (_) => widget.onNameChange(),
              style: const TextStyle(fontFamily: 'Satoshi',
                color: DelightColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Business name',
                filled: true, fillColor: DelightColors.surfaceHigh,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: DelightColors.surfaceBorder)))),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8,
              children: _PrintSize.values.map((s) {
                final sel = s == widget.size;
                return GestureDetector(
                  onTap: () => widget.onSizeChange(s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? DelightColors.goldGlow : DelightColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: sel ? DelightColors.gold : DelightColors.surfaceBorder)),
                    child: Text(s.label, style: TextStyle(fontFamily: 'Satoshi',
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: sel ? DelightColors.gold : DelightColors.textMuted))));
              }).toList()),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8,
              children: _langs.map((l) {
                final sel = l.code == widget.lang.code;
                return GestureDetector(
                  onTap: () => widget.onLangChange(l),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: sel ? DelightColors.goldGlow : DelightColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: sel ? DelightColors.gold : DelightColors.surfaceBorder)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(l.flag, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 5),
                      Text(l.name, style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                        color: sel ? DelightColors.gold : DelightColors.textMuted)),
                    ])));
              }).toList()),
            const SizedBox(height: 12),
            _toggle('Show Delight logo', widget.showLogo, widget.onLogoChange),
            _toggle('Show any amount accepted', widget.showAmount, widget.onAmountChange),
            _toggle('Show instructions', widget.showInstructions, widget.onInstructionsChange),
          ],
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Generating PDF...')));
              try {
                final pdf = pw.Document();
                final name = widget.nameCtrl.text.isEmpty ? 'My Business' : widget.nameCtrl.text;
                pdf.addPage(pw.Page(
                  pageFormat: PdfPageFormat.a4,
                  build: (ctx) => pw.Center(child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text(name, style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 24),
                      pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: _paymentUrl, width: 220, height: 220),
                      pw.SizedBox(height: 16),
                      pw.Text('Scan to pay with Delight', style: const pw.TextStyle(fontSize: 14)),
                      pw.Text('delight.africa', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600)),
                    ]))));
                Directory saveDir;
                try {
                  final ext = await getExternalStorageDirectory();
                  saveDir = Directory(ext!.path + '/Downloads');
                  if (!await saveDir.exists()) await saveDir.create(recursive: true);
                } catch (_) { saveDir = await getApplicationDocumentsDirectory(); }
                final file = File(saveDir.path + '/delight_qr_' + DateTime.now().millisecondsSinceEpoch.toString() + '.pdf');
                await file.writeAsBytes(await pdf.save());
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Saved to Downloads'),
                  backgroundColor: DelightColors.emerald,
                  action: SnackBarAction(label: 'Print', textColor: Colors.white,
                    onPressed: () => Printing.layoutPdf(onLayout: (_) => file.readAsBytes()))));
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: ' + e.toString()), backgroundColor: Colors.red));
              }
            },
            child: Container(
              height: 56, width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: DelightColors.goldGradient),
                borderRadius: BorderRadius.circular(16)),
              alignment: Alignment.center,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.print_outlined, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text('Print or Save PDF', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 17,
                    fontWeight: FontWeight.w700, color: Colors.white)),
                ]))),
          const SizedBox(height: 32),
        ]));
  }

  Widget _toggle(String label, bool val, Function(bool) onChange) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(
          fontFamily: 'Satoshi', fontSize: 13, color: DelightColors.textPrimary))),
        Switch(value: val, onChanged: onChange, activeColor: DelightColors.emerald),
      ]));
  }
}

// ── Shared QR card widget ─────────────────────────────────────────────────────

class _QRCard extends StatelessWidget {
  final String businessName;
  final _Lang lang;
  final double amount;
  final bool compact;
  final bool showTapHint;
  const _QRCard({required this.businessName, required this.lang,
    required this.amount, required this.compact, this.showTapHint = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 220 : 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 12 : 18),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.15),
          blurRadius: 24, offset: const Offset(0, 8))]),
      child: Column(children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 20, vertical: compact ? 12 : 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00C96A), Color(0xFF00854A)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(compact ? 12 : 18))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(lang.headline, style: TextStyle(
              fontFamily: 'Clash', fontSize: compact ? 11 : 14,
              fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 1.5)),
            const SizedBox(height: 2),
            Text(businessName, style: TextStyle(
              fontFamily: 'Clash', fontSize: compact ? 18 : 24,
              fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.5)),
            if (amount > 0) ...[
              const SizedBox(height: 4),
              Text('R${amount.toStringAsFixed(2)}', style: const TextStyle(
                fontFamily: 'Clash', fontSize: 18,
                fontWeight: FontWeight.w700, color: Colors.white70)),
            ],
          ])),
        Padding(
          padding: EdgeInsets.all(compact ? 14 : 20),
          child: Column(children: [
            Container(
              padding: EdgeInsets.all(compact ? 8 : 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00C96A), width: 2)),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  QrImageView(
                    data: _paymentUrl,
                    version: QrVersions.auto,
                    size: compact ? 120 : 180,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square, color: Color(0xFF060F0A)),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF060F0A))),
                  Container(
                    width: compact ? 28 : 36, height: compact ? 28 : 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C96A),
                      borderRadius: BorderRadius.circular(compact ? 6 : 8)),
                    alignment: Alignment.center,
                    child: Text('D', style: TextStyle(
                      fontFamily: 'Clash', fontSize: compact ? 14 : 18,
                      fontWeight: FontWeight.w800, color: Colors.white))),
                ])),
            SizedBox(height: compact ? 8 : 12),
            Text(lang.instruction, textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Satoshi',
                fontSize: compact ? 9 : 11,
                color: const Color(0xFF555555), height: 1.4)),
            SizedBox(height: compact ? 6 : 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5EE),
                borderRadius: BorderRadius.circular(20)),
              child: Text('Any amount accepted', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: compact ? 9 : 11,
                fontWeight: FontWeight.w700, color: const Color(0xFF00854A)))),
            SizedBox(height: compact ? 6 : 10),
            if (showTapHint)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FFF7),
                  borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                  Icon(Icons.fullscreen, color: Color(0xFF00854A), size: 16),
                  SizedBox(width: 6),
                  Text('Tap for fullscreen', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 12,
                    color: Color(0xFF00854A), fontWeight: FontWeight.w600)),
                ])),
          ])),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: compact ? 8 : 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(compact ? 12 : 18))),
          child: Text(lang.footer, textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Satoshi',
              fontSize: compact ? 7 : 9, color: const Color(0xFF999999)))),
      ]));
  }
}

// ── Print card ────────────────────────────────────────────────────────────────

class _PrintCard extends StatelessWidget {
  final String businessName;
  final _PrintSize size;
  final _Lang lang;
  final bool showLogo, showAmount, showInstructions;
  const _PrintCard({required this.businessName, required this.size, required this.lang,
    required this.showLogo, required this.showAmount, required this.showInstructions});

  @override
  Widget build(BuildContext context) {
    return _QRCard(
      businessName: businessName,
      lang: lang,
      amount: 0,
      compact: size == _PrintSize.receipt || size == _PrintSize.sticker);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MENU TAB — add items, generate item QRs, print item QR sheet
// Payment ALWAYS works without a menu. This is optional.
// ═══════════════════════════════════════════════════════════════════════════════


// ── Menu Tab ──────────────────────────────────────────────────────────────────
//
// Optional. Payment always works without this.
// Owner adds items when ready — no setup required to start accepting payments.
// Items show as quick-tap shortcuts on the Phone tab.
// Each item can generate its own printable QR code.

class _MenuTab extends StatefulWidget {
  final List<MenuItem> items;
  final Function(MenuItem) onAdd;
  final VoidCallback onUpdate;
  final Function(String) onDelete;

  const _MenuTab({super.key,
    required this.items,
    required this.onAdd,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  State<_MenuTab> createState() => _MenuTabState();
}

class _MenuTabState extends State<_MenuTab> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── "Always works" banner ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DelightColors.emeraldGlow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Text('✅', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Expanded(child: Text('Payment always works without a menu',
                style: TextStyle(fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                  fontSize: 13, color: DelightColors.emerald))),
            ]),
            const SizedBox(height: 6),
            const Text(
              'Your QR code accepts any amount right now — no setup needed. '
              'Adding items is optional. When you do, they appear as quick-tap '
              'shortcuts and each item gets its own QR code customers can scan directly.',
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                color: DelightColors.textSecondary, height: 1.5)),
          ])),
        const SizedBox(height: 20),

        // ── Add item button ───────────────────────────────────────────────
        Row(children: [
          const Expanded(child: Text('Menu Items', style: TextStyle(
            fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary))),
          GestureDetector(
            onTap: () => _showAddItem(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: DelightColors.emeraldGradient),
                borderRadius: BorderRadius.circular(10)),
              child: const Row(children: [
                Icon(Icons.add, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text('Add Item', style: TextStyle(fontFamily: 'Satoshi',
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: Colors.white)),
              ]))),
        ]),
        const SizedBox(height: 6),
        Text(
          widget.items.isEmpty
            ? 'No items yet — your QR still works perfectly.'
            : '${widget.items.length} item${widget.items.length == 1 ? "" : "s"} · tap any to edit or generate item QR',
          style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
            color: DelightColors.textMuted)),
        const SizedBox(height: 14),

        // ── Empty state ───────────────────────────────────────────────────
        if (widget.items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: DelightColors.surfaceHigh,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: DelightColors.surfaceBorder)),
            child: Column(children: [
              const Text('🛒', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              const Text('Add your first item', style: TextStyle(
                fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary)),
              const SizedBox(height: 8),
              const Text(
                'Customers can scan the item QR directly\n'
                'without you touching your phone.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                  color: DelightColors.textMuted, height: 1.5)),
              const SizedBox(height: 20),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showAddItem(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: DelightColors.emeraldGradient),
                      borderRadius: BorderRadius.circular(12)),
                    child: const Text('Add First Item', style: TextStyle(
                      fontFamily: 'Satoshi', fontSize: 14,
                      fontWeight: FontWeight.w700, color: Colors.white))))),
            ])),

        // ── Item list ─────────────────────────────────────────────────────
        ...widget.items.asMap().entries.map((e) {
          final i = e.key;
          final item = e.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DelightColors.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: item.available
                  ? DelightColors.surfaceBorder
                  : DelightColors.surfaceBorder.withOpacity(0.4))),
            child: Row(children: [
              // Emoji + rank
              Stack(children: [
                Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(
                    color: item.available
                      ? DelightColors.emeraldGlow
                      : DelightColors.surfaceBorder,
                    borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: Text(item.emoji,
                    style: TextStyle(
                      fontSize: 26,
                      color: item.available ? null : Colors.grey))),
                if (!item.available)
                  Positioned.fill(child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.center,
                    child: const Text('OFF', style: TextStyle(
                      fontFamily: 'Satoshi', fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: Colors.white, letterSpacing: 0.5)))),
              ]),
              const SizedBox(width: 12),

              // Name + category + price
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                  fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: item.available
                    ? DelightColors.textPrimary
                    : DelightColors.textMuted)),
                Row(children: [
                  if (item.category.isNotEmpty)
                    Flexible(child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: DelightColors.surfaceBorder,
                        borderRadius: BorderRadius.circular(4)),
                      child: Text(item.category, maxLines: 1,
                        overflow: TextOverflow.ellipsis, style: const TextStyle(
                        fontFamily: 'Satoshi', fontSize: 9,
                        color: DelightColors.textMuted)))),
                  Text('R${item.price.toStringAsFixed(0)}',
                    style: const TextStyle(fontFamily: 'Clash', fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: DelightColors.emerald)),
                ]),
              ])),

              // Actions
              Column(children: [
                // Available toggle
                GestureDetector(
                  onTap: () {
                    setState(() => item.available = !item.available);
                    widget.onUpdate();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: item.available
                        ? DelightColors.emeraldGlow
                        : DelightColors.surfaceBorder,
                      borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      item.available ? 'ON' : 'OFF',
                      style: TextStyle(fontFamily: 'Satoshi', fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: item.available
                          ? DelightColors.emerald
                          : DelightColors.textMuted,
                        letterSpacing: 0.5)))),
                const SizedBox(height: 6),
                Row(children: [
                  // QR button
                  GestureDetector(
                    onTap: () => _showItemQR(context, item),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: DelightColors.goldGlow,
                        borderRadius: BorderRadius.circular(7)),
                      child: const Icon(Icons.qr_code,
                        color: DelightColors.gold, size: 14))),
                  const SizedBox(width: 6),
                  // Edit button
                  GestureDetector(
                    onTap: () => _showEditItem(context, item),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: DelightColors.surfaceBorder,
                        borderRadius: BorderRadius.circular(7)),
                      child: const Icon(Icons.edit_outlined,
                        color: DelightColors.textMuted, size: 14))),
                  const SizedBox(width: 6),
                  // Delete
                  GestureDetector(
                    onTap: () => _confirmDelete(context, item),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: DelightColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(7)),
                      child: Icon(Icons.delete_outline,
                        color: DelightColors.error.withOpacity(0.7), size: 14))),
                ]),
              ]),
            ]));
        }),

        // ── Print all QRs button (only if items exist) ────────────────────
        if (widget.items.isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _printAllQRs(context),
            child: Container(
              height: 52, width: double.infinity,
              decoration: BoxDecoration(
                color: DelightColors.goldGlow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: DelightColors.gold.withOpacity(0.4))),
              alignment: Alignment.center,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.print_outlined, color: DelightColors.gold, size: 18),
                  SizedBox(width: 8),
                  Text('Print All Item QR Codes', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 14,
                    fontWeight: FontWeight.w700, color: DelightColors.gold)),
                ]))),
          const SizedBox(height: 8),
          const Text(
            'One page per item. Print, laminate, place next to each product. '
            'Customer scans → pays → done. No owner involvement.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
              color: DelightColors.textMuted, height: 1.4)),
        ],

        const SizedBox(height: 32),
      ]));
  }

  // ── Add item sheet ────────────────────────────────────────────────────────

  void _showAddItem(BuildContext context) {
    _showItemSheet(context, null);
  }

  void _showEditItem(BuildContext context, MenuItem item) {
    _showItemSheet(context, item);
  }

  void _showItemSheet(BuildContext context, MenuItem? existing) {
    final nameCtrl  = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(
      text: existing != null ? existing.price.toStringAsFixed(0) : '');
    final categoryCtrl = TextEditingController(text: existing?.category ?? '');
    String emoji    = existing?.emoji ?? '🛒';
    final emojis    = ['🛒','🍚','🍗','🥩','🌭','🍕','🥗','🍜','🌮','🍱',
                       '🍺','🥤','🍹','🧃','☕','🥛',
                       '👕','👗','👟','🧢','👜','💍',
                       '🎟','🎁','📸','🌿','🍰','🎵'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [

            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: DelightColors.surfaceBorder,
                borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),

            Text(existing == null ? 'Add Menu Item' : 'Edit Item',
              style: const TextStyle(fontFamily: 'Clash', fontSize: 20,
                fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
            const SizedBox(height: 20),

            // Emoji picker
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: emojis.map((e) => GestureDetector(
                onTap: () => setModal(() => emoji = e),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 44, height: 44,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: emoji == e
                      ? DelightColors.emeraldGlow
                      : DelightColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: emoji == e
                        ? DelightColors.emerald
                        : DelightColors.surfaceBorder,
                      width: emoji == e ? 1.5 : 1)),
                  alignment: Alignment.center,
                  child: Text(e, style: const TextStyle(fontSize: 22)))
                )).toList())),
            const SizedBox(height: 16),

            // Name field
            TextField(
              controller: nameCtrl,
              style: const TextStyle(fontFamily: 'Satoshi',
                color: DelightColors.textPrimary, fontSize: 15),
              decoration: InputDecoration(
                labelText: 'Item name',
                labelStyle: const TextStyle(fontFamily: 'Satoshi',
                  color: DelightColors.textMuted),
                prefixIcon: const Icon(Icons.label_outline,
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
                  borderSide: const BorderSide(color: DelightColors.emerald)))),
            const SizedBox(height: 10),

            // Price field
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontFamily: 'Clash',
                color: DelightColors.textPrimary, fontSize: 24,
                fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                labelText: 'Price (Rands)',
                labelStyle: const TextStyle(fontFamily: 'Satoshi',
                  color: DelightColors.textMuted, fontSize: 13),
                prefixText: 'R ',
                prefixStyle: const TextStyle(fontFamily: 'Clash', fontSize: 24,
                  fontWeight: FontWeight.w700, color: DelightColors.gold),
                filled: true, fillColor: DelightColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: DelightColors.gold)))),
            const SizedBox(height: 10),

            // Category field
            TextField(
              controller: categoryCtrl,
              style: const TextStyle(fontFamily: 'Satoshi',
                color: DelightColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Category (optional — e.g. Mains, Drinks)',
                labelStyle: const TextStyle(fontFamily: 'Satoshi',
                  color: DelightColors.textMuted, fontSize: 12),
                prefixIcon: const Icon(Icons.category_outlined,
                  color: DelightColors.textMuted, size: 18),
                filled: true, fillColor: DelightColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: DelightColors.surfaceBorder)))),
            const SizedBox(height: 20),

            // Save button
            GestureDetector(
              onTap: () {
                final name  = nameCtrl.text.trim();
                final price = double.tryParse(priceCtrl.text);
                if (name.isEmpty) return;
                if (price == null || price <= 0) return;

                if (existing == null) {
                  widget.onAdd(MenuItem(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: name,
                    emoji: emoji,
                    category: categoryCtrl.text.trim(),
                    price: price));
                } else {
                  existing.name     = name;
                  existing.emoji    = emoji;
                  existing.price    = price;
                  existing.category = categoryCtrl.text.trim();
                  widget.onUpdate();
                }
                Navigator.pop(context);
              },
              child: Container(
                height: 54, width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: DelightColors.emeraldGradient),
                  borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: Text(
                  existing == null ? 'Add to Menu' : 'Save Changes',
                  style: const TextStyle(fontFamily: 'Satoshi', fontSize: 16,
                    fontWeight: FontWeight.w700, color: Colors.white)))),
          ]))));
  }

  // ── Item QR sheet ─────────────────────────────────────────────────────────

  void _showItemQR(BuildContext context, MenuItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [

          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: DelightColors.surfaceBorder,
              borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),

          Row(children: [
            Text(item.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, style: const TextStyle(fontFamily: 'Clash',
                fontSize: 20, fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary)),
              Text('R${item.price.toStringAsFixed(0)}',
                style: const TextStyle(fontFamily: 'Clash', fontSize: 16,
                  fontWeight: FontWeight.w700, color: DelightColors.emerald)),
            ])),
          ]),
          const SizedBox(height: 20),

          // QR card — white background, customer scans this
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(
                color: DelightColors.emerald.withOpacity(0.2),
                blurRadius: 24, offset: const Offset(0, 8))]),
            child: Column(children: [
              QrImageView(
                data: item.itemUrl,
                version: QrVersions.auto,
                size: 180,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF060F0A)),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF060F0A))),
              const SizedBox(height: 12),
              Text(item.emoji, style: const TextStyle(fontSize: 28)),
              Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Clash',
                fontSize: 16, fontWeight: FontWeight.w700,
                color: Color(0xFF060F0A))),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C96A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20)),
                child: Text('R${item.price.toStringAsFixed(0)}',
                  style: const TextStyle(fontFamily: 'Clash', fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF00854A)))),
              const SizedBox(height: 8),
              const Text('Scan to pay instantly',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                  color: Color(0xFF666666))),
            ])),
          const SizedBox(height: 16),

          const Text(
            'Print this and place it next to the item.\n'
            'Customer scans, amount is pre-filled, they tap pay.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
              color: DelightColors.textMuted, height: 1.5)),
          const SizedBox(height: 16),

          // Share options
          Row(children: [
            _shareBtn('💬', 'WhatsApp', DelightColors.emerald,
              () => _share(context, 'WhatsApp')),
            const SizedBox(width: 8),
            _shareBtn('🖨', 'Print', DelightColors.gold,
              () => _share(context, 'Print')),
            const SizedBox(width: 8),
            _shareBtn('💾', 'Save', DelightColors.blue,
              () => _share(context, 'Save')),
          ]),
        ])));
  }

  void _share(BuildContext context, String method) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$method — generating QR...')));
  }

  Widget _shareBtn(String emoji, String label, Color color,
      VoidCallback onTap) {
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3))),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontFamily: 'Satoshi', fontSize: 10,
            fontWeight: FontWeight.w700, color: color)),
        ]))));
  }

  void _confirmDelete(BuildContext context, MenuItem item) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: DelightColors.surfaceHigh,
        title: Text('Remove ${item.name}?', style: const TextStyle(
          fontFamily: 'Clash', fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        content: const Text('This removes it from quick-tap shortcuts. '
          'Your QR code still works.',
          style: TextStyle(fontFamily: 'Satoshi',
            color: DelightColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(
              fontFamily: 'Satoshi', color: DelightColors.textMuted))),
          TextButton(
            onPressed: () {
              widget.onDelete(item.id);
              Navigator.pop(context);
            },
            child: const Text('Remove', style: TextStyle(
              fontFamily: 'Satoshi', color: DelightColors.error,
              fontWeight: FontWeight.w700))),
        ]));
  }

  void _printAllQRs(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Generating ${widget.items.length} QR codes — '
          'one per item, ready to print and laminate.'),
        backgroundColor: DelightColors.gold));
  }
}