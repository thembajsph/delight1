// lib/features/social/presentation/screens/social_screen.dart
// Instagram-style feed with NFT event posts, stories, and exclusive ticket-gated content

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:delight/core/services/ad_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/models/models.dart';

// ── Exclusive post model ──────────────────────────────────────────────────────
class ExclusivePost {
  final String id, eventId, eventName, organizerName, content;
  final List<String> imageUrls;
  final String requiredTier;   // 'General', 'VIP', 'Table'
  final bool isUnlocked;
  final DateTime timestamp;
  final int likesCount;
  const ExclusivePost({
    required this.id, required this.eventId, required this.eventName,
    required this.organizerName, required this.content, required this.imageUrls,
    required this.requiredTier, required this.isUnlocked,
    required this.timestamp, required this.likesCount,
  });
}

// ── Social Screen ─────────────────────────────────────────────────────────────

class SocialScreen extends ConsumerStatefulWidget {
  const SocialScreen({super.key});
  @override ConsumerState<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends ConsumerState<SocialScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            floating: true, snap: true,
            backgroundColor: DelightColors.background,
            title: Image.asset(
              'assets/images/delight_logo.png',
              height: 32,
              fit: BoxFit.contain),
            actions: [
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline, color: DelightColors.textPrimary),
                onPressed: () => context.push('/messages'),
              ),
              IconButton(
                icon: const Icon(Icons.add_box_outlined, color: DelightColors.textPrimary),
                onPressed: () => _showCreatePost(context),
              ),
            ],
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              controller: _tab,
              indicatorColor: DelightColors.emerald,
              indicatorSize: TabBarIndicatorSize.label,
              indicatorWeight: 2,
              labelColor: DelightColors.textPrimary,
              unselectedLabelColor: DelightColors.textMuted,
              labelStyle: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 13, fontWeight: FontWeight.w700),
              tabs: const [
                Tab(text: 'Feed'),
                Tab(text: 'Reels ▶'),
                Tab(text: 'Exclusive 🔐'),
                Tab(text: 'Discover'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tab,
          children: [
            _FeedTab(),
            _ReelsTab(),
            _ExclusiveTab(),
            _DiscoverTab(),
          ],
        ),
      ),
    );
  }

  void _showCreatePost(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CreatePostSheet(key: UniqueKey()),
    );
  }
}

// ── Feed Tab ──────────────────────────────────────────────────────────────────

class _FeedTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts  = ref.watch(feedProvider);
    final events = ref.watch(eventsProvider);

    // Upcoming events sorted by date, next 30 days
    final upcoming = (events
      .where((e) => e.date.isAfter(DateTime.now()))
      .toList()
      ..sort((a, b) => a.date.compareTo(b.date)))
      .take(4).toList();

    // Build a merged feed list:
    // Every 3rd post → event card, every 7th item → native ad
    final items = <dynamic>[];
    int eventIdx = 0;
    for (int i = 0; i < posts.length; i++) {
      items.add(posts[i]);
      if ((i + 1) % 3 == 0 && eventIdx < upcoming.length) {
        items.add(upcoming[eventIdx++]);
      }
      // Native ad slot every 7 items — seamless, not intrusive
      if ((items.length) % 7 == 0) {
        items.add('__ad__');
      }
    }
    while (eventIdx < upcoming.length) {
      items.add(upcoming[eventIdx++]);
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _WelcomeBanner()),
        SliverToBoxAdapter(child: _StoriesRow()),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              final item = items[i];
              if (item == '__ad__') return const DelightNativeAdCard();
              if (item is EventModel) return _FeedEventCard(event: item);
              return _PostCard(post: item as SocialPost);
            },
            childCount: items.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }
}

// ── Stories ───────────────────────────────────────────────────────────────────

class _StoriesRow extends ConsumerWidget {
  /// "You" + the people who actually posted recently. Nothing invented.
  List<({String name, String emoji, bool isYou, bool hasNew, bool isNFT,
         List<(String, String?)> slides})> _build(List<SocialPost> posts, String? me) {
    final byUser = <String, List<SocialPost>>{};
    for (final p in posts) {
      if (p.userId == me) continue;
      byUser.putIfAbsent(p.userId, () => []).add(p);
    }
    final out = <({String name, String emoji, bool isYou, bool hasNew,
                   bool isNFT, List<(String, String?)> slides})>[
      (name: 'You', emoji: '➕', isYou: true, hasNew: false, isNFT: false, slides: const []),
    ];
    for (final e in byUser.entries.take(12)) {
      final first = e.value.first;
      final n = first.userDisplayName.trim();
      out.add((
        name: n.isEmpty ? 'User' : n,
        emoji: n.isEmpty ? '👤' : n[0].toUpperCase(),
        isYou: false, hasNew: true,
        isNFT: e.value.any((p) => p.isNftMemory),
        slides: e.value.take(5).map((p) =>
          (p.content, p.imageUrls.isEmpty ? null : p.imageUrls.first)).toList()));
    }
    return out;
  }

  void _openStory(BuildContext context, dynamic s) {
    if (s.isYou) {
      // Open the create post / Memory Builder
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _CreatePostSheet(key: UniqueKey()));
      return;
    }
    // Show story viewer for other users
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _StoryViewer(name: s.name, emoji: s.emoji,
        isNFT: s.isNFT, slides: s.slides));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stories = _build(ref.watch(feedProvider),
      SupabaseService.currentUser?.id);
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: stories.length,
        itemBuilder: (_, i) {
          final s = stories[i];
          return GestureDetector(
            onTap: () => _openStory(context, s),
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Column(children: [
                Stack(children: [
                  Container(
                    width: 62, height: 62,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: s.hasNew
                        ? LinearGradient(colors: s.isNFT
                            ? [DelightColors.gold, DelightColors.emerald]
                            : [DelightColors.emerald, DelightColors.emeraldDark])
                        : null,
                      color: s.hasNew ? null : DelightColors.surfaceBorder,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: DelightColors.surface,
                        border: Border.all(color: DelightColors.background, width: 2)),
                      alignment: Alignment.center,
                      child: Text(s.isYou ? '➕' : s.emoji,
                        style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                  if (s.isNFT)
                    Positioned(bottom: 0, right: 0, child: Container(
                      width: 18, height: 18,
                      decoration: BoxDecoration(
                        color: DelightColors.gold,
                        shape: BoxShape.circle,
                        border: Border.all(color: DelightColors.background, width: 1.5)),
                      child: const Icon(Icons.diamond_outlined,
                        size: 10, color: DelightColors.textInverse),
                    )),
                ]),
                const SizedBox(height: 5),
                Text(s.name, style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 10,
                  color: DelightColors.textSecondary),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ── Feed Event Card — upcoming event ad in the timeline ─────────────────────
// Free advertising for organisers. Everyone sees it while scrolling posts.

class _FeedEventCard extends StatelessWidget {
  final EventModel event;
  const _FeedEventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final daysUntil = event.date.difference(DateTime.now()).inDays;
    final lowestZAR = (event.lowestPrice * 9.5).toStringAsFixed(0);

    return GestureDetector(
      onTap: () => context.push('/event/${event.id}', extra: event),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 1),
        decoration: BoxDecoration(
          color: DelightColors.surface,
          border: Border.symmetric(
            horizontal: BorderSide(
              color: DelightColors.surfaceBorder, width: 0.5))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Organiser header (like a post header) ─────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(children: [
              // Organiser avatar
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [DelightColors.emerald, DelightColors.emeraldDark])),
                alignment: Alignment.center,
                child: Text(
                  event.organizerName.isNotEmpty
                    ? event.organizerName[0].toUpperCase() : 'E',
                  style: const TextStyle(fontFamily: 'Clash',
                    fontSize: 16, fontWeight: FontWeight.w700,
                    color: Colors.white))),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(event.organizerName, style: const TextStyle(
                    fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                    fontSize: 14, color: DelightColors.textPrimary)),
                  const SizedBox(width: 6),
                  // Organiser badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: DelightColors.emeraldGlow,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: DelightColors.emerald.withOpacity(0.4))),
                    child: const Text('🎪 Organiser', style: TextStyle(
                      fontFamily: 'Satoshi', fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: DelightColors.emerald))),
                ]),
                Text('Upcoming Event · ${event.city}',
                  style: const TextStyle(fontFamily: 'Satoshi',
                    fontSize: 11, color: DelightColors.textMuted)),
              ])),
              // Days until badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: daysUntil <= 7
                    ? DelightColors.error.withOpacity(0.1)
                    : DelightColors.goldGlow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: daysUntil <= 7
                      ? DelightColors.error.withOpacity(0.4)
                      : DelightColors.gold.withOpacity(0.4))),
                child: Text(
                  daysUntil == 0 ? 'TODAY' :
                  daysUntil == 1 ? 'TOMORROW' :
                  daysUntil <= 7 ? 'IN $daysUntil DAYS' :
                  '${event.date.day}/${event.date.month}',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: daysUntil <= 7
                      ? DelightColors.error : DelightColors.gold))),
            ])),

          // ── Event cover image ──────────────────────────────────────
          if (event.coverImageUrl != null)
            CachedNetworkImage(
              imageUrl: event.coverImageUrl!,
              width: double.infinity,
              height: 220, fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                height: 120, color: DelightColors.surfaceHigh,
                child: const Icon(Icons.event,
                  color: DelightColors.textMuted, size: 40))),

          // ── Event info ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: DelightColors.emeraldGlow,
                    borderRadius: BorderRadius.circular(5)),
                  child: Text(event.category, style: const TextStyle(
                    fontFamily: 'Satoshi', fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: DelightColors.emerald))),
                const SizedBox(width: 8),
                Text(
                  '${event.venue}, ${event.city}',
                  style: const TextStyle(fontFamily: 'Satoshi',
                    fontSize: 11, color: DelightColors.textMuted),
                  overflow: TextOverflow.ellipsis),
              ]),
              const SizedBox(height: 6),
              Text(event.title, style: const TextStyle(
                fontFamily: 'Clash', fontSize: 18,
                fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary)),
              const SizedBox(height: 4),
              Text(
                event.description.length > 100
                  ? '${event.description.substring(0, 100)}...'
                  : event.description,
                style: const TextStyle(fontFamily: 'Satoshi',
                  fontSize: 13, color: DelightColors.textSecondary,
                  height: 1.4)),
            ])),

          // ── Buy tickets CTA ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => context.push('/event/${event.id}', extra: event),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: DelightColors.goldGradient),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(
                      color: DelightColors.gold.withOpacity(0.3),
                      blurRadius: 10, offset: const Offset(0, 3))]),
                  alignment: Alignment.center,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                    const Text('🎟', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text('Get Tickets — from R$lowestZAR',
                      style: const TextStyle(fontFamily: 'Satoshi',
                        fontSize: 13, fontWeight: FontWeight.w800,
                        color: Colors.black)),
                  ])))),
              const SizedBox(width: 10),
              // Share event
              GestureDetector(
                onTap: () => Share.share(
                  '${event.title} — ${event.venue}, ${event.city}\n'
                  'Get tickets on Delight 👉 delight.africa'),
                child: Container(
                  height: 44, width: 44,
                  decoration: BoxDecoration(
                    color: DelightColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: DelightColors.surfaceBorder)),
                  child: const Icon(Icons.share_outlined,
                    color: DelightColors.textMuted, size: 18))),
            ])),
        ])));
  }
}

// ── Story Viewer ──────────────────────────────────────────────────────────────

class _StoryViewer extends StatefulWidget {
  final String name, emoji;
  final bool isNFT;
  final List<(String, String?)> slides;   // (caption, imageUrl)
  const _StoryViewer({required this.name, required this.emoji,
    required this.isNFT, required this.slides});
  @override
  State<_StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<_StoryViewer>
    with SingleTickerProviderStateMixin {
  late AnimationController _progress;
  int _slide = 0;

  List<(String, String?)> get _storyContent => widget.slides;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4))
      ..addListener(() { setState(() {}); })
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          if (_slide < _storyContent.length - 1) {
            setState(() { _slide++; _progress.forward(from: 0); });
          } else {
            Navigator.pop(context);
          }
        }
      })
      ..forward();
  }

  @override
  void dispose() { _progress.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final story = _storyContent[_slide];
    return GestureDetector(
      onTapDown: (d) {
        final x = d.globalPosition.dx;
        final w = MediaQuery.of(context).size.width;
        if (x < w / 2) {
          // Tap left — previous slide
          if (_slide > 0) setState(() { _slide--; _progress.forward(from: 0); });
        } else {
          // Tap right — next slide
          if (_slide < _storyContent.length - 1) {
            setState(() { _slide++; _progress.forward(from: 0); });
          } else {
            Navigator.pop(context);
          }
        }
      },
      child: Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          image: DecorationImage(
            image: story.$2 != null
              ? CachedNetworkImageProvider(story.$2!) as ImageProvider
              : const AssetImage('assets/images/delight_logo.png'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.35), BlendMode.darken))),
        child: Column(children: [
          // Progress bars
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(children: List.generate(_storyContent.length, (i) {
              return Expanded(child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2)),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: i < _slide ? 1.0
                    : i == _slide ? _progress.value : 0.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2))))));
            }))),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.isNFT ? DelightColors.gold : DelightColors.emerald,
                    width: 2),
                  color: DelightColors.surfaceHigh),
                alignment: Alignment.center,
                child: Text(widget.emoji,
                  style: const TextStyle(fontSize: 18))),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.name, style: const TextStyle(
                  fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                  fontSize: 14, color: Colors.white)),
                Text('${_slide + 1} / ${_storyContent.length}',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                    color: Colors.white.withOpacity(0.6))),
              ])),
              if (widget.isNFT)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: DelightColors.gold.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: DelightColors.gold.withOpacity(0.5))),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.diamond_outlined, size: 10, color: DelightColors.gold),
                    SizedBox(width: 4),
                    Text('NFT', style: TextStyle(fontFamily: 'Satoshi',
                      fontSize: 9, fontWeight: FontWeight.w800,
                      color: DelightColors.gold)),
                  ])),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, color: Colors.white, size: 22)),
            ])),

          const Spacer(),

          // Caption at bottom
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(story.$1, style: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 16,
                fontWeight: FontWeight.w600, color: Colors.white,
                shadows: [Shadow(color: Colors.black54, blurRadius: 8)])),
              const SizedBox(height: 14),
              // Reply row
              Row(children: [
                Expanded(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white30)),
                  child: Text('Reply to ${widget.name}...',
                    style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                      color: Colors.white.withOpacity(0.6))))),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Opening chat with ${widget.name}...'),
                        backgroundColor: DelightColors.emerald));
                  },
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: DelightColors.emerald.withOpacity(0.8),
                      shape: BoxShape.circle),
                    child: const Icon(Icons.send, color: Colors.white, size: 18))),
              ]),
            ])),
        ])));
  }
}

// ── Post card — normal post OR NFT Memory (completely different layout) ─────────

class _PostCard extends ConsumerWidget {
  final SocialPost post;
  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (post.isNftMemory) return _MemoryCard(post: post, ref: ref);
    return _NormalCard(post: post, ref: ref);
  }
}

// ── Normal post ───────────────────────────────────────────────────────────────

class _NormalCard extends StatelessWidget {
  final SocialPost post;
  final WidgetRef ref;
  const _NormalCard({required this.post, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      decoration: const BoxDecoration(
        color: DelightColors.surface,
        border: Border(bottom: BorderSide(
          color: DelightColors.surfaceBorder, width: 0.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DelightColors.surfaceBorder),
              child: CircleAvatar(
                radius: 19,
                backgroundColor: DelightColors.surfaceBorder,
                backgroundImage: (post.userAvatarUrl?.isNotEmpty ?? false)
                  ? NetworkImage(post.userAvatarUrl ?? "") : null,
                child: post.userAvatarUrl == null
                  ? Text(post.userDisplayName[0].toUpperCase(),
                      style: const TextStyle(color: DelightColors.emerald,
                        fontWeight: FontWeight.w700, fontSize: 14))
                  : null)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(post.userDisplayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary, fontSize: 14)),
              if (post.eventName != null)
                Row(children: [
                  const Icon(Icons.event, size: 10,
                    color: DelightColors.textMuted),
                  const SizedBox(width: 3),
                  Flexible(child: Text(post.eventName!, style: const TextStyle(
                    fontFamily: 'Satoshi', fontSize: 11,
                    color: DelightColors.textMuted),
                    overflow: TextOverflow.ellipsis)),
                ]),
            ])),
            Text(timeago.format(post.timestamp), style: const TextStyle(
              fontFamily: 'Satoshi', fontSize: 11,
              color: DelightColors.textMuted)),
          ])),
        // Images
        if (post.imageUrls.isNotEmpty)
          post.imageUrls.length == 1
            ? CachedNetworkImage(
                imageUrl: post.imageUrls.first,
                width: double.infinity, height: 280, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  height: 280, color: DelightColors.surfaceHigh,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined,
                    color: DelightColors.textMuted, size: 40)))
            : SizedBox(
                height: 200,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: post.imageUrls.length,
                  itemBuilder: (_, i) => Padding(
                    padding: EdgeInsets.only(
                      right: i == post.imageUrls.length - 1 ? 0 : 2),
                    child: CachedNetworkImage(
                      imageUrl: post.imageUrls[i],
                      width: 200, height: 200, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        width: 200, height: 200,
                        color: DelightColors.surfaceHigh))))),
        // Actions + caption
        _PostActions(post: post, ref: ref),
      ]));
  }
}

// ── NFT Memory card — the special one ────────────────────────────────────────

class _MemoryCard extends StatelessWidget {
  final SocialPost post;
  final WidgetRef ref;
  const _MemoryCard({required this.post, required this.ref});

  // Each style has its own colour identity
  Color get _accent {
    switch (post.memoryStyle ?? 'Electric') {
      case 'Electric': return const Color(0xFF00C96A);
      case 'Midnight': return const Color(0xFF6C63FF);
      case 'Gold':     return const Color(0xFFD4AF37);
      case 'Neon':     return const Color(0xFFFF006E);
      default:         return DelightColors.emerald;
    }
  }

  List<Color> get _gradientColors {
    switch (post.memoryStyle) {
      case 'Electric': return [const Color(0xFF0A2A1A), const Color(0xFF060F0A)];
      case 'Midnight': return [const Color(0xFF12103A), const Color(0xFF08070F)];
      case 'Gold':     return [const Color(0xFF2A1E05), const Color(0xFF0F0A00)];
      case 'Neon':     return [const Color(0xFF2A0518), const Color(0xFF0F0009)];
      default:         return [const Color(0xFF0A2A1A), const Color(0xFF060F0A)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    final grads  = _gradientColors;
    final dateFmt = post.eventDate != null
      ? '${post.eventDate!.day}/${post.eventDate!.month}/${post.eventDate!.year}'
      : '';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: grads, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.4), width: 1.5),
        boxShadow: [BoxShadow(
          color: accent.withOpacity(0.2), blurRadius: 24,
          offset: const Offset(0, 8))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Top: Verified attendee header ─────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Row(children: [
            // Avatar with glowing ring
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [accent, accent.withOpacity(0.4)])),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: DelightColors.surfaceBorder,
                backgroundImage: (post.userAvatarUrl?.isNotEmpty ?? false)
                  ? NetworkImage(post.userAvatarUrl ?? "") : null,
                child: (post.userAvatarUrl == null)
                  ? Text(post.userDisplayName.isNotEmpty
                      ? post.userDisplayName[0].toUpperCase() : '?',
                      style: TextStyle(color: accent,
                        fontWeight: FontWeight.w700, fontSize: 14))
                  : null)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(post.userDisplayName, maxLines: 1,
                  overflow: TextOverflow.ellipsis, style: const TextStyle(
                  fontFamily: 'Satoshi', fontWeight: FontWeight.w800,
                  color: Colors.white, fontSize: 14))),
                const SizedBox(width: 6),
                // Verified badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: accent.withOpacity(0.5))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.verified, size: 10, color: accent),
                    const SizedBox(width: 3),
                    Text('VERIFIED', style: TextStyle(
                      fontFamily: 'Satoshi', fontSize: 8,
                      fontWeight: FontWeight.w800, color: accent,
                      letterSpacing: 0.8)),
                  ])),
              ]),
              Text(timeago.format(post.timestamp), style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 10,
                color: Colors.white.withOpacity(0.5))),
            ])),
            // Memory NFT badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accent.withOpacity(0.4))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.diamond_outlined, size: 11, color: accent),
                const SizedBox(width: 4),
                Text('NFT MEMORY', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 8,
                  fontWeight: FontWeight.w800, color: accent,
                  letterSpacing: 0.5)),
              ])),
          ])),

        // ── Event banner strip ────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withOpacity(0.25))),
          child: Row(children: [
            Icon(Icons.confirmation_number_outlined, size: 14, color: accent),
            const SizedBox(width: 8),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(post.attendedEventName ?? post.eventName ?? '',
                style: const TextStyle(fontFamily: 'Satoshi',
                  fontWeight: FontWeight.w700, fontSize: 12,
                  color: Colors.white),
                overflow: TextOverflow.ellipsis),
              if (post.attendedEventVenue != null)
                Text('${post.attendedEventVenue}  ·  $dateFmt',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 10,
                    color: Colors.white.withOpacity(0.5))),
            ])),
            // Tier badge
            if (post.attendedTier != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6)),
                child: Text(post.attendedTier!.toUpperCase(),
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 9,
                    fontWeight: FontWeight.w800, color: accent,
                    letterSpacing: 0.5))),
          ])),

        // ── Photos ───────────────────────────────────────────────────
        if (post.imageUrls.isNotEmpty) ...[
          const SizedBox(height: 10),
          if (post.imageUrls.length == 1)
            ClipRRect(
              borderRadius: BorderRadius.zero,
              child: CachedNetworkImage(
                imageUrl: post.imageUrls.first,
                width: double.infinity, height: 260, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  height: 260, color: DelightColors.surfaceHigh,
                  child: const Icon(Icons.broken_image_outlined,
                    color: DelightColors.textMuted))))
          else
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: post.imageUrls.length,
                itemBuilder: (_, i) => Container(
                  margin: const EdgeInsets.only(right: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: post.imageUrls[i],
                      width: 180, height: 200, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        width: 180, height: 200,
                        color: DelightColors.surfaceHigh)))))),
        ],

        // ── Caption ──────────────────────────────────────────────────
        if (post.content.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Text(post.content, style: const TextStyle(
              fontFamily: 'Satoshi', fontSize: 14,
              color: Colors.white, height: 1.5))),

        // ── On-chain proof strip ──────────────────────────────────────
        if (post.memoryTokenId != null)
          GestureDetector(
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(
                'Verified on XRP Ledger: ${post.memoryTokenId}'))),
            child: Container(
              margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.link, size: 12,
                  color: Colors.white.withOpacity(0.4)),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  post.memoryTokenId!,
                  style: TextStyle(fontFamily: 'Courier', fontSize: 10,
                    color: Colors.white.withOpacity(0.35)),
                  overflow: TextOverflow.ellipsis)),
                Icon(Icons.open_in_new, size: 11,
                  color: accent.withOpacity(0.6)),
              ])),
          ),

        // ── Actions ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Row(children: [
            _memAction(
              post.isLiked ? Icons.favorite : Icons.favorite_border,
              '${post.likesCount}',
              post.isLiked ? Colors.redAccent : Colors.white54,
              () => ref.read(feedProvider.notifier).toggleLike(post.id)),
            const SizedBox(width: 18),
            _memAction(Icons.chat_bubble_outline,
              '${post.commentsCount}', Colors.white54, () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: DelightColors.surfaceHigh,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20))),
                  builder: (_) => _CommentsSheet(post: post));
              }),
            const SizedBox(width: 18),
            _memAction(Icons.send_outlined, 'Share', accent, () {
              HapticFeedback.lightImpact();
              final shareText = post.content + '\n\nSeen on Delight 👉 delight.africa';
              showModalBottomSheet(
                context: context, isScrollControlled: true,
                backgroundColor: DelightColors.surfaceHigh,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (_) => _FeedShareSheet(text: shareText, post: post));
            }),
            const Spacer(),
            _memAction(Icons.bookmark_border, '', Colors.white54, () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Saved to your collection ✓'),
                backgroundColor: Color(0xFF00C96A),
                duration: Duration(seconds: 2)));
            }),
          ])),
      ]));
  }

  Widget _memAction(IconData icon, String label, Color color,
      VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(children: [
        Icon(icon, size: 22, color: color),
        if (label.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontFamily: 'Satoshi',
            fontSize: 13, color: color, fontWeight: FontWeight.w600)),
        ],
      ]));
  }
}

// ── Shared post actions (normal posts) ───────────────────────────────────────

class _PostActions extends StatelessWidget {
  final SocialPost post;
  final WidgetRef ref;
  const _PostActions({required this.post, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(children: [
          _btn(
            post.isLiked ? Icons.favorite : Icons.favorite_border,
            '${post.likesCount}',
            post.isLiked ? Colors.redAccent : DelightColors.textMuted,
            () => ref.read(feedProvider.notifier).toggleLike(post.id)),
          const SizedBox(width: 18),
          _btn(Icons.chat_bubble_outline, '${post.commentsCount}',
            DelightColors.textMuted, () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: DelightColors.surfaceHigh,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (_) => _CommentsSheet(post: post));
            }),
          const SizedBox(width: 18),
          _btn(Icons.send_outlined, 'Share', DelightColors.textMuted, () {
            HapticFeedback.lightImpact();
            final shareText = post.content + '\n\nSeen on Delight 👉 delight.africa';
            showModalBottomSheet(
              context: context, isScrollControlled: true,
              backgroundColor: DelightColors.surfaceHigh,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              builder: (_) => _FeedShareSheet(text: shareText, post: post));
          }),
          const Spacer(),
          _SaveButton(post: post),
        ])),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: RichText(text: TextSpan(children: [
          TextSpan(text: '${post.userDisplayName}  ',
            style: const TextStyle(fontFamily: 'Satoshi',
              fontWeight: FontWeight.w700, color: DelightColors.textPrimary,
              fontSize: 13)),
          TextSpan(text: post.content,
            style: const TextStyle(fontFamily: 'Satoshi',
              color: DelightColors.textSecondary, fontSize: 13, height: 1.5)),
        ]))),
    ]);
  }

  Widget _btn(IconData icon, String label, Color color, VoidCallback onTap) =>
    GestureDetector(onTap: onTap,
      child: Row(children: [
        Icon(icon, size: 22, color: color),
        if (label.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
            color: color, fontWeight: FontWeight.w500)),
        ],
      ]));
}

// ── Reels Tab — TikTok-style full screen vertical video ───────────────────────

class _ReelData {
  final String id, userName, userFlag, eventName, eventId, caption, audioTrack;
  final String bgEmoji;
  final Color bgColor1, bgColor2;
  final int likes, comments, shares;
  final bool isLiked;
  final String? ticketTier;    // if exclusive, which tier unlocks it
  final bool isLocked;
  final String? imageUrl;

  const _ReelData({
    required this.id, required this.userName, required this.userFlag,
    required this.eventName, required this.eventId, required this.caption,
    required this.audioTrack, required this.bgEmoji,
    required this.bgColor1, required this.bgColor2,
    required this.likes, required this.comments, required this.shares,
    this.isLiked = false, this.ticketTier, this.isLocked = false, this.imageUrl,
  });
}

class _ReelsTab extends ConsumerStatefulWidget {
  @override ConsumerState<_ReelsTab> createState() => _ReelsTabState();
}

class _ReelsTabState extends ConsumerState<_ReelsTab> {
  final _pageCtrl = PageController();
  int _current = 0;
  List<_ReelData> _reelsList = [];

  static const _palette = [
    [Color(0xFF0D2B0A), Color(0xFF051505)], [Color(0xFF1A0A2E), Color(0xFF0D0517)],
    [Color(0xFF001A2E), Color(0xFF000D17)], [Color(0xFF2E1000), Color(0xFF170800)],
  ];

  /// Reels are real posts that carry media — nothing is invented.
  List<_ReelData> _fromPosts(List<SocialPost> posts) {
    final media = posts.where((p) => p.hasVideo || p.imageUrls.isNotEmpty).toList();
    return media.asMap().entries.map((e) {
      final p = e.value, c = _palette[e.key % _palette.length];
      final name = p.userDisplayName.trim();
      return _ReelData(
        id: p.id, userName: name.isEmpty ? 'Delight user' : name,
        userFlag: name.isEmpty ? '👤' : name[0].toUpperCase(),
        eventName: p.eventName ?? p.attendedEventName ?? '',
        eventId: p.eventId ?? '', caption: p.content, audioTrack: '',
        bgEmoji: p.hasVideo ? '🎬' : '📸', bgColor1: c[0], bgColor2: c[1],
        likes: p.likesCount, comments: p.commentsCount, shares: 0,
        isLiked: p.isLiked, imageUrl: p.imageUrls.isEmpty ? null : p.imageUrls.first);
    }).toList();
  }

  @override
  void dispose() { _pageCtrl.dispose(); super.dispose(); }

  void _toggleLike(String id) {
    HapticFeedback.lightImpact();
    ref.read(feedProvider.notifier).toggleLike(id);
  }

  int get _safeCurrent => _current.clamp(0, _reelsList.isEmpty ? 0 : _reelsList.length - 1);

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    _reelsList = _fromPosts(ref.watch(feedProvider));
    if (_reelsList.isEmpty) {
      return const Center(child: Text('No reels yet — posts with photos or video appear here',
        style: TextStyle(fontFamily: 'Satoshi', color: DelightColors.textMuted)));
    }
    return PageView.builder(
      controller: _pageCtrl,
      scrollDirection: Axis.vertical,
      itemCount: _reelsList.length,
      onPageChanged: (i) => setState(() => _current = i.clamp(0, _reelsList.length - 1)),
      itemBuilder: (_, i) {
        final reel = _reelsList[i];
        final isLiked = reel.isLiked;
        final likeCount = reel.likes;

        return Stack(children: [

          // ── Background gradient (simulates video) ─────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [reel.bgColor1, reel.bgColor2],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          if (reel.imageUrl != null)
            Positioned.fill(child: CachedNetworkImage(
              imageUrl: reel.imageUrl!, fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox())),

          // ── Animated background emoji ──────────────────────────────────
          if (reel.imageUrl == null) Center(child: Opacity(
            opacity: 0.15,
            child: Text(reel.bgEmoji,
              style: const TextStyle(fontSize: 200)),
          )),

          // ── Large emoji focal point ────────────────────────────────────
          if (reel.imageUrl == null) Center(child: Text(reel.bgEmoji,
            style: const TextStyle(fontSize: 90))),

          // ── Locked overlay ─────────────────────────────────────────────
          if (reel.isLocked)
            Container(
              color: Colors.black.withOpacity(0.75),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🔐', style: TextStyle(fontSize: 52)),
                  const SizedBox(height: 14),
                  Text('${reel.ticketTier} Ticket Required',
                    style: const TextStyle(
                      fontFamily: 'Clash', fontSize: 22,
                      fontWeight: FontWeight.w700, color: Colors.white)),
                  const SizedBox(height: 8),
                  const Text('Buy a ticket to unlock this exclusive reel',
                    style: TextStyle(fontFamily: 'Satoshi', fontSize: 14,
                      color: Colors.white70), textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  Material(color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => context.go('/events'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: DelightColors.goldGradient),
                          borderRadius: BorderRadius.circular(14)),
                        child: const Text('Buy Ticket to Unlock',
                          style: TextStyle(fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                            color: DelightColors.textInverse, fontSize: 15))))),
                ]),
              ),
            ),

          // ── Bottom gradient ────────────────────────────────────────────
          if (!reel.isLocked)
            Positioned(
              bottom: 0, left: 0, right: 0, height: 320,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),

          // ── Event badge (top left) ─────────────────────────────────────
          if (!reel.isLocked)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.confirmation_number_outlined,
                    size: 12, color: DelightColors.emerald),
                  const SizedBox(width: 5),
                  Text(reel.eventName,
                    style: const TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                      color: Colors.white, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),

          // ── VIP/Exclusive badge (top right) ───────────────────────────
          if (reel.ticketTier != null && !reel.isLocked)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: DelightColors.gold.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: DelightColors.gold.withOpacity(0.6))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.diamond_outlined,
                    size: 11, color: DelightColors.gold),
                  const SizedBox(width: 4),
                  Text('${reel.ticketTier} Exclusive',
                    style: const TextStyle(fontFamily: 'Satoshi', fontSize: 10,
                      color: DelightColors.gold, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),

          // ── Right action column ────────────────────────────────────────
          if (!reel.isLocked)
            Positioned(
              right: 12,
              bottom: 100,
              child: Column(children: [
                // Avatar
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: DelightColors.emerald, width: 2),
                    color: DelightColors.surfaceHigh),
                  alignment: Alignment.center,
                  child: Text(reel.userFlag,
                    style: const TextStyle(fontSize: 22)),
                ),
                // Follow +
                Transform.translate(
                  offset: const Offset(0, -8),
                  child: Container(
                    width: 20, height: 20,
                    decoration: const BoxDecoration(
                      color: DelightColors.emerald, shape: BoxShape.circle),
                    child: const Icon(Icons.add, size: 14,
                      color: DelightColors.textInverse),
                  ),
                ),
                const SizedBox(height: 22),

                // Like
                GestureDetector(
                  onTap: () => _toggleLike(reel.id),
                  child: Column(children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        key: ValueKey(isLiked),
                        color: isLiked ? Colors.redAccent : Colors.white,
                        size: 32,
                        shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(_formatCount(likeCount),
                      style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                        color: Colors.white, fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                  ]),
                ),
                const SizedBox(height: 20),

                // Comment
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: DelightColors.surfaceHigh,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                      builder: (_) => _ReelCommentSheet(reel: reel));
                  },
                  child: Column(children: [
                    const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 30,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                    const SizedBox(height: 4),
                    Text(_formatCount(reel.comments),
                      style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                        color: Colors.white, fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                  ]),
                ),
                const SizedBox(height: 20),

                // Share
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    final text = reel.caption +
                      '\n\nSeen at: ' + reel.eventName +
                      '\n\nDiscover events on Delight 👉 delight.africa';
                    showModalBottomSheet(
                      context: context, isScrollControlled: true,
                      backgroundColor: DelightColors.surfaceHigh,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                      builder: (_) => _ReelShareSheet(text: text, reel: reel));
                  },
                  child: Column(children: [
                    const Icon(Icons.send_outlined, color: Colors.white, size: 30,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                    const SizedBox(height: 4),
                    const Text('Share',
                      style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                        color: Colors.white, fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                  ]),
                ),
                const SizedBox(height: 20),

                // Spinning audio disc
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [DelightColors.surfaceHigh, DelightColors.surface]),
                    border: Border.all(color: Colors.white24, width: 3)),
                  child: const Center(child: Text('🎵',
                    style: TextStyle(fontSize: 18))),
                ),
              ]),
            ),

          // ── Bottom info ────────────────────────────────────────────────
          if (!reel.isLocked)
            Positioned(
              bottom: 0, left: 0, right: 70,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16,
                  MediaQuery.of(context).padding.bottom + 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // User row
                  Row(children: [
                    Text(reel.userFlag, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Flexible(child: Text(reel.userName, maxLines: 1,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(
                      fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                      color: Colors.white, fontSize: 15,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 6)]))),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white60),
                        borderRadius: BorderRadius.circular(6)),
                      child: const Text('Follow', style: TextStyle(
                        fontFamily: 'Satoshi', fontSize: 12,
                        color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 8),

                  // Caption
                  Text(reel.caption,
                    style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                      color: Colors.white, height: 1.4,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 6)]),
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 10),

                  // Audio track ticker
                  if (reel.audioTrack.isNotEmpty) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.music_note, size: 13, color: Colors.white70),
                      const SizedBox(width: 5),
                      Text(reel.audioTrack,
                        style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                          color: Colors.white70)),
                    ]),
                  ),
                ]),
              ),
            ),

          // ── Scroll hint on first reel ──────────────────────────────────
          if (i == 0 && _current == 0)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 80,
              left: 0, right: 0,
              child: const Column(children: [
                Icon(Icons.keyboard_arrow_up, color: Colors.white54, size: 28),
                Text('Swipe up', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 11, color: Colors.white38)),
              ]),
            ),

          // ── Page dots (right mini indicators) ─────────────────────────
          Positioned(
            right: 6,
            top: MediaQuery.of(context).padding.top + 60,
            child: Column(
              children: List.generate(_reelsList.length, (idx) => Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                width: 3, height: idx == _safeCurrent ? 18 : 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: idx == _safeCurrent
                    ? Colors.white : Colors.white.withOpacity(0.3)),
              )),
            ),
          ),
        ]);
      },
    );
  }
}



class _ExclusiveTab extends StatefulWidget {
  @override State<_ExclusiveTab> createState() => _ExclusiveTabState();
}

class _ExclusiveTabState extends State<_ExclusiveTab> {
  List<ExclusivePost> _posts = [];
  List<Map<String, dynamic>> _myEvents = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final rows = await SupabaseService.getExclusivePosts();
    final mine = await SupabaseService.getMyEvents();
    if (!mounted) return;
    setState(() {
      _myEvents = mine;
      _posts = rows.map((r) => ExclusivePost(
        id: '${r['id']}', eventId: '${r['event_id']}',
        eventName: r['event_name'] as String? ?? 'Event',
        organizerName: r['organiser_name'] as String? ?? 'Organiser',
        content: r['content'] as String? ?? 'Locked — upgrade your ticket to view.',
        imageUrls: List<String>.from((r['image_urls'] as List?) ?? const []),
        requiredTier: r['required_tier'] as String? ?? 'Ticket holders',
        isUnlocked: r['unlocked'] as bool? ?? false,
        timestamp: DateTime.tryParse('${r['created_at']}')?.toLocal() ?? DateTime.now(),
        likesCount: 0)).toList();
      _loading = false;
    });
  }

  Future<void> _compose() async {
    String? eventId = '${_myEvents.first['id']}';
    final body = TextEditingController();
    final tier = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        backgroundColor: DelightColors.surfaceHigh,
        title: const Text('Post to ticket holders'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: eventId, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Event'),
            items: _myEvents.map((e) => DropdownMenuItem(
              value: '${e['id']}', child: Text('${e['name']}',
                overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setD(() => eventId = v)),
          TextField(controller: tier,
            decoration: const InputDecoration(
              labelText: 'Only this tier (blank = any ticket)')),
          TextField(controller: body, maxLines: 4, maxLength: 2000,
            decoration: const InputDecoration(labelText: 'Message')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Post')),
        ])));
    if (ok != true || eventId == null || body.text.trim().isEmpty) return;
    try {
      await SupabaseService.createExclusivePost(
        eventId: eventId!, content: body.text,
        requiredTier: tier.text.trim().isEmpty ? null : tier.text.trim());
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [DelightColors.gold.withOpacity(0.12), DelightColors.emerald.withOpacity(0.06)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: DelightColors.gold.withOpacity(0.3))),
            child: Row(children: [
              const Text('🔐', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 14),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Exclusive Content', style: TextStyle(
                  fontFamily: 'Clash', fontSize: 17, fontWeight: FontWeight.w700,
                  color: DelightColors.textPrimary)),
                SizedBox(height: 3),
                Text('Only visible to NFT ticket holders. Buy a ticket to unlock.',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                    color: DelightColors.textMuted, height: 1.4)),
              ])),
              if (_myEvents.isNotEmpty)
                IconButton(
                  tooltip: 'Post to ticket holders',
                  icon: const Icon(Icons.add_circle_outline, color: DelightColors.gold),
                  onPressed: _compose),
            ]),
          ),
        ),
        if (_loading)
          const SliverToBoxAdapter(child: Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator(color: DelightColors.emerald))))
        else if (_posts.isEmpty)
          const SliverToBoxAdapter(child: Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: Text(
              'Nothing here yet.\nBuy a ticket and organisers can share behind-the-scenes content with you.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Satoshi', color: DelightColors.textMuted,
                height: 1.5)))))
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _ExclusiveCard(post: _posts[i]),
              childCount: _posts.length)),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ]));
  }
}

class _ExclusiveCard extends StatelessWidget {
  final ExclusivePost post;
  const _ExclusiveCard({required this.post});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: post.isUnlocked
            ? DelightColors.emerald.withOpacity(0.35)
            : DelightColors.gold.withOpacity(0.3)),
        boxShadow: post.isUnlocked ? [BoxShadow(
          color: DelightColors.emerald.withOpacity(0.08), blurRadius: 12)] : [],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Event + tier header
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: post.isUnlocked ? DelightColors.emeraldGlow : DelightColors.goldGlow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: post.isUnlocked
                    ? DelightColors.emerald.withOpacity(0.4)
                    : DelightColors.gold.withOpacity(0.4))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(post.isUnlocked ? Icons.lock_open_outlined : Icons.lock_outlined,
                  size: 12,
                  color: post.isUnlocked ? DelightColors.emerald : DelightColors.gold),
                const SizedBox(width: 5),
                Text('${post.requiredTier} only', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 11, fontWeight: FontWeight.w700,
                  color: post.isUnlocked ? DelightColors.emerald : DelightColors.gold)),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(post.eventName, style: const TextStyle(
              fontFamily: 'Satoshi', fontSize: 12, color: DelightColors.textMuted),
              overflow: TextOverflow.ellipsis)),
            Text(timeago.format(post.timestamp), style: const TextStyle(
              fontFamily: 'Satoshi', fontSize: 11, color: DelightColors.textMuted)),
          ]),
        ),

        // Image — blurred if locked
        if (post.imageUrls.isNotEmpty)
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.zero,
              child: CachedNetworkImage(
                imageUrl: post.imageUrls.first,
                width: double.infinity, height: 220, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(height: 220, color: DelightColors.surfaceHigh),
                color: post.isUnlocked ? null : Colors.black.withOpacity(0.0),
                colorBlendMode: post.isUnlocked ? null : BlendMode.darken),
            ),
            if (!post.isUnlocked)
              Positioned.fill(child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.72)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('🔐', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 10),
                  Text('${post.requiredTier} Ticket Required', style: const TextStyle(
                    fontFamily: 'Clash', fontSize: 17, fontWeight: FontWeight.w700,
                    color: Colors.white)),
                  const SizedBox(height: 6),
                  const Text('Buy a ticket to unlock this exclusive content',
                    style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                      color: Colors.white70), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Material(color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => context.go('/events'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: DelightColors.goldGradient),
                          borderRadius: BorderRadius.circular(12)),
                        child: const Text('Buy Ticket to Unlock', style: TextStyle(
                          fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                          color: DelightColors.textInverse, fontSize: 13))))),
                ]),
              )),
            if (post.imageUrls.length > 1 && post.isUnlocked)
              Positioned(top: 10, right: 10, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                child: Text('1/${post.imageUrls.length}', style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 11, color: Colors.white)),
              )),
          ]),

        // Content
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(post.organizerName, style: const TextStyle(
                fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary, fontSize: 13))),
              if (post.isUnlocked)
                Row(children: [
                  Icon(Icons.favorite_border, size: 16, color: DelightColors.textMuted),
                  const SizedBox(width: 4),
                  Text('${post.likesCount}', style: const TextStyle(
                    fontFamily: 'Satoshi', fontSize: 12, color: DelightColors.textMuted)),
                ]),
            ]),
            const SizedBox(height: 6),
            if (post.isUnlocked)
              Text(post.content, style: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 13,
                color: DelightColors.textSecondary, height: 1.5))
            else
              Text(post.content.substring(0, post.content.length > 60 ? 60 : post.content.length) + '...',
                style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                  color: DelightColors.textMuted, height: 1.5)),
          ]),
        ),
      ]),
    );
  }
}

// ── Discover Tab ──────────────────────────────────────────────────────────────

class _DiscoverTab extends ConsumerWidget {
  // Tag → category mapping for the events filter
  static const _tagCategories = {
    '#Music': 'Music',
    '#Technology': 'Technology',
    '#Art': 'Art',
    '#Food': 'Food',
    '#AfrobeatsLagos': 'Music',
    '#Web3Africa': 'Technology',
    '#KigaliArt': 'Art',
    '#AccraFood': 'Food',
    '#NFTTickets': 'All',
    '#DelightEvents': 'All',
    '#Festival': 'Music',
    '#Sports': 'Sports',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider);
    final upcoming = events.where((e) =>
      e.date.isAfter(DateTime.now())).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Trending tags (tappable → navigate to events) ──────────
        const Text('Trending Tags', style: TextStyle(
          fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _tagCategories.keys.map((tag) => GestureDetector(
            onTap: () {
              // Navigate to events tab — the Discover is tab 0 of social
              // Push to events screen which handles filtering
              context.push('/events');
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: DelightColors.emeraldGlow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: DelightColors.emerald.withOpacity(0.35))),
              child: Text(tag, style: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 13,
                color: DelightColors.emerald, fontWeight: FontWeight.w700)),
            ),
          )).toList()),
        const SizedBox(height: 24),

        // ── Upcoming events (LIVE from eventsProvider) ─────────────
        Row(children: [
          const Expanded(child: Text('Upcoming Events', style: TextStyle(
            fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary))),
          GestureDetector(
            onTap: () => context.push('/events'),
            child: const Text('See all →', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 13,
              color: DelightColors.emerald, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 12),

        if (upcoming.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: Column(children: [
              const Text('🎟', style: TextStyle(fontSize: 36)),
              const SizedBox(height: 8),
              const Text('No upcoming events yet',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 14,
                  color: DelightColors.textMuted)),
            ]))
        else
          ...upcoming.take(6).map((event) => GestureDetector(
            onTap: () => context.push('/event/${event.id}', extra: event),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: DelightColors.surfaceHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: DelightColors.surfaceBorder)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // Cover image
                if (event.coverImageUrl != null)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16)),
                    child: CachedNetworkImage(
                      imageUrl: event.coverImageUrl!,
                      width: double.infinity,
                      height: 140, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        height: 80, color: DelightColors.background,
                        child: const Icon(Icons.event,
                          color: DelightColors.textMuted)))),
                // Details
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: DelightColors.emeraldGlow,
                            borderRadius: BorderRadius.circular(5)),
                          child: Text(event.category, style: const TextStyle(
                            fontFamily: 'Satoshi', fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: DelightColors.emerald))),
                        const SizedBox(width: 6),
                        Text(
                          '${event.date.day}/${event.date.month}/${event.date.year}',
                          style: const TextStyle(fontFamily: 'Satoshi',
                            fontSize: 10, color: DelightColors.textMuted)),
                      ]),
                      const SizedBox(height: 4),
                      Text(event.title, style: const TextStyle(
                        fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                        fontSize: 14, color: DelightColors.textPrimary),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('${event.venue}, ${event.city}',
                        style: const TextStyle(fontFamily: 'Satoshi',
                          fontSize: 11, color: DelightColors.textMuted),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                      Text(
                        'from R${(event.lowestPrice * 9.5).toStringAsFixed(0)}',
                        style: const TextStyle(fontFamily: 'Clash',
                          fontSize: 14, fontWeight: FontWeight.w700,
                          color: DelightColors.gold)),
                      const Icon(Icons.chevron_right,
                        color: DelightColors.textMuted, size: 18),
                    ]),
                  ])),
              ])),
          )),
      ]));
  }
}

// ── Memory Builder ───────────────────────────────────────────────────────────
// The create-post flow for Delight.
// Normal post if no attended ticket. Full Memory Builder if you have one.

class _CreatePostSheet extends ConsumerStatefulWidget {
  const _CreatePostSheet({super.key});
  @override
  ConsumerState<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends ConsumerState<_CreatePostSheet> {
  final _ctrl = TextEditingController();
  bool _posting = false;
  String _memoryStyle = 'Electric';
  NFTTicket? _selectedTicket;
  final List<dynamic> _photos = []; // File from gallery, or String URL
  String? _videoPath;
  final Set<String> _alsoShare = {}; // networks to share to after posting

  // Every ticket the user owns is shown, so the Memory NFT option is always
  // visible. A ticket unlocks once its event has happened or the user was
  // scanned in at the gate; the database enforces the same rule.
  List<NFTTicket> get _attendedTickets {
    final all = ref.read(ticketsProvider)
      .where((t) => t.eventId.isNotEmpty).toList();
    all.sort((a, b) => b.eventDate.compareTo(a.eventDate));
    return all;
  }

  bool _canMint(NFTTicket t) =>
    t.isUsed || t.eventDate.isBefore(DateTime.now());

  static const _styles = ['Electric', 'Midnight', 'Gold', 'Neon'];

  Color _styleAccent(String s) {
    switch (s) {
      case 'Electric': return const Color(0xFF00C96A);
      case 'Midnight': return const Color(0xFF6C63FF);
      case 'Gold':     return const Color(0xFFD4AF37);
      case 'Neon':     return const Color(0xFFFF006E);
      default:         return DelightColors.emerald;
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _mintAndPost() async {
    if (_ctrl.text.trim().isEmpty && _photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Add some text or photos first')));
      return;
    }
    setState(() => _posting = true);

    // Memory NFTs get a short "minting" animation over the sheet while the
    // photos upload and the post saves.
    final minting = _selectedTicket != null;
    final mintDone = ValueNotifier<bool>(false);
    var overlayOpen = false;
    if (minting) {
      overlayOpen = true;
      showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 250),
        transitionBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
        pageBuilder: (_, __, ___) => _MintingOverlay(
          done: mintDone,
          accent: _styleAccent(_memoryStyle),
          eventName: _selectedTicket!.eventName,
          tier: _selectedTicket!.tier));
    }

    try {
      // Upload any real local photos to Supabase Storage first —
      // never save a raw device file path, other users couldn't see it.
      final List<String> uploadedUrls = [];
      for (final photo in _photos) {
        if (photo is File) {
          final bytes = await photo.readAsBytes();
          final path = 'posts/${DateTime.now().millisecondsSinceEpoch}_${uploadedUrls.length}.jpg';
          final url = await SupabaseService.uploadImage('delight-images', path, bytes);
          if (url != null) uploadedUrls.add(url);
        } else if (photo is String) {
          uploadedUrls.add(photo);
        }
      }

      final user = ref.read(authProvider);
      final db = Supabase.instance.client;
      final memTokenId = _selectedTicket != null
        ? 'MEM_${DateTime.now().millisecondsSinceEpoch}'
        : null;

      await db.from('posts').insert({
        'user_id':             user?.id,
        'user_display_name':   user?.displayName,
        'content':             _ctrl.text.trim(),
        'image_urls':          uploadedUrls,
        'is_nft_memory':       _selectedTicket != null,
        'memory_token_id':     memTokenId,
        'attended_event_name': _selectedTicket?.eventName,
        'attended_event_venue': _selectedTicket != null
          ? '${_selectedTicket!.eventVenue}, ${_selectedTicket!.eventCity}'
          : null,
        'attended_tier':       _selectedTicket?.tier,
        'attended_ticket_id':  _selectedTicket?.id,
        'event_date':          _selectedTicket?.eventDate?.toIso8601String(),
        'memory_style':        _selectedTicket != null ? _memoryStyle : null,
        'nft_token_id':        memTokenId,
      });

      // Re-load from DB so local state exactly matches what was saved —
      // no risk of local/DB drift.
      await ref.read(feedProvider.notifier).refresh();

      ref.read(analyticsProvider.notifier).track(
        _selectedTicket != null ? 'memory_minted' : 'post_created');
      if (overlayOpen) {
        mintDone.value = true;
        await Future.delayed(const Duration(milliseconds: 1400));
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        overlayOpen = false;
      }
      final shareText = '${_ctrl.text.trim()}\n\nSeen on Delight 👉 delight.africa';
      final nets = Set<String>.from(_alsoShare);
      if (mounted) Navigator.pop(context);
      await _shareOutside(nets, shareText);
    } catch (e) {
      if (overlayOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        overlayOpen = false;
      }
      if (mounted) setState(() => _posting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not post: ${e.toString().split(']').last.trim()}')));
      }
    }
  }

  // Post is already saved on Delight; now hand it to the chosen networks.
  // One network opens directly; several open the phone's own share sheet.
  Future<void> _shareOutside(Set<String> nets, String text) async {
    if (nets.isEmpty) return;
    final enc = Uri.encodeComponent(text);
    if (nets.length > 1) { await Share.share(text); return; }
    switch (nets.first) {
      case 'whatsapp':
        await launchUrl(Uri.parse('https://wa.me/?text=$enc'),
          mode: LaunchMode.externalApplication); break;
      case 'x':
        await launchUrl(Uri.parse('https://twitter.com/intent/tweet?text=$enc'),
          mode: LaunchMode.externalApplication); break;
      case 'instagram':
        await Clipboard.setData(ClipboardData(text: text));
        await launchUrl(Uri.parse('https://www.instagram.com/'),
          mode: LaunchMode.externalApplication); break;
      case 'tiktok':
        await Clipboard.setData(ClipboardData(text: text));
        await launchUrl(Uri.parse('https://www.tiktok.com/'),
          mode: LaunchMode.externalApplication); break;
      default:
        await Share.share(text);
    }
  }

  Widget _netChip(String key, String emoji, String label) {
    final on = _alsoShare.contains(key);
    return GestureDetector(
      onTap: () => setState(() => on ? _alsoShare.remove(key) : _alsoShare.add(key)),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on ? DelightColors.emerald.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on
            ? DelightColors.emerald : DelightColors.surfaceBorder)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
            fontWeight: FontWeight.w700,
            color: on ? DelightColors.emerald : DelightColors.textMuted)),
        ])));
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= 4) return;
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery, imageQuality: 80);
    if (xfile != null && mounted) {
      setState(() => _photos.add(File(xfile.path)));
    }
  }

  Future<void> _addVideo() async {
    final picker = ImagePicker();
    final xfile = await picker.pickVideo(source: ImageSource.gallery);
    if (xfile != null && mounted) {
      setState(() => _videoPath = xfile.path);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Video attached: ${xfile.name}'),
        backgroundColor: DelightColors.emerald));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMemory = _selectedTicket != null;
    final accent   = isMemory ? _styleAccent(_memoryStyle) : DelightColors.emerald;

    return Container(
      decoration: BoxDecoration(
        color: isMemory ? const Color(0xFF0A0A12) : DelightColors.surfaceHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [

            // Handle
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(
                color: isMemory
                  ? Colors.white.withOpacity(0.15)
                  : DelightColors.surfaceBorder,
                borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),

            // Header — changes based on mode
            Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  isMemory ? 'Mint Memory NFT' : 'New Post',
                  style: TextStyle(fontFamily: 'Clash', fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: isMemory ? Colors.white : DelightColors.textPrimary)),
                Text(
                  isMemory
                    ? 'Your proof of attendance — minted on XRP Ledger'
                    : 'Share a moment',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                    color: isMemory
                      ? Colors.white.withOpacity(0.5)
                      : DelightColors.textMuted)),
              ])),
              GestureDetector(
                onTap: _posting ? null : _mintAndPost,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isMemory
                        ? [accent, accent.withOpacity(0.7)]
                        : DelightColors.emeraldGradient),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(
                      color: accent.withOpacity(0.4),
                      blurRadius: 12, offset: const Offset(0, 4))]),
                  child: _posting
                    ? SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                          color: isMemory ? Colors.black : Colors.white,
                          strokeWidth: 2))
                    : Text(
                        isMemory ? 'Mint & Share' : 'Post',
                        style: TextStyle(fontFamily: 'Satoshi',
                          fontWeight: FontWeight.w800, fontSize: 14,
                          color: isMemory ? Colors.black : Colors.white)))),
            ]),
            const SizedBox(height: 16),

            // ── Attended tickets picker ──────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isMemory
                  ? Colors.white.withOpacity(0.05)
                  : DelightColors.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isMemory
                    ? accent.withOpacity(0.3)
                    : DelightColors.surfaceBorder)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.confirmation_number_outlined,
                    color: isMemory ? accent : DelightColors.textMuted,
                    size: 16),
                  const SizedBox(width: 8),
                  Text(
                    isMemory
                      ? 'Ticket attached — this post is verified'
                      : 'Attach a ticket to create a Memory NFT',
                    style: TextStyle(fontFamily: 'Satoshi',
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: isMemory ? accent : DelightColors.textMuted)),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  height: 72,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      // "None" option
                      GestureDetector(
                        onTap: () => setState(() => _selectedTicket = null),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 130),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedTicket == null
                              ? DelightColors.surfaceBorder
                              : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _selectedTicket == null
                                ? DelightColors.textMuted
                                : DelightColors.surfaceBorder.withOpacity(0.4))),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                            Text('✕', style: TextStyle(fontSize: 16,
                              color: DelightColors.textMuted)),
                            SizedBox(height: 2),
                            Text('None', style: TextStyle(
                              fontFamily: 'Satoshi', fontSize: 9,
                              color: DelightColors.textMuted)),
                          ]))),

                      if (_attendedTickets.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(left: 4, top: 14),
                          child: Text('Buy a ticket to unlock Memory NFTs',
                            style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                              color: DelightColors.textMuted))),
                      // Attended ticket cards
                      ..._attendedTickets.map((t) {
                        final sel = _selectedTicket?.id == t.id;
                        final tc = _styleAccent(_memoryStyle);
                        final ok = _canMint(t);
                        return GestureDetector(
                          onTap: () {
                            if (!ok) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Unlocks after the event — '
                                  '${t.eventDate.day}/${t.eventDate.month}/${t.eventDate.year}')));
                              return;
                            }
                            setState(() => _selectedTicket = sel ? null : t);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(right: 8),
                            foregroundDecoration: ok ? null : BoxDecoration(
                              color: Colors.black.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: sel ? LinearGradient(
                                colors: [tc.withOpacity(0.2), tc.withOpacity(0.05)]) : null,
                              color: sel ? null : Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: sel ? tc : Colors.white.withOpacity(0.1),
                                width: sel ? 1.5 : 1)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                              Row(children: [
                                Icon(Icons.diamond_outlined,
                                  size: 10, color: sel ? tc : Colors.white38),
                                const SizedBox(width: 3),
                                Text(t.tier, style: TextStyle(
                                  fontFamily: 'Satoshi', fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: sel ? tc : Colors.white38,
                                  letterSpacing: 0.5)),
                              ]),
                              const SizedBox(height: 3),
                              SizedBox(
                                width: 120,
                                child: Text(t.eventName, style: TextStyle(
                                  fontFamily: 'Satoshi', fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: sel ? Colors.white : Colors.white60),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1)),
                              Text(
                                ok
                                  ? '${t.eventCity}  ·  ${t.eventDate.day}/${t.eventDate.month}/${t.eventDate.year}'
                                  : '🔒 Unlocks ${t.eventDate.day}/${t.eventDate.month}/${t.eventDate.year}',
                                style: TextStyle(fontFamily: 'Satoshi',
                                  fontSize: 9,
                                  color: sel
                                    ? Colors.white.withOpacity(0.6)
                                    : Colors.white.withOpacity(0.35))),
                            ])));
                      }),
                    ])),
              ])),
            const SizedBox(height: 12),

            // ── Style picker (only if ticket selected) ───────────────
            if (isMemory) ...[
              Row(children: _styles.map((s) {
                final sel = s == _memoryStyle;
                final sc  = _styleAccent(s);
                return Expanded(child: GestureDetector(
                  onTap: () => setState(() => _memoryStyle = s),
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
                      fontFamily: 'Satoshi', fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: sel ? sc : Colors.white38)))));
              }).toList()),
              const SizedBox(height: 12),
            ],

            // ── Text input ───────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isMemory
                  ? Colors.white.withOpacity(0.05)
                  : DelightColors.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isMemory
                    ? Colors.white.withOpacity(0.1)
                    : DelightColors.surfaceBorder)),
              child: TextField(
                controller: _ctrl,
                maxLines: 3, autofocus: false,
                style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 15,
                  color: isMemory ? Colors.white : DelightColors.textPrimary),
                decoration: InputDecoration(
                  hintText: isMemory
                    ? 'Describe your moment — what did you feel, who did you meet, what made it unforgettable...'
                    : 'Share a moment...',
                  hintStyle: TextStyle(
                    color: isMemory
                      ? Colors.white.withOpacity(0.3)
                      : DelightColors.textMuted),
                  border: InputBorder.none))),
            const SizedBox(height: 10),

            // ── Attached photo thumbnails ─────────────────────────────
            if (_photos.isNotEmpty)
              SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photos.length,
                  itemBuilder: (_, i) => Stack(children: [
                    Container(
                      width: 80, height: 80,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isMemory
                            ? accent.withOpacity(0.4)
                            : DelightColors.surfaceBorder),
                        image: DecorationImage(
                          image: _photos[i] is File
                            ? FileImage(_photos[i] as File) as ImageProvider
                            : NetworkImage(_photos[i] as String),
                          fit: BoxFit.cover))),
                    Positioned(top: 4, right: 12,
                      child: GestureDetector(
                        onTap: () =>
                          setState(() => _photos.removeAt(i)),
                        child: Container(
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            shape: BoxShape.circle),
                          child: const Icon(Icons.close,
                            color: Colors.white, size: 12)))),
                  ]))),

            // ── Also share outside Delight ───────────────────────────
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft,
              child: Text('ALSO SHARE TO', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 9, fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: isMemory ? Colors.white54 : DelightColors.textMuted))),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _netChip('whatsapp',  '💬', 'WhatsApp'),
                _netChip('instagram', '📸', 'Instagram'),
                _netChip('x',         '🐦', 'X'),
                _netChip('tiktok',    '🎵', 'TikTok'),
                _netChip('more',      '📤', 'More apps'),
              ])),
            const SizedBox(height: 12),

            // ── Bottom action bar ─────────────────────────────────────
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(
                  color: isMemory
                    ? Colors.white.withOpacity(0.08)
                    : DelightColors.surfaceBorder))),
              child: Row(children: [
                _bar(Icons.add_photo_alternate_outlined, 'Photo',
                  isMemory ? accent : DelightColors.blue,
                  () => _addPhoto()),
                _bar(Icons.videocam_outlined, 'Video',
                  isMemory ? accent.withOpacity(0.8) : DelightColors.gold,
                  () => _addVideo()),
                if (isMemory)
                  Expanded(child: Container(
                    alignment: Alignment.center,
                    child: Text(
                      '${_photos.length}/4 photos',
                      style: TextStyle(fontFamily: 'Satoshi', fontSize: 10,
                        color: accent.withOpacity(0.6))))),
              ])),
          ]))));
  }

  Widget _bar(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontFamily: 'Satoshi', fontSize: 9,
          fontWeight: FontWeight.w600, color: color)),
      ])));
  }
}



// ── Comments Sheet ────────────────────────────────────────────────────────────

class _CommentsSheet extends StatefulWidget {
  final SocialPost post;
  const _CommentsSheet({required this.post});
  @override State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _ctrl = TextEditingController();
  List<({String user, String text, String emoji})> _comments = [];
  bool _loadingC = true, _posting = false;

  @override
  void initState() { super.initState(); _loadC(); }

  Future<void> _loadC() async {
    final rows = await SupabaseService.getPostComments(widget.post.id);
    if (!mounted) return;
    setState(() {
      _comments = rows.map((r) {
        final n = (r['display_name'] as String?)?.trim() ?? '';
        return (user: n.isEmpty ? 'User' : n, text: '${r['content']}',
                emoji: n.isEmpty ? '👤' : n[0].toUpperCase());
      }).toList();
      _loadingC = false;
    });
  }

  Future<void> _postC() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty || _posting) return;
    setState(() => _posting = true);
    try {
      await SupabaseService.addPostComment(widget.post.id, t);
      _ctrl.clear();
      await _loadC();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't post your comment")));
      }
    }
    if (mounted) setState(() => _posting = false);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.72,
        decoration: const BoxDecoration(
          color: Color(0xFF0D1F14),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          // Handle
          Container(margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: DelightColors.surfaceBorder,
              borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              Text('Comments', style: const TextStyle(
                fontFamily: 'Clash', fontSize: 17, fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: DelightColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(8)),
                child: Text('${_comments.length}',
                  style: const TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                    color: DelightColors.textMuted))),
            ])),
          const Divider(color: Color(0xFF1A2F1A), height: 1),
          Expanded(child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _comments.length,
            itemBuilder: (_, i) {
              final c = _comments[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: DelightColors.surfaceHigh),
                    alignment: Alignment.center,
                    child: Text(c.emoji, style: const TextStyle(fontSize: 16))),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                    RichText(text: TextSpan(children: [
                      TextSpan(text: '${c.user}  ',
                        style: const TextStyle(fontFamily: 'Satoshi',
                          fontWeight: FontWeight.w700, color: DelightColors.textPrimary,
                          fontSize: 13)),
                      TextSpan(text: c.text,
                        style: const TextStyle(fontFamily: 'Satoshi',
                          color: DelightColors.textSecondary, fontSize: 13)),
                    ])),
                    const SizedBox(height: 4),
                  ])),
                ]));
            })),
          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(
                color: DelightColors.surfaceBorder))),
            child: Row(children: [
              Expanded(child: TextField(
                controller: _ctrl,
                style: const TextStyle(fontFamily: 'Satoshi',
                  color: DelightColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Add a comment...',
                  hintStyle: const TextStyle(
                    color: DelightColors.textMuted, fontSize: 13),
                  filled: true, fillColor: DelightColors.surfaceHigh,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(
                      color: DelightColors.surfaceBorder)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(
                      color: DelightColors.surfaceBorder))))),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _postC,
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: DelightColors.emeraldGradient),
                    shape: BoxShape.circle),
                  child: const Icon(Icons.send,
                    color: Colors.white, size: 18))),
            ])),
        ])));
  }
}

// ── Save Button ───────────────────────────────────────────────────────────────

class _SaveButton extends StatefulWidget {
  final SocialPost post;
  const _SaveButton({required this.post});
  @override State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton>
    with SingleTickerProviderStateMixin {
  bool _saved = false;
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 200));
  }

  @override
  void dispose() { _anim.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() => _saved = !_saved);
        if (_saved) {
          _anim.forward(from: 0);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Saved to your collection ✓'),
            backgroundColor: Color(0xFF00C96A),
            duration: Duration(seconds: 2)));
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          _saved ? Icons.bookmark : Icons.bookmark_border,
          key: ValueKey(_saved),
          color: _saved ? DelightColors.gold : DelightColors.textMuted,
          size: 22)));
  }
}

// ── Reel Comment Sheet ────────────────────────────────────────────────────────
class _ReelCommentSheet extends StatefulWidget {
  final _ReelData reel;
  const _ReelCommentSheet({required this.reel});
  @override State<_ReelCommentSheet> createState() => _ReelCommentSheetState();
}
class _ReelCommentSheetState extends State<_ReelCommentSheet> {
  final _ctrl = TextEditingController();
  List<Map<String,String>> _comments = [];

  @override
  void initState() { super.initState(); _loadC(); }

  Future<void> _loadC() async {
    final rows = await SupabaseService.getPostComments(widget.reel.id);
    if (!mounted) return;
    setState(() {
      _comments = rows.map((r) {
        final n = (r['display_name'] as String?)?.trim() ?? '';
        final t = DateTime.tryParse('${r['created_at']}')?.toLocal();
        return {'user': n.isEmpty ? 'User' : n, 'text': '${r['content']}',
                'time': t == null ? '' : timeago.format(t)};
      }).toList();
    });
  }

  Future<void> _postC() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    try {
      await SupabaseService.addPostComment(widget.reel.id, t);
      _ctrl.clear();
      await _loadC();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't post your comment")));
      }
    }
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65, maxChildSize: 0.92, minChildSize: 0.4,
      expand: false,
      builder: (_, scroll) => Column(children: [
        const SizedBox(height: 12),
        Center(child: Container(width: 36, height: 4,
          decoration: BoxDecoration(color: DelightColors.surfaceBorder,
            borderRadius: BorderRadius.circular(2)))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text('${_comments.length} Comments', style: const TextStyle(
            fontFamily: 'Clash', fontSize: 16, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary))),
        const Divider(color: DelightColors.surfaceBorder, height: 1),
        Expanded(child: ListView.builder(
          controller: scroll,
          padding: const EdgeInsets.all(16),
          itemCount: _comments.length,
          itemBuilder: (_, i) {
            final c = _comments[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 16,
                  backgroundColor: DelightColors.emeraldGlow,
                  child: Text(c['user']![0],
                    style: const TextStyle(color: DelightColors.emerald,
                      fontWeight: FontWeight.w700, fontSize: 12))),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Row(children: [
                    Flexible(child: Text(c['user']!, maxLines: 1,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(
                      fontFamily: 'Satoshi', fontWeight: FontWeight.w700, fontSize: 13,
                      color: DelightColors.textPrimary))),
                    const SizedBox(width: 6),
                    Text(c['time']!, style: const TextStyle(fontFamily: 'Satoshi',
                      fontSize: 11, color: DelightColors.textMuted)),
                  ]),
                  const SizedBox(height: 2),
                  Text(c['text']!, style: const TextStyle(fontFamily: 'Satoshi',
                    fontSize: 13, color: DelightColors.textSecondary, height: 1.4)),
                ])),
              ]));
          })),
        Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            top: 8),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _ctrl,
              style: const TextStyle(fontFamily: 'Satoshi',
                color: DelightColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Add a comment...',
                hintStyle: const TextStyle(color: DelightColors.textMuted, fontSize: 13),
                filled: true, fillColor: DelightColors.surfaceHigh,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(
                    color: DelightColors.emerald, width: 1.5))))),
            const SizedBox(width: 8),
            Material(color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: _postC,
                child: Container(
                  width: 42, height: 42,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: DelightColors.emeraldGradient),
                    shape: BoxShape.circle),
                  child: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 18)))),
          ])),
      ]));
  }
}

// ── Reel Share Sheet ──────────────────────────────────────────────────────────
class _ReelShareSheet extends StatelessWidget {
  final String text;
  final _ReelData reel;
  const _ReelShareSheet({required this.text, required this.reel});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 36, height: 4,
          decoration: BoxDecoration(color: DelightColors.surfaceBorder,
            borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        const Text('Share', style: TextStyle(fontFamily: 'Clash',
          fontSize: 20, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 4),
        Text(reel.eventName, style: const TextStyle(fontFamily: 'Satoshi',
          fontSize: 13, color: DelightColors.textMuted)),
        const SizedBox(height: 18),

        // SHARE OUTSIDE DELIGHT
        const Row(children: [
          Expanded(child: Divider(color: DelightColors.surfaceBorder)),
          Padding(padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text('SHARE OUTSIDE DELIGHT', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 9, fontWeight: FontWeight.w700,
              color: DelightColors.textMuted, letterSpacing: 1.2))),
          Expanded(child: Divider(color: DelightColors.surfaceBorder)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _btn(context, '💬', 'WhatsApp', const Color(0xFF25D366), () {
            Navigator.pop(context);
            launchUrl(Uri.parse('https://wa.me/?text=' + Uri.encodeComponent(text)),
              mode: LaunchMode.externalApplication);
          }),
          const SizedBox(width: 8),
          _btn(context, '🐦', 'X', const Color(0xFF1DA1F2), () {
            Navigator.pop(context);
            launchUrl(Uri.parse(
              'https://twitter.com/intent/tweet?text=' + Uri.encodeComponent(text)),
              mode: LaunchMode.externalApplication);
          }),
          const SizedBox(width: 8),
          _btn(context, '📸', 'Instagram', const Color(0xFFE4405F), () async {
            await Clipboard.setData(ClipboardData(text: text));
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Caption copied! Open Instagram and paste it 📋'),
              backgroundColor: Color(0xFFE4405F),
              duration: Duration(seconds: 4)));
            launchUrl(Uri.parse('https://www.instagram.com/'),
              mode: LaunchMode.externalApplication);
          }),
          const SizedBox(width: 8),
          _btn(context, '🎵', 'TikTok', const Color(0xFF010101), () async {
            await Clipboard.setData(ClipboardData(text: text));
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Caption copied! Open TikTok and paste it 📋'),
              backgroundColor: Color(0xFF010101),
              duration: Duration(seconds: 4)));
            launchUrl(Uri.parse('https://www.tiktok.com/'),
              mode: LaunchMode.externalApplication);
          }),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _btn(context, '📱', 'SMS', DelightColors.emerald, () {
            Navigator.pop(context);
            launchUrl(Uri.parse('sms:?body=' + Uri.encodeComponent(text)),
              mode: LaunchMode.externalApplication);
          }),
          const SizedBox(width: 8),
          _btn(context, '🔗', 'Copy', DelightColors.textMuted, () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Copied ✓'),
                backgroundColor: DelightColors.emerald));
            }
          }),
          const SizedBox(width: 8),
          _btn(context, '📤', 'More apps', DelightColors.blue, () {
            Navigator.pop(context);
            Share.share(text);
          }),
          const SizedBox(width: 8),
          const Expanded(child: SizedBox()),
        ]),
      ])));
  }

  Widget _btn(BuildContext ctx, String emoji, String label, Color color,
      VoidCallback onTap) =>
    Expanded(child: Material(color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2))),
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontFamily: 'Satoshi', fontSize: 9,
              fontWeight: FontWeight.w700, color: color),
              textAlign: TextAlign.center),
          ])))));
}

// ── Feed & Memory Post Share Sheet ──────────────────────────────────────────
class _FeedShareSheet extends StatelessWidget {
  final String text;
  final SocialPost post;
  const _FeedShareSheet({required this.text, required this.post});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Center(child: Container(width: 36, height: 4,
          decoration: BoxDecoration(color: DelightColors.surfaceBorder,
            borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        // Header
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text(
              post.isNftMemory ? 'Share Memory NFT' : 'Share Post',
              style: const TextStyle(fontFamily: 'Clash', fontSize: 20,
                fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
            Text(post.userDisplayName,
              style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                color: DelightColors.textMuted)),
          ])),
          if (post.isNftMemory)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: DelightColors.goldGlow,
                borderRadius: BorderRadius.circular(6)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.diamond_outlined, size: 11, color: DelightColors.gold),
                SizedBox(width: 4),
                Text('NFT', style: TextStyle(fontFamily: 'Satoshi',
                  fontSize: 10, fontWeight: FontWeight.w800,
                  color: DelightColors.gold)),
              ])),
        ]),
        const SizedBox(height: 18),

        // SHARE OUTSIDE DELIGHT
        const Row(children: [
          Expanded(child: Divider(color: DelightColors.surfaceBorder)),
          Padding(padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text('SHARE OUTSIDE DELIGHT', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 9, fontWeight: FontWeight.w700,
              color: DelightColors.textMuted, letterSpacing: 1.2))),
          Expanded(child: Divider(color: DelightColors.surfaceBorder)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _btn(context, '💬', 'WhatsApp', const Color(0xFF25D366), () {
            Navigator.pop(context);
            launchUrl(Uri.parse(
              'https://wa.me/?text=' + Uri.encodeComponent(text)),
              mode: LaunchMode.externalApplication);
          }),
          const SizedBox(width: 8),
          _btn(context, '🐦', 'X', const Color(0xFF1DA1F2), () {
            Navigator.pop(context);
            launchUrl(Uri.parse(
              'https://twitter.com/intent/tweet?text=' + Uri.encodeComponent(text)),
              mode: LaunchMode.externalApplication);
          }),
          const SizedBox(width: 8),
          _btn(context, '📸', 'Instagram', const Color(0xFFE4405F), () async {
            await Clipboard.setData(ClipboardData(text: text));
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Caption copied! Open Instagram and paste it 📋'),
              backgroundColor: Color(0xFFE4405F),
              duration: Duration(seconds: 4)));
            launchUrl(Uri.parse('https://www.instagram.com/'),
              mode: LaunchMode.externalApplication);
          }),
          const SizedBox(width: 8),
          _btn(context, '🎵', 'TikTok', const Color(0xFF010101), () async {
            await Clipboard.setData(ClipboardData(text: text));
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Caption copied! Open TikTok and paste it 📋'),
              backgroundColor: Color(0xFF010101),
              duration: Duration(seconds: 4)));
            launchUrl(Uri.parse('https://www.tiktok.com/'),
              mode: LaunchMode.externalApplication);
          }),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _btn(context, '📱', 'SMS', DelightColors.emerald, () {
            Navigator.pop(context);
            launchUrl(Uri.parse('sms:?body=' + Uri.encodeComponent(text)),
              mode: LaunchMode.externalApplication);
          }),
          const SizedBox(width: 8),
          _btn(context, '🔗', 'Copy', DelightColors.textMuted, () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Copied ✓'),
                backgroundColor: DelightColors.emerald));
            }
          }),
          const SizedBox(width: 8),
          _btn(context, '📤', 'More apps', DelightColors.blue, () {
            Navigator.pop(context);
            Share.share(text);
          }),
          const SizedBox(width: 8),
          const Expanded(child: SizedBox()),
        ]),
        const SizedBox(height: 14),

        // POST ON DELIGHT
        const Row(children: [
          Expanded(child: Divider(color: DelightColors.surfaceBorder)),
          Padding(padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text('POST ON DELIGHT', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 9, fontWeight: FontWeight.w700,
              color: DelightColors.textMuted, letterSpacing: 1.2))),
          Expanded(child: Divider(color: DelightColors.surfaceBorder)),
        ]),
        const SizedBox(height: 10),
        Material(color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              final row = await SupabaseService.createPost(
                content: '🔁 ${post.userDisplayName}: ${post.content}',
                imageUrls: post.imageUrls,
                eventId: post.eventId,
                eventName: post.eventName);
              messenger.showSnackBar(SnackBar(
                content: Text(row != null
                  ? 'Reposted to your Delight feed 🔥'
                  : 'Could not repost — try again'),
                backgroundColor: row != null
                  ? DelightColors.emerald : DelightColors.error));
            },
            child: Container(
              height: 52, width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: DelightColors.emeraldGradient),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(
                  color: DelightColors.emerald.withOpacity(0.3),
                  blurRadius: 12, offset: const Offset(0, 4))]),
              alignment: Alignment.center,
              child: const Row(mainAxisAlignment: MainAxisAlignment.center,
                children: [
                Text('🔥', style: TextStyle(fontSize: 18)),
                SizedBox(width: 8),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Repost on Delight',
                    style: TextStyle(fontFamily: 'Satoshi', fontSize: 15,
                      fontWeight: FontWeight.w800, color: Colors.white)),
                  Text('Visible to your Delight followers',
                    style: TextStyle(fontFamily: 'Satoshi', fontSize: 10,
                      color: Colors.white70)),
                ]),
              ])))),
      ])));
  }

  Widget _btn(BuildContext ctx, String emoji, String label, Color color,
      VoidCallback onTap) =>
    Expanded(child: Material(color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2))),
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontFamily: 'Satoshi', fontSize: 9,
              fontWeight: FontWeight.w700, color: color),
              textAlign: TextAlign.center),
          ])))));
}

// ── Welcome Banner — shows quick-start actions on first use ──────────────────
class _WelcomeBanner extends ConsumerStatefulWidget {
  @override
  ConsumerState<_WelcomeBanner> createState() => _WelcomeBannerState();
}

class _WelcomeBannerState extends ConsumerState<_WelcomeBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    // Hide if dismissed or user already has transactions
    if (_dismissed) return const SizedBox.shrink();

    final firstName = user?.displayName.split(' ').first ?? 'there';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            DelightColors.emerald.withOpacity(0.15),
            DelightColors.blue.withOpacity(0.08)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text('👋 Welcome, $firstName!', style: const TextStyle(
              fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
              color: DelightColors.textPrimary)),
            const SizedBox(height: 2),
            const Text('What do you want to do?', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 13,
              color: DelightColors.textMuted)),
          ])),
          // Dismiss
          GestureDetector(
            onTap: () => setState(() => _dismissed = true),
            child: const Icon(Icons.close, color: DelightColors.textMuted, size: 18)),
        ]),
        const SizedBox(height: 14),
        // Three big simple actions — words a grade 1 student knows
        Row(children: [
          _action(context, '💸', 'Send Money', DelightColors.emerald, '/send'),
          const SizedBox(width: 8),
          _action(context, '🎟', 'Buy Tickets', DelightColors.gold, '/events'),
          const SizedBox(width: 8),
          _action(context, '➕', 'Add Money', DelightColors.blue, '/topup'),
        ]),
      ]));
  }

  Widget _action(BuildContext ctx, String emoji, String label,
      Color color, String route) =>
    Expanded(child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => ctx.push(route),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3))),
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                fontWeight: FontWeight.w700, color: color, height: 1.2)),
          ])))));
}


// ── Minting animation shown while a Memory NFT post is created ──────────────
class _MintingOverlay extends StatefulWidget {
  final ValueNotifier<bool> done;
  final Color accent;
  final String eventName;
  final String tier;
  const _MintingOverlay({required this.done, required this.accent,
    required this.eventName, required this.tier});
  @override State<_MintingOverlay> createState() => _MintingOverlayState();
}

class _MintingOverlayState extends State<_MintingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1500))
    ..repeat(reverse: true);

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Material(
      color: Colors.black.withOpacity(0.88),
      child: Center(child: ValueListenableBuilder<bool>(
        valueListenable: widget.done,
        builder: (_, done, __) => AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final g = Curves.easeInOut.transform(_c.value);
            return Column(mainAxisSize: MainAxisSize.min, children: [
              Transform.scale(
                scale: done ? 1.08 : 1 + 0.04 * g,
                child: Container(
                  width: 240, height: 140,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [accent.withOpacity(0.35), accent.withOpacity(0.06)]),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accent, width: 1.5),
                    boxShadow: [BoxShadow(
                      color: accent.withOpacity(done ? 0.75 : 0.25 + 0.4 * g),
                      blurRadius: 24 + 24 * g, spreadRadius: 2 + 4 * g)]),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                    Icon(done ? Icons.check_circle_outline : Icons.diamond_outlined,
                      size: 40, color: accent),
                    const SizedBox(height: 8),
                    Text(widget.tier.toUpperCase(), style: TextStyle(
                      fontFamily: 'Satoshi', fontSize: 11, letterSpacing: 1.4,
                      fontWeight: FontWeight.w800, color: accent)),
                    const SizedBox(height: 4),
                    Text(widget.eventName, maxLines: 2, textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Clash', fontSize: 15,
                        fontWeight: FontWeight.w700, color: Colors.white)),
                  ]))),
              const SizedBox(height: 28),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  done ? 'Memory NFT created ✓' : 'Minting your memory…',
                  key: ValueKey(done),
                  style: TextStyle(fontFamily: 'Clash', fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: done ? accent : Colors.white))),
              const SizedBox(height: 14),
              SizedBox(width: 160, child: done
                ? const SizedBox(height: 3)
                : ClipRRect(borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 3, color: accent,
                      backgroundColor: Colors.white12))),
            ]);
          }))),
    );
  }
}
