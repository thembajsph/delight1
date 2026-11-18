// lib/features/insights/presentation/screens/event_insights_screen.dart
//
// SALES INSIGHTS + INDOOR INSIGHTS — real data only.
//
// Everything comes from one Postgres function, get_event_insights(event_id),
// which only the event's organiser (or an admin) may call:
//   • Ticket sales            → tickets
//   • Arrivals                → gate_checkins (real gate scans)
//   • Stall / section sales   → transactions tagged with event_id + vendor_id
//                               (created by pay_event_vendor)
//   • Spend per ticket tier   → vendor payments joined to the payer's ticket
//   • Staff performance       → transactions tagged with staff_id
//
// Nothing is simulated. If an event has no tagged vendor payments yet, the
// screens say so instead of showing made-up numbers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/xrpl_service.dart';
import '../../../products/presentation/screens/product_insights_screen.dart';

// ─── Data models (parsed from get_event_insights) ────────────────────────────

double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;
int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

class _Stall {
  final String id, name, category, emoji;
  final String? sectionType;
  final double revenue, avg;
  final int txns;
  final int? peakHour;
  const _Stall({required this.id, required this.name, required this.category,
    required this.emoji, required this.sectionType, required this.revenue,
    required this.avg, required this.txns, required this.peakHour});
  factory _Stall.from(Map<String, dynamic> m) => _Stall(
    id: '${m['id']}', name: m['name'] as String? ?? 'Stall',
    category: m['category'] as String? ?? 'Other',
    emoji: m['emoji'] as String? ?? '🏪',
    sectionType: m['section_type'] as String?,
    revenue: _d(m['revenue']), avg: _d(m['avg_txn']), txns: _i(m['txns']),
    peakHour: m['peak_hour'] == null ? null : _i(m['peak_hour']));
  Color get color => _categoryColor(category);
}

class _Hour {
  final int hour, txns;
  final double foodDrink, merchandise, other;
  const _Hour({required this.hour, required this.txns, required this.foodDrink,
    required this.merchandise, required this.other});
  double get total => foodDrink + merchandise + other;
  factory _Hour.from(Map<String, dynamic> m) => _Hour(
    hour: _i(m['hour']), txns: _i(m['txns']), foodDrink: _d(m['food_drink']),
    merchandise: _d(m['merchandise']), other: _d(m['other']));
}

class _Tier {
  final String tier;
  final int tickets, holders;
  final double ticketRevenue, vendorSpend;
  const _Tier({required this.tier, required this.tickets, required this.holders,
    required this.ticketRevenue, required this.vendorSpend});
  double get avgSpend => holders > 0 ? vendorSpend / holders : 0;
  factory _Tier.from(Map<String, dynamic> m) => _Tier(
    tier: m['tier'] as String? ?? 'General', tickets: _i(m['tickets']),
    holders: _i(m['holders']), ticketRevenue: _d(m['ticket_revenue']),
    vendorSpend: _d(m['vendor_spend']));
}

class _StaffRow {
  final String name, section;
  final double revenue, avg;
  final int txns;
  const _StaffRow({required this.name, required this.section,
    required this.revenue, required this.avg, required this.txns});
  factory _StaffRow.from(Map<String, dynamic> m) => _StaffRow(
    name: m['name'] as String? ?? 'Staff', section: m['section'] as String? ?? '',
    revenue: _d(m['revenue']), avg: _d(m['avg_txn']), txns: _i(m['txns']));
}

class _Insights {
  final String eventId, eventName, venueType;
  final String? eventDate, venue, city;
  final int ticketsSold, attended, vendorTxns;
  final double ticketRevenue, vendorRevenue;
  final double? vsLastEventPct;
  final List<_Stall> stalls;
  final List<_Hour> byHour;
  final List<MapEntry<int, int>> arrivals;
  final List<_Tier> tiers;
  final List<_StaffRow> staff;

  const _Insights({required this.eventId, required this.eventName, required this.eventDate,
    required this.venue, required this.city, required this.venueType,
    required this.ticketsSold, required this.attended, required this.vendorTxns,
    required this.ticketRevenue, required this.vendorRevenue,
    required this.vsLastEventPct, required this.stalls, required this.byHour,
    required this.arrivals, required this.tiers, required this.staff});

  bool get hasSales => vendorRevenue > 0;
  double get avgPerAttendee => attended > 0 ? vendorRevenue / attended : 0;

  _Hour? get peakHour {
    if (byHour.isEmpty) return null;
    return byHour.reduce((a, b) => a.total >= b.total ? a : b);
  }

  factory _Insights.from(Map<String, dynamic> m) {
    final ev = Map<String, dynamic>.from(m['event'] as Map);
    List<Map<String, dynamic>> list(String k) => List<Map<String, dynamic>>.from(
      ((m[k] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    return _Insights(
      eventId: '${ev['id']}',
      eventName: ev['name'] as String? ?? 'Event',
      eventDate: ev['event_date'] as String?,
      venue: ev['venue'] as String?, city: ev['city'] as String?,
      venueType: ev['venue_type'] as String? ?? '',
      ticketsSold: _i(m['tickets_sold']), attended: _i(m['attended']),
      vendorTxns: _i(m['vendor_txns']),
      ticketRevenue: _d(m['ticket_revenue']), vendorRevenue: _d(m['vendor_revenue']),
      vsLastEventPct: m['vs_last_event_pct'] == null ? null : _d(m['vs_last_event_pct']),
      stalls: list('stalls').map(_Stall.from).toList(),
      byHour: list('by_hour').map(_Hour.from).toList(),
      arrivals: list('arrivals')
        .map((a) => MapEntry(_i(a['hour']), _i(a['arrivals']))).toList(),
      tiers: list('tiers').map(_Tier.from).toList(),
      staff: list('staff').map(_StaffRow.from).toList(),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

Color _categoryColor(String c) {
  switch (c) {
    case 'Food':          return const Color(0xFFFF6B35);
    case 'Drinks':        return DelightColors.blue;
    case 'Merchandise':   return DelightColors.emerald;
    case 'VIP Services':  return DelightColors.gold;
    case 'Entertainment': return const Color(0xFFBF5FFF);
    default:              return DelightColors.textMuted;
  }
}

String _hh(int h) => '${h.toString().padLeft(2, '0')}:00';

String _fmtDate(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return 'Date not set';
  const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

String _int(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

TextStyle _h2() => const TextStyle(fontFamily: 'Clash', fontSize: 18,
  fontWeight: FontWeight.w700, color: DelightColors.textPrimary);

TextStyle _muted(double size) => TextStyle(fontFamily: 'Satoshi',
  fontSize: size, color: DelightColors.textMuted);

class _Empty extends StatelessWidget {
  final String emoji, text;
  final VoidCallback? onRetry;
  const _Empty(this.emoji, this.text, {this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 44)),
      const SizedBox(height: 12),
      Text(text, textAlign: TextAlign.center,
        style: const TextStyle(fontFamily: 'Satoshi', fontSize: 14,
          height: 1.5, color: DelightColors.textMuted)),
      if (onRetry != null) ...[
        const SizedBox(height: 12),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ])));
}

/// Shown on a tab when the event has no tagged vendor payments yet.
class _NoSales extends StatelessWidget {
  const _NoSales();
  @override
  Widget build(BuildContext context) => const _Empty('🧾',
    'No vendor sales recorded for this event yet.\n\n'
    'Sales appear here once attendees pay your registered stalls through Delight '
    '(each payment is tagged to the event and stall).');
}

class _Insight {
  final String emoji, title, body, tag;
  final Color color;
  const _Insight(this.emoji, this.title, this.body, this.tag, this.color);
}

/// Observations computed from the numbers — nothing hardcoded.
List<_Insight> _derive(_Insights d) {
  final out = <_Insight>[];
  if (d.hasSales && d.stalls.isNotEmpty) {
    final top = d.stalls.first;
    final share = top.revenue / d.vendorRevenue * 100;
    out.add(_Insight(top.emoji, '${top.name} led sales',
      '${DelightCurrency.formatZAR(top.revenue)} across ${_int(top.txns)} '
      'transactions — ${share.toStringAsFixed(0)}% of all vendor spend.',
      share >= 40 ? 'Concentrated' : 'Top stall', DelightColors.gold));
    if (share >= 40 && d.stalls.length > 1) {
      out.add(_Insight('⚖️', 'Sales depend on one stall',
        '${top.name} took ${share.toStringAsFixed(0)}% of spend. If it runs out of stock '
        'or queues build, the event loses most of its revenue.',
        'Risk', DelightColors.error));
    }
  }
  final peak = d.peakHour;
  if (peak != null && d.vendorRevenue > 0) {
    out.add(_Insight('🔥', 'Spend peaked at ${_hh(peak.hour)}',
      '${DelightCurrency.formatZAR(peak.total)} was spent in that hour '
      '(${(peak.total / d.vendorRevenue * 100).toStringAsFixed(0)}% of the total).',
      'Timing', DelightColors.emerald));
  }
  final withSpend = d.tiers.where((t) => t.avgSpend > 0 && t.holders > 0).toList();
  if (withSpend.length >= 2) {
    withSpend.sort((a, b) => b.avgSpend.compareTo(a.avgSpend));
    final hi = withSpend.first, lo = withSpend.last;
    out.add(_Insight('🎟', '${hi.tier} holders spend more',
      '${hi.tier} averaged ${DelightCurrency.formatZAR(hi.avgSpend)} per person vs '
      '${DelightCurrency.formatZAR(lo.avgSpend)} for ${lo.tier} '
      '(${(hi.avgSpend / lo.avgSpend).toStringAsFixed(1)}×).',
      'Tiers', DelightColors.blue));
  }
  if (d.ticketsSold > 0 && d.attended > 0) {
    final noShow = (d.ticketsSold - d.attended) / d.ticketsSold * 100;
    if (noShow > 0) {
      out.add(_Insight('🚪', '${noShow.toStringAsFixed(0)}% did not scan in',
        '${_int(d.ticketsSold)} tickets sold, ${_int(d.attended)} scanned at the gate.',
        'Attendance', DelightColors.textMuted));
    }
  }
  return out;
}

List<Widget> _insightCards(_Insights d) {
  final items = _derive(d);
  if (items.isEmpty) {
    return [Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Text('Not enough data yet. Observations appear once the event has '
        'ticket scans and vendor payments.', style: _muted(12)))];
  }
  return items.map((r) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: r.color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: r.color.withOpacity(0.25))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(r.emoji, style: const TextStyle(fontSize: 22)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(r.title, style: const TextStyle(
            fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
            fontSize: 13, color: DelightColors.textPrimary))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: r.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6)),
            child: Text(r.tag, style: TextStyle(fontFamily: 'Satoshi',
              fontSize: 9, fontWeight: FontWeight.w700, color: r.color))),
        ]),
        const SizedBox(height: 4),
        Text(r.body, style: const TextStyle(fontFamily: 'Satoshi',
          fontSize: 12, color: DelightColors.textMuted, height: 1.4)),
      ])),
    ]))).toList();
}

Widget _kpi(String emoji, String label, String value, Color color) =>
  Expanded(child: Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: DelightColors.surfaceHigh,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: DelightColors.surfaceBorder)),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 22)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontFamily: 'Satoshi',
          fontSize: 10, color: DelightColors.textMuted, letterSpacing: 0.5)),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontFamily: 'Clash', fontSize: 16,
            fontWeight: FontWeight.w700, color: color)),
      ])),
    ])));

// ─── Shared shell: event picker + loading / empty / error handling ───────────

class _InsightsShell extends StatefulWidget {
  final String title;
  final List<String> tabs;
  final List<Widget> Function(_Insights d) pages;
  const _InsightsShell({required this.title, required this.tabs,
    required this.pages});
  @override
  State<_InsightsShell> createState() => _InsightsShellState();
}

class _InsightsShellState extends State<_InsightsShell>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _events = [];
  Map<String, dynamic>? _selected;
  _Insights? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: widget.tabs.length, vsync: this);
    _init();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _init() async {
    setState(() { _loading = true; _error = null; });
    final events = await SupabaseService.getMyEvents();
    if (!mounted) return;
    _events = events;
    if (events.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    // Newest event that has already started; otherwise the newest overall.
    final now = DateTime.now();
    _selected = events.firstWhere((e) {
      final dt = DateTime.tryParse('${e['event_date'] ?? ''}');
      return dt != null && !dt.isAfter(now);
    }, orElse: () => events.first);
    await _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final m = await SupabaseService.getEventInsights('${_selected!['id']}');
      if (!mounted) return;
      setState(() { _data = _Insights.from(m); _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _pickEvent() {
    showModalBottomSheet(
      context: context,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text('Choose event', style: _h2()),
          const SizedBox(height: 8),
          ..._events.map((e) => ListTile(
            title: Text(e['name'] as String? ?? 'Event', style: const TextStyle(
              fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
              color: DelightColors.textPrimary)),
            subtitle: Text(_fmtDate(e['event_date'] as String?), style: _muted(12)),
            trailing: e['id'] == _selected?['id']
              ? const Icon(Icons.check, color: DelightColors.emerald) : null,
            onTap: () {
              Navigator.pop(context);
              _selected = e;
              _loadData();
            })),
        ])));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      appBar: AppBar(
        backgroundColor: DelightColors.background,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: const TextStyle(
            fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary)),
          Text(_data?.eventName ?? (_selected?['name'] as String? ?? ''),
            style: _muted(11)),
        ]),
        actions: [
          if (_events.length > 1)
            IconButton(
              tooltip: 'Switch event',
              icon: const Icon(Icons.swap_horiz, color: DelightColors.textMuted),
              onPressed: _pickEvent),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: DelightColors.textMuted),
            onPressed: _selected == null ? _init : _loadData),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: DelightColors.emerald,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: DelightColors.textPrimary,
          unselectedLabelColor: DelightColors.textMuted,
          labelStyle: const TextStyle(
            fontFamily: 'Satoshi', fontWeight: FontWeight.w700, fontSize: 12),
          tabs: widget.tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(
        color: DelightColors.emerald));
    }
    if (_events.isEmpty) {
      return const _Empty('🎪',
        "You haven't created any events yet.\nInsights appear here once you have an event.");
    }
    if (_error != null || _data == null) {
      return _Empty('📡', _error ?? "Couldn't load insights.",
        onRetry: _selected == null ? _init : _loadData);
    }
    return TabBarView(controller: _tab, children: widget.pages(_data!));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SALES INSIGHTS (outdoor / festival style events with many stalls)
// ═══════════════════════════════════════════════════════════════════════════════

class EventInsightsScreen extends ConsumerWidget {
  const EventInsightsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => _InsightsShell(
    title: 'Event Insights',
    tabs: const ['📊 Overview', '🏪 Stalls', '🛒 Products', '⏱ Timeline', '🎟 By Tier'],
    pages: (d) => [
      _OverviewTab(d: d),
      _StallsTab(d: d),
      EventProductsTab(eventId: d.eventId, vendorRevenue: d.vendorRevenue),
      _TimelineTab(d: d),
      _TierTab(d: d),
    ]);
}

class _OverviewTab extends StatelessWidget {
  final _Insights d;
  const _OverviewTab({required this.d});

  @override
  Widget build(BuildContext context) {
    final past = DateTime.tryParse(d.eventDate ?? '')?.isBefore(DateTime.now()) ?? false;
    final peak = d.peakHour;
    final cat = <String, double>{};
    for (final s in d.stalls) {
      cat[s.category] = (cat[s.category] ?? 0) + s.revenue;
    }
    final cats = cat.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0D2A1A), Color(0xFF0A1F14)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text(d.eventName, style: const TextStyle(fontFamily: 'Clash',
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: DelightColors.textPrimary)),
                Text(_fmtDate(d.eventDate), style: _muted(12)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: DelightColors.emeraldGlow,
                  borderRadius: BorderRadius.circular(8)),
                child: Text(past ? 'COMPLETE' : 'UPCOMING', style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 10, fontWeight: FontWeight.w800,
                  color: DelightColors.emerald, letterSpacing: 1.5))),
            ]),
            const SizedBox(height: 20),
            Text('VENDOR SPEND AT EVENT', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 10, color: DelightColors.textMuted,
              letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Text(DelightCurrency.formatZAR(d.vendorRevenue), style: const TextStyle(
              fontFamily: 'Clash', fontSize: 42, fontWeight: FontWeight.w700,
              color: DelightColors.textPrimary, letterSpacing: -1, height: 1)),
            const SizedBox(height: 6),
            Text(
              '${_int(d.attended)} scanned in · '
              '${d.attended > 0 && d.hasSales ? '${DelightCurrency.formatZAR(d.avgPerAttendee)} avg per person' : 'no per-person average yet'}',
              style: _muted(12)),
            const SizedBox(height: 4),
            Text('${_int(d.ticketsSold)} tickets sold · '
              '${DelightCurrency.formatZAR(d.ticketRevenue)} ticket revenue',
              style: _muted(12)),
          ])),
        const SizedBox(height: 16),

        Row(children: [
          _kpi('🏆', 'Top Stall', d.stalls.isNotEmpty && d.hasSales
            ? d.stalls.first.name : '—', DelightColors.gold),
          const SizedBox(width: 10),
          _kpi('🔥', 'Peak Hour', peak == null ? '—'
            : '${_hh(peak.hour)}–${_hh((peak.hour + 1) % 24)}', DelightColors.error),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _kpi('💸', 'Avg Spend', d.attended > 0 && d.hasSales
            ? 'R${d.avgPerAttendee.toStringAsFixed(0)}' : '—', DelightColors.emerald),
          const SizedBox(width: 10),
          _kpi('📈', 'vs Last Event', d.vsLastEventPct == null ? '—'
            : '${d.vsLastEventPct! >= 0 ? '+' : ''}${d.vsLastEventPct!.toStringAsFixed(1)}%',
            (d.vsLastEventPct ?? 0) >= 0 ? DelightColors.emerald : DelightColors.error),
        ]),
        const SizedBox(height: 20),

        Text('Spend by Category', style: _h2()),
        const SizedBox(height: 12),
        if (cats.isEmpty)
          Text('No vendor sales recorded yet.', style: _muted(12))
        else
          Row(children: [
            SizedBox(
              width: 160, height: 160,
              child: PieChart(PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 48,
                sections: cats.map((e) => PieChartSectionData(
                  value: e.value, color: _categoryColor(e.key),
                  title: '', radius: 30)).toList()))),
            const SizedBox(width: 16),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: cats.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(
                    color: _categoryColor(e.key),
                    borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e.key, style: const TextStyle(
                    fontFamily: 'Satoshi', fontSize: 12,
                    color: DelightColors.textSecondary))),
                  Text('${(e.value / d.vendorRevenue * 100).toStringAsFixed(1)}%',
                    style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _categoryColor(e.key))),
                ]))).toList())),
          ]),
        const SizedBox(height: 20),

        Text('What the data says', style: _h2()),
        const SizedBox(height: 6),
        Text("Computed from this event's real tickets, gate scans and payments",
          style: _muted(12)),
        const SizedBox(height: 12),
        ..._insightCards(d),
        const SizedBox(height: 32),
      ]));
  }
}

// ─── Stalls ──────────────────────────────────────────────────────────────────

class _StallsTab extends StatefulWidget {
  final _Insights d;
  const _StallsTab({required this.d});
  @override
  State<_StallsTab> createState() => _StallsTabState();
}

class _StallsTabState extends State<_StallsTab> {
  String _sortBy = 'Revenue';
  String _category = 'All';

  List<_Stall> get _sorted {
    var list = _category == 'All'
      ? List<_Stall>.from(widget.d.stalls)
      : widget.d.stalls.where((s) => s.category == _category).toList();
    switch (_sortBy) {
      case 'Transactions': list.sort((a, b) => b.txns.compareTo(a.txns)); break;
      case 'Avg Spend':    list.sort((a, b) => b.avg.compareTo(a.avg)); break;
      default:             list.sort((a, b) => b.revenue.compareTo(a.revenue));
    }
    return list;
  }

  Widget _chip(String label, bool sel, Color active, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: sel ? active : DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: sel
            ? Colors.transparent : DelightColors.surfaceBorder)),
        child: Text(label, style: TextStyle(fontFamily: 'Satoshi',
          fontSize: 11, fontWeight: FontWeight.w600,
          color: sel ? DelightColors.textInverse : DelightColors.textMuted))));

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    if (d.stalls.isEmpty) {
      return const _Empty('🏪',
        'No stalls are registered for this event yet.\n'
        'Add vendors to the event so their sales can be tracked.');
    }
    if (!d.hasSales) return const _NoSales();

    final cats = ['All', ...{for (final s in d.stalls) s.category}];
    final sorted = _sorted;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              Text('Sort: ', style: _muted(12)),
              ...['Revenue', 'Transactions', 'Avg Spend'].map((s) =>
                _chip(s, _sortBy == s, DelightColors.emerald,
                  () => setState(() => _sortBy = s))),
            ])),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              Text('Filter: ', style: _muted(12)),
              ...cats.map((c) => _chip(c, _category == c, DelightColors.gold,
                () => setState(() => _category = c))),
            ])),
        ])),
      const SizedBox(height: 12),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: sorted.length,
        itemBuilder: (_, i) => _StallCard(
          stall: sorted[i], rank: i + 1, total: d.vendorRevenue))),
    ]);
  }
}

class _StallCard extends StatelessWidget {
  final _Stall stall;
  final int rank;
  final double total;
  const _StallCard({required this.stall, required this.rank, required this.total});

  @override
  Widget build(BuildContext context) {
    final isTop3 = rank <= 3 && stall.revenue > 0;
    final share = total > 0 ? stall.revenue / total * 100 : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isTop3
          ? DelightColors.gold.withOpacity(0.4) : DelightColors.surfaceBorder)),
      child: Column(children: [
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: isTop3 ? DelightColors.gold.withOpacity(0.15)
                : DelightColors.surfaceBorder,
              borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: Text('#$rank', style: TextStyle(
              fontFamily: 'Clash', fontSize: 13, fontWeight: FontWeight.w700,
              color: isTop3 ? DelightColors.gold : DelightColors.textMuted))),
          const SizedBox(width: 10),
          Text(stall.emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(stall.name, style: const TextStyle(fontFamily: 'Satoshi',
              fontWeight: FontWeight.w700, fontSize: 14,
              color: DelightColors.textPrimary)),
            Text(stall.category, style: _muted(11)),
          ])),
          Text(DelightCurrency.formatZAR(stall.revenue), style: const TextStyle(
            fontFamily: 'Clash', fontSize: 16, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _stat('Transactions', _int(stall.txns)),
          _vDivider(),
          _stat('Avg Spend', DelightCurrency.formatZAR(stall.avg)),
          _vDivider(),
          _stat('Peak Hour', stall.peakHour == null ? '—' : _hh(stall.peakHour!)),
          _vDivider(),
          _stat('Share', '${share.toStringAsFixed(1)}%'),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (share / 100).clamp(0.0, 1.0),
            backgroundColor: DelightColors.surfaceBorder,
            valueColor: AlwaysStoppedAnimation(
              isTop3 ? DelightColors.gold : DelightColors.emerald),
            minHeight: 4)),
      ]));
  }

  Widget _stat(String label, String value) => Expanded(
    child: Column(children: [
      Text(value, style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
        fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
      Text(label, style: _muted(9)),
    ]));

  Widget _vDivider() => Container(
    width: 1, height: 28, color: DelightColors.surfaceBorder,
    margin: const EdgeInsets.symmetric(horizontal: 4));
}

// ─── Timeline ────────────────────────────────────────────────────────────────

class _TimelineTab extends StatelessWidget {
  final _Insights d;
  const _TimelineTab({required this.d});

  @override
  Widget build(BuildContext context) {
    final hours = d.byHour;
    final maxTotal = hours.isEmpty
      ? 0.0 : hours.map((h) => h.total).reduce((a, b) => a > b ? a : b);
    final maxArr = d.arrivals.isEmpty
      ? 0 : d.arrivals.map((a) => a.value).reduce((a, b) => a > b ? a : b);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Spend by Hour', style: _h2()),
        const SizedBox(height: 4),
        Text('Total ZAR spent at all stalls each hour of the event',
          style: _muted(12)),
        const SizedBox(height: 16),

        if (hours.isEmpty || maxTotal <= 0)
          Text('No vendor sales recorded yet.', style: _muted(12))
        else ...[
          SizedBox(
            height: 220,
            child: BarChart(BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxTotal * 1.2,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final h = hours[group.x];
                    return BarTooltipItem(
                      '${_hh(h.hour)}\n${DelightCurrency.formatZAR(rod.toY)}',
                      const TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                        color: Colors.white, fontWeight: FontWeight.w600));
                  })),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 22,
                  getTitlesWidget: (val, _) {
                    final i = val.toInt();
                    if (i < 0 || i >= hours.length) return const SizedBox();
                    return Text('${hours[i].hour}h', style: const TextStyle(
                      fontFamily: 'Satoshi', fontSize: 9,
                      color: DelightColors.textMuted));
                  })),
                leftTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 40,
                  getTitlesWidget: (val, _) => Text(
                    val >= 1000
                      ? 'R${(val / 1000).toStringAsFixed(0)}K'
                      : 'R${val.toStringAsFixed(0)}',
                    style: const TextStyle(fontFamily: 'Satoshi', fontSize: 8,
                      color: DelightColors.textMuted)))),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(
                  color: DelightColors.surfaceBorder, strokeWidth: 1)),
              borderData: FlBorderData(show: false),
              barGroups: hours.asMap().entries.map((e) {
                final h = e.value;
                final isPeak = h.total == maxTotal;
                return BarChartGroupData(x: e.key, barRods: [
                  BarChartRodData(
                    toY: h.total,
                    width: 20,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    rodStackItems: [
                      BarChartRodStackItem(0, h.foodDrink, const Color(0xFFFF6B35)),
                      BarChartRodStackItem(h.foodDrink,
                        h.foodDrink + h.merchandise, DelightColors.emerald),
                      BarChartRodStackItem(h.foodDrink + h.merchandise,
                        h.total, DelightColors.gold),
                    ],
                    borderSide: isPeak
                      ? const BorderSide(color: Colors.white, width: 1.5)
                      : BorderSide.none),
                ]);
              }).toList(),
            ))),
          const SizedBox(height: 12),
          Row(children: [
            _legend('🍽 Food & Drink', const Color(0xFFFF6B35)),
            const SizedBox(width: 16),
            _legend('👕 Merchandise', DelightColors.emerald),
            const SizedBox(width: 16),
            _legend('✨ Other', DelightColors.gold),
          ]),
        ],
        const SizedBox(height: 24),

        Text('Attendee Arrivals by Hour', style: _h2()),
        const SizedBox(height: 4),
        Text('Real gate scans — tickets admitted per hour', style: _muted(12)),
        const SizedBox(height: 12),
        if (d.arrivals.isEmpty)
          Text('No gate scans recorded yet.', style: _muted(12))
        else
          ...d.arrivals.map((a) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              SizedBox(width: 48, child: Text(_hh(a.key), style: _muted(11))),
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: maxArr == 0 ? 0 : a.value / maxArr,
                  backgroundColor: DelightColors.surfaceBorder,
                  valueColor: AlwaysStoppedAnimation(
                    DelightColors.emerald.withOpacity(0.8)),
                  minHeight: 8))),
              const SizedBox(width: 8),
              Text('+${_int(a.value)}', style: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 11,
                color: DelightColors.emerald)),
            ]))),
        const SizedBox(height: 32),
      ]));
  }

  Widget _legend(String label, Color color) => Row(children: [
    Container(width: 10, height: 10,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 5),
    Text(label, style: _muted(10)),
  ]);
}

// ─── By tier ─────────────────────────────────────────────────────────────────

class _TierTab extends StatelessWidget {
  final _Insights d;
  const _TierTab({required this.d});

  Color _tierColor(int i) => const [
    DelightColors.gold, DelightColors.emerald, Color(0xFFBF5FFF),
    DelightColors.blue, Color(0xFFFF6B35)][i % 5];

  @override
  Widget build(BuildContext context) {
    if (d.tiers.isEmpty) {
      return const _Empty('🎟', 'No tickets have been sold for this event yet.');
    }
    final maxAvg = d.tiers.map((t) => t.avgSpend).reduce((a, b) => a > b ? a : b);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!d.hasSales)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DelightColors.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: DelightColors.surfaceBorder)),
            child: Text('Ticket numbers below are real. Spend per person will '
              'appear once attendees pay stalls through Delight.',
              style: _muted(12))),

        if (d.hasSales)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: DelightColors.surfaceHigh,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: DelightColors.surfaceBorder)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Average Spend Per Ticket Holder', style: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 12, fontWeight: FontWeight.w700,
                color: DelightColors.textMuted, letterSpacing: 0.5)),
              const SizedBox(height: 16),
              ...d.tiers.asMap().entries.map((e) {
                final t = e.value; final c = _tierColor(e.key);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(
                        color: c, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 8),
                      Flexible(child: Text(t.tier, maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: DelightColors.textPrimary))),
                      const Spacer(),
                      Text(DelightCurrency.formatZAR(t.avgSpend), style: TextStyle(
                        fontFamily: 'Clash', fontSize: 18,
                        fontWeight: FontWeight.w700, color: c)),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: maxAvg > 0 ? t.avgSpend / maxAvg : 0,
                        backgroundColor: DelightColors.surfaceBorder,
                        valueColor: AlwaysStoppedAnimation(c),
                        minHeight: 6)),
                  ]));
              }),
            ])),
        const SizedBox(height: 20),

        Text('Tier Breakdown', style: _h2()),
        const SizedBox(height: 12),
        ...d.tiers.asMap().entries.map((e) {
          final t = e.value; final c = _tierColor(e.key);
          final pct = d.vendorRevenue > 0 ? t.vendorSpend / d.vendorRevenue * 100 : 0.0;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.withOpacity(0.3))),
            child: Column(children: [
              Row(children: [
                Flexible(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8)),
                  child: Text(t.tier, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Clash', fontSize: 16,
                      fontWeight: FontWeight.w700, color: c)))),
                const Spacer(),
                Text('${_int(t.tickets)} tickets', style: _muted(12)),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                _tierStat('Ticket Revenue',
                  DelightCurrency.formatZAR(t.ticketRevenue), c),
                _vDiv(),
                _tierStat('Stall Spend',
                  d.hasSales ? DelightCurrency.formatZAR(t.vendorSpend) : '—', c),
                _vDiv(),
                _tierStat('% of Stall Spend',
                  d.hasSales ? '${pct.toStringAsFixed(0)}%' : '—', c),
              ]),
            ]));
        }),
        const SizedBox(height: 32),
      ]));
  }

  Widget _tierStat(String label, String value, Color color) => Expanded(
    child: Column(children: [
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontFamily: 'Clash', fontSize: 14,
          fontWeight: FontWeight.w700, color: color)),
      Text(label, style: _muted(10)),
    ]));

  Widget _vDiv() => Container(
    width: 1, height: 28, color: DelightColors.surfaceBorder,
    margin: const EdgeInsets.symmetric(horizontal: 8));
}

// ═══════════════════════════════════════════════════════════════════════════════
// INDOOR VENUE INSIGHTS (club / stadium / concert hall / church / arena)
// Same real data, presented per section of the venue.
// ═══════════════════════════════════════════════════════════════════════════════

enum VenueType { club, stadium, concert, church, arena, restaurant }

extension VenueTypeExt on VenueType {
  String get label => const {
    VenueType.club:       'Club / Nightclub',
    VenueType.stadium:    'Stadium',
    VenueType.concert:    'Concert Hall',
    VenueType.church:     'Church Event',
    VenueType.arena:      'Indoor Arena',
    VenueType.restaurant: 'Restaurant / Banquet',
  }[this]!;
  String get emoji => const {
    VenueType.club:       '🎧',
    VenueType.stadium:    '🏟️',
    VenueType.concert:    '🎻',
    VenueType.church:     '⛪',
    VenueType.arena:      '🏀',
    VenueType.restaurant: '🍽',
  }[this]!;
}

VenueType? _venueTypeOf(String name) {
  for (final v in VenueType.values) {
    if (v.name == name) return v;
  }
  return null;
}

class IndoorEventInsightsScreen extends ConsumerWidget {
  const IndoorEventInsightsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => _InsightsShell(
    title: 'Indoor Insights',
    tabs: const ['📊 Overview', '🗺 Floor Map', '👤 Staff', '⏱ Timeline'],
    pages: (d) => [
      _IndoorOverview(d: d),
      _FloorMapTab(d: d),
      _StaffTab(d: d),
      _IndoorTimeline(d: d),
    ]);
}

class _IndoorOverview extends StatelessWidget {
  final _Insights d;
  const _IndoorOverview({required this.d});

  @override
  Widget build(BuildContext context) {
    final vt = _venueTypeOf(d.venueType);
    final sorted = List<_Stall>.from(d.stalls)
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    final top = sorted.isNotEmpty && sorted.first.revenue > 0 ? sorted.first : null;
    final topStaff = d.staff.isEmpty ? null : d.staff.first;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0D2A1A), Color(0xFF0A1F14)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(vt?.emoji ?? '🏛', style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.eventName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Clash', fontSize: 16,
                    fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
                Text('${vt?.label ?? 'Indoor venue'} · ${_fmtDate(d.eventDate)}',
                  style: _muted(11)),
              ])),
            ]),
            const SizedBox(height: 18),
            const Text('TOTAL REVENUE', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 10, color: DelightColors.textMuted,
              letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Text(DelightCurrency.formatZAR(d.vendorRevenue), style: const TextStyle(
              fontFamily: 'Clash', fontSize: 40, fontWeight: FontWeight.w700,
              color: DelightColors.textPrimary, letterSpacing: -1, height: 1)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              _pill('${d.stalls.length} sections', DelightColors.emerald),
              _pill('${_int(d.vendorTxns)} txns', DelightColors.blue),
              if (d.vsLastEventPct != null)
                _pill('${d.vsLastEventPct! >= 0 ? '+' : ''}'
                  '${d.vsLastEventPct!.toStringAsFixed(1)}% vs last',
                  d.vsLastEventPct! >= 0
                    ? DelightColors.emerald : DelightColors.error),
            ]),
          ])),
        const SizedBox(height: 16),

        if (top != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: DelightColors.goldGlow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: DelightColors.gold.withOpacity(0.35))),
            child: Row(children: [
              Text(top.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Top Revenue Section', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 10, color: DelightColors.textMuted,
                  letterSpacing: 1, fontWeight: FontWeight.w600)),
                Text(top.name, style: const TextStyle(fontFamily: 'Clash',
                  fontSize: 17, fontWeight: FontWeight.w700,
                  color: DelightColors.textPrimary)),
                Text(DelightCurrency.formatZAR(top.revenue), style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 13,
                  fontWeight: FontWeight.w700, color: DelightColors.gold)),
              ])),
              if (topStaff != null)
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('Top Staff', style: TextStyle(fontFamily: 'Satoshi',
                    fontSize: 10, color: DelightColors.textMuted, letterSpacing: 1)),
                  Text(topStaff.name, style: const TextStyle(fontFamily: 'Satoshi',
                    fontWeight: FontWeight.w700, fontSize: 13,
                    color: DelightColors.textPrimary)),
                  Text(DelightCurrency.formatZAR(topStaff.revenue),
                    style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                      color: DelightColors.gold, fontWeight: FontWeight.w600)),
                ]),
            ])),
        if (top != null) const SizedBox(height: 20),

        Text('Revenue by Section', style: _h2()),
        const SizedBox(height: 12),
        if (d.stalls.isEmpty)
          Text('No sections are registered for this event yet.', style: _muted(12))
        else if (!d.hasSales)
          const SizedBox(height: 260, child: _NoSales())
        else
          ...sorted.map((sec) {
            final pct = sec.revenue / d.vendorRevenue;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: DelightColors.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: DelightColors.surfaceBorder)),
              child: Column(children: [
                Row(children: [
                  Text(sec.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(sec.name, style: const TextStyle(fontFamily: 'Satoshi',
                      fontWeight: FontWeight.w700, fontSize: 14,
                      color: DelightColors.textPrimary)),
                    Text('${_int(sec.txns)} transactions · '
                      'avg ${DelightCurrency.formatZAR(sec.avg)}', style: _muted(11)),
                  ])),
                  Text(DelightCurrency.formatZAR(sec.revenue), style: const TextStyle(
                    fontFamily: 'Clash', fontSize: 15, fontWeight: FontWeight.w700,
                    color: DelightColors.textPrimary)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: DelightColors.surfaceBorder,
                      valueColor: AlwaysStoppedAnimation(sec.color),
                      minHeight: 5))),
                  const SizedBox(width: 10),
                  Text('${(pct * 100).toStringAsFixed(1)}%', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 11,
                    fontWeight: FontWeight.w700, color: sec.color)),
                ]),
              ]));
          }),
        const SizedBox(height: 20),

        Text('What the data says', style: _h2()),
        const SizedBox(height: 12),
        ..._insightCards(d),
        const SizedBox(height: 32),
      ]));
  }

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3))),
    child: Text(label, style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
      fontWeight: FontWeight.w600, color: color)));
}

// ─── Floor map ───────────────────────────────────────────────────────────────

class _FloorMapTab extends StatelessWidget {
  final _Insights d;
  const _FloorMapTab({required this.d});

  @override
  Widget build(BuildContext context) {
    if (d.stalls.isEmpty) {
      return const _Empty('🗺', 'No sections are registered for this event yet.');
    }
    if (!d.hasSales) return const _NoSales();

    final sections = List<_Stall>.from(d.stalls)
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    final maxRev = sections.first.revenue <= 0 ? 1.0 : sections.first.revenue;
    final church = _venueTypeOf(d.venueType) == VenueType.church;

    final rows = <List<_Stall>>[];
    for (int i = 0; i < sections.length; i += 2) {
      rows.add(sections.sublist(i, (i + 2).clamp(0, sections.length)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Revenue Heat Map', style: _h2()),
        const SizedBox(height: 4),
        Text('Brighter = more revenue. Tap a section for details.',
          style: _muted(12)),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: DelightColors.surfaceHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DelightColors.surfaceBorder)),
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
              alignment: Alignment.center,
              child: Text(church ? '⛪ ALTAR' : '🎧 STAGE',
                style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                  fontWeight: FontWeight.w700, color: Colors.white54,
                  letterSpacing: 2))),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: rows.map((row) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: row.asMap().entries.map((e) {
                  final sec = e.value;
                  final k = sec.revenue / maxRev;
                  return Expanded(child: Padding(
                    padding: EdgeInsets.only(left: e.key == 0 ? 0 : 8),
                    child: GestureDetector(
                      onTap: () => _detail(context, sec),
                      child: Container(
                        height: 80,
                        decoration: BoxDecoration(
                          color: sec.color.withOpacity(0.1 + k * 0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: sec.color.withOpacity(0.3 + k * 0.5), width: 1.5)),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          Text(sec.emoji, style: const TextStyle(fontSize: 20)),
                          const SizedBox(height: 3),
                          Text(sec.name, textAlign: TextAlign.center, maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: 'Satoshi', fontSize: 9,
                              color: sec.color, fontWeight: FontWeight.w600)),
                          Text(DelightCurrency.formatZAR(sec.revenue),
                            style: TextStyle(fontFamily: 'Satoshi', fontSize: 9,
                              color: sec.color.withOpacity(0.8))),
                        ])))));
                }).toList()))).toList())),
          ])),
        const SizedBox(height: 24),
        Text('All Sections', style: const TextStyle(fontFamily: 'Clash',
          fontSize: 16, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 10),
        ...sections.map((sec) {
          final k = sec.revenue / maxRev;
          return GestureDetector(
            onTap: () => _detail(context, sec),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: sec.color.withOpacity(0.06 + k * 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: sec.color.withOpacity(0.2 + k * 0.3))),
              child: Row(children: [
                Text(sec.emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(child: Text(sec.name, style: const TextStyle(
                  fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                  fontSize: 13, color: DelightColors.textPrimary))),
                Text(DelightCurrency.formatZAR(sec.revenue), style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 13, fontWeight: FontWeight.w700,
                  color: sec.color)),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right,
                  color: DelightColors.textMuted, size: 16),
              ])));
        }),
        const SizedBox(height: 32),
      ]));
  }

  void _detail(BuildContext context, _Stall sec) {
    Widget row(String l, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(child: Text(l, style: _muted(13))),
        Text(v, style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
          fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
      ]));
    showModalBottomSheet(
      context: context,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(sec.emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(sec.name, style: const TextStyle(fontFamily: 'Clash',
                fontSize: 20, fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary)),
              Text((sec.sectionType ?? sec.category).replaceAll('_', ' ').toUpperCase(),
                style: const TextStyle(fontFamily: 'Satoshi', fontSize: 10,
                  color: DelightColors.textMuted, letterSpacing: 1.5)),
            ])),
          ]),
          const SizedBox(height: 20),
          row('Total Revenue', DelightCurrency.formatZAR(sec.revenue)),
          row('Transactions', _int(sec.txns)),
          row('Avg Transaction', DelightCurrency.formatZAR(sec.avg)),
          row('Peak Hour', sec.peakHour == null
            ? '—' : '${_hh(sec.peakHour!)} – ${_hh((sec.peakHour! + 1) % 24)}'),
          const SizedBox(height: 8),
        ])));
  }
}

// ─── Staff ───────────────────────────────────────────────────────────────────

class _StaffTab extends StatelessWidget {
  final _Insights d;
  const _StaffTab({required this.d});

  @override
  Widget build(BuildContext context) {
    final staff = d.staff;
    if (staff.isEmpty) {
      return const _Empty('👤',
        'No staff-attributed sales yet.\n\n'
        'When a stall payment is taken by a named staff member, their totals '
        'show up here.');
    }
    final top = staff.first;
    final maxRev = top.revenue <= 0 ? 1.0 : top.revenue;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              DelightColors.gold.withOpacity(0.15),
              DelightColors.gold.withOpacity(0.05)]),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: DelightColors.gold.withOpacity(0.35))),
          child: Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: DelightColors.gold.withOpacity(0.2), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(top.name.isEmpty ? '?' : top.name[0].toUpperCase(),
                style: const TextStyle(fontFamily: 'Clash', fontSize: 22,
                  fontWeight: FontWeight.w700, color: DelightColors.gold))),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('⭐ TOP PERFORMER', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 10, color: DelightColors.gold,
                letterSpacing: 1.5, fontWeight: FontWeight.w700)),
              Text(top.name, style: const TextStyle(fontFamily: 'Clash',
                fontSize: 18, fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary)),
              Text(top.section, style: _muted(12)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(DelightCurrency.formatZAR(top.revenue), style: const TextStyle(
                fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
                color: DelightColors.gold)),
              Text('${_int(top.txns)} txns', style: _muted(11)),
            ]),
          ])),
        const SizedBox(height: 20),
        Text('All Staff', style: _h2()),
        const SizedBox(height: 12),
        ...staff.map((s) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DelightColors.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DelightColors.surfaceBorder)),
          child: Column(children: [
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: const BoxDecoration(
                  color: DelightColors.emeraldGlow, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
                  style: const TextStyle(fontFamily: 'Clash', fontSize: 16,
                    fontWeight: FontWeight.w700, color: DelightColors.emerald))),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.name, style: const TextStyle(fontFamily: 'Satoshi',
                  fontWeight: FontWeight.w700, fontSize: 14,
                  color: DelightColors.textPrimary)),
                Text(s.section, style: _muted(11)),
              ])),
              Text(DelightCurrency.formatZAR(s.revenue), style: const TextStyle(
                fontFamily: 'Clash', fontSize: 15, fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: s.revenue / maxRev,
                  backgroundColor: DelightColors.surfaceBorder,
                  valueColor: const AlwaysStoppedAnimation(DelightColors.emerald),
                  minHeight: 4))),
              const SizedBox(width: 10),
              Text('${_int(s.txns)} txns · avg ${DelightCurrency.formatZAR(s.avg)}',
                style: _muted(10)),
            ]),
          ]))),
        const SizedBox(height: 32),
      ]));
  }
}

// ─── Indoor timeline ─────────────────────────────────────────────────────────

class _IndoorTimeline extends StatelessWidget {
  final _Insights d;
  const _IndoorTimeline({required this.d});

  @override
  Widget build(BuildContext context) {
    if (!d.hasSales || d.byHour.isEmpty) return const _NoSales();
    final hours = d.byHour;
    final maxV = hours.map((h) => h.total).reduce((a, b) => a > b ? a : b);
    final peak = d.peakHour!;
    final church = _venueTypeOf(d.venueType) == VenueType.church;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Revenue Timeline — ${church ? 'Service Flow' : 'Night Timeline'}',
          style: _h2()),
        const SizedBox(height: 4),
        Text(church ? 'When people gave and bought, hour by hour'
          : 'When people spent throughout the event', style: _muted(12)),
        const SizedBox(height: 20),
        ...hours.map((h) {
          final isPeak = h.hour == peak.hour;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              SizedBox(width: 44, child: Text(_hh(h.hour), style: _muted(10))),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maxV > 0 ? h.total / maxV : 0,
                      backgroundColor: DelightColors.surfaceBorder,
                      valueColor: AlwaysStoppedAnimation(isPeak
                        ? DelightColors.gold : DelightColors.emerald),
                      minHeight: isPeak ? 12 : 8))),
                  const SizedBox(width: 8),
                  Text(DelightCurrency.formatZAR(h.total), style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 11, fontWeight: FontWeight.w700,
                    color: isPeak ? DelightColors.gold : DelightColors.textPrimary)),
                ]),
                const SizedBox(height: 3),
                Text('${_int(h.txns)} transactions${isPeak ? ' · peak hour' : ''}',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 10,
                    color: isPeak ? DelightColors.gold : DelightColors.textMuted,
                    fontWeight: isPeak ? FontWeight.w700 : FontWeight.normal)),
              ])),
            ]));
        }),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: DelightColors.goldGlow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DelightColors.gold.withOpacity(0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('💡 Key Insight', style: TextStyle(
              fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
              fontSize: 13, color: DelightColors.gold)),
            const SizedBox(height: 8),
            Text('${_hh(peak.hour)} was your busiest hour: '
              '${DelightCurrency.formatZAR(peak.total)} across ${_int(peak.txns)} '
              'transactions (${(peak.total / d.vendorRevenue * 100).toStringAsFixed(0)}% '
              'of total revenue).',
              style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                color: DelightColors.textSecondary, height: 1.5)),
          ])),
        const SizedBox(height: 32),
      ]));
  }
}
