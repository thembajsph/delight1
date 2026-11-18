// lib/features/rewards/presentation/screens/rewards_screen.dart
// Daily DC rewards + NFT badges + Leaderboard — all backed by Supabase.
//
//  • Daily tasks are verified AND credited server-side (claim_reward_task RPC).
//    The client can no longer credit itself.
//  • Badge progress comes from real counters (get_my_stats RPC).
//  • The leaderboard ranks users by DC earned from rewards in the period
//    (get_leaderboard RPC) — not by spending, so no private financial data is
//    exposed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/services/supabase_service.dart';

class RewardsScreen extends ConsumerStatefulWidget {
  const RewardsScreen({super.key});
  @override ConsumerState<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends ConsumerState<RewardsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      appBar: AppBar(
        title: const Text('Rewards & Leaderboard', style: TextStyle(
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
          labelStyle: const TextStyle(
            fontFamily: 'Satoshi', fontWeight: FontWeight.w700, fontSize: 12),
          tabs: const [
            Tab(text: 'Daily DC'),
            Tab(text: 'NFT Badges'),
            Tab(text: 'Leaderboard'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _DailyRewardsTab(),
          _BadgesTab(),
          _LeaderboardTab(),
        ],
      ),
    );
  }
}

// ── Shared small widgets ─────────────────────────────────────────────────────

class _Message extends StatelessWidget {
  final String emoji, text;
  final VoidCallback? onRetry;
  const _Message(this.emoji, this.text, {this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 44)),
      const SizedBox(height: 12),
      Text(text, textAlign: TextAlign.center, style: const TextStyle(
        fontFamily: 'Satoshi', fontSize: 14, height: 1.5,
        color: DelightColors.textMuted)),
      if (onRetry != null) ...[
        const SizedBox(height: 12),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ])));
}

// ── Daily DC Rewards ─────────────────────────────────────────────────────────

class _DailyRewardsTab extends ConsumerStatefulWidget {
  const _DailyRewardsTab();
  @override ConsumerState<_DailyRewardsTab> createState() => _DailyRewardsTabState();
}

class _DailyRewardsTabState extends ConsumerState<_DailyRewardsTab> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _claiming;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await SupabaseService.getRewardsToday();
    if (!mounted) return;
    setState(() { _data = d; _loading = false; });
  }

  Future<void> _claim(String id) async {
    if (_claiming != null) return;
    setState(() => _claiming = id);
    try {
      final reward = await SupabaseService.claimRewardTask(id);
      await ref.read(walletProvider.notifier).refreshBalance();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('+${reward.toStringAsFixed(2)} DC earned! 🔥'),
        backgroundColor: DelightColors.emerald));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: DelightColors.error));
    } finally {
      if (mounted) setState(() => _claiming = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator(
        color: DelightColors.emerald));
    }
    final d = _data;
    if (d == null) {
      return _Message('📡', "Couldn't load your rewards. Check your connection.",
        onRetry: _load);
    }

    final tasks = List<Map<String, dynamic>>.from(d['tasks'] as List);
    final streak = (d['streak'] as num?)?.toInt() ?? 0;
    final week = List<bool>.from((d['week'] as List).map((e) => e == true));
    final earned = (d['earned_today'] as num?)?.toDouble() ?? 0;
    final total = tasks.fold<double>(
      0, (s, t) => s + ((t['reward'] as num?)?.toDouble() ?? 0));

    return RefreshIndicator(
      color: DelightColors.emerald,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Streak card — consecutive days you opened Delight
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A2E0A), Color(0xFF0A1F05)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('🔥', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(streak == 0
                      ? 'No streak yet'
                      : '$streak Day Streak${streak == 1 ? '' : '!'}',
                    style: const TextStyle(
                      fontFamily: 'Clash', fontSize: 22, fontWeight: FontWeight.w700,
                      color: DelightColors.textPrimary)),
                  const Text('Open Delight every day to keep it going',
                    style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                      color: DelightColors.textMuted)),
                ])),
              ]),
              const SizedBox(height: 16),
              Row(children: List.generate(7, (i) => Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: i < week.length && week[i]
                      ? DelightColors.gold : DelightColors.surfaceBorder)),
              ))),
              const SizedBox(height: 6),
              Row(children: ['M','T','W','T','F','S','S'].map((d) => Expanded(
                child: Text(d, textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Satoshi',
                    fontSize: 9, color: DelightColors.textMuted)))).toList()),
            ]),
          ),
          const SizedBox(height: 20),

          Row(children: [
            Expanded(child: _stat('Earned Today', earned, DelightColors.emerald)),
            const SizedBox(width: 10),
            Expanded(child: _stat('Available Today', total, DelightColors.gold)),
          ]),
          const SizedBox(height: 20),

          const Text("Today's Tasks", style: TextStyle(
            fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('Complete the activity, then tap to claim. Tasks reset daily.',
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
              color: DelightColors.textMuted)),
          const SizedBox(height: 12),

          if (tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No reward tasks are active right now.',
                style: TextStyle(fontFamily: 'Satoshi',
                  color: DelightColors.textMuted)))),

          ...tasks.map(_taskTile),
        ]),
      ),
    );
  }

  Widget _stat(String label, double dc, Color color) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: DelightColors.surfaceHigh,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: DelightColors.surfaceBorder)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
        fontFamily: 'Satoshi', fontSize: 11, color: DelightColors.textMuted)),
      const SizedBox(height: 4),
      Text('${dc.toStringAsFixed(2)} DC', style: TextStyle(
        fontFamily: 'Clash', fontSize: 22, fontWeight: FontWeight.w700,
        color: color)),
    ]));

  Widget _taskTile(Map<String, dynamic> t) {
    final id = t['id'] as String;
    final claimed = t['claimed'] == true;
    final eligible = t['eligible'] == true;
    final reward = (t['reward'] as num?)?.toDouble() ?? 0;
    final busy = _claiming == id;
    final canClaim = eligible && !claimed && _claiming == null;

    final String label = claimed
      ? '✓ Claimed'
      : busy ? '…'
      : eligible ? 'Claim +${reward.toStringAsFixed(2)} DC'
      : '+${reward.toStringAsFixed(2)} DC';
    final Color labelColor = claimed
      ? DelightColors.emerald
      : eligible ? DelightColors.gold : DelightColors.textMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: canClaim ? () => _claim(id) : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: claimed ? DelightColors.emeraldGlow : DelightColors.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: claimed
                ? DelightColors.emerald.withOpacity(0.4)
                : eligible
                  ? DelightColors.gold.withOpacity(0.5)
                  : DelightColors.surfaceBorder)),
          child: Row(children: [
            Text(t['emoji'] as String? ?? '🎁',
              style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t['title'] as String? ?? '', style: const TextStyle(
                fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                fontSize: 14, color: DelightColors.textPrimary)),
              Text(eligible || claimed
                  ? (claimed ? 'Reward claimed for today' : 'Done — tap to claim')
                  : (t['description'] as String? ?? ''),
                style: const TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                  color: DelightColors.textMuted)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: claimed
                  ? DelightColors.emerald.withOpacity(0.2)
                  : eligible ? DelightColors.goldGlow : DelightColors.surfaceBorder,
                borderRadius: BorderRadius.circular(8)),
              child: Text(label, style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 11, fontWeight: FontWeight.w700,
                color: labelColor))),
          ]),
        )));
  }
}

// ── NFT Badges ────────────────────────────────────────────────────────────────

class _Badge {
  final String emoji, name, desc, rarity;
  final Color color;
  final String statKey;     // key in get_my_stats()
  final int target;         // value needed to earn it
  const _Badge({required this.emoji, required this.name, required this.desc,
    required this.rarity, required this.color, required this.statKey,
    required this.target});
}

const _badgeDefs = <_Badge>[
  _Badge(emoji: '🎟', name: 'First Ticket', desc: 'Bought your first NFT ticket',
    rarity: 'Common', color: DelightColors.emerald, statKey: 'tickets_bought', target: 1),
  _Badge(emoji: '⚡', name: 'Early Adopter', desc: 'Joined in the first 1,000 users',
    rarity: 'Rare', color: DelightColors.gold, statKey: 'early_adopter', target: 1),
  _Badge(emoji: '💸', name: 'First Payment', desc: 'Sent your first payment',
    rarity: 'Common', color: DelightColors.emerald, statKey: 'payments_sent', target: 1),
  _Badge(emoji: '🔥', name: 'VIP Regular', desc: 'Hold VIP tickets to 3 events',
    rarity: 'Rare', color: DelightColors.gold, statKey: 'vip_events', target: 3),
  _Badge(emoji: '👑', name: 'Event Royalty', desc: 'Attend 10 events on Delight',
    rarity: 'Legendary', color: Colors.purple, statKey: 'events_attended', target: 10),
  _Badge(emoji: '🎯', name: 'Influencer', desc: 'Get 500 likes on a single post',
    rarity: 'Rare', color: DelightColors.gold, statKey: 'best_post_likes', target: 500),
  _Badge(emoji: '🚀', name: 'Power User', desc: 'Open the app 30 days in a row',
    rarity: 'Epic', color: DelightColors.blue, statKey: 'streak', target: 30),
];

class _BadgesTab extends StatefulWidget {
  const _BadgesTab();
  @override State<_BadgesTab> createState() => _BadgesTabState();
}

class _BadgesTabState extends State<_BadgesTab> {
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await SupabaseService.getMyStats();
    if (!mounted) return;
    setState(() { _stats = s; _loading = false; });
  }

  int _value(_Badge b) {
    final v = _stats?[b.statKey];
    if (v is bool) return v ? 1 : 0;
    return (v as num?)?.toInt() ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _stats == null) {
      return const Center(child: CircularProgressIndicator(
        color: DelightColors.emerald));
    }
    if (_stats == null) {
      return _Message('📡', "Couldn't load your badges. Check your connection.",
        onRetry: _load);
    }
    final earned = _badgeDefs.where((b) => _value(b) >= b.target).toList();
    final locked = _badgeDefs.where((b) => _value(b) < b.target).toList();

    return RefreshIndicator(
      color: DelightColors.emerald,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Earned (${earned.length})', style: const TextStyle(
            fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary)),
          const SizedBox(height: 12),
          if (earned.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('No badges yet — complete the goals below to earn your first.',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                  color: DelightColors.textMuted)))
          else
            _grid(earned, false),
          const SizedBox(height: 24),
          Text('In Progress / Locked (${locked.length})', style: const TextStyle(
            fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary)),
          const SizedBox(height: 12),
          _grid(locked, true),
        ]),
      ),
    );
  }

  Widget _grid(List<_Badge> badges, bool locked) => GridView.builder(
    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2, childAspectRatio: 1.4,
      crossAxisSpacing: 10, mainAxisSpacing: 10),
    itemCount: badges.length,
    itemBuilder: (_, i) {
      final b = badges[i];
      final v = _value(b);
      return _BadgeCard(badge: b, locked: locked,
        progress: locked ? '${v.clamp(0, b.target)}/${b.target}' : null);
    });
}

class _BadgeCard extends StatelessWidget {
  final _Badge badge;
  final bool locked;
  final String? progress;
  const _BadgeCard({required this.badge, required this.locked, this.progress});

  Color get _rarityColor {
    switch (badge.rarity) {
      case 'Legendary': return Colors.purple;
      case 'Epic':      return DelightColors.blue;
      case 'Rare':      return DelightColors.gold;
      default:          return DelightColors.emerald;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: locked ? DelightColors.surfaceHigh : badge.color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: locked ? DelightColors.surfaceBorder : badge.color.withOpacity(0.4)),
        boxShadow: locked ? [] : [BoxShadow(
          color: badge.color.withOpacity(0.1), blurRadius: 12)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(locked ? '🔒' : badge.emoji,
            style: TextStyle(fontSize: locked ? 16 : 24)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _rarityColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4)),
            child: Text(badge.rarity, style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 8,
              fontWeight: FontWeight.w700, color: _rarityColor)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(badge.name, style: TextStyle(
          fontFamily: 'Satoshi', fontWeight: FontWeight.w700, fontSize: 12,
          color: locked ? DelightColors.textMuted : DelightColors.textPrimary)),
        Text(badge.desc, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: 'Satoshi', fontSize: 9,
            color: DelightColors.textMuted)),
        if (progress != null)
          Text(progress!, style: const TextStyle(
            fontFamily: 'Satoshi', fontSize: 10, color: DelightColors.gold)),
      ]),
    );
  }
}

// ── Leaderboard ───────────────────────────────────────────────────────────────

class _LeaderboardTab extends ConsumerStatefulWidget {
  const _LeaderboardTab();
  @override ConsumerState<_LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends ConsumerState<_LeaderboardTab> {
  static const _allAfrica = 'All Africa';
  String _city = _allAfrica;
  String _period = 'This Week';
  List<String> _cities = const [_allAfrica];
  List<Map<String, dynamic>> _leaders = [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() { super.initState(); _loadCities(); _load(); }

  Future<void> _loadCities() async {
    final c = await SupabaseService.getLeaderboardCities();
    if (!mounted) return;
    setState(() => _cities = [_allAfrica, ...c]);
  }

  Future<void> _load() async {
    setState(() { _loading = true; _failed = false; });
    try {
      final rows = await SupabaseService.getLeaderboard(
        city: _city == _allAfrica ? null : _city,
        period: _period == 'This Month' ? 'month' : 'week');
      if (!mounted) return;
      setState(() { _leaders = rows; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _failed = true; });
    }
  }

  Future<void> _setMyCity() async {
    final uid = ref.read(authProvider)?.id;
    if (uid == null) return;
    final ctrl = TextEditingController();
    final city = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DelightColors.surfaceHigh,
        title: const Text('Set your city'),
        content: TextField(
          controller: ctrl, autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Johannesburg')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save')),
        ]));
    if (city == null || city.isEmpty) return;
    try {
      await SupabaseService.updateProfile(uid, {'city': city});
      await _loadCities();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('City set to $city'),
        backgroundColor: DelightColors.emerald));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't save your city"),
        backgroundColor: DelightColors.error));
    }
  }

  Color _rankColor(int rank) => rank == 1 ? DelightColors.gold
    : rank == 2 ? Colors.grey
    : rank == 3 ? const Color(0xFFCD7F32) : DelightColors.textMuted;

  String _score(Map<String, dynamic> l) =>
    '${((l['score'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} DC';

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider)?.id;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(child: _filterChips(_cities, _city,
            (v) { setState(() => _city = v); _load(); })),
          const SizedBox(width: 8),
          Expanded(child: _filterChips(['This Week', 'This Month'], _period,
            (v) { setState(() => _period = v); _load(); })),
        ]),
      ),
      Expanded(child: _body(me)),
    ]);
  }

  Widget _body(String? me) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(
        color: DelightColors.emerald));
    }
    if (_failed) {
      return _Message('📡', "Couldn't load the leaderboard.", onRetry: _load);
    }
    if (_leaders.isEmpty) {
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const _Message('🏆',
          'No one has earned rewards in this period yet.\nClaim a daily task to take the #1 spot!'),
        TextButton(onPressed: _setMyCity,
          child: const Text('Set my city to join local boards')),
      ]);
    }

    final podium = _leaders.length >= 3 ? _leaders.take(3).toList() : <Map<String, dynamic>>[];
    final rest = _leaders.length >= 3 ? _leaders.skip(3).toList() : _leaders;

    return RefreshIndicator(
      color: DelightColors.emerald,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          if (podium.isNotEmpty) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: _podiumItem(podium[1], 80)),
              const SizedBox(width: 8),
              Expanded(child: _podiumItem(podium[0], 110)),
              const SizedBox(width: 8),
              Expanded(child: _podiumItem(podium[2], 60)),
            ]),
            const SizedBox(height: 16),
          ],
          ...rest.map((l) => _row(l, me)),
          const SizedBox(height: 8),
          Center(child: TextButton(onPressed: _setMyCity,
            child: const Text('Set my city'))),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> l, String? me) {
    final rank = (l['rank'] as num?)?.toInt() ?? 0;
    final isMe = l['user_id'] == me;
    final name = (l['display_name'] as String?)?.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isMe ? DelightColors.emeraldGlow : DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isMe
          ? DelightColors.emerald.withOpacity(0.5) : DelightColors.surfaceBorder)),
      child: Row(children: [
        SizedBox(width: 34, child: Text('#$rank', style: TextStyle(
          fontFamily: 'Satoshi', fontSize: 13, fontWeight: FontWeight.w600,
          color: _rankColor(rank)))),
        const SizedBox(width: 6),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isMe ? '${name ?? 'You'} (you)' : (name ?? 'Delight user'),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
              color: DelightColors.textPrimary, fontSize: 14)),
          if ((l['city'] as String?)?.isNotEmpty == true)
            Text(l['city'] as String, style: const TextStyle(
              fontFamily: 'Satoshi', fontSize: 11, color: DelightColors.textMuted)),
        ])),
        Text(_score(l), style: const TextStyle(
          fontFamily: 'Clash', fontSize: 14, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
      ]),
    );
  }

  Widget _podiumItem(Map<String, dynamic> l, double height) {
    final rank = (l['rank'] as num?)?.toInt() ?? 0;
    final color = _rankColor(rank);
    final name = ((l['display_name'] as String?) ?? 'User').trim();
    return Column(children: [
      Text(rank == 1 ? '👑' : rank == 2 ? '🥈' : '🥉',
        style: const TextStyle(fontSize: 24)),
      const SizedBox(height: 4),
      Text(name.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontFamily: 'Satoshi', fontSize: 11,
          color: DelightColors.textPrimary),
        textAlign: TextAlign.center),
      Text(_score(l), style: TextStyle(
        fontFamily: 'Satoshi', fontSize: 10, color: color,
        fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.6), color.withOpacity(0.2)],
            begin: Alignment.topCenter, end: Alignment.bottomCenter),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6))),
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.only(top: 8),
        child: Text('#$rank', style: TextStyle(
          fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
          color: color)),
      ),
    ]);
  }

  Widget _filterChips(List<String> opts, String current, Function(String) onSelect) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: opts.map((o) {
        final sel = o == current;
        return GestureDetector(
          onTap: () => onSelect(o),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: sel ? DelightColors.emerald : DelightColors.surfaceHigh,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: sel ? Colors.transparent : DelightColors.surfaceBorder)),
            child: Text(o, style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 12, fontWeight: FontWeight.w600,
              color: sel ? DelightColors.textInverse : DelightColors.textMuted)),
          ),
        );
      }).toList()),
    );
  }
}
