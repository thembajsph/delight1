// lib/features/analytics/presentation/screens/admin_analytics_screen.dart
//
// DELIGHT ADMIN ANALYTICS DASHBOARD
//
// This is what YOU (Delight) see — not what organisers see.
// Every rand earned, every user gained, every agent transaction, every fee collected.
//
// Revenue streams tracked:
//  • P2P payments      — 0.5% fee per transaction (internal ledger)
//  • Ticket sales      — 3% fee per ticket
//  • Free event NFTs   — R2 per ticket (scan infrastructure)
//  • Private events    — R2 per ticket + R1 per guest over 50
//  • Premium invites   — R49 one-time
//  • ZAR/XRP spread    — difference between VALR buy rate and user rate
//  • Agent commissions — platform earns net float margin
//  • Event subscriptions — R299–R2,500/month (organiser plans)
//  • NFT resale royalty — 3% permanent on secondary sales
//
// User metrics tracked:
//  • DAU / MAU / WAU
//  • Consumer vs Business vs Organiser split
//  • Top-up method breakdown (agent / voucher / EFT / USSD)
//  • Retention by cohort
//  • Unbanked vs banked ratio
//
// Agent network tracked:
//  • Total agents by tier (Basic / Merchant / Super)
//  • Total float in network
//  • Top performing agents
//  • Flagged / reported agents
//  • Transaction volume per agent

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/xrpl_service.dart';

// ─── Seed data — what the admin sees ─────────────────────────────────────────

const _todayRevenue    = 48420.0;
const _weekRevenue     = 312800.0;
const _monthRevenue    = 1248600.0;
const _totalRevenue    = 8420000.0;
const _revenueGrowth   = 23.4;  // % vs last month

const _totalUsers      = 84200;
const _dau             = 12400;
const _mau             = 51800;
const _newToday        = 847;
const _userGrowth      = 18.2;

const _totalAgents     = 3840;
const _basicAgents     = 2910;
const _merchantAgents  = 782;
const _superAgents     = 148;
const _flaggedAgents   = 23;
const _totalFloat      = 4820000.0; // ZAR in network

const _totalEvents     = 2140;
const _activeEvents    = 84;
const _ticketsSold     = 284600;
const _ticketRevenue   = 854820.0; // Delight's 3% cut

// Revenue breakdown by stream — what feeds the business
final _revenueStreams = [
  _Stream('P2P Payments',     '💸', 312400,  DelightColors.emerald,
    'R1.5 per R100 sent. 208,267 transactions this month.'),
  _Stream('Ticket Sales (3%)', '🎟', 854820,  DelightColors.gold,
    '284,600 tickets × avg R4.99 fee (1.5%). Still biggest driver, 10× cheaper than Ticketmaster.'),
  _Stream('Free Event NFTs',   '🎫', 84200,   DelightColors.blue,
    'R2 per ticket × 42,100 free event tickets.'),
  _Stream('ZAR/XRP Spread',   '💱', 124800,  const Color(0xFFBF5FFF),
    '1.4% avg spread on R8.9M in top-ups this month.'),
  _Stream('Agent Float Margin','🏪', 48200,   DelightColors.textSecondary,
    'Net margin on agent float deployment.'),
  _Stream('Private Events',   '💍', 28400,   const Color(0xFFE8B4D0),
    '14,200 private event tickets × R2 + premium invites.'),
  _Stream('NFT Resale (3%)',  '♦️', 18200,   DelightColors.gold,
    '3% permanent royalty on secondary ticket market.'),
  _Stream('Subscriptions',    '📋', 42800,   const Color(0xFF00BFFF),
    '18 Pro organisers × R2,500/mo + 24 Standard × R299/mo.'),
];

// User acquisition by top-up method — tells you what channels to invest in
final _topupMethods = [
  _Method('Cash Agent',  DelightColors.emerald, 0.48, 40440),
  _Method('Voucher',     DelightColors.blue,    0.22, 18524),
  _Method('Bank EFT',    DelightColors.gold,    0.19, 16012),
  _Method('USSD',        DelightColors.textSecondary, 0.11, 9262),
];

// Revenue by day (last 14 days)
final _dailyRevenue = <double>[
  18400, 22100, 19800, 31200, 28400, 24600, 42800,
  38200, 44100, 36800, 29400, 51200, 48420, 48420,
];

// Top agents
final _topAgents = [
  _AgentRow('Mama Tuck Shop',    'Soweto',     4.9, 2400, 184200,  'Merchant'),
  _AgentRow('Flash Spaza Alex',  'Alexandra',  4.8, 1820, 142800,  'Merchant'),
  _AgentRow('Kazang Hillbrow',   'Hillbrow',   4.7, 3200, 218400,  'Super'),
  _AgentRow('OTT Maboneng',      'Maboneng',   4.6, 940,  72400,   'Basic'),
  _AgentRow('Mdumba Corner',     'Khayelitsha',4.9, 1640, 128600,  'Merchant'),
];

// Flagged agents (multiple reports)
final _flaggedAgentList = [
  _FlagRow('Unknown Spaza',    'Reports: 4', '3 users reported overcharging'),
  _FlagRow('Fast Cash Point',  'Reports: 2', 'Did not credit wallet after cash received'),
  _FlagRow('Voucher Express',  'Reports: 6', 'Selling at premium — multiple complaints'),
];

// ─── Screen ───────────────────────────────────────────────────────────────────

class AdminAnalyticsScreen extends ConsumerStatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  ConsumerState<AdminAnalyticsScreen> createState() =>
      _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends ConsumerState<AdminAnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String _period = 'Month';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      appBar: AppBar(
        backgroundColor: DelightColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: DelightColors.textPrimary),
          onPressed: () => context.pop()),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Delight Analytics', style: TextStyle(
            fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary)),
          const Text('Platform · Admin only', style: TextStyle(
            fontFamily: 'Satoshi', fontSize: 11,
            color: DelightColors.textMuted)),
        ]),
        actions: [
          // Period selector
          Container(
            margin: const EdgeInsets.only(right: 14),
            child: Row(children: ['Today', 'Week', 'Month', 'All'].map((p) {
              final sel = p == _period;
              return GestureDetector(
                onTap: () => setState(() => _period = p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  margin: const EdgeInsets.only(left: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: sel ? DelightColors.emerald : DelightColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: sel
                        ? Colors.transparent
                        : DelightColors.surfaceBorder)),
                  child: Text(p, style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: sel
                      ? DelightColors.textInverse
                      : DelightColors.textMuted))));
            }).toList()),
          ),
        ],
        bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
          controller: _tab,
          indicatorColor: DelightColors.emerald,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: DelightColors.textPrimary,
          unselectedLabelColor: DelightColors.textMuted,
          labelStyle: const TextStyle(
            fontFamily: 'Satoshi', fontWeight: FontWeight.w700, fontSize: 12),
          tabs: const [
            Tab(text: '💰 Revenue'),
            Tab(text: '👥 Users'),
            Tab(text: '🏪 Agents'),
            Tab(text: '🎟 Events'),
          ],
        )),
      body: TabBarView(
        controller: _tab,
        children: [
          _RevenueTab(period: _period),
          _UsersTab(period: _period),
          _AgentsTab(),
          _EventsTab(period: _period),
        ],
      ));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// REVENUE TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _RevenueTab extends StatelessWidget {
  final String period;
  const _RevenueTab({required this.period});

  double get _rev {
    switch (period) {
      case 'Today': return _todayRevenue;
      case 'Week':  return _weekRevenue;
      case 'Month': return _monthRevenue;
      default:      return _totalRevenue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Hero revenue card
        _heroRevCard(_rev, _revenueGrowth, period),
        const SizedBox(height: 16),

        // 14-day sparkline
        _DailyChart(data: _dailyRevenue),
        const SizedBox(height: 20),

        // Revenue breakdown by stream
        const Text('Revenue by Stream', style: TextStyle(
          fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('Every rand earned and where it came from',
          style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
            color: DelightColors.textMuted)),
        const SizedBox(height: 12),

        ..._revenueStreams.map((s) => _streamCard(s)),
        const SizedBox(height: 20),

        // Pie chart
        const Text('Revenue Split', style: TextStyle(
          fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 12),
        _RevenuePie(),
        const SizedBox(height: 20),

        // Fee model explainer
        _feeExplainer(),
        const SizedBox(height: 32),
      ]));
  }

  Widget _heroRevCard(double rev, double growth, String period) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D2A1A), Color(0xFF0A1F14)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('DELIGHT REVENUE · $period'.toUpperCase(), style: const TextStyle(
          fontFamily: 'Satoshi', fontSize: 10, color: DelightColors.textMuted,
          letterSpacing: 1.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(DelightCurrency.formatZAR(rev), style: const TextStyle(
          fontFamily: 'Clash', fontSize: 44, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary, letterSpacing: -1.5, height: 1)),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.trending_up, color: DelightColors.emerald, size: 16),
          const SizedBox(width: 4),
          Text('+$growth% vs last $period', style: const TextStyle(
            fontFamily: 'Satoshi', fontSize: 13, fontWeight: FontWeight.w700,
            color: DelightColors.emerald)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          _miniStat('R${(_todayRevenue / 1000).toStringAsFixed(1)}K', 'Today'),
          _vd(),
          _miniStat('R${(_weekRevenue / 1000).toStringAsFixed(0)}K', 'This Week'),
          _vd(),
          _miniStat('R${(_monthRevenue / 1000).toStringAsFixed(0)}K', 'This Month'),
        ]),
      ]));
  }

  Widget _miniStat(String v, String l) => Expanded(child: Column(children: [
    Text(v, style: const TextStyle(fontFamily: 'Clash', fontSize: 15,
      fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
    Text(l, style: const TextStyle(fontFamily: 'Satoshi', fontSize: 9,
      color: DelightColors.textMuted)),
  ]));

  Widget _vd() => Container(
    width: 1, height: 28, color: Colors.white12);

  Widget _streamCard(_Stream s) {
    final pct = s.amount / _revenueStreams.fold(0.0, (t, x) => t + x.amount);
    return GestureDetector(
      onTap: () {},
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: DelightColors.surfaceBorder)),
        child: Column(children: [
          Row(children: [
            Text(s.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name, style: const TextStyle(fontFamily: 'Satoshi',
                fontWeight: FontWeight.w700, fontSize: 14,
                color: DelightColors.textPrimary)),
              Text(s.detail, style: const TextStyle(fontFamily: 'Satoshi',
                fontSize: 11, color: DelightColors.textMuted, height: 1.3)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(DelightCurrency.formatZAR(s.amount), style: TextStyle(
                fontFamily: 'Clash', fontSize: 15, fontWeight: FontWeight.w700,
                color: s.color)),
              Text('${(pct * 100).toStringAsFixed(1)}%', style: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 10,
                color: DelightColors.textMuted)),
            ]),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: DelightColors.surfaceBorder,
              valueColor: AlwaysStoppedAnimation(s.color),
              minHeight: 4)),
        ])));
  }

  Widget _feeExplainer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DelightColors.goldGlow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DelightColors.gold.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('💡 Fee Model', style: TextStyle(fontFamily: 'Satoshi',
          fontWeight: FontWeight.w700, fontSize: 13, color: DelightColors.gold)),
        const SizedBox(height: 10),
        ...[
          ('P2P Send/Receive', '0.5% — internal, no conversion'),
          ('Consumer → Business', '1.0% — internal ledger'),
          ('Ticket Sales', '1.5% + R0.05 NFT mint'),
          ('Cashout to ZAR', '0.5% app + VALR maker = ~0.5–2.1%'),
          ('Free Event Ticket', 'R2 per ticket (NFT scan infrastructure)'),
          ('Private Event Ticket', 'R2 per ticket + R1/guest above 50'),
          ('Premium Invite Design', 'R49 one-time'),
          ('NFT Resale Royalty', '3% permanent on secondary sales'),
          ('Organiser Subscription', 'R299–R2,500/month'),
          ('Agent Commission', '1% Basic · 2% Merchant · 0.5% Super network'),
          ('VALR Maker Rebates', '+0.05% per order — earns on cashout flows'),
        ].map((f) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(child: Text(f.$1, style: const TextStyle(
              fontFamily: 'Satoshi', fontSize: 12,
              color: DelightColors.textSecondary))),
            Text(f.$2, style: const TextStyle(fontFamily: 'Satoshi',
              fontSize: 12, fontWeight: FontWeight.w700,
              color: DelightColors.gold)),
          ]))),
      ]));
  }
}

class _RevenuePie extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final total = _revenueStreams.fold(0.0, (t, s) => t + s.amount);
    return Row(children: [
      SizedBox(width: 160, height: 160,
        child: PieChart(PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 44,
          sections: _revenueStreams.map((s) =>
            PieChartSectionData(
              value: s.amount,
              color: s.color,
              title: '',
              radius: 28)).toList()))),
      const SizedBox(width: 14),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _revenueStreams.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Container(width: 8, height: 8,
              decoration: BoxDecoration(
                color: s.color,
                borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 6),
            Expanded(child: Text(s.name, style: const TextStyle(
              fontFamily: 'Satoshi', fontSize: 10,
              color: DelightColors.textSecondary),
              overflow: TextOverflow.ellipsis)),
            Text('${(s.amount / total * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 10,
                fontWeight: FontWeight.w700, color: s.color)),
          ]))).toList())),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// USERS TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _UsersTab extends StatelessWidget {
  final String period;
  const _UsersTab({required this.period});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Total users hero
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              DelightColors.blue.withOpacity(0.15),
              DelightColors.background]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: DelightColors.blue.withOpacity(0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            const Text('TOTAL USERS', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 10,
              color: DelightColors.textMuted, letterSpacing: 1.5)),
            const SizedBox(height: 6),
            Text(_totalUsers.toLocaleString(), style: const TextStyle(
              fontFamily: 'Clash', fontSize: 44, fontWeight: FontWeight.w700,
              color: DelightColors.textPrimary, letterSpacing: -1.5, height: 1)),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.trending_up, color: DelightColors.emerald, size: 16),
              const SizedBox(width: 4),
              Text('+$_newToday new today · +$_userGrowth% this month',
                style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                  fontWeight: FontWeight.w700, color: DelightColors.emerald)),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              _uStat(_dau.toLocaleString(), 'DAU', DelightColors.emerald),
              _vd(),
              _uStat(_mau.toLocaleString(), 'MAU', DelightColors.blue),
              _vd(),
              _uStat(
                '${(_dau / _mau * 100).toStringAsFixed(0)}%',
                'DAU/MAU', DelightColors.gold),
            ]),
          ])),
        const SizedBox(height: 16),

        // Role breakdown
        const Text('Users by Mode', style: TextStyle(
          fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('How many people switched to each mode this month',
          style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
            color: DelightColors.textMuted)),
        const SizedBox(height: 12),
        _roleBar('👤 Consumer',  0.78, _totalUsers, DelightColors.blue),
        _roleBar('🏪 Business',  0.14, _totalUsers, DelightColors.emerald),
        _roleBar('🎪 Organiser', 0.08, _totalUsers, DelightColors.gold),
        const SizedBox(height: 20),

        // Top-up method breakdown — KEY for unbanked strategy
        const Text('Top-Up Method Breakdown', style: TextStyle(
          fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('48% of users top up via cash agent — zero bank account needed',
          style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
            color: DelightColors.emerald, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ..._topupMethods.map((m) => _topupMethodCard(m)),
        const SizedBox(height: 20),

        // Unbanked insight card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              DelightColors.emerald.withOpacity(0.1),
              DelightColors.gold.withOpacity(0.05)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Text('🌍', style: TextStyle(fontSize: 24)),
              SizedBox(width: 10),
              Text('Unbanked Impact', style: TextStyle(
                fontFamily: 'Clash', fontSize: 16, fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary)),
            ]),
            const SizedBox(height: 12),
            ...[
              ('40,296 users', 'topped up via cash agent — no bank account'),
              ('7,814 users',  'using USSD only — no smartphone'),
              ('R4.2M',        'moved through the agent network this month'),
              ('3,840 agents', 'in the network processing cash top-ups'),
            ].map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: DelightColors.emeraldGlow,
                    borderRadius: BorderRadius.circular(6)),
                  child: Text(s.$1, style: const TextStyle(
                    fontFamily: 'Clash', fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: DelightColors.emerald))),
                const SizedBox(width: 8),
                Expanded(child: Text(s.$2, style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 12,
                  color: DelightColors.textSecondary))),
              ]))),
          ])),
        const SizedBox(height: 20),

        // Retention
        const Text('30-Day Retention', style: TextStyle(
          fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 12),
        _RetentionChart(),
        const SizedBox(height: 32),
      ]));
  }

  Widget _uStat(String v, String l, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontFamily: 'Clash', fontSize: 15,
      fontWeight: FontWeight.w700, color: c)),
    Text(l, style: const TextStyle(fontFamily: 'Satoshi', fontSize: 9,
      color: DelightColors.textMuted)),
  ]));

  Widget _vd() => Container(width: 1, height: 28, color: Colors.white12);

  Widget _roleBar(String label, double pct, int total, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Column(children: [
        Row(children: [
          Text(label, style: const TextStyle(fontFamily: 'Satoshi',
            fontWeight: FontWeight.w700, fontSize: 14,
            color: DelightColors.textPrimary)),
          const Spacer(),
          Text('${(total * pct).round().toLocaleString()} users',
            style: TextStyle(fontFamily: 'Clash', fontSize: 14,
              fontWeight: FontWeight.w700, color: color)),
          const SizedBox(width: 6),
          Text('${(pct * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontFamily: 'Satoshi', fontSize: 11,
              color: DelightColors.textMuted)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: DelightColors.surfaceBorder,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6)),
      ]));
  }

  Widget _topupMethodCard(_Method m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: m.color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: m.color.withOpacity(0.25))),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(m.name, style: const TextStyle(fontFamily: 'Satoshi',
            fontWeight: FontWeight.w700, fontSize: 14,
            color: DelightColors.textPrimary)),
          Text('${m.count.toLocaleString()} users',
            style: const TextStyle(fontFamily: 'Satoshi', fontSize: 11,
              color: DelightColors.textMuted)),
        ])),
        Text('${(m.pct * 100).toStringAsFixed(0)}%', style: TextStyle(
          fontFamily: 'Clash', fontSize: 22, fontWeight: FontWeight.w700,
          color: m.color)),
        const SizedBox(width: 10),
        SizedBox(width: 80, child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: m.pct,
            backgroundColor: DelightColors.surfaceBorder,
            valueColor: AlwaysStoppedAnimation(m.color),
            minHeight: 8))),
      ]));
  }
}

class _RetentionChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final data = [100.0, 72, 58, 48, 42, 38, 35, 32, 30, 29, 28, 27, 26, 25, 24];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Day 30 Retention: 24%',
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
              fontWeight: FontWeight.w700, color: DelightColors.textPrimary))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: DelightColors.emeraldGlow,
              borderRadius: BorderRadius.circular(6)),
            child: const Text('Industry avg: 18%', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 10,
              fontWeight: FontWeight.w700, color: DelightColors.emerald))),
        ]),
        const SizedBox(height: 14),
        SizedBox(height: 100, child: LineChart(LineChartData(
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => const FlLine(
              color: DelightColors.surfaceBorder, strokeWidth: 1)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 18,
              getTitlesWidget: (v, _) => Text(
                v == 0 ? 'D1' : v == 7 ? 'D7' : v == 14 ? 'D14' : v == 14 ? 'D30' : '',
                style: const TextStyle(fontFamily: 'Satoshi', fontSize: 8,
                  color: DelightColors.textMuted)))),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))),
          lineBarsData: [LineChartBarData(
            spots: data.asMap().entries.map((e) =>
              FlSpot(e.key.toDouble(), e.value.toDouble())).toList(),
            isCurved: true,
            color: DelightColors.emerald,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: DelightColors.emerald.withOpacity(0.1)))],
        ))),
      ]));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AGENTS TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _AgentsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Agent network overview
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              DelightColors.gold.withOpacity(0.12),
              DelightColors.background]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: DelightColors.gold.withOpacity(0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            const Text('AGENT NETWORK', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 10,
              color: DelightColors.textMuted,
              letterSpacing: 1.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(_totalAgents.toLocaleString(), style: const TextStyle(
              fontFamily: 'Clash', fontSize: 44, fontWeight: FontWeight.w700,
              color: DelightColors.textPrimary, letterSpacing: -1.5, height: 1)),
            const Text('active agents across SA', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 13, color: DelightColors.textMuted)),
            const SizedBox(height: 16),
            Row(children: [
              _aStat(_basicAgents.toString(), 'Basic (1%)', DelightColors.textSecondary),
              _vd(),
              _aStat(_merchantAgents.toString(), 'Merchant (2%)', DelightColors.emerald),
              _vd(),
              _aStat(_superAgents.toString(), 'Super (0.5%)', DelightColors.gold),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.account_balance_wallet_outlined,
                color: DelightColors.emerald, size: 14),
              const SizedBox(width: 6),
              Text(
                'R${(_totalFloat / 1000000).toStringAsFixed(1)}M total float in network',
                style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                  fontWeight: FontWeight.w600, color: DelightColors.emerald)),
            ]),
            if (_flaggedAgents > 0) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.warning_amber_outlined,
                  color: DelightColors.error, size: 14),
                const SizedBox(width: 6),
                Text('$_flaggedAgents agents flagged for review',
                  style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                    fontWeight: FontWeight.w600, color: DelightColors.error)),
              ]),
            ],
          ])),
        const SizedBox(height: 20),

        // Top agents
        const Text('Top Performing Agents', style: TextStyle(
          fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('Ranked by total volume processed this month',
          style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
            color: DelightColors.textMuted)),
        const SizedBox(height: 12),
        ..._topAgents.asMap().entries.map((e) =>
          _agentCard(e.key + 1, e.value)),
        const SizedBox(height: 20),

        // Flagged agents — Uber-style review system
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: DelightColors.error.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DelightColors.error.withOpacity(0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.flag_outlined,
                color: DelightColors.error, size: 20),
              const SizedBox(width: 8),
              const Expanded(child: Text('Flagged Agents',
                style: TextStyle(fontFamily: 'Clash', fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: DelightColors.textPrimary))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: DelightColors.error.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6)),
                child: Text('$_flaggedAgents pending', style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 11,
                  fontWeight: FontWeight.w700, color: DelightColors.error))),
            ]),
            const SizedBox(height: 4),
            const Text('Multiple user reports. Review and suspend if confirmed.',
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                color: DelightColors.textMuted)),
            const SizedBox(height: 12),
            ..._flaggedAgentList.map((f) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DelightColors.surfaceHigh,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DelightColors.surfaceBorder)),
              child: Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.name, style: const TextStyle(fontFamily: 'Satoshi',
                    fontWeight: FontWeight.w700, fontSize: 13,
                    color: DelightColors.textPrimary)),
                  Text(f.complaint, style: const TextStyle(fontFamily: 'Satoshi',
                    fontSize: 11, color: DelightColors.textMuted)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: DelightColors.error.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6)),
                    child: Text(f.reportCount, style: const TextStyle(
                      fontFamily: 'Satoshi', fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: DelightColors.error))),
                  const SizedBox(height: 4),
                  Row(children: [
                    GestureDetector(
                      onTap: () {},
                      child: const Text('Review', style: TextStyle(
                        fontFamily: 'Satoshi', fontSize: 11,
                        color: DelightColors.gold,
                        decoration: TextDecoration.underline))),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {},
                      child: const Text('Suspend', style: TextStyle(
                        fontFamily: 'Satoshi', fontSize: 11,
                        color: DelightColors.error,
                        decoration: TextDecoration.underline))),
                  ]),
                ]),
              ]))),
          ])),
        const SizedBox(height: 32),
      ]));
  }

  Widget _aStat(String v, String l, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontFamily: 'Clash', fontSize: 15,
      fontWeight: FontWeight.w700, color: c)),
    Text(l, style: const TextStyle(fontFamily: 'Satoshi', fontSize: 9,
      color: DelightColors.textMuted)),
  ]));

  Widget _vd() => Container(width: 1, height: 28, color: Colors.white12);

  Widget _agentCard(int rank, _AgentRow agent) {
    final tierColor = agent.tier == 'Super'
      ? DelightColors.gold
      : agent.tier == 'Merchant'
      ? DelightColors.emerald
      : DelightColors.textSecondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: rank <= 3
            ? DelightColors.gold.withOpacity(0.3)
            : DelightColors.surfaceBorder)),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: rank <= 3
              ? DelightColors.gold.withOpacity(0.15)
              : DelightColors.surfaceBorder,
            borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Text('#$rank', style: TextStyle(
            fontFamily: 'Clash', fontSize: 12, fontWeight: FontWeight.w700,
            color: rank <= 3 ? DelightColors.gold : DelightColors.textMuted))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(agent.name, style: const TextStyle(fontFamily: 'Satoshi',
            fontWeight: FontWeight.w700, fontSize: 13,
            color: DelightColors.textPrimary)),
          Row(children: [
            Text(agent.location, style: const TextStyle(fontFamily: 'Satoshi',
              fontSize: 10, color: DelightColors.textMuted)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: tierColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4)),
              child: Text(agent.tier, style: TextStyle(fontFamily: 'Satoshi',
                fontSize: 8, fontWeight: FontWeight.w700, color: tierColor))),
          ]),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(DelightCurrency.formatZAR(agent.volume), style: const TextStyle(
            fontFamily: 'Clash', fontSize: 13, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary)),
          Row(children: [
            ...List.generate(5, (i) => Icon(
              i < agent.rating.floor() ? Icons.star : Icons.star_border,
              color: DelightColors.gold, size: 10)),
            const SizedBox(width: 3),
            Text('${agent.txCount.toLocaleString()} tx', style: const TextStyle(
              fontFamily: 'Satoshi', fontSize: 10,
              color: DelightColors.textMuted)),
          ]),
        ]),
      ]));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENTS TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _EventsTab extends StatelessWidget {
  final String period;
  const _EventsTab({required this.period});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Events hero
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              DelightColors.gold.withOpacity(0.1),
              DelightColors.background]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: DelightColors.gold.withOpacity(0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            const Text('EVENTS ON PLATFORM', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 10,
              color: DelightColors.textMuted,
              letterSpacing: 1.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(_totalEvents.toLocaleString(), style: const TextStyle(
              fontFamily: 'Clash', fontSize: 44, fontWeight: FontWeight.w700,
              color: DelightColors.textPrimary, letterSpacing: -1.5, height: 1)),
            const Text('total events created', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 13,
              color: DelightColors.textMuted)),
            const SizedBox(height: 16),
            Row(children: [
              _eStat('$_activeEvents', 'Live Now', DelightColors.emerald),
              _vd(),
              _eStat(_ticketsSold.toLocaleString(), 'Tickets Sold', DelightColors.gold),
              _vd(),
              _eStat(DelightCurrency.formatZAR(_ticketRevenue * 0.5), 'Our Cut (1.5%)', DelightColors.blue),
            ]),
          ])),
        const SizedBox(height: 20),

        // Event categories
        const Text('Events by Category', style: TextStyle(
          fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 12),
        ...[
          ('🎵', 'Music / Festival',  0.38, 813,  DelightColors.emerald),
          ('⛪', 'Church / Gospel',   0.22, 471,  DelightColors.gold),
          ('🏃', 'Sport',             0.14, 300,  DelightColors.blue),
          ('💒', 'Wedding / Private', 0.12, 257,  const Color(0xFFE8B4D0)),
          ('🎨', 'Arts / Culture',    0.08, 171,  const Color(0xFFBF5FFF)),
          ('💼', 'Corporate',         0.06, 128,  DelightColors.textSecondary),
        ].map((c) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DelightColors.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DelightColors.surfaceBorder)),
          child: Row(children: [
            Text(c.$1, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.$2, style: const TextStyle(fontFamily: 'Satoshi',
                fontWeight: FontWeight.w700, fontSize: 13,
                color: DelightColors.textPrimary)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: c.$3,
                  backgroundColor: DelightColors.surfaceBorder,
                  valueColor: AlwaysStoppedAnimation(c.$5 as Color),
                  minHeight: 4)),
            ])),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${c.$4}', style: TextStyle(fontFamily: 'Clash',
                fontSize: 15, fontWeight: FontWeight.w700,
                color: c.$5 as Color)),
              Text('events', style: const TextStyle(fontFamily: 'Satoshi',
                fontSize: 9, color: DelightColors.textMuted)),
            ]),
          ]))),
        const SizedBox(height: 20),

        // Top organisers
        const Text('Top Organisers', style: TextStyle(
          fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('Ranked by Delight revenue generated',
          style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
            color: DelightColors.textMuted)),
        const SizedBox(height: 12),
        ...[
          ('Thabo Ndlovu',    'Johannesburg', 12400, 124500.0, 'Pro'),
          ('Amara Diallo',    'Lagos',        8200,  84200.0,  'Pro'),
          ('Kwame Asante',    'Accra',        6800,  68400.0,  'Standard'),
          ('Zainab Osei',     'Kigali',       4200,  42800.0,  'Standard'),
          ('Sipho Dlamini',   'Cape Town',    3800,  38200.0,  'Standard'),
        ].asMap().entries.map((e) {
          final o = e.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DelightColors.surfaceHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DelightColors.surfaceBorder)),
            child: Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: e.key < 3
                    ? DelightColors.gold.withOpacity(0.15)
                    : DelightColors.surfaceBorder,
                  borderRadius: BorderRadius.circular(6)),
                alignment: Alignment.center,
                child: Text('#${e.key + 1}', style: TextStyle(
                  fontFamily: 'Clash', fontSize: 11, fontWeight: FontWeight.w700,
                  color: e.key < 3 ? DelightColors.gold : DelightColors.textMuted))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text(o.$1, style: const TextStyle(fontFamily: 'Satoshi',
                  fontWeight: FontWeight.w700, fontSize: 13,
                  color: DelightColors.textPrimary)),
                Row(children: [
                  Text(o.$2, style: const TextStyle(fontFamily: 'Satoshi',
                    fontSize: 10, color: DelightColors.textMuted)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: o.$5 == 'Pro'
                        ? DelightColors.gold.withOpacity(0.15)
                        : DelightColors.emeraldGlow,
                      borderRadius: BorderRadius.circular(4)),
                    child: Text(o.$5, style: TextStyle(
                      fontFamily: 'Satoshi', fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: o.$5 == 'Pro'
                        ? DelightColors.gold
                        : DelightColors.emerald))),
                ]),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(DelightCurrency.formatZAR(o.$4), style: const TextStyle(
                  fontFamily: 'Clash', fontSize: 13, fontWeight: FontWeight.w700,
                  color: DelightColors.emerald)),
                Text('${o.$3.toLocaleString()} tickets', style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 10,
                  color: DelightColors.textMuted)),
              ]),
            ]));
        }),
        const SizedBox(height: 32),
      ]));
  }

  Widget _eStat(String v, String l, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontFamily: 'Clash', fontSize: 13,
      fontWeight: FontWeight.w700, color: c)),
    Text(l, style: const TextStyle(fontFamily: 'Satoshi', fontSize: 9,
      color: DelightColors.textMuted)),
  ]));

  Widget _vd() => Container(width: 1, height: 28, color: Colors.white12);
}

// ─── Revenue sparkline chart ─────────────────────────────────────────────────

class _DailyChart extends StatelessWidget {
  final List<double> data;
  const _DailyChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxY = data.reduce((a, b) => a > b ? a : b) * 1.2;
    return Container(
      height: 140,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Revenue — Last 14 Days', style: TextStyle(
          fontFamily: 'Satoshi', fontSize: 11, fontWeight: FontWeight.w700,
          color: DelightColors.textMuted, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Expanded(child: LineChart(LineChartData(
          gridData: FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))),
          maxY: maxY,
          lineBarsData: [LineChartBarData(
            spots: data.asMap().entries.map((e) =>
              FlSpot(e.key.toDouble(), e.value.toDouble())).toList(),
            isCurved: true,
            color: DelightColors.emerald,
            barWidth: 2.5,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, index) => FlDotCirclePainter(
                radius: index == data.length - 1 ? 4 : 0,
                color: DelightColors.gold,
                strokeWidth: 0,
                strokeColor: Colors.transparent)),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  DelightColors.emerald.withOpacity(0.2),
                  DelightColors.emerald.withOpacity(0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter)))],
        ))),
      ]));
  }
}

// ─── Models ───────────────────────────────────────────────────────────────────

class _Stream {
  final String name, emoji, detail;
  final double amount;
  final Color color;
  const _Stream(this.name, this.emoji, this.amount, this.color, this.detail);
}

class _Method {
  final String name;
  final Color color;
  final double pct;
  final int count;
  const _Method(this.name, this.color, this.pct, this.count);
}

class _AgentRow {
  final String name, location, tier;
  final double rating, volume;
  final int txCount;
  const _AgentRow(this.name, this.location, this.rating,
    this.txCount, this.volume, this.tier);
}

class _FlagRow {
  final String name, reportCount, complaint;
  const _FlagRow(this.name, this.reportCount, this.complaint);
}

extension _IntFmt on int {
  String toLocaleString() {
    final s = toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
