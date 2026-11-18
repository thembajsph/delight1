// lib/features/analytics/presentation/screens/admin_dashboard_screen.dart
//
// DELIGHT ADMIN DASHBOARD — real data, pulled from Supabase.
//
// This app is pre-launch, so these numbers will often be small, or empty —
// that's correct and honest. Every section below either shows a genuine
// aggregate query result or a plain "not enough data yet" state. Nothing
// here is randomly generated or hardcoded as a stand-in for real traffic.
//
// Sections:
//  1. Top bar    — real signed-in user count + real XRP/ZAR price + clock
//  2. Overview   — KPI cards, revenue chart, revenue streams, live
//                  transaction feed, geography, feature usage, top users,
//                  operational alerts (FICA/KYC/inactive-agent checks)
//  3. Time Spent — real session-length telemetry from app-open/screen-view
//                  events logged by the router's analytics observer
//  4. Return Visits — real opens-per-day / opens-per-user telemetry
//  5. Scale Readiness — P-E-T score, retention and growth computed from
//                  real data; CAC and NPS are admin-entered business inputs
//                  (no product table has them) and show "not set" until
//                  an admin fills them in

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/xrpl_service.dart';

// ─── Shared display helpers ─────────────────────────────────────────────────

String _fmt(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}K';
  return n.toString();
}

String _fmtDuration(num seconds) {
  final s = seconds.round();
  if (s >= 3600) return '${s ~/ 3600}h ${(s % 3600) ~/ 60}m';
  if (s >= 60)   return '${s ~/ 60}m ${s % 60}s';
  return '${s}s';
}

({String label, String emoji, Color color}) _txMeta(String type) {
  switch (type) {
    case 'send':             return (label: 'SEND',    emoji: '💸', color: DelightColors.emerald);
    case 'receive':          return (label: 'RECEIVE', emoji: '📥', color: DelightColors.blue);
    case 'topup':            return (label: 'TOPUP',   emoji: '📱', color: const Color(0xFF9B59B6));
    case 'cashout':          return (label: 'CASHOUT', emoji: '🏦', color: const Color(0xFFFF6B35));
    case 'ticket_purchase':  return (label: 'TICKET',  emoji: '🎟', color: DelightColors.gold);
    case 'ticket_sale':      return (label: 'RESALE',  emoji: '♦️', color: const Color(0xFFBF5FFF));
    case 'reward':           return (label: 'REWARD',  emoji: '🎁', color: DelightColors.emerald);
    default:                 return (label: type.toUpperCase(), emoji: '•', color: DelightColors.textMuted);
  }
}

Widget _sectionTitle(String title, String sub) => Column(
  crossAxisAlignment: CrossAxisAlignment.start, children: [
  Text(title, style: const TextStyle(fontFamily: 'Clash', fontSize: 17,
    fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
  Text(sub, style: const TextStyle(fontFamily: 'Satoshi', fontSize: 11,
    color: DelightColors.textMuted)),
]);

Widget _emptyState(String message) => Container(
  width: double.infinity,
  padding: const EdgeInsets.all(20),
  decoration: BoxDecoration(
    color: DelightColors.surfaceHigh,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: DelightColors.surfaceBorder)),
  child: Text(message, textAlign: TextAlign.center,
    style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
      color: DelightColors.textMuted)));

class _KPI {
  final String label, value, sub;
  final Color color;
  final IconData icon;
  final List<double> sparkline;
  const _KPI(this.label, this.value, this.sub, this.color, this.icon,
    [this.sparkline = const []]);
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  Timer? _refreshTimer;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  Map<String, dynamic>? _overview;
  List<Map<String, dynamic>> _geography = [];
  List<Map<String, dynamic>> _featureUsage = [];
  List<Map<String, dynamic>> _alerts = [];
  Map<String, dynamic>? _timeSpent;
  Map<String, dynamic>? _returnVisits;
  Map<String, dynamic>? _growth;
  Map<String, double?> _settings = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _load();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    // A genuine re-fetch of the same real queries every 60s — not a fake
    // tick incrementing counters, an actual refresh of live data.
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _tab.dispose();
    _refreshTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        SupabaseService.getAdminOverview(),
        SupabaseService.getUserGeography(),
        SupabaseService.getFeatureUsage(),
        SupabaseService.getAdminAlerts(),
        SupabaseService.getTimeSpentStats(),
        SupabaseService.getReturnVisitStats(),
        SupabaseService.getGrowthStats(),
      ]);
      final settings = await SupabaseService.getAdminSettings(['cac_zar', 'nps']);
      if (!mounted) return;
      setState(() {
        _overview     = results[0] as Map<String, dynamic>;
        _geography    = results[1] as List<Map<String, dynamic>>;
        _featureUsage = results[2] as List<Map<String, dynamic>>;
        _alerts       = results[3] as List<Map<String, dynamic>>;
        _timeSpent    = results[4] as Map<String, dynamic>;
        _returnVisits = results[5] as Map<String, dynamic>;
        _growth       = results[6] as Map<String, dynamic>;
        _settings     = settings;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstLoad = _loading && _overview == null;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      body: Column(children: [
        _TopBar(now: _now, totalUsers: _overview?['totalUsers'] as int?,
          onRefresh: () => _load()),
        _TabBar(tab: _tab),
        Expanded(child: firstLoad
          ? const Center(child: CircularProgressIndicator(color: DelightColors.emerald))
          : TabBarView(
              controller: _tab,
              children: [
                _OverviewTab(
                  overview: _overview ?? const {},
                  geography: _geography,
                  featureUsage: _featureUsage,
                  alerts: _alerts),
                _TimeSpentTab(data: _timeSpent ?? const {}),
                _ReturnVisitsTab(data: _returnVisits ?? const {}),
                _ScaleReadinessTab(
                  growth: _growth ?? const {},
                  settings: _settings,
                  onSettingsChanged: () => _load()),
              ])),
      ]),
    );
  }
}

// ─── Top bar ──────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final DateTime now;
  final int? totalUsers;
  final VoidCallback onRefresh;
  const _TopBar({required this.now, required this.totalUsers, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final xrpPrice = DelightCurrency.xrpPriceZAR;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: DelightColors.surfaceBorder))),
        child: Row(children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: const Icon(Icons.arrow_back,
              color: DelightColors.textMuted, size: 20)),
          const SizedBox(width: 10),

          Image.asset('assets/images/delight_logo.png',
            height: 24, fit: BoxFit.contain),

          const Spacer(),

          if (totalUsers != null) ...[
            Text('${_fmt(totalUsers!)} users', style: const TextStyle(
              fontFamily: 'Satoshi', fontSize: 11, color: DelightColors.textMuted)),
            const SizedBox(width: 12),
          ],

          // XRP price — the same live value the wallet uses, not a
          // simulated random walk.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: DelightColors.emeraldGlow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
            child: Text('XRP R${xrpPrice.toStringAsFixed(2)}', style: const TextStyle(
              fontFamily: 'Clash', fontSize: 13, fontWeight: FontWeight.w700,
              color: DelightColors.emerald))),

          const SizedBox(width: 10),
          Text('$h:$m:$s', style: const TextStyle(
            fontFamily: 'Courier', fontSize: 12,
            color: DelightColors.textMuted)),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onRefresh,
            child: const Icon(Icons.refresh, color: DelightColors.textMuted, size: 18)),
        ])));
  }
}

class _TabBar extends StatelessWidget {
  final TabController tab;
  const _TabBar({required this.tab});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DelightColors.surfaceBorder))),
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        controller: tab,
        indicatorColor: DelightColors.emerald,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: DelightColors.textPrimary,
        unselectedLabelColor: DelightColors.textMuted,
        labelStyle: const TextStyle(
          fontFamily: 'Satoshi', fontWeight: FontWeight.w700, fontSize: 13),
        tabs: const [
          Tab(text: '📊 Overview'),
          Tab(text: '⏱ Time Spent'),
          Tab(text: '🔁 Return Visits'),
          Tab(text: '🚀 Scale Readiness'),
        ],
      ));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// OVERVIEW TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _OverviewTab extends StatelessWidget {
  final Map<String, dynamic> overview;
  final List<Map<String, dynamic>> geography;
  final List<Map<String, dynamic>> featureUsage;
  final List<Map<String, dynamic>> alerts;
  const _OverviewTab({required this.overview, required this.geography,
    required this.featureUsage, required this.alerts});

  @override
  Widget build(BuildContext context) {
    final revenueByDay = (overview['revenueByDay'] as List<dynamic>? ?? [])
      .map((v) => (v as num).toDouble()).toList();
    final recentTx = (overview['recentTx'] as List<dynamic>? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final revenueStreams = Map<String, double>.from(
      (overview['revenueStreams'] as Map<String, dynamic>? ?? {}));
    final topUsers = (overview['topUsers'] as List<dynamic>? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map)).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        _kpiGrid(),
        const SizedBox(height: 20),

        _sectionTitle('Revenue Over Time', '14-day platform fee revenue'),
        const SizedBox(height: 12),
        revenueByDay.every((v) => v == 0)
          ? _emptyState('No completed transactions in the last 14 days yet.')
          : _RevenueBarChart(data: revenueByDay),
        const SizedBox(height: 20),

        _sectionTitle('Revenue Streams', 'Fees by transaction type, last 7 days'),
        const SizedBox(height: 12),
        revenueStreams.isEmpty
          ? _emptyState('No fee revenue in the last 7 days yet.')
          : _StreamBreakdown(streams: revenueStreams),
        const SizedBox(height: 20),

        _sectionTitle('Live Transactions', 'Most recent, refreshes every minute'),
        const SizedBox(height: 12),
        recentTx.isEmpty
          ? _emptyState('No transactions yet.')
          : _TxFeed(transactions: recentTx),
        const SizedBox(height: 20),

        _sectionTitle('User Geography', 'By city, where set on signup'),
        const SizedBox(height: 12),
        geography.isEmpty
          ? _emptyState('No city data collected yet.')
          : _GeoSection(cities: geography),
        const SizedBox(height: 20),

        _sectionTitle('Feature Usage', 'Screen views, last 30 days'),
        const SizedBox(height: 12),
        featureUsage.isEmpty
          ? _emptyState('Not enough screen-view data yet.')
          : _FeatureUsage(usage: featureUsage),
        const SizedBox(height: 20),

        _sectionTitle('Top Users by Volume', 'Completed transaction totals'),
        const SizedBox(height: 12),
        topUsers.isEmpty
          ? _emptyState('No completed transactions yet.')
          : _TopUsersTable(users: topUsers),
        const SizedBox(height: 20),

        _sectionTitle('System Alerts', 'Real threshold checks'),
        const SizedBox(height: 12),
        _Alerts(alerts: alerts),
        const SizedBox(height: 32),
      ]));
  }

  Widget _kpiGrid() {
    final revenueByDay = (overview['revenueByDay'] as List<dynamic>? ?? [])
      .map((v) => (v as num).toDouble()).toList();
    final totalUsers = overview['totalUsers'] as int? ?? 0;
    final kpis = [
      _KPI('Total Users', _fmt(totalUsers), 'All signups',
        DelightColors.blue, Icons.people_outline),
      _KPI('Revenue (7D)', DelightCurrency.formatZAR((overview['revenue7d'] as num?)?.toDouble() ?? 0),
        'Platform fees', DelightColors.emerald, Icons.attach_money,
        revenueByDay.length >= 7 ? revenueByDay.sublist(revenueByDay.length - 7) : revenueByDay),
      _KPI('XRP Volume (7D)', DelightCurrency.formatZAR((overview['xrpVolume7d'] as num?)?.toDouble() ?? 0),
        'Top-up + cash-out', DelightColors.gold, Icons.currency_exchange),
      _KPI('Daily Active', _fmt(overview['dau'] as int? ?? 0),
        totalUsers > 0 ? '${(((overview['dau'] as int? ?? 0) / totalUsers) * 100).toStringAsFixed(0)}% of users' : 'Today',
        DelightColors.textSecondary, Icons.person_outline),
      _KPI('NFT Tickets', _fmt(overview['nftTickets'] as int? ?? 0),
        'Minted on XRP Ledger', const Color(0xFFBF5FFF),
        Icons.confirmation_number_outlined),
    ];

    return Column(children: [
      Row(children: [
        Expanded(child: _kpiCard(kpis[0])),
        const SizedBox(width: 10),
        Expanded(child: _kpiCard(kpis[1])),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _kpiCard(kpis[2])),
        const SizedBox(width: 10),
        Expanded(child: _kpiCard(kpis[3])),
      ]),
      const SizedBox(height: 10),
      _kpiCard(kpis[4], wide: true),
    ]);
  }

  Widget _kpiCard(_KPI kpi, {bool wide = false}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kpi.color.withOpacity(0.25)),
        boxShadow: [BoxShadow(
          color: kpi.color.withOpacity(0.06), blurRadius: 10)]),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(children: [
            Icon(kpi.icon, color: kpi.color, size: 14),
            const SizedBox(width: 5),
            Text(kpi.label, style: TextStyle(fontFamily: 'Satoshi',
              fontSize: 10, color: kpi.color.withOpacity(0.8),
              fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ]),
          const SizedBox(height: 6),
          Text(kpi.value, style: const TextStyle(fontFamily: 'Clash',
            fontSize: 22, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary, letterSpacing: -0.5)),
          Text(kpi.sub, style: const TextStyle(fontFamily: 'Satoshi',
            fontSize: 10, color: DelightColors.textMuted)),
        ])),
        if (kpi.sparkline.length >= 2)
          SizedBox(width: 60, height: 32,
            child: LineChart(LineChartData(
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))),
              lineBarsData: [LineChartBarData(
                spots: kpi.sparkline.asMap().entries.map((e) =>
                  FlSpot(e.key.toDouble(), e.value)).toList(),
                isCurved: true,
                color: kpi.color,
                barWidth: 1.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: kpi.color.withOpacity(0.12)))],
            ))),
      ]));
  }
}

class _RevenueBarChart extends StatelessWidget {
  final List<double> data;
  const _RevenueBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxVal = data.isEmpty ? 1.0 : data.reduce((a, b) => a > b ? a : b);
    final maxY = maxVal <= 0 ? 1.0 : maxVal * 1.2;

    return Container(
      height: 180,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: BarChart(BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, reservedSize: 16,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i % 3 != 0) return const SizedBox.shrink();
              return Text('D${i + 1}', style: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 8,
                color: DelightColors.textMuted));
            })),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: DelightColors.surfaceBorder, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        barGroups: data.asMap().entries.map((e) =>
          BarChartGroupData(x: e.key, barRods: [
            BarChartRodData(
              toY: e.value, width: 14, color: DelightColors.emerald,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)))
          ])).toList())));
  }
}

class _StreamBreakdown extends StatelessWidget {
  final Map<String, double> streams;
  const _StreamBreakdown({required this.streams});

  @override
  Widget build(BuildContext context) {
    final total = streams.values.fold(0.0, (t, v) => t + v);
    final entries = streams.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Column(children: entries.map((e) {
      final meta = _txMeta(e.key);
      final pct = total > 0 ? e.value / total : 0.0;
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: meta.color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: meta.color.withOpacity(0.2))),
        child: Column(children: [
          Row(children: [
            Expanded(child: Text(meta.label, style: const TextStyle(
              fontFamily: 'Satoshi', fontWeight: FontWeight.w700, fontSize: 13,
              color: DelightColors.textPrimary))),
            Text(DelightCurrency.formatZAR(e.value), style: TextStyle(
              fontFamily: 'Clash', fontSize: 14, fontWeight: FontWeight.w700,
              color: meta.color)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: DelightColors.surfaceBorder,
              valueColor: AlwaysStoppedAnimation(meta.color),
              minHeight: 4)),
        ]));
    }).toList());
  }
}

class _TxFeed extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;
  const _TxFeed({required this.transactions});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Column(children:
        transactions.map((tx) => _txRow(tx)).toList()));
  }

  Widget _txRow(Map<String, dynamic> tx) {
    final type = tx['type'] as String? ?? '';
    final meta = _txMeta(type);
    final amountZar = (tx['amount_zar'] as num?)?.toDouble() ?? 0;
    final profile = tx['profiles'] as Map<String, dynamic>?;
    final name = profile?['display_name'] as String? ?? 'User';
    final ts = DateTime.tryParse(tx['created_at'] as String? ?? '');
    final timeLabel = ts == null ? '' :
      '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DelightColors.surfaceBorder))),
      child: Row(children: [
        Container(
          width: 72, height: 20,
          decoration: BoxDecoration(
            color: meta.color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4)),
          alignment: Alignment.center,
          child: Text(meta.label, style: TextStyle(fontFamily: 'Satoshi',
            fontSize: 9, fontWeight: FontWeight.w800, color: meta.color,
            letterSpacing: 0.3))),
        const SizedBox(width: 10),
        Expanded(child: Text(name, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: 'Satoshi',
          fontSize: 12, color: DelightColors.textPrimary))),
        Text(DelightCurrency.formatZAR(amountZar), style: TextStyle(fontFamily: 'Clash', fontSize: 13,
          fontWeight: FontWeight.w700, color: meta.color)),
        const SizedBox(width: 10),
        Text(timeLabel, style: const TextStyle(fontFamily: 'Courier',
          fontSize: 10, color: DelightColors.textMuted)),
      ]));
  }
}

class _GeoSection extends StatelessWidget {
  final List<Map<String, dynamic>> cities;
  const _GeoSection({required this.cities});

  @override
  Widget build(BuildContext context) {
    final total = cities.fold(0, (t, c) => t + (c['count'] as int));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Column(children: [
        Container(
          height: 80, width: double.infinity,
          decoration: BoxDecoration(
            color: DelightColors.background,
            borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: Text('${_fmt(total)} users with a known city',
            style: const TextStyle(fontFamily: 'Satoshi', fontSize: 11,
              color: DelightColors.textMuted)),
        ),
        const SizedBox(height: 14),
        ...cities.map((c) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(c['city'] as String, style: const TextStyle(fontFamily: 'Satoshi',
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: DelightColors.textPrimary)),
                const Spacer(),
                Text(_fmt(c['count'] as int), style: const TextStyle(fontFamily: 'Clash',
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: DelightColors.emerald)),
                Text('  ${((c['pct'] as double) * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontFamily: 'Satoshi', fontSize: 10,
                    color: DelightColors.textMuted)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: c['pct'] as double,
                  backgroundColor: DelightColors.surfaceBorder,
                  valueColor: const AlwaysStoppedAnimation(DelightColors.emerald),
                  minHeight: 3)),
            ])),
          ]))),
      ]));
  }
}

class _FeatureUsage extends StatelessWidget {
  final List<Map<String, dynamic>> usage;
  const _FeatureUsage({required this.usage});

  @override
  Widget build(BuildContext context) {
    const colors = [DelightColors.emerald, DelightColors.blue, DelightColors.gold,
      Color(0xFFBF5FFF), DelightColors.textSecondary, DelightColors.textMuted];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Column(
        children: usage.asMap().entries.map((e) {
          final color = colors[e.key % colors.length];
          final screen = e.value['screen'] as String;
          final pct = e.value['pct'] as double;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              SizedBox(width: 96, child: Text(screen, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                color: DelightColors.textSecondary))),
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: DelightColors.surfaceBorder,
                  valueColor: AlwaysStoppedAnimation(color),
                  minHeight: 8))),
              const SizedBox(width: 8),
              Text('${(pct * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                  fontWeight: FontWeight.w700, color: color)),
            ]));
        }).toList()));
  }
}

class _TopUsersTable extends StatelessWidget {
  final List<Map<String, dynamic>> users;
  const _TopUsersTable({required this.users});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: DelightColors.surfaceBorder))),
          child: const Row(children: [
            SizedBox(width: 28, child: Text('#', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 10, fontWeight: FontWeight.w700,
              color: DelightColors.textMuted))),
            Expanded(child: Text('User', style: TextStyle(fontFamily: 'Satoshi',
              fontSize: 10, fontWeight: FontWeight.w700,
              color: DelightColors.textMuted))),
            Text('Volume', style: TextStyle(fontFamily: 'Satoshi',
              fontSize: 10, fontWeight: FontWeight.w700,
              color: DelightColors.textMuted)),
            SizedBox(width: 10),
            Text('Type', style: TextStyle(fontFamily: 'Satoshi',
              fontSize: 10, fontWeight: FontWeight.w700,
              color: DelightColors.textMuted)),
          ])),
        ...users.asMap().entries.map((e) {
          final u = e.value;
          final isTop = e.key == 0;
          final name = u['display_name'] as String? ?? 'User';
          final role = u['role'] as String? ?? 'consumer';
          final volume = (u['total_zar'] as num?)?.toDouble() ?? 0;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: const Border(
                bottom: BorderSide(color: DelightColors.surfaceBorder)),
              color: isTop
                ? DelightColors.gold.withOpacity(0.04)
                : Colors.transparent),
            child: Row(children: [
              SizedBox(width: 28, child: Text('${e.key + 1}', style: TextStyle(
                fontFamily: 'Clash', fontSize: 12, fontWeight: FontWeight.w700,
                color: isTop ? DelightColors.gold : DelightColors.textMuted))),
              Expanded(child: Text(name, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Satoshi',
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: DelightColors.textPrimary))),
              Text(DelightCurrency.formatZAR(volume), style: const TextStyle(fontFamily: 'Clash',
                fontSize: 13, fontWeight: FontWeight.w700,
                color: DelightColors.emerald)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: DelightColors.surfaceBorder,
                  borderRadius: BorderRadius.circular(4)),
                child: Text(role, style: const TextStyle(fontFamily: 'Satoshi',
                  fontSize: 9, color: DelightColors.textSecondary))),
            ]));
        }),
      ]));
  }
}

class _Alerts extends StatelessWidget {
  final List<Map<String, dynamic>> alerts;
  const _Alerts({required this.alerts});

  Color _levelColor(String level) {
    switch (level) {
      case 'error':   return DelightColors.error;
      case 'warning': return DelightColors.gold;
      case 'ok':      return DelightColors.emerald;
      default:        return DelightColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: alerts.map((a) {
      final color = _levelColor(a['level'] as String? ?? 'muted');
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25))),
        child: Row(children: [
          Text(a['icon'] as String? ?? '•', style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text(a['title'] as String, style: TextStyle(fontFamily: 'Satoshi',
              fontWeight: FontWeight.w700, fontSize: 12, color: color)),
            Text(a['message'] as String, style: const TextStyle(fontFamily: 'Satoshi',
              fontSize: 11, color: DelightColors.textMuted, height: 1.3)),
          ])),
        ]));
    }).toList());
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TIME SPENT TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _TimeSpentTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _TimeSpentTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final sessionCount = data['sessionCount'] as int? ?? 0;
    final avgSeconds = (data['avgSessionSeconds'] as num?)?.toDouble() ?? 0;
    final longestSeconds = (data['longestSessionSeconds'] as num?)?.toDouble() ?? 0;
    final totalSeconds = (data['totalSecondsLogged'] as num?)?.toDouble() ?? 0;
    final dailyAvg = (data['dailyAvgSeconds'] as List<dynamic>? ?? [])
      .map((v) => (v as num).toDouble()).toList();
    final sessionLengths = (data['sessionLengths'] as List<dynamic>? ?? [])
      .map((v) => (v as num).toInt()).toList();
    final featureUsage = (data['featureUsage'] as List<dynamic>? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map)).toList();

    if (sessionCount == 0) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _emptyState('No session data yet — this fills in as people use the '
            'app. Every screen visit is logged for real, there\'s just none '
            'to show yet.'),
        ]));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        _miniKPIs(sessionCount, avgSeconds, longestSeconds, totalSeconds),
        const SizedBox(height: 20),

        _sectionTitle('Avg Session Length', 'Last 14 days'),
        const SizedBox(height: 12),
        _TimeChart(data: dailyAvg),
        const SizedBox(height: 20),

        _sectionTitle('Session Length Distribution', 'Across logged sessions'),
        const SizedBox(height: 12),
        _SessionDistribution(lengths: sessionLengths),
        const SizedBox(height: 20),

        _sectionTitle('Time Per Screen', 'Share of screen views, last 30 days'),
        const SizedBox(height: 12),
        featureUsage.isEmpty
          ? _emptyState('Not enough screen-view data yet.')
          : _FeatureUsage(usage: featureUsage),
        const SizedBox(height: 32),
      ]));
  }

  Widget _miniKPIs(int count, double avg, double longest, double total) {
    final kpis = [
      ('Avg Session', _fmtDuration(avg), DelightColors.emerald),
      ('Sessions Logged', '$count', DelightColors.blue),
      ('Longest', _fmtDuration(longest), DelightColors.gold),
      ('Total Time', _fmtDuration(total), DelightColors.textSecondary),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: kpis.map((k) => Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: (k.$3).withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: (k.$3).withOpacity(0.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k.$1, style: TextStyle(fontFamily: 'Satoshi', fontSize: 9,
            color: (k.$3).withOpacity(0.8),
            fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(k.$2, style: TextStyle(fontFamily: 'Clash', fontSize: 18,
            fontWeight: FontWeight.w700, color: k.$3)),
        ]))).toList()));
  }
}

class _TimeChart extends StatelessWidget {
  final List<double> data;
  const _TimeChart({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: LineChart(LineChartData(
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: DelightColors.surfaceBorder, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, reservedSize: 16,
            getTitlesWidget: (v, _) {
              if (v.toInt() % 3 != 0) return const SizedBox.shrink();
              return Text('D${v.toInt() + 1}', style: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 8,
                color: DelightColors.textMuted));
            })),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))),
        lineBarsData: [
          LineChartBarData(
            spots: data.asMap().entries.map((e) =>
              FlSpot(e.key.toDouble(), e.value)).toList(),
            isCurved: true,
            color: DelightColors.emerald,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true, color: DelightColors.emerald.withOpacity(0.08))),
        ])));
  }
}

class _SessionDistribution extends StatelessWidget {
  final List<int> lengths;
  const _SessionDistribution({required this.lengths});

  @override
  Widget build(BuildContext context) {
    final buckets = [
      ('<1 min', 0, 59, DelightColors.error),
      ('1–3 min', 60, 179, DelightColors.gold),
      ('3–7 min', 180, 419, DelightColors.emerald),
      ('7–15 min', 420, 899, DelightColors.blue),
      ('15+ min', 900, 999999999, const Color(0xFFBF5FFF)),
    ];
    final total = lengths.length;

    return Row(children: buckets.map((b) {
      final count = lengths.where((l) => l >= b.$2 && l <= b.$3).length;
      final pct = total > 0 ? count / total : 0.0;
      return Expanded(child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: b.$4.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: b.$4.withOpacity(0.25))),
        child: Column(children: [
          Text('${(pct * 100).toStringAsFixed(0)}%',
            style: TextStyle(fontFamily: 'Clash', fontSize: 16,
              fontWeight: FontWeight.w700, color: b.$4)),
          const SizedBox(height: 4),
          Text(b.$1, style: const TextStyle(fontFamily: 'Satoshi', fontSize: 9,
            color: DelightColors.textMuted), textAlign: TextAlign.center),
        ])));
    }).toList());
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RETURN VISITS TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _ReturnVisitsTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ReturnVisitsTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final opensByDay = (data['opensByDay'] as List<dynamic>? ?? [])
      .map((v) => (v as num).toDouble()).toList();
    final opensToday = data['opensToday'] as int? ?? 0;
    final activeUsersToday = data['activeUsersToday'] as int? ?? 0;
    final opensPerUser = (data['opensPerUser'] as List<dynamic>? ?? [])
      .map((v) => (v as num).toInt()).toList();

    if (opensByDay.every((v) => v == 0) && opensToday == 0) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _emptyState('No app-open data yet — this fills in as people use '
            'the app.'),
        ]));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        _returnKPIs(opensToday, activeUsersToday, opensPerUser),
        const SizedBox(height: 20),

        _sectionTitle('Opens Over 14 Days', 'Total app opens logged'),
        const SizedBox(height: 12),
        _OpensChart(data: opensByDay),
        const SizedBox(height: 20),

        _sectionTitle('Opens Per Active User Today', 'How often today\'s users came back'),
        const SizedBox(height: 12),
        opensPerUser.isEmpty
          ? _emptyState('No opens logged today yet.')
          : _OpensBuckets(counts: opensPerUser),
        const SizedBox(height: 32),
      ]));
  }

  Widget _returnKPIs(int opensToday, int activeUsersToday, List<int> opensPerUser) {
    final avgOpens = opensPerUser.isEmpty
      ? 0.0 : opensPerUser.reduce((a, b) => a + b) / opensPerUser.length;
    final kpis = [
      ('Opens Today', '$opensToday', DelightColors.emerald),
      ('Active Users Today', '$activeUsersToday', DelightColors.blue),
      ('Avg Opens / Active User', avgOpens.toStringAsFixed(1), DelightColors.gold),
    ];
    return Row(children: kpis.map((k) => Expanded(child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (k.$3).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (k.$3).withOpacity(0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k.$1, style: TextStyle(fontFamily: 'Satoshi', fontSize: 9,
          color: (k.$3).withOpacity(0.8), fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(k.$2, style: TextStyle(fontFamily: 'Clash', fontSize: 18,
          fontWeight: FontWeight.w700, color: k.$3)),
      ])))).toList());
  }
}

class _OpensChart extends StatelessWidget {
  final List<double> data;
  const _OpensChart({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: LineChart(LineChartData(
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: DelightColors.surfaceBorder, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, reservedSize: 14,
            getTitlesWidget: (v, _) {
              if (v.toInt() % 3 != 0) return const SizedBox.shrink();
              return Text('D${v.toInt() + 1}', style: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 8,
                color: DelightColors.textMuted));
            })),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))),
        lineBarsData: [LineChartBarData(
          spots: data.asMap().entries.map((e) =>
            FlSpot(e.key.toDouble(), e.value)).toList(),
          isCurved: true, color: DelightColors.emerald, barWidth: 2.5,
          dotData: const FlDotData(show: false))])));
  }
}

class _OpensBuckets extends StatelessWidget {
  final List<int> counts;
  const _OpensBuckets({required this.counts});

  @override
  Widget build(BuildContext context) {
    final buckets = [
      ('1×', 1, 1, DelightColors.textMuted),
      ('2×', 2, 2, DelightColors.blue),
      ('3–4×', 3, 4, DelightColors.emerald),
      ('5–7×', 5, 7, DelightColors.gold),
      ('8+×', 8, 999999, const Color(0xFFBF5FFF)),
    ];
    final total = counts.length;

    return Row(children: [
      SizedBox(width: 140, height: 140,
        child: PieChart(PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 36,
          sections: buckets.map((b) {
            final count = counts.where((c) => c >= b.$2 && c <= b.$3).length;
            return PieChartSectionData(
              value: count.toDouble(), color: b.$4, title: '', radius: 26);
          }).toList()))),
      const SizedBox(width: 16),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: buckets.map((b) {
          final count = counts.where((c) => c >= b.$2 && c <= b.$3).length;
          final pct = total > 0 ? count / total : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(width: 10, height: 10,
                decoration: BoxDecoration(color: b.$4,
                  borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
              Text(b.$1, style: const TextStyle(fontFamily: 'Satoshi',
                fontSize: 12, color: DelightColors.textSecondary)),
              const Spacer(),
              Text('${(pct * 100).toStringAsFixed(0)}%', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 12, fontWeight: FontWeight.w700,
                color: b.$4)),
            ]));
        }).toList())),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCALE READINESS TAB
// ═══════════════════════════════════════════════════════════════════════════════
//
// P-E-T score, retention and growth are computed from real data. CAC and
// NPS have no product-table source — they're business inputs an admin
// enters here — so the ratios that depend on them show "not set" until
// they're filled in, rather than a plausible-looking invented number.

class _ScaleReadinessTab extends StatelessWidget {
  final Map<String, dynamic> growth;
  final Map<String, double?> settings;
  final VoidCallback onSettingsChanged;
  const _ScaleReadinessTab({required this.growth, required this.settings,
    required this.onSettingsChanged});

  Future<void> _editSetting(BuildContext context, String key, String label) async {
    final ctrl = TextEditingController(text: settings[key]?.toStringAsFixed(0) ?? '');
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DelightColors.surfaceHigh,
        title: Text('Set $label', style: const TextStyle(
          fontFamily: 'Clash', fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        content: TextField(controller: ctrl, keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.trim())),
            child: const Text('Save')),
        ]));
    if (result == null) return;
    await SupabaseService.setAdminSetting(key, result);
    onSettingsChanged();
  }

  @override
  Widget build(BuildContext context) {
    final totalUsers = growth['totalUsers'] as int? ?? 0;
    final petScore = (growth['petScore'] as num?)?.toDouble() ?? 0;
    final momGrowth = growth['momGrowth'] as double?;
    final retention30d = growth['retention30d'] as double?;
    final revenuePerUser = (growth['revenuePerUser'] as num?)?.toDouble() ?? 0;
    final monthlyRevenuePerActiveUser =
      (growth['monthlyRevenuePerActiveUser'] as num?)?.toDouble() ?? 0;
    final cac = settings['cac_zar'];
    final nps = settings['nps'];

    final revToCac = (cac != null && cac > 0) ? revenuePerUser / cac : null;
    final paybackMonths = (cac != null && cac > 0 && monthlyRevenuePerActiveUser > 0)
      ? cac / monthlyRevenuePerActiveUser : null;

    final readyPET     = totalUsers > 0 ? petScore > 70 : null;
    final readyRevCac  = revToCac != null ? revToCac > 3 : null;
    final readyPayback = paybackMonths != null ? paybackMonths < 12 : null;
    final readyRetain  = retention30d != null ? retention30d >= 0.80 : null;
    final readyGrowth  = momGrowth != null ? momGrowth >= 0.20 : null;

    final checks = [readyPET, readyRevCac, readyPayback, readyRetain, readyGrowth];
    final evaluated = checks.where((c) => c != null).length;
    final greenCount = checks.where((c) => c == true).length;

    final (String decision, Color decisionColor, String decisionEmoji) =
      totalUsers == 0
        ? ('NOT ENOUGH DATA YET', DelightColors.textMuted, '⏳')
      : evaluated < 3
        ? ('NEEDS MORE INPUTS', DelightColors.gold, '📝')
      : greenCount >= (evaluated * 0.8)
        ? ('READY TO SCALE', const Color(0xFF00C96A), '✅')
      : greenCount >= (evaluated * 0.5)
        ? ('APPROACHING READY', DelightColors.gold, '🟡')
        : ('NOT YET READY', DelightColors.error, '🔴');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [decisionColor.withOpacity(0.15), decisionColor.withOpacity(0.03)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: decisionColor.withOpacity(0.4))),
          child: Column(children: [
            Text(decisionEmoji, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 8),
            Text(decision, style: TextStyle(fontFamily: 'Clash', fontSize: 20,
              fontWeight: FontWeight.w700, color: decisionColor)),
            const SizedBox(height: 6),
            Text('$greenCount of $evaluated evaluated metrics in good shape'
              '${evaluated < 5 ? ' (${5 - evaluated} need more data/inputs)' : ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                color: DelightColors.textMuted)),
          ])),
        const SizedBox(height: 20),

        _metricCard('P-E-T Score', totalUsers > 0 ? '${petScore.toStringAsFixed(1)}%' : '—',
          'Users with ≥1 completed transaction', readyPET,
          'Target: >70%'),
        _metricCard('Revenue : CAC', revToCac != null ? '${revToCac.toStringAsFixed(1)}×' : 'Not set',
          'Revenue earned per user so far, vs acquisition cost', readyRevCac,
          'Target: >3×', onEdit: () => _editSetting(context, 'cac_zar', 'Acquisition cost (R)')),
        _metricCard('Payback Period', paybackMonths != null ? '${paybackMonths.toStringAsFixed(1)} mo' : 'Not set',
          'Months to recover acquisition cost at current revenue/user', readyPayback,
          'Target: <12 months'),
        _metricCard('30-Day Retention', retention30d != null ? '${(retention30d * 100).toStringAsFixed(0)}%' : '—',
          'Users active again after their first 30 days', readyRetain,
          'Target: ≥80%'),
        _metricCard('MoM User Growth', momGrowth != null ? '${(momGrowth * 100).toStringAsFixed(0)}%' : '—',
          'Signups this month vs last month', readyGrowth,
          'Target: ≥20%'),
        _metricCard('NPS', nps != null ? nps.toStringAsFixed(0) : 'Not set',
          'Net Promoter Score — admin-entered from survey data', null,
          'No automatic target', onEdit: () => _editSetting(context, 'nps', 'NPS (-100 to 100)')),

        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DelightColors.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DelightColors.surfaceBorder)),
          child: const Text(
            'Acquisition cost and NPS have no source in the app\'s data — '
            'they come from marketing spend and survey results, so they\'re '
            'entered here manually (tap "Not set" above). Everything else on '
            'this tab is computed live from real signups and transactions.',
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
              color: DelightColors.textMuted, height: 1.4))),
        const SizedBox(height: 32),
      ]));
  }

  Widget _metricCard(String label, String value, String sub, bool? ready, String target,
      {VoidCallback? onEdit}) {
    final color = ready == null ? DelightColors.textMuted
      : ready ? DelightColors.emerald : DelightColors.error;
    return GestureDetector(
      onTap: onEdit,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: DelightColors.surfaceBorder)),
        child: Row(children: [
          Container(width: 8, height: 40,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
              fontSize: 13, color: DelightColors.textPrimary)),
            Text(sub, style: const TextStyle(fontFamily: 'Satoshi', fontSize: 10,
              color: DelightColors.textMuted)),
            Text(target, style: const TextStyle(fontFamily: 'Satoshi', fontSize: 9,
              color: DelightColors.textMuted)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(value, style: TextStyle(fontFamily: 'Clash', fontSize: 18,
              fontWeight: FontWeight.w700, color: color)),
            if (onEdit != null)
              const Text('tap to set', style: TextStyle(fontFamily: 'Satoshi',
                fontSize: 9, color: DelightColors.textMuted)),
          ]),
        ])));
  }
}
