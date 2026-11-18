import 'package:flutter/material.dart';
import '../../../../core/services/supabase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/models/models.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:timeago/timeago.dart' as timeago;
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/xrpl_service.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class Conversation {
  final String id, name, lastMessage, avatarEmoji;
  final int unread;
  final bool isGroup, isEventGroup;
  final DateTime timestamp;
  final Color color;
  const Conversation({
    required this.id, required this.name, required this.lastMessage,
    required this.avatarEmoji, this.unread = 0, this.isGroup = false,
    this.isEventGroup = false, required this.timestamp, required this.color});
}

class ChatMessage {
  final String id, senderId, senderName, text;
  final bool isMe;
  final DateTime timestamp;
  final double? zarTip;
  const ChatMessage({
    required this.id, required this.senderId, required this.senderName,
    required this.text, required this.isMe, required this.timestamp,
    this.zarTip});
}

// ── Messages list ─────────────────────────────────────────────────────────────

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});
  @override State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  late List<Conversation> _convs;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _convs = [];
    _loadFromSupabase();
  }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  bool _loadingConvs = true;

  Future<void> _loadFromSupabase() async {
    try {
      final rows = await SupabaseService.getConversations();
      if (!mounted) return;
      final loaded = rows.map((r) {
        final isEvent = r['event_id'] != null;
        return Conversation(
          id:          '${r['conversation_id'] ?? ''}',
          name:        r['name'] as String? ?? 'Direct Message',
          lastMessage: r['last_message'] as String? ?? 'Say hello 👋',
          avatarEmoji: r['avatar_emoji'] as String? ?? (isEvent ? '🎟' : '💬'),
          unread:      (r['unread_count'] as num?)?.toInt() ?? 0,
          isGroup:     r['is_group'] as bool? ?? false,
          isEventGroup: isEvent,
          timestamp:   DateTime.tryParse('${r['last_message_at'] ?? ''}')?.toLocal() ?? DateTime.now(),
          color:       isEvent ? DelightColors.blue : DelightColors.emerald);
      }).where((c) => c.id.isNotEmpty).toList();
      if (mounted) setState(() { _convs = loaded; _loadingConvs = false; });
    } catch (e) {
      debugPrint('loadConversations: $e');
      if (mounted) setState(() => _loadingConvs = false);
    }
  }

  void _addConversation(Conversation conv) {
    setState(() {
      // Don't add duplicates
      if (!_convs.any((c) => c.id == conv.id)) {
        _convs.insert(0, conv);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) => _buildBody(context, ref));
  }

  Widget _buildBody(BuildContext context, WidgetRef ref) {
    // Merge into display list
    final allConvs = [..._convs];
    final dms    = allConvs.where((c) => !c.isGroup).toList().cast<Conversation>();
    final groups = allConvs.where((c) => c.isGroup).toList().cast<Conversation>();
    final unread = allConvs.fold<int>(0, (s, c) => s + c.unread);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      appBar: AppBar(
        backgroundColor: DelightColors.background,
        title: Row(children: [
          const Text('Messages', style: TextStyle(
            fontFamily: 'Clash', fontSize: 22, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary)),
          if (unread > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: DelightColors.emerald,
                borderRadius: BorderRadius.circular(10)),
              child: Text('$unread', style: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 11,
                fontWeight: FontWeight.w700,
                color: DelightColors.textInverse))),
          ],
        ]),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: DelightColors.emerald,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: DelightColors.textPrimary,
          unselectedLabelColor: DelightColors.textMuted,
          labelStyle: const TextStyle(
            fontFamily: 'Satoshi', fontWeight: FontWeight.w700, fontSize: 13),
          tabs: [
            Tab(text: 'Direct (${dms.length})'),
            Tab(text: 'Events (${groups.length})'),
          ],
        ),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            style: const TextStyle(fontFamily: 'Satoshi',
              color: DelightColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search messages...',
              prefixIcon: const Icon(Icons.search,
                color: DelightColors.textMuted, size: 20),
              contentPadding: EdgeInsets.zero,
              filled: true,
              fillColor: DelightColors.surfaceHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: DelightColors.surfaceBorder)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: DelightColors.surfaceBorder))),
          ),
        ),
        Expanded(child: TabBarView(
          controller: _tab,
          children: [
            _ConvList(conversations: dms),
            _ConvList(conversations: groups),
          ],
        )),
      ]),
      floatingActionButton: FloatingActionButton(
        backgroundColor: DelightColors.emerald,
        onPressed: () => _showNewMessage(context),
        child: const Icon(Icons.add_comment_outlined,
          color: DelightColors.textInverse)),
    );
  }

  void _showNewMessage(BuildContext context) {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool loading = false;
    bool loadedOnce = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> search(String q) async {
            setSheet(() => loading = true);
            try {
              if (q.trim().isEmpty) {
                final rows = await SupabaseService.getRecentContacts();
                results = rows.map((r) {
                  final p = r['profiles'] as Map<String, dynamic>? ?? r;
                  return {
                    'id': p['id'],
                    'display_name': p['display_name'] ?? 'User',
                    'phone': p['phone'] ?? '',
                    'avatar_url': p['avatar_url'],
                  };
                }).toList();
              } else {
                results = await SupabaseService.searchUsers(q);
              }
            } catch (_) {
              results = [];
            }
            setSheet(() => loading = false);
          }

          if (!loadedOnce) {
            loadedOnce = true;
            Future.microtask(() => search(''));
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            expand: false,
            builder: (_, ctrl) => Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(children: [
                  Center(child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: DelightColors.surfaceBorder,
                      borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 14),
                  const Text('New Message', style: TextStyle(
                    fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
                    color: DelightColors.textPrimary)),
                  const SizedBox(height: 12),
                  // Real search — queries Supabase profiles by name or phone
                  TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    onChanged: search,
                    style: const TextStyle(fontFamily: 'Satoshi',
                      color: DelightColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search by name or phone...',
                      hintStyle: const TextStyle(
                        fontFamily: 'Satoshi', color: DelightColors.textMuted),
                      prefixIcon: const Icon(Icons.search,
                        color: DelightColors.textMuted, size: 18),
                      filled: true,
                      fillColor: DelightColors.background,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: DelightColors.emerald, width: 1.5)))),
                  const SizedBox(height: 8),
                ])),
              const Divider(color: DelightColors.surfaceBorder, height: 1),
              Expanded(child: loading
                ? const Center(child: CircularProgressIndicator(
                    color: DelightColors.emerald))
                : results.isEmpty
                  ? Center(child: Text(
                      searchCtrl.text.trim().isEmpty
                        ? 'No recent contacts yet'
                        : 'No Delight users found',
                      style: const TextStyle(fontFamily: 'Satoshi',
                        color: DelightColors.textMuted)))
                  : ListView.builder(
                      controller: ctrl,
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final u = results[i];
                        final uid  = u['id'] as String? ?? '';
                        final name = u['display_name'] as String? ?? 'User';
                        final phone = u['phone'] as String? ?? '';
                        final avatarUrl = u['avatar_url'] as String?;
                        return GestureDetector(
                          onTap: () async {
                            if (uid.isEmpty) return;
                            Navigator.pop(context);
                            try {
                              final convId = await SupabaseService.getOrCreateDM(uid);
                              final newConv = Conversation(
                                id: convId,
                                name: name,
                                lastMessage: 'Say hello! 👋',
                                avatarEmoji: '💬',
                                unread: 0,
                                timestamp: DateTime.now(),
                                color: DelightColors.emerald);
                              _addConversation(newConv);
                              if (context.mounted) {
                                await context.push('/chat/$convId', extra: newConv);
                                _loadFromSupabase();
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Could not start chat: $e')));
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                            child: Row(children: [
                              CircleAvatar(
                                radius: 23,
                                backgroundColor: DelightColors.emeraldGlow,
                                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                                  ? NetworkImage(avatarUrl) : null,
                                child: (avatarUrl == null || avatarUrl.isEmpty)
                                  ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                      style: const TextStyle(fontSize: 18,
                                        color: DelightColors.emerald,
                                        fontWeight: FontWeight.w700))
                                  : null),
                              const SizedBox(width: 12),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(
                                  fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                                  fontSize: 14, color: DelightColors.textPrimary)),
                                if (phone.isNotEmpty)
                                  Text(phone, overflow: TextOverflow.ellipsis, style: const TextStyle(
                                    fontFamily: 'Satoshi', fontSize: 12,
                                    color: DelightColors.textMuted)),
                              ])),
                              const Icon(Icons.chevron_right,
                                color: DelightColors.textMuted, size: 18),
                            ])));
                      })),
            ]));
        }));
  }
}

class _ConvList extends StatelessWidget {
  final List<Conversation> conversations;
  const _ConvList({required this.conversations});
  @override
  Widget build(BuildContext context) => ListView.separated(
    itemCount: conversations.length,
    separatorBuilder: (_, __) => const Divider(
      color: DelightColors.surfaceBorder, height: 1, indent: 72),
    itemBuilder: (_, i) => _ConvTile(conv: conversations[i]),
  );
}

class _ConvTile extends StatelessWidget {
  final Conversation conv;
  const _ConvTile({required this.conv});

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: Stack(clipBehavior: Clip.none, children: [
      Container(
        width: 50, height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: conv.color.withOpacity(0.15),
          border: Border.all(
            color: conv.unread > 0 ? conv.color : DelightColors.surfaceBorder,
            width: conv.unread > 0 ? 1.5 : 1)),
        alignment: Alignment.center,
        child: Text(conv.avatarEmoji, style: const TextStyle(fontSize: 22))),
      if (conv.isEventGroup)
        Positioned(bottom: 0, right: 0, child: Container(
          width: 16, height: 16,
          decoration: BoxDecoration(
            color: DelightColors.emerald, shape: BoxShape.circle,
            border: Border.all(
              color: DelightColors.background, width: 1.5)),
          child: const Icon(Icons.confirmation_number_outlined,
            size: 9, color: DelightColors.textInverse))),
    ]),
    title: Row(children: [
      Expanded(child: Text(conv.name, style: const TextStyle(
        fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
        color: DelightColors.textPrimary, fontSize: 14))),
      Text(timeago.format(conv.timestamp, allowFromNow: true),
        style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
          color: conv.unread > 0 ? conv.color : DelightColors.textMuted)),
    ]),
    subtitle: Row(children: [
      Expanded(child: Text(conv.lastMessage, style: TextStyle(
        fontFamily: 'Satoshi', fontSize: 12,
        color: conv.unread > 0
          ? DelightColors.textPrimary : DelightColors.textMuted),
        maxLines: 1, overflow: TextOverflow.ellipsis)),
      if (conv.unread > 0)
        Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: conv.color, borderRadius: BorderRadius.circular(10)),
          child: Text('${conv.unread}', style: const TextStyle(
            fontFamily: 'Satoshi', fontSize: 10,
            fontWeight: FontWeight.w700,
            color: DelightColors.textInverse))),
    ]),
    onTap: () => context.push('/chat/${conv.id}', extra: conv),
  );
}

// ── Chat screen ───────────────────────────────────────────────────────────────

class ChatScreen extends ConsumerStatefulWidget {
  final Conversation conv;
  const ChatScreen({super.key, required this.conv});
  @override ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _msgCtrl   = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<ChatMessage> _msgs = [];
  RealtimeChannel? _channel;
  bool _loading = true, _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = SupabaseService.subscribeToMessages(widget.conv.id, _load);
  }

  Future<void> _load() async {
    final me = SupabaseService.currentUser?.id;
    final rows = await SupabaseService.getMessages(widget.conv.id);
    if (!mounted) return;
    setState(() {
      _msgs = rows.map((m) => ChatMessage(
        id: '${m['id']}', senderId: '${m['sender_id']}',
        senderName: (m['sender_name'] as String?)?.trim().isNotEmpty == true
          ? m['sender_name'] as String : 'User',
        text: '${m['content']}', isMe: '${m['sender_id']}' == me,
        timestamp: DateTime.tryParse('${m['created_at']}')?.toLocal() ?? DateTime.now(),
      )).toList();
      _loading = false;
    });
    SupabaseService.markRead(widget.conv.id);
    _toBottom();
  }

  void _toBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await SupabaseService.sendMessage(
        conversationId: widget.conv.id, content: text);
      _msgCtrl.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Message didn't send. Try again.")));
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  // Real money only — goes through the normal Send flow (balance checks,
  // ledger, receipts). No fake in-chat "sent" bubbles.
  void _showTip() => context.push('/send');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      appBar: AppBar(
        backgroundColor: DelightColors.background,
        titleSpacing: 0,
        title: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.conv.color.withOpacity(0.15)),
            alignment: Alignment.center,
            child: Text(widget.conv.avatarEmoji,
              style: const TextStyle(fontSize: 18))),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.conv.name, style: const TextStyle(
              fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
              color: DelightColors.textPrimary, fontSize: 15)),
            if (widget.conv.isGroup)
              Text(widget.conv.isEventGroup
                ? 'Event group · ticket holders only' : 'Group',
                style: const TextStyle(fontFamily: 'Satoshi',
                  fontSize: 11, color: DelightColors.textMuted)),
          ]),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline,
              color: DelightColors.textPrimary),
            onPressed: () {}),
        ],
      ),
      body: Column(children: [
        if (widget.conv.isEventGroup)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: DelightColors.emeraldGlow,
            child: const Row(children: [
              Icon(Icons.confirmation_number_outlined,
                color: DelightColors.emerald, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text('Ticket holders only',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                  color: DelightColors.emerald, fontWeight: FontWeight.w600))),
            ])),

        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator(color: DelightColors.emerald))
            : _msgs.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(widget.conv.avatarEmoji,
                  style: const TextStyle(fontSize: 52)),
                const SizedBox(height: 14),
                Text('Chat with ${widget.conv.name}',
                  style: const TextStyle(fontFamily: 'Clash', fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: DelightColors.textPrimary)),
                const SizedBox(height: 6),
                const Text('Send a message to start the conversation',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                    color: DelightColors.textMuted)),
                const SizedBox(height: 20),
                Wrap(spacing: 8, runSpacing: 8,
                  children: ['👋 Hey!', '🎟 Ticket sorted?', '🔥 See you there']
                    .map((t) => GestureDetector(
                      onTap: () {
                        _msgCtrl.text = t;
                        _send();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: DelightColors.emeraldGlow,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: DelightColors.emerald.withOpacity(0.3))),
                        child: Text(t, style: const TextStyle(
                          fontFamily: 'Satoshi', fontSize: 13,
                          color: DelightColors.emerald,
                          fontWeight: FontWeight.w600))))).toList()),
              ]))
            : ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
                itemCount: _msgs.length,
                itemBuilder: (_, i) => _Bubble(msg: _msgs[i]))),

        // Input bar
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
          decoration: const BoxDecoration(
            color: DelightColors.surface,
            border: Border(top: BorderSide(
              color: DelightColors.surfaceBorder))),
          child: Row(children: [
            // Money tip button
            GestureDetector(
              onTap: _showTip,
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: DelightColors.goldGlow,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: DelightColors.gold.withOpacity(0.4))),
                child: const Icon(Icons.bolt,
                  color: DelightColors.gold, size: 18))),
            const SizedBox(width: 8),
            // Text field
            Expanded(
              child: TextField(
                controller: _msgCtrl,
                style: const TextStyle(fontFamily: 'Satoshi',
                  color: DelightColors.textPrimary, fontSize: 14),
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Message...',
                  filled: true,
                  fillColor: DelightColors.surfaceHigh,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(
                      color: DelightColors.surfaceBorder)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(
                      color: DelightColors.surfaceBorder)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(
                      color: DelightColors.emerald)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.image_outlined,
                      color: DelightColors.textMuted, size: 20),
                    onPressed: () {})))),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: DelightColors.emeraldGradient),
                  shape: BoxShape.circle),
                child: const Icon(Icons.send,
                  color: DelightColors.textInverse, size: 18))),
          ]),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    if (msg.zarTip != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A2E0A), Color(0xFF0F2010)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: DelightColors.emerald.withOpacity(0.4))),
          child: Column(children: [
            const Text('💸', style: TextStyle(fontSize: 28)),
            const SizedBox(height: 4),
            Text('R${msg.zarTip!.toStringAsFixed(2)} sent',
              style: const TextStyle(fontFamily: 'Clash', fontSize: 20,
                fontWeight: FontWeight.w700, color: DelightColors.emerald)),
            Text(msg.isMe ? 'You sent this' : '${msg.senderName} sent this',
              style: const TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                color: DelightColors.textMuted)),
          ]))));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: msg.isMe
          ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!msg.isMe) ...[
            CircleAvatar(radius: 14,
              backgroundColor: DelightColors.surfaceBorder,
              child: Text(msg.senderName.isEmpty ? '?' : msg.senderName[0], style: const TextStyle(
                fontSize: 11, color: DelightColors.emerald,
                fontWeight: FontWeight.w700))),
            const SizedBox(width: 6),
          ],
          Flexible(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: msg.isMe ? const LinearGradient(
                colors: [Color(0xFF0D2A1A), Color(0xFF0A2015)]) : null,
              color: msg.isMe ? null : DelightColors.surfaceHigh,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(msg.isMe ? 16 : 4),
                bottomRight: Radius.circular(msg.isMe ? 4 : 16)),
              border: Border.all(
                color: msg.isMe
                  ? DelightColors.emerald.withOpacity(0.3)
                  : DelightColors.surfaceBorder)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!msg.isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(msg.senderName, style: const TextStyle(
                      fontFamily: 'Satoshi', fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: DelightColors.emerald))),
                Text(msg.text, style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 14,
                  color: DelightColors.textPrimary, height: 1.4)),
                const SizedBox(height: 3),
                Text(
                  '${msg.timestamp.hour.toString().padLeft(2, "0")}:'
                  '${msg.timestamp.minute.toString().padLeft(2, "0")}',
                  style: const TextStyle(fontFamily: 'Satoshi',
                    fontSize: 10, color: DelightColors.textMuted)),
              ]))),
        ]));
  }
}
