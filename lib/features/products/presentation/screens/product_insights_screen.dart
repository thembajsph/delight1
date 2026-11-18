// lib/features/products/presentation/screens/product_insights_screen.dart
//
// PRODUCTS — catalogue, product-level sales insights, AI recommendations.
//
//  • ProductCatalogScreen         — a business lists what it sells + prices.
//  • BusinessProductInsightsScreen — what is selling, what isn't, when, and
//                                    how it compares (owner's own data only).
//  • EventProductsTab              — organiser's cross-stall product view.
//  • AiReportCard                  — Claude-written recommendations built from
//                                    the AGGREGATED numbers (see ai_insights).
//
// Sales are only itemised when a customer pays with items selected (prices are
// read from the catalogue server-side). Nothing here is simulated.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/xrpl_service.dart';

const kProductCategories = [
  'Food', 'Drinks', 'Merchandise', 'VIP Services', 'Entertainment', 'Other',
];

double _n(dynamic v) => (v as num?)?.toDouble() ?? 0;
int _k(dynamic v) => (v as num?)?.toInt() ?? 0;
String _hh(int h) => '${h.toString().padLeft(2, '0')}:00';
String _zar(double v) => DelightCurrency.formatZAR(v);

TextStyle _h2() => const TextStyle(fontFamily: 'Clash', fontSize: 18,
  fontWeight: FontWeight.w700, color: DelightColors.textPrimary);
TextStyle _muted(double s) => TextStyle(fontFamily: 'Satoshi', fontSize: s,
  color: DelightColors.textMuted);

Color _catColor(String c) {
  switch (c) {
    case 'Food':          return const Color(0xFFFF6B35);
    case 'Drinks':        return DelightColors.blue;
    case 'Merchandise':   return DelightColors.emerald;
    case 'VIP Services':  return DelightColors.gold;
    case 'Entertainment': return const Color(0xFFBF5FFF);
    default:              return DelightColors.textMuted;
  }
}

Widget _card({required Widget child, Color? border}) => Container(
  margin: const EdgeInsets.only(bottom: 10),
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: DelightColors.surfaceHigh,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: border ?? DelightColors.surfaceBorder)),
  child: child);

class _Msg extends StatelessWidget {
  final String emoji, text;
  final String? action;
  final VoidCallback? onAction;
  const _Msg(this.emoji, this.text, {this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 44)),
      const SizedBox(height: 12),
      Text(text, textAlign: TextAlign.center, style: const TextStyle(
        fontFamily: 'Satoshi', fontSize: 14, height: 1.5,
        color: DelightColors.textMuted)),
      if (action != null) ...[
        const SizedBox(height: 12),
        FilledButton(onPressed: onAction, child: Text(action!)),
      ],
    ])));
}

// ═══════════════════════════════════════════════════════════════════════════════
// AI REPORT CARD
// ═══════════════════════════════════════════════════════════════════════════════

class AiReportCard extends StatefulWidget {
  final String scope;          // 'business' | 'event' | 'platform'
  final String? eventId;
  final int days;
  const AiReportCard({super.key, required this.scope, this.eventId, this.days = 30});
  @override
  State<AiReportCard> createState() => _AiReportCardState();
}

class _AiReportCardState extends State<AiReportCard> {
  Map<String, dynamic>? _report;
  bool _busy = false, _loaded = false;
  String? _error;

  @override
  void initState() { super.initState(); _loadLatest(); }

  @override
  void didUpdateWidget(covariant AiReportCard old) {
    super.didUpdateWidget(old);
    if (old.eventId != widget.eventId || old.scope != widget.scope) {
      _report = null; _error = null; _loaded = false; _loadLatest();
    }
  }

  Future<void> _loadLatest() async {
    final r = await SupabaseService.getLatestAiReport(
      scope: widget.scope, eventId: widget.eventId);
    if (!mounted) return;
    setState(() { _report = r; _loaded = true; });
  }

  Future<void> _generate({bool force = false}) async {
    setState(() { _busy = true; _error = null; });
    try {
      final r = await SupabaseService.generateAiReport(
        scope: widget.scope, eventId: widget.eventId,
        days: widget.days, force: force);
      if (!mounted) return;
      setState(() { _report = r; _busy = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  Color _impact(String i) => i == 'high' ? DelightColors.gold
    : i == 'low' ? DelightColors.textMuted : DelightColors.emerald;

  @override
  Widget build(BuildContext context) {
    final recs = List<Map<String, dynamic>>.from(
      ((_report?['recommendations'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map)));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          const Color(0xFFBF5FFF).withOpacity(0.12),
          DelightColors.surfaceHigh]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBF5FFF).withOpacity(0.35))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('✨', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(child: Text('AI recommendations', style: _h2())),
          if (_busy)
            const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          else
            TextButton(
              onPressed: _loaded ? () => _generate(force: _report != null) : null,
              child: Text(_report == null ? 'Generate' : 'Refresh')),
        ]),
        if (_report == null && _error == null && _loaded && !_busy)
          Text('Get plain-language advice written from your real sales numbers.',
            style: _muted(12)),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, style: const TextStyle(fontFamily: 'Satoshi',
              fontSize: 12, color: DelightColors.error, height: 1.4))),
        if (_report != null) ...[
          const SizedBox(height: 8),
          Text('${_report!['summary']}', style: const TextStyle(
            fontFamily: 'Satoshi', fontSize: 13, height: 1.5,
            color: DelightColors.textSecondary)),
          const SizedBox(height: 12),
          ...recs.map((r) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _impact('${r['impact']}').withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _impact('${r['impact']}').withOpacity(0.3))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${r['title']}', style: const TextStyle(
                  fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                  fontSize: 13, color: DelightColors.textPrimary))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: _impact('${r['impact']}').withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6)),
                  child: Text('${r['impact']}'.toUpperCase(), style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: _impact('${r['impact']}')))),
              ]),
              const SizedBox(height: 4),
              Text('${r['detail']}', style: _muted(12).copyWith(height: 1.4)),
            ]))),
          Text('AI-generated from aggregated sales data — no customer details '
            'are shared with the AI. Treat as guidance, not guarantees.',
            style: _muted(10)),
        ],
      ]));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRODUCT CATALOGUE (business owner)
// ═══════════════════════════════════════════════════════════════════════════════

class ProductCatalogScreen extends ConsumerStatefulWidget {
  const ProductCatalogScreen({super.key});
  @override
  ConsumerState<ProductCatalogScreen> createState() => _CatalogState();
}

class _CatalogState extends ConsumerState<ProductCatalogScreen> {
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _vendors = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await Future.wait([
      SupabaseService.getMyProducts(), SupabaseService.getMyVendors()]);
    if (!mounted) return;
    setState(() { _products = r[0]; _vendors = r[1]; _loading = false; });
  }

  Future<void> _edit([Map<String, dynamic>? p]) async {
    final name = TextEditingController(text: p?['name'] as String? ?? '');
    final price = TextEditingController(
      text: p == null ? '' : _n(p['price_zar']).toStringAsFixed(2));
    String category = p?['category'] as String? ?? 'Other';
    String? vendorId = p?['vendor_id'] as String?;
    bool active = p?['active'] as bool? ?? true;
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        backgroundColor: DelightColors.surfaceHigh,
        title: Text(p == null ? 'Add product' : 'Edit product'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, maxLength: 80,
            decoration: const InputDecoration(labelText: 'Name')),
          TextField(controller: price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Price (R)')),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: kProductCategories.map((c) =>
              DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setD(() => category = v ?? 'Other')),
          if (_vendors.isNotEmpty)
            DropdownButtonFormField<String?>(
              value: vendorId,
              decoration: const InputDecoration(labelText: 'Sold at (optional)'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null, child: Text('Everywhere')),
                ..._vendors.map((v) => DropdownMenuItem<String?>(
                  value: v['id'] as String,
                  child: Text('${v['name']}'))),
              ],
              onChanged: (v) => setD(() => vendorId = v)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero, value: active,
            title: const Text('Available to sell'),
            onChanged: (v) => setD(() => active = v)),
          if (error != null)
            Text(error!, style: const TextStyle(color: DelightColors.error)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final pr = double.tryParse(price.text.trim().replaceAll(',', '.'));
              if (name.text.trim().isEmpty || pr == null || pr < 0) {
                setD(() => error = 'Enter a name and a valid price');
                return;
              }
              try {
                await SupabaseService.saveProduct(
                  id: p?['id'] as String?, name: name.text, category: category,
                  priceZar: pr, vendorId: vendorId, active: active);
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                setD(() => error = e.toString().replaceFirst('Exception: ', ''));
              }
            },
            child: const Text('Save')),
        ])));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DelightColors.background,
      appBar: AppBar(
        backgroundColor: DelightColors.background,
        title: const Text('My Products', style: TextStyle(fontFamily: 'Clash',
          fontSize: 20, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary))),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: DelightColors.emerald,
        onPressed: () => _edit(),
        icon: const Icon(Icons.add, color: DelightColors.textInverse),
        label: const Text('Add product',
          style: TextStyle(color: DelightColors.textInverse))),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: DelightColors.emerald))
        : _products.isEmpty
          ? _Msg('🛍', 'Add what you sell and its price.\n\nCustomers then pay '
              'by choosing items, and Delight shows you exactly what sells, '
              'when, and what to stock more of.',
              action: 'Add your first product', onAction: () => _edit())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: _products.map((p) => _card(
                child: InkWell(
                  onTap: () => _edit(p),
                  child: Row(children: [
                    Container(width: 8, height: 36, decoration: BoxDecoration(
                      color: _catColor('${p['category']}'),
                      borderRadius: BorderRadius.circular(4))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${p['name']}', style: TextStyle(
                        fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: p['active'] == true
                          ? DelightColors.textPrimary : DelightColors.textMuted)),
                      Text('${p['category']}${p['active'] == true ? '' : ' · hidden'}',
                        style: _muted(11)),
                    ])),
                    Text(_zar(_n(p['price_zar'])), style: const TextStyle(
                      fontFamily: 'Clash', fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: DelightColors.textPrimary)),
                  ])))).toList()),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BUSINESS PRODUCT INSIGHTS (owner's own data)
// ═══════════════════════════════════════════════════════════════════════════════

class BusinessProductInsightsScreen extends ConsumerStatefulWidget {
  const BusinessProductInsightsScreen({super.key});
  @override
  ConsumerState<BusinessProductInsightsScreen> createState() => _BizInsightsState();
}

class _BizInsightsState extends ConsumerState<BusinessProductInsightsScreen> {
  int _days = 30;
  Map<String, dynamic>? _d;
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await SupabaseService.getBusinessProductInsights(days: _days);
      if (!mounted) return;
      setState(() { _d = d; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _list(String k) => List<Map<String, dynamic>>.from(
    ((_d?[k] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DelightColors.background,
      appBar: AppBar(
        backgroundColor: DelightColors.background,
        title: const Text('Product Insights', style: TextStyle(
          fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'My products',
            icon: const Icon(Icons.inventory_2_outlined,
              color: DelightColors.textMuted),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ProductCatalogScreen())).then((_) => _load())),
        ]),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: DelightColors.emerald))
        : _error != null || _d == null
          ? _Msg('📡', _error ?? "Couldn't load insights.",
              action: 'Try again', onAction: _load)
          : _body(),
    );
  }

  Widget _body() {
    final d = _d!;
    final units = _k(d['units']);
    final revenue = _n(d['revenue']), prev = _n(d['prev_revenue']);
    final customers = _k(d['customers']), repeat = _k(d['repeat_customers']);
    final products = _list('products');
    final unsold = _list('unsold');
    final hours = _list('by_hour');
    final days = _list('by_weekday');
    final cats = _list('categories');
    final bench = _list('benchmark');
    final change = prev > 0 ? (revenue - prev) / prev * 100 : null;

    return RefreshIndicator(
      color: DelightColors.emerald,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [7, 30, 90].map((n) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('$n days'),
              selected: _days == n,
              onSelected: (_) { setState(() => _days = n); _load(); }))).toList()),
          const SizedBox(height: 12),

          if (units == 0) ...[
            _card(child: Column(children: [
              const Text('🧾', style: TextStyle(fontSize: 36)),
              const SizedBox(height: 8),
              Text('No itemised sales in this period yet.\n\nAdd your products, '
                'then customers pay by choosing items — every sale shows up here.',
                textAlign: TextAlign.center, style: _muted(13).copyWith(height: 1.5)),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ProductCatalogScreen())).then((_) => _load()),
                child: const Text('Manage products')),
            ])),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D2A1A), Color(0xFF0A1F14)]),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('PRODUCT REVENUE · LAST $_days DAYS', style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 10, letterSpacing: 1.5,
                  color: DelightColors.textMuted)),
                const SizedBox(height: 4),
                Text(_zar(revenue), style: const TextStyle(fontFamily: 'Clash',
                  fontSize: 36, fontWeight: FontWeight.w700,
                  color: DelightColors.textPrimary, height: 1)),
                const SizedBox(height: 6),
                Text(
                  '$units items · ${_k(d['orders'])} orders · $customers customers'
                  '${customers > 0 ? ' · ${(repeat / customers * 100).toStringAsFixed(0)}% came back' : ''}',
                  style: _muted(12)),
                if (change != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${change >= 0 ? '▲' : '▼'} ${change.abs().toStringAsFixed(1)}% vs previous $_days days',
                      style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: change >= 0
                          ? DelightColors.emerald : DelightColors.error))),
              ])),
            const SizedBox(height: 18),

            Text('Best sellers', style: _h2()),
            const SizedBox(height: 10),
            ...products.take(10).toList().asMap().entries.map((e) {
              final p = e.value;
              final u = _k(p['units']), pu = _k(p['prev_units']);
              final trend = pu > 0 ? (u - pu) / pu * 100 : null;
              final maxRev = _n(products.first['revenue']);
              return _card(child: Column(children: [
                Row(children: [
                  Text('#${e.key + 1}', style: _muted(12)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${p['name']}', style: const TextStyle(
                      fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                      fontSize: 14, color: DelightColors.textPrimary)),
                    Text('$u sold · ${p['category'] ?? 'Other'}', style: _muted(11)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(_zar(_n(p['revenue'])), style: const TextStyle(
                      fontFamily: 'Clash', fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: DelightColors.textPrimary)),
                    Text(trend == null ? 'new' :
                      '${trend >= 0 ? '▲' : '▼'} ${trend.abs().toStringAsFixed(0)}%',
                      style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: trend == null ? DelightColors.textMuted
                          : trend >= 0 ? DelightColors.emerald : DelightColors.error)),
                  ]),
                ]),
                const SizedBox(height: 8),
                ClipRRect(borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: maxRev > 0 ? _n(p['revenue']) / maxRev : 0,
                    minHeight: 4,
                    backgroundColor: DelightColors.surfaceBorder,
                    valueColor: AlwaysStoppedAnimation(
                      _catColor('${p['category']}')))),
              ]));
            }),

            if (unsold.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Not selling', style: _h2()),
              const SizedBox(height: 4),
              Text('Listed but no sales in $_days days', style: _muted(12)),
              const SizedBox(height: 10),
              _card(child: Wrap(spacing: 8, runSpacing: 8, children: unsold.map((u) =>
                Chip(label: Text('${u['name']} · ${_zar(_n(u['price_zar']))}',
                  style: const TextStyle(fontSize: 11)))).toList())),
            ],

            const SizedBox(height: 10),
            Text('When you sell', style: _h2()),
            const SizedBox(height: 10),
            _bars(hours.map((h) => MapEntry(_hh(_k(h['hour'])), _n(h['revenue']))).toList()),
            const SizedBox(height: 10),
            _bars(days.map((w) => MapEntry(
              const ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][(_k(w['dow']) - 1).clamp(0, 6)],
              _n(w['revenue']))).toList()),

            if (cats.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('By category', style: _h2()),
              const SizedBox(height: 10),
              ...cats.map((c) => _card(child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(
                  color: _catColor('${c['category']}'),
                  borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 10),
                Expanded(child: Text('${c['category']}', style: const TextStyle(
                  fontFamily: 'Satoshi', fontWeight: FontWeight.w600,
                  color: DelightColors.textPrimary))),
                Text('${_k(c['units'])} · ${_zar(_n(c['revenue']))}',
                  style: _muted(12)),
              ]))),
            ],

            if (bench.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('How you compare', style: _h2()),
              const SizedBox(height: 4),
              Text('Average price across other Delight businesses (shown only when '
                '5+ businesses sell in a category)', style: _muted(12)),
              const SizedBox(height: 10),
              ...bench.map((b) => _card(child: Row(children: [
                Expanded(child: Text('${b['category']}', style: const TextStyle(
                  fontFamily: 'Satoshi', fontWeight: FontWeight.w600,
                  color: DelightColors.textPrimary))),
                Text('avg ${_zar(_n(b['platform_avg_price']))} · '
                  '${_k(b['businesses'])} businesses', style: _muted(12)),
              ]))),
            ],
          ],

          const SizedBox(height: 18),
          if (units > 0) AiReportCard(scope: 'business', days: _days),
          const SizedBox(height: 32),
        ]),
    );
  }

  Widget _bars(List<MapEntry<String, double>> data) {
    if (data.isEmpty) return const SizedBox();
    final max = data.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    return _card(child: Column(children: data.map((e) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 44, child: Text(e.key, style: _muted(11))),
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: max > 0 ? e.value / max : 0, minHeight: 8,
            backgroundColor: DelightColors.surfaceBorder,
            valueColor: AlwaysStoppedAnimation(
              e.value == max ? DelightColors.gold : DelightColors.emerald)))),
        const SizedBox(width: 8),
        Text(_zar(e.value), style: _muted(11)),
      ]))).toList()));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT PRODUCTS TAB (organiser — all stalls at one event)
// ═══════════════════════════════════════════════════════════════════════════════

class EventProductsTab extends StatefulWidget {
  final String eventId;
  final double vendorRevenue;   // total stall spend, to show how much is itemised
  const EventProductsTab({super.key, required this.eventId, required this.vendorRevenue});
  @override
  State<EventProductsTab> createState() => _EventProductsTabState();
}

class _EventProductsTabState extends State<EventProductsTab> {
  Map<String, dynamic>? _d;
  bool _loading = true;
  String? _error;
  String _sort = 'Revenue';
  List<Map<String, dynamic>> _tips = [];

  @override
  void initState() { super.initState(); _load(); }

  @override
  void didUpdateWidget(covariant EventProductsTab old) {
    super.didUpdateWidget(old);
    if (old.eventId != widget.eventId) _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await SupabaseService.getEventProductInsights(widget.eventId);
      final tips = await SupabaseService.getMyRecommendations(eventId: widget.eventId);
      if (!mounted) return;
      setState(() { _d = d; _tips = tips; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: DelightColors.emerald));
    }
    if (_error != null || _d == null) {
      return _Msg('📡', _error ?? "Couldn't load products.",
        action: 'Try again', onAction: _load);
    }
    final products = List<Map<String, dynamic>>.from(
      ((_d!['products'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    final cats = List<Map<String, dynamic>>.from(
      ((_d!['categories'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    final itemised = _n(_d!['itemised_revenue']);

    if (products.isEmpty) {
      return const _Msg('🛒',
        'No itemised product sales at this event yet.\n\n'
        'When stalls list their products in Delight and customers pay by '
        'choosing items, you will see exactly what sold at each stall.');
    }
    products.sort((a, b) => _sort == 'Units'
      ? _n(b['units']).compareTo(_n(a['units']))
      : _n(b['revenue']).compareTo(_n(a['revenue'])));
    final coverage = widget.vendorRevenue > 0
      ? (itemised / widget.vendorRevenue * 100).clamp(0, 100) : 0.0;

    return ListView(padding: const EdgeInsets.all(16), children: [
      ..._tips.take(3).map((t) => _card(border: DelightColors.gold.withOpacity(0.4),
        child: Text('💡 From Delight: ${t['body']}', style: _muted(12).copyWith(height: 1.4)))),
      _card(child: Text(
        '${_zar(itemised)} of ${_zar(widget.vendorRevenue)} stall spend is '
        'itemised (${coverage.toStringAsFixed(0)}%). The rest was paid without '
        'choosing products.', style: _muted(12).copyWith(height: 1.4))),
      Row(children: ['Revenue', 'Units'].map((s) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(s), selected: _sort == s,
          onSelected: (_) => setState(() => _sort = s)))).toList()),
      const SizedBox(height: 10),
      if (cats.isNotEmpty) ...[
        Wrap(spacing: 8, runSpacing: 8, children: cats.map((c) => Chip(
          avatar: CircleAvatar(backgroundColor: _catColor('${c['category']}'), radius: 5),
          label: Text('${c['category']} · ${_zar(_n(c['revenue']))}',
            style: const TextStyle(fontSize: 11)))).toList()),
        const SizedBox(height: 12),
      ],
      ...products.asMap().entries.map((e) {
        final p = e.value;
        return _card(child: Row(children: [
          Text('#${e.key + 1}', style: _muted(12)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p['name']}', style: const TextStyle(fontFamily: 'Satoshi',
              fontWeight: FontWeight.w700, fontSize: 14,
              color: DelightColors.textPrimary)),
            Text('${p['stall'] ?? 'Stall'} · ${_k(p['units'])} sold · '
              'avg ${_zar(_n(p['avg_price']))}', style: _muted(11)),
          ])),
          Text(_zar(_n(p['revenue'])), style: const TextStyle(fontFamily: 'Clash',
            fontSize: 14, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary)),
        ]));
      }),
      const SizedBox(height: 12),
      AiReportCard(scope: 'event', eventId: widget.eventId),
      const SizedBox(height: 32),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PLATFORM TRENDS (admin only — the market-intelligence product)
// ═══════════════════════════════════════════════════════════════════════════════

class PlatformProductTrendsScreen extends StatefulWidget {
  const PlatformProductTrendsScreen({super.key});
  @override
  State<PlatformProductTrendsScreen> createState() => _PlatformTrendsState();
}

class _PlatformTrendsState extends State<PlatformProductTrendsScreen> {
  Map<String, dynamic>? _d;
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await SupabaseService.getPlatformProductTrends();
      if (!mounted) return;
      setState(() { _d = d; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = List<Map<String, dynamic>>.from(
      ((_d?['products'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    final cats = List<Map<String, dynamic>>.from(
      ((_d?['categories'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    return Scaffold(
      backgroundColor: DelightColors.background,
      appBar: AppBar(
        backgroundColor: DelightColors.background,
        title: const Text('Market Trends', style: TextStyle(fontFamily: 'Clash',
          fontSize: 20, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary))),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: DelightColors.emerald))
        : _error != null
          ? _Msg('📡', _error!, action: 'Try again', onAction: _load)
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text('Only groups with 3+ businesses are shown, so no single '
                'business can be identified.', style: _muted(12)),
              const SizedBox(height: 12),
              if (products.isEmpty && cats.isEmpty)
                const SizedBox(height: 300, child: _Msg('📈',
                  'Not enough cross-business data yet.'))
              else ...[
                Text('Categories', style: _h2()),
                const SizedBox(height: 10),
                ...cats.map((c) => _card(child: Row(children: [
                  Expanded(child: Text('${c['category']}', style: const TextStyle(
                    fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                    color: DelightColors.textPrimary))),
                  Text('${_k(c['businesses'])} businesses · ${_zar(_n(c['revenue']))}',
                    style: _muted(12)),
                ]))),
                const SizedBox(height: 14),
                Text('Top products', style: _h2()),
                const SizedBox(height: 10),
                ...products.take(30).map((p) {
                  final u = _k(p['units']), pu = _k(p['prev_units']);
                  final g = pu > 0 ? (u - pu) / pu * 100 : null;
                  return _card(child: Row(children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${p['name']}', style: const TextStyle(
                        fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                        color: DelightColors.textPrimary)),
                      Text('${p['category'] ?? 'Other'} · $u sold · '
                        '${_k(p['businesses'])} businesses · avg ${_zar(_n(p['avg_price']))}',
                        style: _muted(11)),
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(_zar(_n(p['revenue'])), style: const TextStyle(
                        fontFamily: 'Clash', fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DelightColors.textPrimary)),
                      Text(g == null ? 'new'
                        : '${g >= 0 ? '▲' : '▼'} ${g.abs().toStringAsFixed(0)}%',
                        style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: g == null ? DelightColors.textMuted
                            : g >= 0 ? DelightColors.emerald : DelightColors.error)),
                    ]),
                  ]));
                }),
                const SizedBox(height: 14),
                const AiReportCard(scope: 'platform'),
                const SizedBox(height: 32),
              ],
            ]),
    );
  }
}
