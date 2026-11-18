import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/models/models.dart';

String _maskAddress(String address) {
  if (address.length <= 12) return address;
  return '${address.substring(0, 8)}...${address.substring(address.length - 4)}';
}

Color _roleColor(UserRole r) {
  switch (r) {
    case UserRole.consumer:  return DelightColors.blue;
    case UserRole.business:  return DelightColors.emerald;
    case UserRole.organizer: return DelightColors.gold;
    case UserRole.admin:     return DelightColors.error;
  }
}

String _roleLabel(UserRole r) {
  switch (r) {
    case UserRole.consumer:  return '👤 Consumer';
    case UserRole.business:  return '🏪 Business';
    case UserRole.organizer: return '🎪 Organiser';
    case UserRole.admin:     return '🔑 Admin';
  }
}

String _roleDesc(UserRole r) {
  switch (r) {
    case UserRole.consumer:
      return 'Browse events, buy tickets, pay friends, earn rewards.';
    case UserRole.business:
      return 'Accept QR payments. View your daily takings. Cash out anytime.';
    case UserRole.organizer:
      return 'Create events, sell tickets, scan at the door. Your events only.';
    case UserRole.admin:
      return 'Full platform view. All events, all venues, all analytics. Push insights to organisers.';
  }
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user   = ref.watch(authProvider);
    final wallet = ref.watch(walletProvider);
    final role   = user?.role ?? UserRole.consumer;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          backgroundColor: DelightColors.background,
          floating: true, snap: true,
          title: const Text('Me', style: TextStyle(
            fontFamily: 'Clash', fontSize: 22, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary)),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout_outlined, color: DelightColors.textMuted, size: 20),
              onPressed: () {
                ref.read(authProvider.notifier).logout();
                context.go('/login');
              }),
          ]),

        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Identity card ───────────────────────────────────────────
            _IdentityCard(user: user, wallet: wallet, role: role),
            const SizedBox(height: 24),

            // ── Mode switcher ───────────────────────────────────────────
            _ModeSwitcher(role: role),
            const SizedBox(height: 24),

            // ── Role-specific actions ───────────────────────────────────
            _RoleActions(role: role),
            const SizedBox(height: 24),

            // ── Private event — available to everyone ───────────────────
            if (role == UserRole.consumer || role == UserRole.organizer)
              _PrivateEventBanner(),

            // ── General settings — always shown ─────────────────────────
            const SizedBox(height: 8),
            _GeneralSettings(),

          ]))),
      ]));
  }
}

// ─── Identity card ────────────────────────────────────────────────────────────

class _IdentityCard extends ConsumerStatefulWidget {
  final dynamic user, wallet;
  final UserRole role;
  const _IdentityCard({required this.user, required this.wallet, required this.role});
  @override
  ConsumerState<_IdentityCard> createState() => _IdentityCardState();
}

class _IdentityCardState extends ConsumerState<_IdentityCard> {
  bool _uploading = false;
  String? _localAvatar;

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final userId = ref.read(authProvider)?.id;
      if (userId == null) return;
      final url = await SupabaseService.uploadAvatar(userId, bytes);
      await SupabaseService.updateProfile(userId, {'avatar_url': url});
      final cur = ref.read(authProvider);
      if (cur != null) ref.read(authProvider.notifier).update(cur.copyWith(avatarUrl: url));
      if (mounted) {
        setState(() => _localAvatar = url);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Profile photo updated ✓'),
          backgroundColor: Color(0xFF00C96A)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Upload failed'),
        backgroundColor: const Color(0xFFFF5555)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final wallet = widget.wallet;
    final role = widget.role;
    final avatarUrl = _localAvatar ?? user?.avatarUrl;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            _roleColor(role).withOpacity(0.12), DelightColors.background]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _roleColor(role).withOpacity(0.3))),
        child: Row(children: [
          // Tappable avatar — tap to change photo (Instagram-style)
          GestureDetector(
            onTap: _uploading ? null : _pickPhoto,
            child: Stack(children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [
                    _roleColor(role), _roleColor(role).withOpacity(0.6)]),
                  boxShadow: [BoxShadow(
                    color: _roleColor(role).withOpacity(0.4), blurRadius: 12)]),
                child: _uploading
                  ? const Padding(
                      padding: EdgeInsets.all(22),
                      child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                  : avatarUrl != null
                    ? ClipOval(child: CachedNetworkImage(
                        imageUrl: avatarUrl,
                        width: 72, height: 72, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _initialsAvatar(user, role)))
                    : _initialsAvatar(user, role)),
              Positioned(bottom: 0, right: 0,
                child: Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: _roleColor(role), shape: BoxShape.circle,
                    border: Border.all(color: DelightColors.background, width: 2)),
                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 11))),
            ])),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user?.displayName ?? 'Delight User',
              style: const TextStyle(fontFamily: 'Clash', fontSize: 18,
                fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
            if (user?.username != null && user!.username.isNotEmpty)
              Text('@${user.username}',
                style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                  color: DelightColors.textMuted)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _roleColor(role).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _roleColor(role).withOpacity(0.4))),
              child: Text(_roleLabel(role), style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 11, fontWeight: FontWeight.w700,
                color: _roleColor(role)))),
          ])),
        ])),
      const SizedBox(height: 14),
      // ── Followers / Following / Posts stats ─────────────────────────
      _ProfileStatsRow(userId: user?.id),
    ]);
  }

  Widget _initialsAvatar(dynamic user, UserRole role) =>
    Container(
      alignment: Alignment.center,
      child: Text(
        user?.displayName?.isNotEmpty == true
          ? (user!.displayName as String)[0].toUpperCase() : 'D',
        style: const TextStyle(fontFamily: 'Clash', fontSize: 26,
          fontWeight: FontWeight.w700, color: Colors.white)));

}

// ─── Mode switcher ────────────────────────────────────────────────────────────

class _ModeSwitcher extends ConsumerWidget {
  final UserRole role;
  const _ModeSwitcher({required this.role});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('SWITCH MODE', style: TextStyle(fontFamily: 'Satoshi',
        fontSize: 10, fontWeight: FontWeight.w700,
        color: DelightColors.textMuted, letterSpacing: 1.5)),
      const SizedBox(height: 10),
      Row(children: [
        _pill(context, ref, UserRole.consumer,  '👤', 'Consumer'),
        const SizedBox(width: 8),
        _pill(context, ref, UserRole.organizer, '🎪', 'Organiser'),
        const SizedBox(width: 8),
        _pill(context, ref, UserRole.business,  '🏪', 'Business'),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: DelightColors.surfaceBorder)),
        child: Text(_roleDesc(role), style: const TextStyle(
          fontFamily: 'Satoshi', fontSize: 12,
          color: DelightColors.textSecondary, height: 1.5))),
    ]);
  }

  Widget _pill(BuildContext context, WidgetRef ref,
      UserRole target, String emoji, String label) {
    final sel = role == target;
    return Expanded(child: GestureDetector(
      onTap: () {
        final user = ref.read(authProvider);
        if (user != null) {
          ref.read(authProvider.notifier).update(user.copyWith(role: target));
          switch (target) {
            case UserRole.business:  context.go('/business-home'); break;
            case UserRole.organizer: context.go('/events'); break;
            case UserRole.consumer:  context.go('/feed'); break;
            case UserRole.admin:     context.go('/feed'); break;
          }
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: sel ? _roleColor(target).withOpacity(0.15) : DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sel ? _roleColor(target) : DelightColors.surfaceBorder,
            width: sel ? 1.5 : 1)),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
            fontWeight: FontWeight.w700,
            color: sel ? _roleColor(target) : DelightColors.textMuted)),
        ]))));
  }
}

// ─── Role-specific actions ────────────────────────────────────────────────────

class _RoleActions extends StatelessWidget {
  final UserRole role;
  const _RoleActions({required this.role});

  @override
  Widget build(BuildContext context) {
    switch (role) {
      case UserRole.consumer:  return _ConsumerActions();
      case UserRole.business:  return _BusinessActions();
      case UserRole.organizer: return _OrganiserActions();
      case UserRole.admin:     return _AdminActions();
    }
  }
}

class _ConsumerActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel('QUICK ACTIONS'),
      const SizedBox(height: 10),
      _tile(context, '📱', 'Top Up Wallet',
        'Add funds — agent, voucher, EFT or USSD',
        DelightColors.emerald, () => context.push('/topup')),
      _tile(context, '💸', 'Cash Out',
        'Withdraw to your bank or mobile money',
        DelightColors.gold, () => context.push('/cashout')),
      _tile(context, '🎟', 'My Tickets',
        'All your event tickets in one place',
        DelightColors.blue, () => context.go('/wallet')),
    ]);
  }
}

class _BusinessActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel('BUSINESS TOOLS'),
      const SizedBox(height: 10),
      _tile(context, '📲', 'My Payment QR',
        'Show or print your QR — customers scan to pay',
        DelightColors.emerald, () => context.go('/business-home')),
      _tile(context, '📊', 'Sales Insights',
        'Today\'s takings, weekly trends, busiest hours',
        DelightColors.blue, () => context.push('/indoor-insights')),
      _tile(context, '🛍', 'My Products',
        'List what you sell and its price',
        DelightColors.emerald, () => context.push('/my-products')),
      _tile(context, '🧠', 'Product Insights',
        'What sells, when, and AI advice to grow',
        DelightColors.gold, () => context.push('/product-insights')),
      _tile(context, '💸', 'Cash Out',
        'Move your earnings to bank or mobile money',
        DelightColors.gold, () => context.push('/cashout')),
      _tile(context, '📱', 'Top Up Float',
        'Add funds to give change or pay suppliers',
        DelightColors.textSecondary, () => context.push('/topup')),
    ]);
  }
}

class _OrganiserActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel('ORGANISER TOOLS'),
      const SizedBox(height: 10),
      _tile(context, '🎪', 'Create Public Event',
        'Sell tickets to anyone — festival, concert, sports',
        DelightColors.emerald, () => context.push('/events/create')),
      _tile(context, '🔲', 'Scan Gate',
        'Scan tickets at the door — works offline',
        DelightColors.gold, () => context.push('/gate-scan')),
      _tile(context, '👥', 'Gate Staff & Dashboard',
        'Add staff, set or reset their PINs, see live entry counts',
        DelightColors.emerald, () => context.push('/gate-dashboard')),
      _tile(context, '📊', 'Outdoor Insights',
        'Festival analytics — stalls, tiers, timeline',
        DelightColors.blue, () => context.push('/event-insights')),
      _tile(context, '🏟', 'Indoor Venue Insights',
        'Club, church, stadium — section and staff data',
        const Color(0xFF74B9FF), () => context.push('/indoor-insights')),
    ]);
  }
}

class _AdminActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel('ADMIN TOOLS'),
      const SizedBox(height: 10),
      // Admin overview banner
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            DelightColors.error.withOpacity(0.15),
            DelightColors.background]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DelightColors.error.withOpacity(0.4))),
        child: Row(children: [
          const Text('🔑', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Admin Dashboard', style: TextStyle(
              fontFamily: 'Clash', fontSize: 16, fontWeight: FontWeight.w700,
              color: DelightColors.textPrimary)),
            const Text('Full platform visibility. '
              'View all events, all venues, all organiser data. '
              'Push recommendations. Export reports.',
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                color: DelightColors.textSecondary, height: 1.4)),
          ])),
        ])),
      _tile(context, '🖥', 'Live Dashboard',
        'XRP ticker, live transactions, heatmap, return visits — real time',
        DelightColors.error, () => context.push('/admin-dashboard')),
      _tile(context, '📈', 'Platform Analytics',
        'Revenue, users, agents, events — Delight business dashboard',
        DelightColors.emerald, () => context.push('/admin-analytics')),
      _tile(context, '📊', 'All Event Insights',
        'Outdoor + indoor data across every organiser',
        DelightColors.blue, () => context.push('/event-insights')),
      _tile(context, '🏟', 'All Venue Insights',
        'Every club, stadium, church — full benchmarks',
        const Color(0xFF74B9FF), () => context.push('/indoor-insights')),
      _tile(context, '🌍', 'Market Trends',
        'Cross-business product trends (3+ businesses per group)',
        DelightColors.gold, () => context.push('/market-trends')),
      _tile(context, '🔲', 'Scan Gate',
        'Scan tickets at the door — staff log in with a PIN',
        DelightColors.gold, () => context.push('/gate-scan')),
      _tile(context, '👥', 'Gate Staff & Dashboard',
        'Add staff, set or reset their PINs, see live entry counts',
        DelightColors.emerald, () => context.push('/gate-dashboard')),
      _tile(context, '📨', 'Push Recommendation',
        'Send data-driven tips to an organiser',
        DelightColors.gold, () => _pushRecommendation(context)),
      _tile(context, '📥', 'Export Report',
        'Download full analytics as PDF or CSV',
        DelightColors.blue, () => _exportReport(context)),
      _tile(context, '🚨', 'Flag / Disputes',
        'Review flagged agents, fraud, disputes',
        DelightColors.error, () {}),
    ]);
  }

  void _pushRecommendation(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _PushRecommendationSheet());
  }

  void _exportReport(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating full platform report PDF...')));
  }
}

// ─── Private event banner — consumer + organiser ──────────────────────────────

class _PrivateEventBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/private-events'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            const Color(0xFF2A1A30), const Color(0xFF150D18)]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8B4D0).withOpacity(0.4))),
        child: Row(children: [
          const Text('💍', style: TextStyle(fontSize: 36)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Host a Private Event', style: TextStyle(
              fontFamily: 'Clash', fontSize: 17, fontWeight: FontWeight.w700,
              color: Colors.white)),
            const SizedBox(height: 4),
            const Text('Wedding, birthday, baby shower, dinner party. '
              'Send invites, collect RSVPs with meal choices and plus ones, '
              'scan tickets at the door.',
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                color: Colors.white60, height: 1.4)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFE8B4D0).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFE8B4D0).withOpacity(0.5))),
              child: const Text('Create Private Event →', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 12, fontWeight: FontWeight.w700,
                color: Color(0xFFE8B4D0)))),
          ])),
        ])));
  }
}

// ─── General settings ─────────────────────────────────────────────────────────

class _GeneralSettings extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel('ACCOUNT'),
      const SizedBox(height: 10),
      _row(Icons.notifications_outlined, 'Notifications',
        () => _showNotifications(context)),
      _row(Icons.security_outlined, 'Security & PIN',
        () => _showSecurityPin(context)),
      _row(Icons.language_outlined, 'Language',
        () => _showLanguage(context)),
      _row(Icons.help_outline, 'Help & Support',
        () => _showHelpSupport(context)),
      _row(Icons.info_outline, 'About Delight',
        () => _showAbout(context)),
    ]);
  }

  void _showNotifications(BuildContext context) {
    _sheet(context, 'Notifications', [
      _toggle('Event group chat alerts', true),
      _toggle('Direct message alerts', true),
      _toggle('Ticket purchase confirmations', true),
      _toggle('Agent deposit confirmations', true),
      _toggle('Money received', true),
      _toggle('Upcoming event reminders', false),
      _toggle('New followers', false),
      _toggle('Marketing & promotions', false),
    ]);
  }

  void _showSecurityPin(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _SecurityPinSheet());
  }

  void _showLanguage(BuildContext context) {
    _sheet(context, 'Language & Region', [
      _radio('English', true),
      _radio('isiZulu', false),
      _radio('Afrikaans', false),
      _radio('Français', false),
      _radio('Swahili', false),
      _radio('Yorùbá', false),
      _radio('Amharic', false),
    ]);
  }

  void _showHelpSupport(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _HelpSupportSheet());
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Delight',
      applicationVersion: '1.0.0-beta',
      applicationLegalese: '© 2026 Delight Technologies. All rights reserved.',
      children: [
        const SizedBox(height: 12),
        const Text("Africa's super app — payments, events, memories, "
          'all in one place.',
          style: TextStyle(fontFamily: 'Satoshi', fontSize: 13)),
      ]);
  }

  void _sheet(BuildContext context, String title, List<Widget> items) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SimpleSheet(title: title, items: items));
  }

  Widget _toggle(String label, bool initial) =>
    _ToggleTile(label: label, initial: initial);

  Widget _radio(String label, bool selected) =>
    _RadioTile(label: label, selected: selected);

  Widget _row(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: DelightColors.surfaceBorder))),
          child: Row(children: [
            Icon(icon, color: DelightColors.textMuted, size: 20),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: const TextStyle(
              fontFamily: 'Satoshi', fontSize: 14, color: DelightColors.textPrimary))),
            const Icon(Icons.chevron_right, color: DelightColors.textMuted, size: 18),
          ]))));
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

Widget _sectionLabel(String label) {
  return Text(label, style: const TextStyle(fontFamily: 'Satoshi',
    fontSize: 10, fontWeight: FontWeight.w700,
    color: DelightColors.textMuted, letterSpacing: 1.5));
}

Widget _tile(BuildContext context, String emoji, String title, String sub,
    Color color, VoidCallback onTap) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: DelightColors.surfaceBorder)),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.25))),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 20))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontFamily: 'Satoshi',
            fontWeight: FontWeight.w700, fontSize: 14,
            color: DelightColors.textPrimary)),
          Text(sub, style: const TextStyle(fontFamily: 'Satoshi',
            fontSize: 11, color: DelightColors.textMuted, height: 1.3)),
        ])),
        Icon(Icons.chevron_right, color: color.withOpacity(0.5), size: 18),
      ]))));
}

// ── Settings helper widgets ───────────────────────────────────────────────────

class _SimpleSheet extends StatelessWidget {
  final String title;
  final List<Widget> items;
  const _SimpleSheet({required this.title, required this.items});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.of(context).viewInsets.bottom + 20),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 12),
      Center(child: Container(width: 36, height: 4,
        decoration: BoxDecoration(color: DelightColors.surfaceBorder,
          borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          Text(title, style: const TextStyle(fontFamily: 'Clash', fontSize: 18,
            fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
        ])),
      const SizedBox(height: 12),
      const Divider(color: DelightColors.surfaceBorder, height: 1),
      ...items,
      const SizedBox(height: 8),
    ]));
}

class _ToggleTile extends StatefulWidget {
  final String label;
  final bool initial;
  const _ToggleTile({required this.label, required this.initial});
  @override State<_ToggleTile> createState() => _ToggleTileState();
}
class _ToggleTileState extends State<_ToggleTile> {
  late bool _val;
  @override void initState() { super.initState(); _val = widget.initial; }
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    child: Row(children: [
      Expanded(child: Text(widget.label, style: const TextStyle(
        fontFamily: 'Satoshi', fontSize: 14, color: DelightColors.textPrimary))),
      Switch(value: _val, onChanged: (v) => setState(() => _val = v),
        activeColor: DelightColors.emerald),
    ]));
}

class _RadioTile extends StatelessWidget {
  final String label;
  final bool selected;
  const _RadioTile({required this.label, required this.selected});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label, style: TextStyle(
        fontFamily: 'Satoshi', fontSize: 14,
        color: selected ? DelightColors.emerald : DelightColors.textPrimary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w400))),
      if (selected) const Icon(Icons.check_circle, color: DelightColors.emerald, size: 20)
      else const Icon(Icons.radio_button_unchecked, color: DelightColors.textMuted, size: 20),
    ]));
}

// ── Security & PIN sheet ──────────────────────────────────────────────────────
class _SecurityPinSheet extends StatefulWidget {
  const _SecurityPinSheet();
  @override State<_SecurityPinSheet> createState() => _SecurityPinSheetState();
}
class _SecurityPinSheetState extends State<_SecurityPinSheet> {
  bool _pinEnabled = true, _biometrics = false, _hideBalance = false;
  final _pinCtrl    = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confPassCtrl = TextEditingController();
  bool _setPinMode = false;
  bool _setPassMode = false;
  bool _changingPass = false;
  bool _obscureNew = true, _obscureConf = true;

  @override
  void dispose() {
    _pinCtrl.dispose(); _newPassCtrl.dispose(); _confPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final newPass  = _newPassCtrl.text;
    final confPass = _confPassCtrl.text;
    if (newPass.length < 8) {
      _snack('Password must be at least 8 characters'); return;
    }
    if (newPass != confPass) {
      _snack('Passwords do not match'); return;
    }
    setState(() => _changingPass = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPass));
      _newPassCtrl.clear(); _confPassCtrl.clear();
      if (mounted) {
        setState(() { _setPassMode = false; _changingPass = false; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Password updated successfully ✓'),
          backgroundColor: DelightColors.emerald));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _changingPass = false);
        _snack(e.toString().replaceAll('AuthException: ', ''));
      }
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: DelightColors.error));

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
    padding: EdgeInsets.only(
      left: 20, right: 20, top: 20,
      bottom: MediaQuery.of(context).viewInsets.bottom + 24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Center(child: Container(width: 36, height: 4,
        decoration: BoxDecoration(color: DelightColors.surfaceBorder,
          borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 16),
      const Row(children: [
        Text('Security', style: TextStyle(fontFamily: 'Clash', fontSize: 18,
          fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
      ]),
      const SizedBox(height: 20),
      _tile('PIN Lock', 'Require PIN to open app', _pinEnabled,
        (v) => setState(() => _pinEnabled = v)),
      const SizedBox(height: 8),
      _tile('Biometric Login', 'Use fingerprint or face ID', _biometrics,
        (v) => setState(() => _biometrics = v)),
      const SizedBox(height: 8),
      _tile('Hide Balance', 'Blur balance on home screen', _hideBalance,
        (v) => setState(() => _hideBalance = v)),
      const SizedBox(height: 16),

      // ── Change Password ─────────────────────────────────────────
      Material(color: Colors.transparent, child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _setPassMode = !_setPassMode),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DelightColors.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DelightColors.blue.withOpacity(0.3))),
          child: Row(children: [
            const Icon(Icons.lock_reset_outlined,
              color: DelightColors.blue, size: 18),
            const SizedBox(width: 10),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Change Password', style: TextStyle(
                fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                fontSize: 14, color: DelightColors.textPrimary)),
              Text('Update your Delight account password',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                  color: DelightColors.textMuted)),
            ])),
            Icon(_setPassMode ? Icons.expand_less : Icons.chevron_right,
              color: DelightColors.textMuted, size: 18),
          ])))),
      if (_setPassMode) ...[
        const SizedBox(height: 12),
        _passField('New password (min 8 chars)', _newPassCtrl,
          _obscureNew, () => setState(() => _obscureNew = !_obscureNew)),
        const SizedBox(height: 8),
        _passField('Confirm new password', _confPassCtrl,
          _obscureConf, () => setState(() => _obscureConf = !_obscureConf)),
        const SizedBox(height: 12),
        Material(color: Colors.transparent, child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _changingPass ? null : _changePassword,
          child: Container(
            height: 48, width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [DelightColors.blue, Color(0xFF3A7EFF)]),
              borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: _changingPass
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
              : const Text('Update Password', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 14,
                  fontWeight: FontWeight.w800, color: Colors.white))))),
      ],
      const SizedBox(height: 12),

      // ── Change PIN ──────────────────────────────────────────────
      Material(color: Colors.transparent, child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _setPinMode = !_setPinMode),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DelightColors.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
          child: Row(children: [
            const Icon(Icons.pin_outlined, color: DelightColors.emerald, size: 18),
            const SizedBox(width: 10),
            const Expanded(child: Text('Change PIN', style: TextStyle(
              fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
              fontSize: 14, color: DelightColors.textPrimary))),
            Icon(_setPinMode ? Icons.expand_less : Icons.chevron_right,
              color: DelightColors.textMuted, size: 18),
          ])))),
      if (_setPinMode) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _pinCtrl,
          keyboardType: TextInputType.number,
          obscureText: true, maxLength: 6,
          decoration: InputDecoration(
            hintText: 'Enter new 6-digit PIN',
            hintStyle: const TextStyle(color: DelightColors.textMuted),
            filled: true, fillColor: DelightColors.background,
            counterText: '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DelightColors.emerald))),
          onSubmitted: (v) {
            setState(() => _setPinMode = false);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('PIN updated ✓'),
              backgroundColor: DelightColors.emerald));
          }),
      ],
    ])));

  Widget _passField(String hint, TextEditingController ctrl,
      bool obscure, VoidCallback toggle) =>
    TextField(
      controller: ctrl, obscureText: obscure,
      style: const TextStyle(fontFamily: 'Satoshi',
        color: DelightColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: DelightColors.textMuted, fontSize: 13),
        filled: true, fillColor: DelightColors.background,
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_outlined
            : Icons.visibility_off_outlined,
            color: DelightColors.textMuted, size: 18),
          onPressed: toggle),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: DelightColors.blue, width: 1.5))));

  Widget _tile(String label, String sub, bool val, Function(bool) onChanged) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(label, style: const TextStyle(fontFamily: 'Satoshi',
            fontWeight: FontWeight.w700, fontSize: 14,
            color: DelightColors.textPrimary)),
          Text(sub, style: const TextStyle(fontFamily: 'Satoshi', fontSize: 11,
            color: DelightColors.textMuted)),
        ])),
        Switch(value: val, onChanged: onChanged,
          activeColor: DelightColors.emerald),
      ]));
}

// ── Help & Support sheet ──────────────────────────────────────────────────────
class _HelpSupportSheet extends StatelessWidget {
  const _HelpSupportSheet();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: DelightColors.surfaceBorder,
              borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('Help & Support', style: TextStyle(
                fontFamily: 'Clash', fontSize: 20,
                fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary)))),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('We respond within 2 hours.',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                  color: DelightColors.textMuted)))),
          const SizedBox(height: 16),

          // ── Direct contact ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(children: [
              // Email
              _contactTile(
                context,
                emoji: '✉️',
                label: 'Email us',
                value: 'thembajsph1@gmail.com',
                subtitle: 'For anything — we reply fast',
                color: const Color(0xFF4A9EFF),
                onTap: () {
                  launchUrl(Uri.parse(
                    'mailto:thembajsph1@gmail.com?subject=Delight Support'),
                    mode: LaunchMode.externalApplication);
                }),
              const SizedBox(height: 8),
              // WhatsApp
              _contactTile(
                context,
                emoji: '💬',
                label: 'WhatsApp us',
                value: '063 062 8833',
                subtitle: 'Fastest way to reach us',
                color: const Color(0xFF25D366),
                onTap: () {
                  launchUrl(Uri.parse(
                    'https://wa.me/27630628833?text=Hi Delight Support'),
                    mode: LaunchMode.externalApplication);
                }),
              const SizedBox(height: 8),
              // Call
              _contactTile(
                context,
                emoji: '📞',
                label: 'Call us',
                value: '063 062 8833',
                subtitle: 'Mon–Fri, 08:00–20:00',
                color: DelightColors.emerald,
                onTap: () {
                  launchUrl(Uri.parse('tel:+27630628833'),
                    mode: LaunchMode.externalApplication);
                }),
            ])),
          const SizedBox(height: 16),

          // ── Common issues ───────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('COMMON ISSUES', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 9,
                fontWeight: FontWeight.w700,
                color: DelightColors.textMuted, letterSpacing: 1.2)))),
          const SizedBox(height: 8),
          _issueTile(context, '💸', 'Payment issue',
            'Transaction failed or wrong amount',
            'mailto:thembajsph1@gmail.com?subject=Payment Issue'),
          _issueTile(context, '🎟', 'Ticket problem',
            'Cannot access or share my ticket',
            'mailto:thembajsph1@gmail.com?subject=Ticket Problem'),
          _issueTile(context, '🏪', 'Agent dispute',
            'Agent did not credit my wallet',
            'mailto:thembajsph1@gmail.com?subject=Agent Dispute'),
          _issueTile(context, '🔐', 'Account access',
            'Cannot log in or forgot PIN',
            'mailto:thembajsph1@gmail.com?subject=Account Access'),
          _issueTile(context, '🐛', 'Report a bug',
            'Something in the app is not working',
            'mailto:thembajsph1@gmail.com?subject=Bug Report'),
          _issueTile(context, '💡', 'Feature request',
            'Suggest an improvement',
            'mailto:thembajsph1@gmail.com?subject=Feature Request'),
          const SizedBox(height: 20),
        ])));
  }

  Widget _issueTile(BuildContext ctx, String emoji, String label,
      String subtitle, String mailto) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.pop(ctx);
          launchUrl(Uri.parse(mailto), mode: LaunchMode.externalApplication);
        },
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: DelightColors.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DelightColors.surfaceBorder)),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontFamily: 'Satoshi',
                fontWeight: FontWeight.w700, fontSize: 13,
                color: DelightColors.textPrimary)),
              Text(subtitle, style: const TextStyle(fontFamily: 'Satoshi',
                fontSize: 11, color: DelightColors.textMuted)),
            ])),
            const Icon(Icons.chevron_right,
              color: DelightColors.textMuted, size: 16),
          ]))));
  }

  Widget _contactTile(BuildContext context, {
    required String emoji, required String label,
    required String value, required String subtitle,
    required Color color, required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.25))),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text(label, style: TextStyle(fontFamily: 'Satoshi',
                fontWeight: FontWeight.w700, fontSize: 14, color: color)),
              Text(value, style: const TextStyle(fontFamily: 'Satoshi',
                fontSize: 13, color: DelightColors.textPrimary,
                fontWeight: FontWeight.w600)),
              Text(subtitle, style: const TextStyle(fontFamily: 'Satoshi',
                fontSize: 11, color: DelightColors.textMuted)),
            ])),
            Icon(Icons.arrow_forward_ios, color: color, size: 14),
          ]))));
  }
}


// ─── Real followers / following / posts / events ─────────────────────────────
// Numbers come from get_profile_stats (computed live in Postgres); the lists
// open real data, and follow / unfollow writes to the `follows` table.

class _ProfileStatsRow extends ConsumerStatefulWidget {
  final String? userId;
  const _ProfileStatsRow({required this.userId});
  @override
  ConsumerState<_ProfileStatsRow> createState() => _ProfileStatsRowState();
}

class _ProfileStatsRowState extends ConsumerState<_ProfileStatsRow> {
  Map<String, int>? _stats;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void didUpdateWidget(covariant _ProfileStatsRow old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) _load();
  }

  Future<void> _load() async {
    final id = widget.userId;
    if (id == null) return;
    final s = await SupabaseService.getProfileStats(id);
    if (mounted) setState(() => _stats = s);
  }

  String _fmt(int? n) {
    if (n == null) return '–';
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Row(children: [
        _pill('Followers', _stats?['followers']),
        _div(),
        _pill('Following', _stats?['following']),
        _div(),
        _pill('Posts', _stats?['posts']),
        _div(),
        _pill('Events', _stats?['events']),
      ]));
  }

  Widget _div() => Container(width: 1, height: 32,
    color: DelightColors.surfaceBorder);

  Widget _pill(String label, int? n) => Expanded(child: Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: widget.userId == null ? null : () => _open(label),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          Text(_fmt(n), style: const TextStyle(fontFamily: 'Clash',
            fontSize: 16, fontWeight: FontWeight.w800,
            color: DelightColors.textPrimary)),
          Text(label, style: const TextStyle(fontFamily: 'Satoshi',
            fontSize: 10, color: DelightColors.textMuted)),
        ])))));

  void _open(String type) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7, maxChildSize: 0.95, minChildSize: 0.4,
        expand: false,
        builder: (_, ctrl) => _ProfileListSheet(
          type: type, userId: widget.userId!, controller: ctrl,
          onChanged: _load),
      ),
    ).whenComplete(_load);
  }
}

class _ProfileListSheet extends StatefulWidget {
  final String type, userId;
  final ScrollController controller;
  final VoidCallback onChanged;
  const _ProfileListSheet({required this.type, required this.userId,
    required this.controller, required this.onChanged});
  @override
  State<_ProfileListSheet> createState() => _ProfileListSheetState();
}

class _ProfileListSheetState extends State<_ProfileListSheet> {
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>>? _search;   // non-null while searching
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  bool get _isPeople => widget.type == 'Followers' || widget.type == 'Following';

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    List<Map<String, dynamic>> rows;
    switch (widget.type) {
      case 'Followers': rows = await SupabaseService.getFollowers(widget.userId); break;
      case 'Following': rows = await SupabaseService.getFollowing(widget.userId); break;
      case 'Posts':     rows = await SupabaseService.getUserPosts(widget.userId); break;
      default:          rows = await SupabaseService.getProfileEvents(widget.userId);
    }
    if (!mounted) return;
    setState(() { _items = rows; _loading = false; });
  }

  Future<void> _runSearch(String q) async {
    if (q.trim().length < 2) {
      setState(() => _search = null);
      return;
    }
    final rows = await SupabaseService.searchPeople(q.trim());
    if (!mounted || _searchCtrl.text.trim() != q.trim()) return;
    setState(() => _search = rows);
  }

  Future<void> _toggle(Map<String, dynamic> p) async {
    final nowFollowing = !(p['is_following'] == true);
    final ok = await SupabaseService.setFollowing(p['id'] as String, nowFollowing);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't update — try again"),
        backgroundColor: DelightColors.error));
      return;
    }
    setState(() => p['is_following'] = nowFollowing);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final list = _search ?? _items;
    return Column(children: [
      const SizedBox(height: 12),
      Center(child: Container(width: 36, height: 4,
        decoration: BoxDecoration(color: DelightColors.surfaceBorder,
          borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Align(alignment: Alignment.centerLeft,
          child: Text(widget.type, style: const TextStyle(fontFamily: 'Clash',
            fontSize: 18, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary)))),
      if (_isPeople)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _runSearch,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Find people by name or @username'))),
      const SizedBox(height: 8),
      const Divider(color: DelightColors.surfaceBorder, height: 1),
      Expanded(child: _loading
        ? const Center(child: CircularProgressIndicator(color: DelightColors.emerald))
        : list.isEmpty
          ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_emptyText(), textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Satoshi', height: 1.5,
                  color: DelightColors.textMuted))))
          : ListView.builder(
              controller: widget.controller,
              itemCount: list.length,
              itemBuilder: (_, i) => _isPeople || _search != null
                ? _personTile(list[i])
                : widget.type == 'Posts' ? _postTile(list[i]) : _eventTile(list[i]))),
    ]);
  }

  String _emptyText() {
    if (_search != null) return 'No one found.';
    switch (widget.type) {
      case 'Followers': return 'No followers yet.\nSearch above to find people to follow.';
      case 'Following': return "You're not following anyone yet.\nSearch above to find people.";
      case 'Posts':     return 'No posts yet.';
      default:          return 'No events yet.';
    }
  }

  Widget _personTile(Map<String, dynamic> p) {
    final me = SupabaseService.currentUser?.id;
    final name = (p['display_name'] as String?)?.trim().isNotEmpty == true
      ? p['display_name'] as String : 'Delight user';
    final sub = [
      if ((p['username'] as String?)?.isNotEmpty == true) '@${p['username']}',
      if ((p['city'] as String?)?.isNotEmpty == true) p['city'] as String,
    ].join(' · ');
    final following = p['is_following'] == true;
    final avatar = p['avatar_url'] as String?;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: DelightColors.emeraldGlow,
        backgroundImage: avatar != null && avatar.isNotEmpty
          ? CachedNetworkImageProvider(avatar) : null,
        child: avatar == null || avatar.isEmpty
          ? Text(name[0].toUpperCase(), style: const TextStyle(
              fontFamily: 'Clash', color: DelightColors.emerald))
          : null),
      title: Text(name, style: const TextStyle(fontFamily: 'Satoshi',
        fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
      subtitle: sub.isEmpty ? null : Text(sub, style: const TextStyle(
        fontFamily: 'Satoshi', fontSize: 12, color: DelightColors.textMuted)),
      trailing: p['id'] == me ? null : Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _toggle(p),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: following ? DelightColors.surfaceHigh : DelightColors.emeraldGlow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: following
                ? DelightColors.surfaceBorder
                : DelightColors.emerald.withOpacity(0.3))),
            child: Text(following ? 'Following' : 'Follow',
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                fontWeight: FontWeight.w700,
                color: following ? DelightColors.textMuted : DelightColors.emerald))))),
    );
  }

  String _date(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return '';
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  Widget _postTile(Map<String, dynamic> p) {
    final content = (p['content'] as String?)?.trim() ?? '';
    return ListTile(
      title: Text(content.isEmpty ? '(photo post)' : content,
        maxLines: 2, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontFamily: 'Satoshi',
          color: DelightColors.textPrimary)),
      subtitle: Text('${_date(p['created_at'])} · '
        '❤️ ${p['likes_count'] ?? 0} · 💬 ${p['comments_count'] ?? 0}',
        style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
          color: DelightColors.textMuted)));
  }

  Widget _eventTile(Map<String, dynamic> e) {
    final organiser = e['relation'] == 'organiser';
    return ListTile(
      leading: Text(organiser ? '🎪' : '🎟', style: const TextStyle(fontSize: 22)),
      title: Text(e['name'] as String? ?? 'Event', style: const TextStyle(
        fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
        color: DelightColors.textPrimary)),
      subtitle: Text([
        _date(e['event_date']),
        if ((e['venue'] as String?)?.isNotEmpty == true) e['venue'] as String,
        organiser ? 'Organiser' : 'Attending',
      ].where((s) => s.isNotEmpty).join(' · '),
        style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
          color: DelightColors.textMuted)));
  }
}


// ─── Admin: send a real recommendation to an organiser ───────────────────────

class _PushRecommendationSheet extends StatefulWidget {
  const _PushRecommendationSheet();
  @override
  State<_PushRecommendationSheet> createState() => _PushRecState();
}

class _PushRecState extends State<_PushRecommendationSheet> {
  List<Map<String, dynamic>> _events = [];
  Map<String, dynamic>? _sel;
  final _body = TextEditingController();
  bool _loading = true, _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    SupabaseService.getEventsForAdmin().then((e) {
      if (mounted) setState(() { _events = e; _loading = false; });
    });
  }

  @override
  void dispose() { _body.dispose(); super.dispose(); }

  Future<void> _send() async {
    if (_sel == null || _body.text.trim().length < 5) {
      setState(() => _error = 'Pick an event and write a message');
      return;
    }
    setState(() { _sending = true; _error = null; });
    try {
      await SupabaseService.pushRecommendation('${_sel!['id']}', _body.text.trim());
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recommendation sent to the organiser')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24,
        24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Push Recommendation', style: TextStyle(fontFamily: 'Clash',
          fontSize: 20, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 12),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_events.isEmpty)
          const Text('No organiser events yet.',
            style: TextStyle(color: DelightColors.textMuted))
        else ...[
          DropdownButtonFormField<Map<String, dynamic>>(
            value: _sel,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Event'),
            items: _events.map((e) => DropdownMenuItem(
              value: e, child: Text('${e['name']}',
                overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => _sel = v)),
          const SizedBox(height: 10),
          TextField(controller: _body, maxLines: 4, maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'Tip for the organiser')),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: DelightColors.error)),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: _sending ? null : _send,
            child: Text(_sending ? 'Sending…' : 'Send'))),
        ],
      ]));
  }
}
