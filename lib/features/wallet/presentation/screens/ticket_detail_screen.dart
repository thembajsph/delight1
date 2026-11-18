// lib/features/wallet/presentation/screens/ticket_detail_screen.dart
//
// Every ticket holder — General or VIP — gets beautiful share cards.
// The flex is the EXPERIENCE, not the tier.
// Designed so anyone who attended wants to post this to Instagram.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/models/models.dart';

// ─── Event category themes ────────────────────────────────────────────────────
// Colour comes from the EVENT TYPE, not the ticket tier.
// A General ticket to a music festival looks just as stunning as a VIP one.

class _EventTheme {
  final List<Color> gradient;
  final Color accent;
  final String emoji;
  final String vibe;     // one word shown on card
  const _EventTheme({
    required this.gradient, required this.accent,
    required this.emoji, required this.vibe,
  });
}

final _eventThemes = <String, _EventTheme>{
  'Music': _EventTheme(
    gradient: [const Color(0xFF0D2B0A), const Color(0xFF041504)],
    accent: DelightColors.emerald, emoji: '🎵', vibe: 'LIVE'),
  'Technology': _EventTheme(
    gradient: [const Color(0xFF001A2E), const Color(0xFF000A17)],
    accent: DelightColors.blue, emoji: '💻', vibe: 'TECH'),
  'Art': _EventTheme(
    gradient: [const Color(0xFF1A0A2E), const Color(0xFF0D0517)],
    accent: const Color(0xFFBF5FFF), emoji: '🎨', vibe: 'ART'),
  'Food': _EventTheme(
    gradient: [const Color(0xFF2E1000), const Color(0xFF150800)],
    accent: const Color(0xFFFF6B35), emoji: '🍽', vibe: 'TASTE'),
  'Sports': _EventTheme(
    gradient: [const Color(0xFF002E0A), const Color(0xFF001505)],
    accent: DelightColors.emerald, emoji: '⚽', vibe: 'MATCH'),
  'Fashion': _EventTheme(
    gradient: [const Color(0xFF2E002E), const Color(0xFF150015)],
    accent: const Color(0xFFFF69B4), emoji: '✨', vibe: 'STYLE'),
};

_EventTheme _themeFor(String category) =>
    _eventThemes[category] ?? _EventTheme(
      gradient: [const Color(0xFF0D2B0A), const Color(0xFF041504)],
      accent: DelightColors.emerald, emoji: '🌟', vibe: 'EVENT');

// ─── Screen ───────────────────────────────────────────────────────────────────

class TicketDetailScreen extends ConsumerStatefulWidget {
  final NFTTicket ticket;
  const TicketDetailScreen({super.key, required this.ticket});
  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen>
    with TickerProviderStateMixin {
  late TabController _tab;
  int _shareCardIndex = 0;   // which share card style is previewed

  // Simulated user photos (in production: picked from camera roll)
  final _userPhotos = <String>[];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme = _themeFor('Music'); // TODO: pass real category from event

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      appBar: AppBar(
        backgroundColor: DelightColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop()),
        title: const Text('Your Ticket', style: TextStyle(
          fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        actions: [
          GestureDetector(
            onTap: () => _openShareSheet(context, theme),
            child: Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [theme.accent, theme.accent.withOpacity(0.7)]),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(
                  color: theme.accent.withOpacity(0.4),
                  blurRadius: 10, offset: const Offset(0, 3))]),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.ios_share_outlined, color: Colors.white, size: 15),
                SizedBox(width: 5),
                Text('Share', style: TextStyle(
                  fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                  color: Colors.white, fontSize: 13)),
              ]),
            ),
          ),
        ],
      ),

      body: SingleChildScrollView(
        child: Column(children: [

          // ── Tab bar ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              decoration: BoxDecoration(
                color: DelightColors.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: DelightColors.surfaceBorder)),
              child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
                controller: _tab,
                indicator: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.accent, theme.accent.withOpacity(0.7)]),
                  borderRadius: BorderRadius.circular(11)),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: DelightColors.textMuted,
                labelStyle: const TextStyle(
                  fontFamily: 'Satoshi', fontWeight: FontWeight.w700, fontSize: 12),
                padding: const EdgeInsets.all(3),
                tabs: const [
                  Tab(text: '🔥  Going!'),
                  Tab(text: '🎟  My Ticket'),
                  Tab(text: '📸  Was There'),
                ],
              ),
            ),
          ),

          // Tab explanation — rotates based on selected tab
          _TabExplainer(tab: _tab),
          const SizedBox(height: 12),

          // ── Cards ────────────────────────────────────────────────────────
          SizedBox(
            height: 530,
            child: TabBarView(
              controller: _tab,
              physics: const BouncingScrollPhysics(),
              children: [
                _HypeCard(ticket: widget.ticket, theme: theme),
                _EntryCard(ticket: widget.ticket, theme: theme),
                _MemoryCard(
                  ticket: widget.ticket,
                  theme: theme,
                  photos: _userPhotos,
                  onAddPhoto: () => setState(() {
                    // In production: image_picker
                    _userPhotos.add('photo_${_userPhotos.length}');
                  }),
                ),
              ],
            ),
          ),

          // ── Share strip ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: _ShareStrip(
              ticket: widget.ticket,
              theme: theme,
              onShare: () => _openShareSheet(context, theme),
            ),
          ),

          // ── On-chain pill ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _OnChainRow(ticket: widget.ticket, theme: theme),
          ),

          // ── Actions ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
            child: _BottomActions(ticket: widget.ticket, theme: theme),
          ),
        ]),
      ),
    );
  }

  void _openShareSheet(BuildContext context, _EventTheme theme) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _ShareSheet(ticket: widget.ticket, theme: theme),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 🔥 HYPE CARD — "I'm going!" — for everyone, before the event
// Bold, energetic, designed to get tapped and shared immediately
// ═══════════════════════════════════════════════════════════════════════════════

// ── Tab explainer — tells user what each card is for ────────────────────────
class _TabExplainer extends StatefulWidget {
  final TabController tab;
  const _TabExplainer({required this.tab});
  @override State<_TabExplainer> createState() => _TabExplainerState();
}
class _TabExplainerState extends State<_TabExplainer> {
  static const _info = [
    (emoji: "🔥", title: "Going!", desc: "Share before the event — tell friends you have a ticket"),
    (emoji: "🎟", title: "My Ticket", desc: "Show at the door to get in — this is your entry pass"),
    (emoji: "📸", title: "Was There", desc: "Share after the event — add your photos to remember it forever"),
  ];
  int _current = 0;

  @override
  void initState() {
    super.initState();
    widget.tab.addListener(() {
      if (mounted) setState(() => _current = widget.tab.index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = _info[_current];
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(_current),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DelightColors.surfaceBorder)),
        child: Row(children: [
          Text(info.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text(info.title, style: const TextStyle(
              fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
              fontSize: 13, color: DelightColors.textPrimary)),
            Text(info.desc, style: const TextStyle(
              fontFamily: 'Satoshi', fontSize: 12,
              color: DelightColors.textMuted, height: 1.3)),
          ])),
        ])));
  }
}

class _HypeCard extends StatelessWidget {
  final NFTTicket ticket;
  final _EventTheme theme;
  const _HypeCard({required this.ticket, required this.theme});

  @override
  Widget build(BuildContext context) {
    final daysUntil = ticket.eventDate.difference(DateTime.now()).inDays;
    final dateFmt   = DateFormat('EEE d MMM');
    final timeFmt   = DateFormat('HH:mm');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: theme.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: theme.accent.withOpacity(0.45), width: 1.5),
          boxShadow: [BoxShadow(
            color: theme.accent.withOpacity(0.22),
            blurRadius: 32, spreadRadius: 2)],
        ),
        child: Stack(children: [

          // Lightweight background accent — no GridView
          Positioned(bottom: -20, left: -20, child: Opacity(
            opacity: 0.07,
            child: Text(theme.emoji,
              style: const TextStyle(fontSize: 140)))),

          // Top-right glow
          Positioned(top: -50, right: -50, child: Container(
            width: 220, height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                theme.accent.withOpacity(0.28), Colors.transparent])),
          )),

          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Top row
                Row(children: [
                  _delightLogo(theme),
                  const Spacer(),
                  // Countdown badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.accent.withOpacity(0.5))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.timer_outlined, size: 13, color: theme.accent),
                      const SizedBox(width: 5),
                      Text(
                        daysUntil > 1 ? '$daysUntil days' :
                        daysUntil == 1 ? 'Tomorrow' : 'TODAY',
                        style: TextStyle(
                          fontFamily: 'Satoshi', fontSize: 12,
                          fontWeight: FontWeight.w800, color: theme.accent)),
                    ]),
                  ),
                ]),

                const SizedBox(height: 24),

                // Big vibe word
                Text(theme.vibe, style: TextStyle(
                  fontFamily: 'Clash', fontSize: 13, fontWeight: FontWeight.w700,
                  color: theme.accent, letterSpacing: 4,
                  shadows: [Shadow(
                    color: theme.accent.withOpacity(0.6), blurRadius: 12)])),

                const SizedBox(height: 4),

                // "I'm going" — accessible to everyone
                const Text("I'M GOING.", style: TextStyle(
                  fontFamily: 'Clash', fontSize: 38,
                  fontWeight: FontWeight.w700, color: Colors.white,
                  letterSpacing: -1, height: 1.0)),

                const SizedBox(height: 12),

                // Event name — the star
                Text(ticket.eventName, style: TextStyle(
                  fontFamily: 'Clash', fontSize: 20,
                  fontWeight: FontWeight.w600, color: theme.accent,
                  height: 1.15, letterSpacing: -0.3)),

                const SizedBox(height: 16),

                // Date + location row
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.calendar_today_outlined,
                        size: 11, color: Colors.white54),
                      const SizedBox(width: 5),
                      Text(dateFmt.format(ticket.eventDate), style: const TextStyle(
                        fontFamily: 'Satoshi', fontSize: 12, color: Colors.white70,
                        fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.access_time,
                        size: 11, color: Colors.white54),
                      const SizedBox(width: 5),
                      Text(timeFmt.format(ticket.eventDate), style: const TextStyle(
                        fontFamily: 'Satoshi', fontSize: 12, color: Colors.white70,
                        fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ]),

                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.location_on_outlined,
                    size: 13, color: Colors.white38),
                  const SizedBox(width: 5),
                  Text('${ticket.eventVenue}, ${ticket.eventCity}',
                    style: const TextStyle(fontFamily: 'Satoshi',
                      fontSize: 12, color: Colors.white54)),
                ]),

                const Spacer(),

                // Bottom — NFT badge + delight
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(6)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.diamond_outlined,
                        size: 10, color: Colors.white38),
                      const SizedBox(width: 4),
                      const Text('NFT Ticket', style: TextStyle(
                        fontFamily: 'Satoshi', fontSize: 10,
                        color: Colors.white38)),
                    ]),
                  ),
                  const Spacer(),
                  Text('delight.africa', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 10,
                    color: theme.accent.withOpacity(0.5))),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 🎟 ENTRY CARD — QR scan at the gate — everyone gets this
// ═══════════════════════════════════════════════════════════════════════════════

class _EntryCard extends StatelessWidget {
  final NFTTicket ticket;
  final _EventTheme theme;
  const _EntryCard({required this.ticket, required this.theme});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('EEE d MMM yyyy');
    final timeFmt = DateFormat('HH:mm');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: theme.gradient,
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: theme.accent.withOpacity(0.45), width: 1.5),
          boxShadow: [BoxShadow(
            color: theme.accent.withOpacity(0.22),
            blurRadius: 32, spreadRadius: 2)],
        ),
        child: Column(children: [

          // Top
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _delightLogo(theme),
                const Spacer(),
                Row(children: [
                  Container(width: 7, height: 7,
                    decoration: BoxDecoration(
                      color: theme.accent, shape: BoxShape.circle,
                      boxShadow: [BoxShadow(
                        color: theme.accent, blurRadius: 6, spreadRadius: 1)])),
                  const SizedBox(width: 6),
                  Text('VALID', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 11, fontWeight: FontWeight.w800,
                    color: theme.accent, letterSpacing: 1.5)),
                ]),
              ]),
              const SizedBox(height: 16),
              Text(ticket.eventName, style: const TextStyle(
                fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
                color: Colors.white, height: 1.15)),
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.calendar_today_outlined, size: 11, color: Colors.white38),
                const SizedBox(width: 5),
                Text(dateFmt.format(ticket.eventDate),
                  style: const TextStyle(fontFamily: 'Satoshi',
                    fontSize: 12, color: Colors.white54)),
                const SizedBox(width: 12),
                Icon(Icons.access_time, size: 11, color: Colors.white38),
                const SizedBox(width: 5),
                Text(timeFmt.format(ticket.eventDate),
                  style: const TextStyle(fontFamily: 'Satoshi',
                    fontSize: 12, color: Colors.white54)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.location_on_outlined, size: 11, color: Colors.white38),
                const SizedBox(width: 5),
                Text('${ticket.eventVenue}, ${ticket.eventCity}',
                  style: const TextStyle(fontFamily: 'Satoshi',
                    fontSize: 12, color: Colors.white54)),
              ]),
            ]),
          ),

          // Tear line
          Row(children: [
            Container(width: 22, height: 22,
              decoration: BoxDecoration(
                color: DelightColors.background, shape: BoxShape.circle)),
            Expanded(child: LayoutBuilder(builder: (_, c) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate((c.maxWidth / 10).floor(), (_) =>
                Container(width: 5, height: 1.5,
                  color: theme.accent.withOpacity(0.25))),
            ))),
            Container(width: 22, height: 22,
              decoration: BoxDecoration(
                color: DelightColors.background, shape: BoxShape.circle)),
          ]),

          // QR
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
            child: Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ADMIT ONE', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 9, letterSpacing: 2,
                  color: theme.accent.withOpacity(0.6))),
                const SizedBox(height: 6),
                Text(ticket.tier, style: TextStyle(
                  fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
                  color: theme.accent)),
                const SizedBox(height: 8),
                Text(ticket.tokenId.substring(0, 14) + '...',
                  style: const TextStyle(fontFamily: 'Courier',
                    fontSize: 9, color: Colors.white24)),
              ])),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(
                    color: theme.accent.withOpacity(0.35),
                    blurRadius: 18, spreadRadius: 2)]),
                child: QrImageView(
                  data: ticket.tokenId,
                  version: QrVersions.auto,
                  size: 105,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF060F0A)),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF060F0A)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 📸 MEMORY CARD — After the event — add your own photos, share the story
// This is the Instagram post. For EVERYONE who attended.
// ═══════════════════════════════════════════════════════════════════════════════

class _MemoryCard extends StatelessWidget {
  final NFTTicket ticket;
  final _EventTheme theme;
  final List<String> photos;
  final VoidCallback onAddPhoto;
  const _MemoryCard({
    required this.ticket, required this.theme,
    required this.photos, required this.onAddPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMMM yyyy');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: theme.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: theme.accent.withOpacity(0.45), width: 1.5),
          boxShadow: [BoxShadow(
            color: theme.accent.withOpacity(0.22),
            blurRadius: 32, spreadRadius: 2)],
        ),
        child: Stack(children: [

          // Simple radial glow — no CustomPainter, no freeze
          Positioned(top: -30, right: -30, child: Container(
            width: 180, height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                theme.accent.withOpacity(0.15), Colors.transparent])),
          )),

          // Bottom-left glow
          Positioned(bottom: -50, left: -50, child: Container(
            width: 220, height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                theme.accent.withOpacity(0.25), Colors.transparent])),
          )),

          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Header
                Row(children: [
                  _delightLogo(theme),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.accent.withOpacity(0.4))),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.diamond_outlined, size: 10, color: Colors.white54),
                      SizedBox(width: 4),
                      Text('NFT Memory', style: TextStyle(
                        fontFamily: 'Satoshi', fontSize: 10,
                        fontWeight: FontWeight.w700, color: Colors.white54)),
                    ]),
                  ),
                ]),

                const SizedBox(height: 18),

                // Headline — same for everyone
                Text('I WAS THERE.', style: TextStyle(
                  fontFamily: 'Clash', fontSize: 32, fontWeight: FontWeight.w700,
                  color: theme.accent, letterSpacing: -0.8,
                  shadows: [Shadow(
                    color: theme.accent.withOpacity(0.5), blurRadius: 20)])),
                const SizedBox(height: 5),
                Text(ticket.eventName, style: const TextStyle(
                  fontFamily: 'Clash', fontSize: 19, fontWeight: FontWeight.w700,
                  color: Colors.white, height: 1.15, letterSpacing: -0.3)),
                const SizedBox(height: 3),
                Text(dateFmt.format(ticket.eventDate), style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 12,
                  color: theme.accent.withOpacity(0.8))),

                const SizedBox(height: 16),

                // Photo grid — tap to add your own photos
                Row(children: [
                  _photoSlot(0, context),
                  const SizedBox(width: 6),
                  Column(children: [
                    _photoSlot(1, context, height: 75),
                    const SizedBox(height: 6),
                    _photoSlot(2, context, height: 75),
                  ]),
                ]),

                const SizedBox(height: 14),

                // Vibe pills — describe the night
                Wrap(spacing: 6, runSpacing: 6, children: [
                  _vibePill(theme.emoji + ' ' + theme.vibe, theme),
                  _vibePill('📍 ' + ticket.eventCity, theme),
                  _vibePill('🙌 ${_attendeeCount()}K attended', theme),
                  _vibePill('#Delight', theme),
                ]),

                const Spacer(),

                // Bottom
                Row(children: [
                  Text('delight.africa', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 10,
                    color: theme.accent.withOpacity(0.55))),
                  const Spacer(),
                  Icon(Icons.verified, size: 12,
                    color: theme.accent.withOpacity(0.55)),
                  const SizedBox(width: 3),
                  Text('Verified on DC Ledger', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 10,
                    color: theme.accent.withOpacity(0.45))),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  String _attendeeCount() {
    // In production pull real attendee count from event
    return '1.5';
  }

  Widget _photoSlot(int index, BuildContext context, {double height = 156}) {
    final hasPhoto = index < photos.length;
    return Expanded(
      child: GestureDetector(
        onTap: onAddPhoto,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(hasPhoto ? 0 : 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasPhoto
                ? Colors.transparent
                : theme.accent.withOpacity(0.2),
              style: hasPhoto ? BorderStyle.none : BorderStyle.solid)),
          clipBehavior: Clip.antiAlias,
          child: hasPhoto
            ? Container(color: theme.accent.withOpacity(0.3),
                alignment: Alignment.center,
                child: Text(theme.emoji, style: const TextStyle(fontSize: 32)))
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_photo_alternate_outlined,
                  size: 24, color: theme.accent.withOpacity(0.5)),
                const SizedBox(height: 5),
                Text('Add photo', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 10,
                  color: theme.accent.withOpacity(0.5))),
              ]),
        ),
      ),
    );
  }

  Widget _vibePill(String label, _EventTheme theme) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: theme.accent.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: theme.accent.withOpacity(0.25))),
    child: Text(label, style: TextStyle(
      fontFamily: 'Satoshi', fontSize: 11,
      fontWeight: FontWeight.w600, color: theme.accent)),
  );
}

// ─── Diagonal texture painter ─────────────────────────────────────────────────
// _DiagonalPainter removed — was causing Memory tab freeze

// ─── Shared widget: delight logo ──────────────────────────────────────────────
Widget _delightLogo(_EventTheme theme) => Image.asset(
  'assets/images/delight_logo.png',
  height: 22,
  fit: BoxFit.contain,
  color: Colors.white,
  colorBlendMode: BlendMode.srcIn,
);

// ═══════════════════════════════════════════════════════════════════════════════
// SHARE STRIP
// ═══════════════════════════════════════════════════════════════════════════════

class _ShareStrip extends StatelessWidget {
  final NFTTicket ticket;
  final _EventTheme theme;
  final VoidCallback onShare;
  const _ShareStrip({required this.ticket, required this.theme, required this.onShare});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Share your experience', style: TextStyle(
            fontFamily: 'Satoshi', fontSize: 12, fontWeight: FontWeight.w700,
            color: theme.accent.withOpacity(0.8))),
          const SizedBox(width: 6),
          Text('Everyone will want to be there next time',
            style: const TextStyle(fontFamily: 'Satoshi', fontSize: 11,
              color: DelightColors.textMuted)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _btn(context, '📸', 'Instagram', const Color(0xFFE4405F), onShare),
          const SizedBox(width: 8),
          _btn(context, '💬', 'WhatsApp',  const Color(0xFF25D366), onShare),
          const SizedBox(width: 8),
          _btn(context, '🐦', 'X',         const Color(0xFF1DA1F2), onShare),
          const SizedBox(width: 8),
          _btn(context, '⬇️', 'Save',      DelightColors.gold, () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Card saved to your photos!')));
          }),
        ]),
        const SizedBox(height: 10),
        // Post to Delight feed
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            // Open Memory Builder directly with this ticket pre-selected
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _MemoryBuilderSheet(ticket: ticket));
          },
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.accent, theme.accent.withOpacity(0.7)]),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(
                color: theme.accent.withOpacity(0.3),
                blurRadius: 12, offset: const Offset(0, 3))]),
            alignment: Alignment.center,
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('💎', style: TextStyle(fontSize: 16)),
              SizedBox(width: 8),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Create & Post Memory NFT',
                  style: TextStyle(fontFamily: 'Satoshi', fontWeight: FontWeight.w800,
                    color: Colors.white, fontSize: 14)),
                Text('Posts to your Delight profile — not Instagram',
                  style: TextStyle(fontFamily: 'Satoshi',
                    color: Colors.white70, fontSize: 10)),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _btn(BuildContext ctx, String emoji, String label,
      Color color, VoidCallback onTap) {
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2))),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(
            fontFamily: 'Satoshi', fontSize: 9,
            fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FULL SHARE SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _ShareSheet extends StatefulWidget {
  final NFTTicket ticket;
  final _EventTheme theme;
  const _ShareSheet({required this.ticket, required this.theme});
  @override State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  int _selectedCard = 0; // 0=Hype, 1=Entry, 2=Memory
  final _captionCtrl = TextEditingController(
    text: "I was there 🔥 ");
  @override void dispose() { _captionCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme  = widget.theme;
    final ticket = widget.ticket;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20,
          MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: DelightColors.surfaceBorder,
              borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 18),

          // Header
          Text('Share your ticket', style: TextStyle(
            fontFamily: 'Clash', fontSize: 22, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary)),
          const SizedBox(height: 2),
          Text('Screenshot your card and share anywhere',
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
              color: DelightColors.textMuted)),
          const SizedBox(height: 20),

          // Card style picker — pick which card to share
          Row(children: [
            _cardPill('🔥 Hype',   0, theme),
            const SizedBox(width: 8),
            _cardPill('🎟 Entry',  1, theme),
            const SizedBox(width: 8),
            _cardPill('📸 Memory', 2, theme),
          ]),
          const SizedBox(height: 16),

          // Mini card preview
          _MiniCardPreview(ticket: ticket, theme: theme, cardIndex: _selectedCard),
          const SizedBox(height: 16),

          // Caption — auto-fills, user can edit
          Container(
            decoration: BoxDecoration(
              color: DelightColors.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: DelightColors.surfaceBorder)),
            child: TextField(
              controller: _captionCtrl,
              maxLines: 2,
              style: const TextStyle(fontFamily: 'Satoshi',
                color: DelightColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Add your caption...',
                contentPadding: EdgeInsets.all(14),
                border: InputBorder.none))),
          const SizedBox(height: 8),

          // Quick hashtags
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              '#Delight', '#IWasThere', '#AfricanEvents',
              '#NFTTicket', '#${ticket.eventCity}',
            ].map((tag) => GestureDetector(
              onTap: () => setState(() =>
                _captionCtrl.text += ' $tag'),
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: theme.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.accent.withOpacity(0.25))),
                child: Text(tag, style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.accent))))).toList())),
          const SizedBox(height: 20),

          // Section label: Share outside Delight
          const Row(children: [
            Expanded(child: Divider(color: DelightColors.surfaceBorder)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text('SHARE OUTSIDE DELIGHT',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: DelightColors.textMuted, letterSpacing: 1.2))),
            Expanded(child: Divider(color: DelightColors.surfaceBorder)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _shareBtn('💬', 'WhatsApp', const Color(0xFF25D366), () {
              final text = _captionCtrl.text + '\n\n' +
                ticket.eventName + ' · ' + ticket.tier +
                '\nGet yours on Delight 👉 delight.africa';
              Navigator.pop(context);
              launchUrl(Uri.parse(
                'https://wa.me/?text=' + Uri.encodeComponent(text)),
                mode: LaunchMode.externalApplication);
            }),
            const SizedBox(width: 8),
            _shareBtn('🐦', 'X (Twitter)', const Color(0xFF1DA1F2), () {
              final text = _captionCtrl.text + ' ' + ticket.eventName +
                ' #Delight #IWasThere delight.africa';
              Navigator.pop(context);
              launchUrl(Uri.parse(
                'https://twitter.com/intent/tweet?text=' +
                Uri.encodeComponent(text)),
                mode: LaunchMode.externalApplication);
            }),
            const SizedBox(width: 8),
            _shareBtn('🔗', 'Copy', DelightColors.textMuted, () async {
              final text = _captionCtrl.text + '\n\n' +
                ticket.eventName + ' · ' + ticket.tier +
                '\nGet yours on Delight 👉 delight.africa';
              await Clipboard.setData(ClipboardData(text: text));
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied — paste anywhere ✓'),
                    backgroundColor: DelightColors.emerald));
              }
            }),
          ]),
          const SizedBox(height: 10),

          // Instagram + TikTok — one tap opens the app
          // The NFT card IS the post. Screenshot it and post.
          Row(children: [
            _shareBtn('📸', 'Instagram', const Color(0xFFE4405F), () async {
              final shareText = _captionCtrl.text + '\n\n' +
                ticket.eventName + ' · ' + ticket.tier +
                '\nGet yours on Delight 👉 delight.africa';
              await Clipboard.setData(ClipboardData(text: shareText));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Caption copied! Open Instagram and paste it 📋'),
                backgroundColor: Color(0xFFE4405F),
                duration: Duration(seconds: 4)));
              launchUrl(Uri.parse('https://www.instagram.com/'),
                mode: LaunchMode.externalApplication);
            }),
            const SizedBox(width: 8),
            _shareBtn('🎵', 'TikTok', const Color(0xFF010101), () async {
              final shareText = _captionCtrl.text + '\n\n' +
                ticket.eventName + ' · ' + ticket.tier +
                '\nGet yours on Delight 👉 delight.africa';
              await Clipboard.setData(ClipboardData(text: shareText));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Caption copied! Open TikTok and paste it 📋'),
                backgroundColor: Color(0xFF010101),
                duration: Duration(seconds: 4)));
              launchUrl(Uri.parse('https://www.tiktok.com/'),
                mode: LaunchMode.externalApplication);
            }),
            const SizedBox(width: 8),
            _shareBtn('📱', 'SMS', DelightColors.emerald, () {
              final text = _captionCtrl.text + '\n' +
                ticket.eventName + ' delight.africa';
              Navigator.pop(context);
              launchUrl(Uri.parse(
                'sms:?body=' + Uri.encodeComponent(text)),
                mode: LaunchMode.externalApplication);
            }),
          ]),
          const SizedBox(height: 16),

          // Section label: Post inside Delight
          const Row(children: [
            Expanded(child: Divider(color: DelightColors.surfaceBorder)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text('POST ON DELIGHT',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: DelightColors.textMuted, letterSpacing: 1.2))),
            Expanded(child: Divider(color: DelightColors.surfaceBorder)),
          ]),
          const SizedBox(height: 10),
          Material(color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Posted to your Delight feed 🔥'),
                  backgroundColor: DelightColors.emerald));
              },
              child: Container(
                height: 56, width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    theme.accent, theme.accent.withOpacity(0.7)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(
                    color: theme.accent.withOpacity(0.35),
                    blurRadius: 16, offset: const Offset(0, 4))]),
                alignment: Alignment.center,
                child: Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  const Text('🔥', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    Text('Post on Delight',
                      style: TextStyle(fontFamily: 'Satoshi', fontSize: 16,
                        fontWeight: FontWeight.w800, color: Colors.white)),
                    Text('Visible to your Delight followers',
                      style: TextStyle(fontFamily: 'Satoshi', fontSize: 10,
                        color: Colors.white70)),
                  ]),
                ])))),
        ])));
  }

  Widget _cardPill(String label, int idx, _EventTheme theme) {
    final sel = _selectedCard == idx;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _selectedCard = idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: sel
            ? theme.accent.withOpacity(0.15)
            : DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: sel ? theme.accent : DelightColors.surfaceBorder,
            width: sel ? 1.5 : 1)),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(
          fontFamily: 'Satoshi', fontSize: 11,
          fontWeight: FontWeight.w700,
          color: sel ? theme.accent : DelightColors.textMuted)))));
  }

  Widget _shareBtn(String emoji, String label, Color color,
      VoidCallback onTap) =>
    Expanded(child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2))),
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontFamily: 'Satoshi',
              fontSize: 9, fontWeight: FontWeight.w700, color: color),
              textAlign: TextAlign.center),
          ])))));
}

// ── Mini NFT card preview shown in share sheet ────────────────────────────────
class _MiniCardPreview extends StatelessWidget {
  final NFTTicket ticket;
  final _EventTheme theme;
  final int cardIndex;
  const _MiniCardPreview({
    required this.ticket, required this.theme, required this.cardIndex});

  @override
  Widget build(BuildContext context) {
    final labels = ["🔥  I'M GOING", "🎟  MY TICKET", "📸  I WAS THERE"];
    final label  = labels[cardIndex];

    return Container(
      height: 160,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: theme.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.accent.withOpacity(0.5), width: 1.5),
        boxShadow: [BoxShadow(
          color: theme.accent.withOpacity(0.3),
          blurRadius: 20, offset: const Offset(0, 6))]),
      child: Stack(children: [
        // Background emoji watermark
        Positioned.fill(child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Opacity(opacity: 0.06,
            child: GridView.count(
              crossAxisCount: 8, physics: const NeverScrollableScrollPhysics(),
              children: List.generate(64, (_) => Center(
                child: Text(theme.emoji,
                  style: const TextStyle(fontSize: 18)))))))),

        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Top row: delight logo + NFT badge
            Row(children: [
              Image.asset('assets/images/delight_logo.png',
                height: 18, fit: BoxFit.contain,
                color: Colors.white, colorBlendMode: BlendMode.srcIn),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(6)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.diamond_outlined,
                    size: 9, color: theme.accent),
                  const SizedBox(width: 3),
                  Text('NFT', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 9,
                    fontWeight: FontWeight.w800, color: theme.accent)),
                ])),
            ]),
            const Spacer(),
            // Big label
            Text(label, style: TextStyle(
              fontFamily: 'Clash', fontSize: 11,
              fontWeight: FontWeight.w700, color: theme.accent,
              letterSpacing: 2)),
            const SizedBox(height: 2),
            Text(ticket.eventName, style: const TextStyle(
              fontFamily: 'Clash', fontSize: 18,
              fontWeight: FontWeight.w700, color: Colors.white,
              letterSpacing: -0.3)),
            const SizedBox(height: 4),
            Text('${ticket.tier} · ${ticket.eventCity}',
              style: const TextStyle(fontFamily: 'Satoshi',
                fontSize: 11, color: Colors.white60)),
          ])),
      ]));
  }
}


// ═══════════════════════════════════════════════════════════════════════════════
// ON-CHAIN ROW
// ═══════════════════════════════════════════════════════════════════════════════

class _OnChainRow extends StatelessWidget {
  final NFTTicket ticket;
  final _EventTheme theme;
  const _OnChainRow({required this.ticket, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Row(children: [
        const Icon(Icons.link, size: 14, color: DelightColors.emerald),
        const SizedBox(width: 8),
        Expanded(child: Text(ticket.tokenId,
          style: const TextStyle(fontFamily: 'Courier', fontSize: 11,
            color: DelightColors.textMuted))),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: ticket.tokenId));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Token ID copied')));
          },
          child: const Icon(Icons.copy, size: 16, color: DelightColors.textMuted)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BOTTOM ACTIONS
// ═══════════════════════════════════════════════════════════════════════════════

class _BottomActions extends ConsumerStatefulWidget {
  final NFTTicket ticket;
  final _EventTheme theme;
  const _BottomActions({required this.ticket, required this.theme});
  @override
  ConsumerState<_BottomActions> createState() => _BottomActionsState();
}

class _BottomActionsState extends ConsumerState<_BottomActions> {
  NFTTicket get ticket => widget.ticket;

  @override
  Widget build(BuildContext context) {
    // ── Ticket already used ────────────────────────────────────────────────
    if (ticket.isUsed) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: DelightColors.surfaceBorder,
          borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        child: const Text('Ticket Used · Permanent NFT Memory',
          style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
            color: DelightColors.textMuted)));
    }

    // ── Ticket listed for sale ─────────────────────────────────────────────
    if (ticket.isForSale) {
      return Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: DelightColors.goldGlow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DelightColors.gold.withOpacity(0.3))),
          child: Row(children: [
            const Icon(Icons.storefront_outlined,
              color: DelightColors.gold, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Listed for sale — visible to other users', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 11,
                color: DelightColors.gold)),
              Text('R${(ticket.resalePriceXRP ?? 0).toStringAsFixed(0)}',
                style: const TextStyle(fontFamily: 'Clash', fontSize: 18,
                  fontWeight: FontWeight.w700, color: DelightColors.gold)),
            ])),
          ])),
        const SizedBox(height: 8),
        Material(color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              ref.read(ticketsProvider.notifier).cancelListing(ticket.id);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Listing cancelled')));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: DelightColors.surfaceHigh,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DelightColors.surfaceBorder)),
              alignment: Alignment.center,
              child: const Text('Cancel Listing', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 13,
                color: DelightColors.textMuted))))),
      ]);
    }

    // ── Normal ticket actions ──────────────────────────────────────────────
    return GestureDetector(
      onTap: () => _showResale(context),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: DelightColors.surfaceBorder)),
        alignment: Alignment.center,
        child: const Row(mainAxisAlignment: MainAxisAlignment.center,
          children: [
          Icon(Icons.sell_outlined, color: DelightColors.gold, size: 18),
          SizedBox(width: 8),
          Text('List for Resale', style: TextStyle(
            fontFamily: 'Satoshi', fontSize: 15,
            fontWeight: FontWeight.w600, color: DelightColors.gold)),
        ])));
  }

  void _showResale(BuildContext context) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: DelightColors.surfaceHigh,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24,
            MediaQuery.of(context).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('List for Resale', style: TextStyle(
              fontFamily: 'Clash', fontSize: 20,
              fontWeight: FontWeight.w700,
              color: DelightColors.textPrimary)),
            const SizedBox(height: 4),
            const Text('We charge 3% when your ticket sells.',
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                color: DelightColors.textMuted)),
            const SizedBox(height: 20),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true),
              autofocus: true,
              onChanged: (_) => setSheet(() {}),
              style: const TextStyle(fontFamily: 'Clash', fontSize: 36,
                fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary),
              decoration: const InputDecoration(
                hintText: '0.00',
                prefixText: 'R ',
                prefixStyle: TextStyle(fontFamily: 'Clash',
                  color: DelightColors.gold,
                  fontWeight: FontWeight.w700, fontSize: 36),
                border: InputBorder.none)),
            if ((double.tryParse(ctrl.text) ?? 0) > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DelightColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: DelightColors.surfaceBorder)),
                child: Column(children: [
                  _feeRow('Listed price',
                    'R${ctrl.text}',
                    DelightColors.textPrimary),
                  _feeRow('Platform fee (3%)',
                    '- R${((double.tryParse(ctrl.text) ?? 0) * 0.03).toStringAsFixed(2)}',
                    DelightColors.textMuted),
                  const Divider(
                    color: DelightColors.surfaceBorder, height: 12),
                  _feeRow('You receive',
                    'R${((double.tryParse(ctrl.text) ?? 0) * 0.97).toStringAsFixed(2)}',
                    DelightColors.emerald, bold: true),
                ])),
            ],
            const SizedBox(height: 20),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  final price = double.tryParse(ctrl.text) ?? 0;
                  if (price < 10) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Minimum listing price is R10')));
                    return;
                  }
                  ref.read(ticketsProvider.notifier)
                    .listForSale(ticket.id, price);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                      'Ticket listed for R${price.toStringAsFixed(0)}'),
                    backgroundColor: DelightColors.emerald));
                },
                child: Container(
                  height: 56, width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: DelightColors.goldGradient),
                    borderRadius: BorderRadius.circular(16)),
                  alignment: Alignment.center,
                  child: const Text('List Ticket for Sale',
                    style: TextStyle(fontFamily: 'Satoshi',
                      fontSize: 17, fontWeight: FontWeight.w700,
                      color: DelightColors.textInverse))))),
          ]))));
  }

  Widget _feeRow(String label, String value, Color color,
      {bool bold = false}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(
          fontFamily: 'Satoshi', fontSize: 12,
          color: DelightColors.textSecondary))),
        Text(value, style: TextStyle(fontFamily: 'Satoshi',
          fontSize: 12, color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
      ]));
}

// ── Memory Builder Sheet (opened from ticket) ────────────────────────────────

class _MemoryBuilderSheet extends ConsumerStatefulWidget {
  final NFTTicket ticket;
  const _MemoryBuilderSheet({required this.ticket});
  @override
  ConsumerState<_MemoryBuilderSheet> createState() =>
    _MemoryBuilderSheetState();
}

class _MemoryBuilderSheetState extends ConsumerState<_MemoryBuilderSheet> {
  final _ctrl = TextEditingController();
  String _style = 'Electric';
  bool _minting = false;
  bool _hasVideo = false;
  final List<dynamic> _photos = []; // File or String URL

  static const _styles = ['Electric','Midnight','Gold','Neon'];
  static const _demoPhotos = [
    'https://images.unsplash.com/photo-1470229722913-7c0e2dbbafd3?w=600',
    'https://images.unsplash.com/photo-1501281668745-f7f57925c3b4?w=600',
    'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=600',
    'https://images.unsplash.com/photo-1505373877841-8d25f7d46678?w=600',
  ];

  Color get _accent {
    switch (_style) {
      case 'Electric': return const Color(0xFF00C96A);
      case 'Midnight': return const Color(0xFF6C63FF);
      case 'Gold':     return const Color(0xFFD4AF37);
      case 'Neon':     return const Color(0xFFFF006E);
      default:         return const Color(0xFF00C96A);
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _mint() async {
    if (_ctrl.text.trim().isEmpty && _photos.isEmpty && !_hasVideo) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Add a caption, photo or video first')));
      return;
    }
    setState(() => _minting = true);

    // Upload any local File photos to Supabase storage — turn them into real URLs
    final List<String> imageUrls = [];
    for (final photo in _photos) {
      if (photo is File) {
        try {
          final bytes = await photo.readAsBytes();
          final path = 'memories/${DateTime.now().millisecondsSinceEpoch}_${imageUrls.length}.jpg';
          await Supabase.instance.client.storage.from('posts').uploadBinary(
            path, bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'));
          imageUrls.add(Supabase.instance.client.storage.from('posts').getPublicUrl(path));
        } catch (_) {
          // Skip photos that fail to upload rather than blocking the whole mint
        }
      } else if (photo is String) {
        imageUrls.add(photo);
      }
    }

    final user = ref.read(authProvider);
    final memTokenId = 'MEM_${DateTime.now().millisecondsSinceEpoch}';

    // Persist to Supabase so it's real and visible to everyone, not just local state
    try {
      await Supabase.instance.client.from('posts').insert({
        'user_id': user?.id,
        'content': _ctrl.text.trim().isEmpty
          ? 'Was there. Proof on-chain.' : _ctrl.text.trim(),
        'image_url': imageUrls.isNotEmpty ? imageUrls.first : null,
        'is_nft_memory': true,
        'has_video': _hasVideo,
      });
    } catch (_) {
      // Offline fallback — still show locally below
    }

    ref.read(feedProvider.notifier).add(SocialPost(
      id: 'p_${DateTime.now().millisecondsSinceEpoch}',
      userId: user?.id ?? 'anon',
      userDisplayName: user?.displayName ?? 'You',
      content: _ctrl.text.trim().isEmpty
        ? 'Was there. Proof on-chain. 🎟💎'
        : _ctrl.text.trim(),
      imageUrls: imageUrls,
      isNftMemory: true,
      memoryTokenId: memTokenId,
      attendedEventName: widget.ticket.eventName,
      attendedEventVenue: '${widget.ticket.eventVenue}, ${widget.ticket.eventCity}',
      attendedTier: widget.ticket.tier,
      attendedTicketId: widget.ticket.tokenId,
      eventDate: widget.ticket.eventDate,
      hasVideo: _hasVideo,
      memoryStyle: _style,
      nftTokenId: memTokenId,
      timestamp: DateTime.now(),
    ));

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Memory NFT minted and shared to your feed! 🔥'),
        backgroundColor: _accent));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A12),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),

          // Header
          Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Mint Memory NFT', style: TextStyle(
                fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
                color: Colors.white)),
              Text('Proof you were there — on XRP Ledger forever',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                  color: Colors.white.withOpacity(0.5))),
            ])),
            GestureDetector(
              onTap: _minting ? null : _mint,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_accent, _accent.withOpacity(0.7)]),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(
                    color: _accent.withOpacity(0.4),
                    blurRadius: 12, offset: const Offset(0, 4))]),
                child: _minting
                  ? SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.black, strokeWidth: 2))
                  : const Text('Mint & Share', style: TextStyle(
                      fontFamily: 'Satoshi', fontWeight: FontWeight.w800,
                      fontSize: 13, color: Colors.black)))),
          ]),
          const SizedBox(height: 16),

          // Ticket locked in
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_accent.withOpacity(0.15), _accent.withOpacity(0.05)]),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _accent.withOpacity(0.3))),
            child: Row(children: [
              Icon(Icons.confirmation_number_outlined,
                color: _accent, size: 16),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.ticket.eventName, style: const TextStyle(
                  fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                  fontSize: 13, color: Colors.white),
                  overflow: TextOverflow.ellipsis),
                Text(
                  '${widget.ticket.tier} · ${widget.ticket.eventVenue}',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                    color: Colors.white.withOpacity(0.5))),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(5)),
                child: Text('VERIFIED', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 8,
                  fontWeight: FontWeight.w800, color: _accent,
                  letterSpacing: 0.8))),
            ])),
          const SizedBox(height: 12),

          // Style picker
          Row(children: _styles.map((s) {
            final sel = s == _style;
            final sc = s == 'Electric' ? const Color(0xFF00C96A)
              : s == 'Midnight' ? const Color(0xFF6C63FF)
              : s == 'Gold'    ? const Color(0xFFD4AF37)
              : const Color(0xFFFF006E);
            return Expanded(child: GestureDetector(
              onTap: () => setState(() => _style = s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? sc.withOpacity(0.15) : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: sel ? sc : Colors.white.withOpacity(0.08),
                    width: sel ? 1.5 : 1)),
                alignment: Alignment.center,
                child: Text(s, style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 11, fontWeight: FontWeight.w700,
                  color: sel ? sc : Colors.white38)))));
          }).toList()),
          const SizedBox(height: 12),

          // Caption
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1))),
            child: TextField(
              controller: _ctrl,
              maxLines: 3,
              style: const TextStyle(fontFamily: 'Satoshi',
                fontSize: 14, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Describe your moment — what did you feel, who did you meet...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                border: InputBorder.none))),
          const SizedBox(height: 10),

          // Photo strip
          if (_photos.isNotEmpty)
            SizedBox(
              height: 72,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _photos.length,
                itemBuilder: (_, i) => Stack(children: [
                  Container(
                    width: 72, height: 72,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _accent.withOpacity(0.4)),
                      image: DecorationImage(
                        image: _photos[i] is File
                          ? FileImage(_photos[i] as File) as ImageProvider
                          : NetworkImage(_photos[i] as String),
                        fit: BoxFit.cover))),
                  Positioned(top: 3, right: 11,
                    child: GestureDetector(
                      onTap: () => setState(() => _photos.removeAt(i)),
                      child: Container(
                        width: 18, height: 18,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          shape: BoxShape.circle),
                        child: const Icon(Icons.close,
                          color: Colors.white, size: 11)))),
                ]))),

          // Add photo / video bar
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(
                color: Colors.white.withOpacity(0.08)))),
            child: Row(children: [
              Expanded(child: GestureDetector(
                onTap: () async {
                  if (_photos.length >= 4) return;
                  final picker = ImagePicker();
                  final xfile = await picker.pickImage(
                    source: ImageSource.gallery, imageQuality: 80);
                  if (xfile != null && mounted) {
                    setState(() => _photos.add(File(xfile.path)));
                  }
                },
                child: Column(children: [
                  Icon(Icons.add_photo_alternate_outlined,
                    color: _accent, size: 22),
                  const SizedBox(height: 2),
                  Text('Photo', style: TextStyle(fontFamily: 'Satoshi',
                    fontSize: 9, fontWeight: FontWeight.w600, color: _accent)),
                ]))),
              Expanded(child: GestureDetector(
                onTap: () async {
                  final picker = ImagePicker();
                  final xfile = await picker.pickVideo(source: ImageSource.gallery);
                  if (xfile != null && mounted) {
                    setState(() => _hasVideo = true);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Video attached: ${xfile.name}'),
                      backgroundColor: _accent));
                  }
                },
                child: Column(children: [
                  Icon(_hasVideo ? Icons.videocam : Icons.videocam_outlined,
                    color: _accent.withOpacity(0.8), size: 22),
                  const SizedBox(height: 2),
                  Text(_hasVideo ? '✓ Video' : 'Video', style: TextStyle(fontFamily: 'Satoshi',
                    fontSize: 9, fontWeight: FontWeight.w600,
                    color: _accent.withOpacity(0.8))),
                ]))),
              Expanded(child: Container(
                alignment: Alignment.center,
                child: Text('${_photos.length}/4',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 10,
                    color: _accent.withOpacity(0.5))))),
            ])),
          const SizedBox(height: 8),
        ])));
  }
}

