import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/models/models.dart';

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(feedProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      body: CustomScrollView(
        slivers: [
          // App bar
          SliverAppBar(
            floating: true,
            backgroundColor: DelightColors.background,
            title: Image.asset(
              'assets/images/delight_logo.png',
              height: 32,
              fit: BoxFit.contain),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_box_outlined, color: DelightColors.textPrimary),
                onPressed: () => _showCreatePost(context, ref),
              ),
              const SizedBox(width: 4),
            ],
          ),

          // Stories row
          SliverToBoxAdapter(child: _StoriesRow()),

          // Posts
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _PostCard(post: posts[i], ref: ref),
              childCount: posts.length,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  void _showCreatePost(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: DelightColors.surfaceHigh,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CreatePostSheet(ref: ref),
    );
  }
}

class _StoriesRow extends StatelessWidget {
  final _stories = [
    ('You', '🤳', true),
    ('Amara D', '🎵', false),
    ('Lagos Vibez', '🎪', false),
    ('Kwame A', '💻', false),
    ('Zainab O', '🎨', false),
    ('Nairobi Tech', '🔗', false),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _stories.length,
        itemBuilder: (_, i) {
          final story = _stories[i];
          return Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Column(
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: story.$3
                      ? const LinearGradient(colors: [DelightColors.surfaceBorder, DelightColors.surfaceHigh])
                      : const LinearGradient(colors: DelightColors.emeraldGradient),
                    border: Border.all(
                      color: story.$3 ? DelightColors.surfaceBorder : DelightColors.emerald,
                      width: 2,
                    ),
                  ),
                  child: story.$3
                    ? const Icon(Icons.add, color: DelightColors.emerald, size: 22)
                    : Center(child: Text(story.$2, style: const TextStyle(fontSize: 22))),
                ),
                const SizedBox(height: 5),
                Text(story.$1, style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 11, color: DelightColors.textSecondary,
                )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final SocialPost post;
  final WidgetRef ref;
  const _PostCard({required this.post, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DelightColors.surface,
        border: Border(bottom: BorderSide(color: DelightColors.surfaceBorder, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: DelightColors.surfaceBorder,
                backgroundImage: post.userAvatarUrl != null
                  ? CachedNetworkImageProvider(post.userAvatarUrl ?? "") : null,
                child: post.userAvatarUrl == null
                  ? Text(post.userDisplayName[0].toUpperCase(), style: const TextStyle(
                      color: DelightColors.emerald, fontWeight: FontWeight.w700))
                  : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.userDisplayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                      fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                      color: DelightColors.textPrimary, fontSize: 14,
                    )),
                    if (post.eventName != null)
                      Row(children: [
                        const Icon(Icons.confirmation_number_outlined, size: 12, color: DelightColors.emerald),
                        const SizedBox(width: 4),
                        Flexible(child: Text(post.eventName!, style: const TextStyle(
                          fontFamily: 'Satoshi', fontSize: 11, color: DelightColors.emerald,
                          overflow: TextOverflow.ellipsis,
                        ))),
                      ]),
                  ],
                ),
              ),
              Text(timeago.format(post.timestamp), style: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 12, color: DelightColors.textMuted,
              )),
            ],
          ),
          const SizedBox(height: 12),

          // Content
          Text(post.content, style: const TextStyle(
            fontFamily: 'Satoshi', fontSize: 14, color: DelightColors.textPrimary, height: 1.55,
          )),

          // Images
          if (post.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            if (post.imageUrls.length == 1)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: post.imageUrls.first, width: double.infinity,
                  height: 220, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(color: const Color(0xFF112016), alignment: Alignment.center, child: const Icon(Icons.image_outlined, color: Color(0xFF3D5E4A), size: 32)),
                ),
              )
            else
              SizedBox(
                height: 160,
                child: Row(
                  children: post.imageUrls.take(3).map((url) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, height: 160),
                      ),
                    ),
                  )).toList(),
                ),
              ),
          ],

          // NFT badge
          if (post.nftTokenId != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: DelightColors.goldGlow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DelightColors.gold.withOpacity(0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.diamond_outlined, size: 12, color: DelightColors.gold),
                const SizedBox(width: 5),
                Text('NFT Memory · ${post.nftTokenId}', style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 11, color: DelightColors.gold,
                  fontWeight: FontWeight.w600,
                )),
              ]),
            ),
          ],

          const SizedBox(height: 12),

          // Actions
          Row(children: [
            _ActionBtn(
              icon: post.isLiked ? Icons.favorite : Icons.favorite_border,
              label: '${post.likesCount}',
              color: post.isLiked ? Colors.red : DelightColors.textMuted,
              onTap: () => ref.read(feedProvider.notifier).toggleLike(post.id),
            ),
            const SizedBox(width: 20),
            _ActionBtn(
              icon: Icons.chat_bubble_outline,
              label: '${post.commentsCount}',
              color: DelightColors.textMuted,
              onTap: () {},
            ),
            const SizedBox(width: 20),
            _ActionBtn(
              icon: Icons.share_outlined,
              label: 'Share',
              color: DelightColors.textMuted,
              onTap: () {},
            ),
          ]),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Row(children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(
        fontFamily: 'Satoshi', fontSize: 13, color: color, fontWeight: FontWeight.w500,
      )),
    ]),
  );
}

class _CreatePostSheet extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _CreatePostSheet({required this.ref});
  @override
  ConsumerState<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends ConsumerState<_CreatePostSheet> {
  final _ctrl = TextEditingController();
  bool _posting = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _post() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() => _posting = true);
    await Future.delayed(const Duration(milliseconds: 400));
    final user = ref.read(authProvider);
    final post = SocialPost(
      id: 'p_${DateTime.now().millisecondsSinceEpoch}',
      userId: user?.id ?? 'usr_anon',
      userDisplayName: user?.displayName ?? 'You',
      content: _ctrl.text.trim(),
      timestamp: DateTime.now(),
    );
    ref.read(feedProvider.notifier).add(post);
    ref.read(analyticsProvider.notifier).track('post_created');
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New Post', style: TextStyle(
              fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
              color: DelightColors.textPrimary,
            )),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              maxLines: 4,
              autofocus: true,
              style: const TextStyle(fontFamily: 'Satoshi', color: DelightColors.textPrimary, fontSize: 15),
              decoration: const InputDecoration(
                hintText: "What's happening at your event?",
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.image_outlined, color: DelightColors.textMuted),
              const SizedBox(width: 16),
              const Icon(Icons.tag, color: DelightColors.textMuted),
              const SizedBox(width: 16),
              const Icon(Icons.diamond_outlined, color: DelightColors.gold),
              const Spacer(),
              GestureDetector(
                onTap: _posting ? null : _post,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: DelightColors.emeraldGradient),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _posting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(
                        color: DelightColors.textInverse, strokeWidth: 2))
                    : const Text('Post', style: TextStyle(
                        fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                        color: DelightColors.textInverse, fontSize: 14,
                      )),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
