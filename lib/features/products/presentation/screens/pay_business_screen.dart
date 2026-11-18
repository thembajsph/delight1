// lib/features/products/presentation/screens/pay_business_screen.dart
//
// Customer side of the business QR: scan → pick items → pay.
// Prices are read from the catalogue by the database; this screen only sends
// product ids and quantities, so a tampered app cannot change what is charged.

import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/xrpl_service.dart';

class PayBusinessScreen extends StatefulWidget {
  final String ownerId;
  final String? vendorId;
  const PayBusinessScreen({super.key, required this.ownerId, this.vendorId});
  @override
  State<PayBusinessScreen> createState() => _PayBusinessState();
}

class _PayBusinessState extends State<PayBusinessScreen> {
  List<Map<String, dynamic>> _menu = [];
  final Map<String, int> _cart = {};
  String _name = 'Business';
  bool _loading = true, _paying = false, _done = false, _custom = false;
  final _amountCtrl = TextEditingController();
  String? _error;
  double _paid = 0;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _amountCtrl.dispose(); super.dispose(); }

  double? get _customAmount =>
    double.tryParse(_amountCtrl.text.trim().replaceAll(',', '.'));

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final menu = await SupabaseService.getBusinessMenu(
        widget.ownerId, vendorId: widget.vendorId);
      final prof = await SupabaseService.getProfile(widget.ownerId);
      if (!mounted) return;
      setState(() {
        _menu = menu;
        _name = (prof?['display_name'] as String?)?.trim().isNotEmpty == true
          ? prof!['display_name'] as String : 'Business';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = "Couldn't load this business."; _loading = false; });
    }
  }

  double _price(Map<String, dynamic> p) => (p['price_zar'] as num).toDouble();

  double get _total => _menu.fold(0.0,
    (s, p) => s + _price(p) * (_cart['${p['id']}'] ?? 0));
  int get _count => _cart.values.fold(0, (a, b) => a + b);

  void _change(String id, int d) => setState(() {
    final n = ((_cart[id] ?? 0) + d).clamp(0, 99);
    if (n == 0) { _cart.remove(id); } else { _cart[id] = n; }
  });

  Future<void> _pay() async {
    final items = _cart.entries
      .map((e) => {'product_id': e.key, 'qty': e.value}).toList();
    final amt = _customAmount;
    final total = _custom ? (amt ?? 0) : _total;
    setState(() { _paying = true; _error = null; });
    try {
      if (_custom) {
        if (amt == null || amt < 1) throw Exception('Enter an amount of at least R1');
        if (widget.vendorId != null) {
          await SupabaseService.payEventVendor(widget.vendorId!, amt);
        } else {
          await SupabaseService.payBusinessAmount(widget.ownerId, amt);
        }
      } else if (widget.vendorId != null) {
        await SupabaseService.payEventVendorItems(widget.vendorId!, items);
      } else {
        await SupabaseService.payBusinessItems(widget.ownerId, items);
      }
      if (!mounted) return;
      setState(() { _paid = total; _done = true; _paying = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _paying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DelightColors.background,
      appBar: AppBar(
        backgroundColor: DelightColors.background,
        title: Text(_name, style: const TextStyle(fontFamily: 'Clash',
          fontSize: 20, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary))),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: DelightColors.emerald))
        : _done ? _success() : _menuView(),
      bottomNavigationBar: (_loading || _done) ? null : SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
            color: DelightColors.surface,
            border: Border(top: BorderSide(color: DelightColors.surfaceBorder))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: const TextStyle(
                  color: DelightColors.error, fontSize: 12))),
            SizedBox(width: double.infinity, height: 50, child: FilledButton(
              onPressed: _paying ? null
                : _custom ? ((_customAmount ?? 0) >= 1 ? _pay : null)
                : (_count == 0 ? null : _pay),
              child: Text(_paying ? 'Paying…'
                : _custom ? ((_customAmount ?? 0) >= 1
                    ? 'Pay ${DelightCurrency.formatZAR(_customAmount!)}'
                    : 'Enter an amount')
                : _count == 0 ? 'Pick items to pay'
                : 'Pay ${DelightCurrency.formatZAR(_total)} · $_count item${_count == 1 ? '' : 's'}'))),
          ]))),
    );
  }

  Widget _success() => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('✅', style: TextStyle(fontSize: 64)),
      const SizedBox(height: 12),
      Text('Paid ${DelightCurrency.formatZAR(_paid)}', style: const TextStyle(
        fontFamily: 'Clash', fontSize: 26, fontWeight: FontWeight.w700,
        color: DelightColors.textPrimary)),
      const SizedBox(height: 6),
      Text('to $_name', style: const TextStyle(
        fontFamily: 'Satoshi', color: DelightColors.textMuted)),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('Done')),
    ])));

  Widget _customView() => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('Pay any amount', style: TextStyle(fontFamily: 'Clash',
      fontSize: 18, fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
    const SizedBox(height: 4),
    const Text('Use this when you are not buying listed items. It will not '
      'appear in the business\'s product insights.',
      style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
        color: DelightColors.textMuted, height: 1.4)),
    const SizedBox(height: 14),
    TextField(
      controller: _amountCtrl, autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() {}),
      style: const TextStyle(fontFamily: 'Clash', fontSize: 28,
        color: DelightColors.textPrimary),
      decoration: const InputDecoration(prefixText: 'R ', hintText: '0.00')),
  ]);

  Widget _menuView() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.shopping_bag_outlined),
              label: Text('Pick items')),
            ButtonSegment(value: true, icon: Icon(Icons.payments_outlined),
              label: Text('Any amount')),
          ],
          selected: {_custom},
          onSelectionChanged: (v) => setState(() { _custom = v.first; _error = null; }))),
      Expanded(child: _custom ? _customView() : _itemsView()),
    ]);
  }

  Widget _itemsView() {
    if (_error != null && _menu.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, style: const TextStyle(color: DelightColors.textMuted)),
        const SizedBox(height: 10),
        FilledButton(onPressed: _load, child: const Text('Try again')),
      ]));
    }
    if (_menu.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(32),
        child: Text('This business has not listed any products yet.\nUse "Any amount" to pay.',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Satoshi', color: DelightColors.textMuted,
            height: 1.5))));
    }
    return ListView(padding: const EdgeInsets.all(16), children: _menu.map((p) {
      final id = '${p['id']}';
      final q = _cart[id] ?? 0;
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: q > 0
            ? DelightColors.emerald.withOpacity(0.5) : DelightColors.surfaceBorder)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p['name']}', style: const TextStyle(fontFamily: 'Satoshi',
              fontWeight: FontWeight.w700, fontSize: 14,
              color: DelightColors.textPrimary)),
            Text('${p['category']}', style: const TextStyle(
              fontFamily: 'Satoshi', fontSize: 11,
              color: DelightColors.textMuted)),
          ])),
          Text(DelightCurrency.formatZAR(_price(p)), style: const TextStyle(
            fontFamily: 'Clash', fontSize: 15, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary)),
          const SizedBox(width: 10),
          if (q > 0) ...[
            IconButton(icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => _change(id, -1)),
            Text('$q', style: const TextStyle(fontWeight: FontWeight.w700,
              color: DelightColors.textPrimary)),
          ],
          IconButton(
            icon: const Icon(Icons.add_circle, color: DelightColors.emerald),
            onPressed: () => _change(id, 1)),
        ]));
    }).toList());
  }
}
