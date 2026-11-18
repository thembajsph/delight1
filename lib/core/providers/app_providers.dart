import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/xrpl_service.dart';
import '../services/supabase_service.dart';

// ─── Admin accounts ───────────────────────────────────────────────────────────
const _adminEmails = {'thembajsph1@gmail.com'};

// ─── Auth ─────────────────────────────────────────────────────────────────────
class AuthNotifier extends StateNotifier<UserModel?> {
  AuthNotifier() : super(null) {
    final existing = Supabase.instance.client.auth.currentUser;
    if (existing != null) _buildUser(existing);
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      if (user != null) _buildUser(user);
      else state = null;
    });
  }

  Future<void> _buildUser(User u) async {
    final email = u.email ?? '';
    final meta  = u.userMetadata ?? {};
    final isAdmin = _adminEmails.contains(email.toLowerCase());

    state = UserModel(
      id:          u.id,
      username:    email.split('@').first,
      displayName: meta['full_name'] ?? meta['display_name'] ?? email.split('@').first,
      email:       email,
      role:        isAdmin ? UserRole.admin : UserRole.consumer,
      avatarUrl:   meta['avatar_url'],
      createdAt:   DateTime.tryParse(u.createdAt) ?? DateTime.now(),
    );

    try {
      final profile = await SupabaseService.getProfile(u.id);
      if (profile != null && mounted) {
        final role = isAdmin ? UserRole.admin
          : _roleFromString(profile['role'] as String? ?? 'consumer');
        state = UserModel(
          id:             u.id,
          username:       profile['username'] as String? ?? email.split('@').first,
          displayName:    profile['display_name'] as String? ??
                          meta['full_name'] ?? email.split('@').first,
          email:          email,
          role:           role,
          avatarUrl:      profile['avatar_url'] as String? ?? meta['avatar_url'],
          bio:            profile['bio'] as String?,
          phone:          (profile['phone'] as String?)?.trim().isNotEmpty == true
                          ? profile['phone'] as String : (u.phone?.isNotEmpty == true ? u.phone : null),
          followersCount: profile['follower_count'] as int? ?? 0,
          followingCount: profile['following_count'] as int? ?? 0,
          createdAt:      DateTime.tryParse(profile['created_at'] as String? ?? '')
                          ?? DateTime.now(),
        );
        if (isAdmin && profile['role'] != 'admin') {
          await SupabaseService.updateProfile(u.id, {'role': 'admin'});
        }
      }
    } catch (_) {}
  }

  UserRole _roleFromString(String r) {
    switch (r) {
      case 'business':  return UserRole.business;
      case 'organizer': return UserRole.organizer;
      case 'admin':     return UserRole.admin;
      default:          return UserRole.consumer;
    }
  }

  void login(UserModel user)  => state = user;
  void update(UserModel user) => state = user;

  Future<void> logout() async {
    await SupabaseService.signOut();
    state = null;
  }

  Future<void> updateRole(UserRole role) async {
    if (state == null) return;
    if (_adminEmails.contains(state!.email.toLowerCase())) return;
    state = state!.copyWith(role: role);
    try { await SupabaseService.updateProfile(state!.id, {'role': role.name}); }
    catch (_) {}
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, UserModel?>(
  (ref) => AuthNotifier());

final isAuthenticatedProvider = Provider<bool>(
  (ref) => ref.watch(authProvider) != null);

// ─── Onboarding ───────────────────────────────────────────────────────────────
final isOnboardedProvider = StateProvider<bool>((ref) => false);

// ─── Wallet ───────────────────────────────────────────────────────────────────
class WalletNotifier extends StateNotifier<WalletModel?> {
  WalletNotifier() : super(null);

  RealtimeChannel? _sub;
  String? _currentUserId;

  /// Called on login — loads the user's custodial balance from Supabase.
  /// Delight holds one pooled XRPL wallet server-side; consumers never
  /// generate or manage their own keypair. A `wallets` row (balance_dc = 0)
  /// is auto-created by a DB trigger on signup — this just reads it, and
  /// falls back to creating one if it's somehow missing.
  Future<void> autoInit(String userId, String userEmail) async {
    _currentUserId = userId;

    try {
      var row = await SupabaseService.getWallet(userId);
      row ??= await SupabaseService.ensureWallet(userId);

      final address   = row['xrp_address'] as String? ?? '';
      final balanceDC = (row['balance_dc'] as num?)?.toDouble() ?? 0.0;

      state = WalletModel(
        address:       address,
        encryptedSeed: 'managed',
        balanceXRP:    balanceDC,
        balanceUSD:    balanceDC * DelightCurrency.xrpPriceZAR / 9.50 * 0.52,
        isImported:    true,
      );

      _sub?.unsubscribe();
      _sub = SupabaseService.subscribeToWallet(userId, (newBal) {
        if (mounted) updateBalance(newBal);
      });

      _syncFromLedger(userId);
    } catch (e) {
      // Network/DB error — leave state null rather than fabricating
      // a fake balance. The UI shows a retry/error state instead.
    }
  }

  /// Re-fetch the real balance from Supabase (post-transaction refresh).
  Future<void> refreshBalance() async {
    if (_currentUserId == null) return;
    try {
      final row = await SupabaseService.getWallet(_currentUserId!);
      if (row != null && row['xrp_address'] != null) {
        final balanceDC = (row['balance_dc'] as num?)?.toDouble() ?? 0.0;
        updateBalance(balanceDC);
      }
    } catch (_) {}
  }

  /// Sync real balance from XRP Ledger via edge function
  Future<void> _syncFromLedger(String userId) async {
    try {
      final data = await SupabaseService.syncBalance(userId);
      if (data != null && mounted) {
        final bal = (data['balance_dc'] as num?)?.toDouble();
        if (bal != null) updateBalance(bal);
      }
    } catch (_) {}
  }

  void updateBalance(double xrp) {
    if (state == null) return;
    state = state!.copyWith(
      balanceXRP: xrp,
      balanceUSD: (xrp * DelightCurrency.xrpPriceZAR / 9.50 * 0.52));
  }

  void deductAmount(double xrp) {
    if (state == null) return;
    final newBal = (state!.balanceXRP - xrp).clamp(0.0, double.infinity);
    updateBalance(newBal);
  }

  void addAmount(double xrp) {
    if (state == null) return;
    updateBalance(state!.balanceXRP + xrp);
  }

  void createWallet(String address, String seed) {
    state = WalletModel(address: address, encryptedSeed: seed,
      balanceXRP: 0.0, balanceUSD: 0.0);
  }

  void importWallet(String address, String seed, double balance) {
    state = WalletModel(address: address, encryptedSeed: seed,
      balanceXRP: balance, balanceUSD: (balance * DelightCurrency.xrpPriceZAR / 9.50 * 0.52),
      isImported: true);
  }

  void clear() {
    _sub?.unsubscribe();
    _sub = null;
    state = null;
  }
}

final walletProvider = StateNotifierProvider<WalletNotifier, WalletModel?>((ref) {
  final notifier = WalletNotifier();
  final user = ref.read(authProvider);
  if (user != null) notifier.autoInit(user.id, user.email);
  ref.listen<UserModel?>(authProvider, (_, next) {
    if (next != null) notifier.autoInit(next.id, next.email);
    else notifier.clear();
  });
  return notifier;
});

final walletReadyProvider = Provider<bool>(
  (ref) => ref.watch(walletProvider) != null);

// ─── Transactions ─────────────────────────────────────────────────────────────
class TransactionNotifier extends StateNotifier<List<TransactionModel>> {
  TransactionNotifier() : super([]);

  /// Load real transactions from Supabase
  Future<void> loadFromDB(String userId) async {
    try {
      final rows = await SupabaseService.getTransactions(userId);
      final txList = rows.map((r) => TransactionModel(
        id:          r['id'] as String,
        type:        _txType(r['type'] as String? ?? 'send'),
        fromAddress: r['metadata']?['from'] as String? ?? '',
        toAddress:   r['metadata']?['to']   as String? ?? '',
        amountXRP:   (r['amount_dc']  as num).toDouble(),
        amountUSD:   (r['amount_zar'] as num).toDouble(),
        feeXRP:      (r['fee_dc']     as num? ?? 0).toDouble(),
        memo:        r['metadata']?['memo'] as String?,
        timestamp:   DateTime.parse(r['created_at'] as String),
      )).toList();
      state = txList;
    } catch (_) {}
  }

  TransactionType _txType(String t) {
    switch (t) {
      case 'receive':          return TransactionType.receive;
      case 'topup':            return TransactionType.receive;
      case 'cashout':          return TransactionType.send;
      case 'ticket_purchase':  return TransactionType.send;
      case 'ticket_sale':      return TransactionType.receive;
      default:                 return TransactionType.send;
    }
  }

  void add(TransactionModel tx) => state = [tx, ...state];
  void clear() => state = [];
}

final transactionsProvider =
  StateNotifierProvider<TransactionNotifier, List<TransactionModel>>(
    (ref) {
      final notifier = TransactionNotifier();
      // Auto-load when user is available
      final user = ref.read(authProvider);
      if (user != null) notifier.loadFromDB(user.id);
      ref.listen<UserModel?>(authProvider, (_, next) {
        if (next != null) notifier.loadFromDB(next.id);
        else notifier.clear();
      });
      return notifier;
    });

// ─── NFT Tickets ──────────────────────────────────────────────────────────────
class TicketNotifier extends StateNotifier<List<NFTTicket>> {
  TicketNotifier() : super([]);

  /// Load real tickets from Supabase
  Future<void> loadFromDB(String userId) async {
    try {
      final rows = await SupabaseService.getMyTickets(userId);
      final tickets = rows.map((r) {
        final ev = r['events'] as Map<String, dynamic>? ?? {};
        return NFTTicket(
          id:            r['id'] as String,
          eventId:       r['event_id'] as String,
          eventName:     ev['name'] as String? ?? 'Event',
          eventDate:     DateTime.tryParse(ev['event_date'] as String? ?? '')
                          ?? DateTime.now(),
          eventVenue:    ev['venue'] as String? ?? '',
          eventCity:     ev['city']  as String? ?? '',
          eventImageUrl: ev['image_url'] as String?,
          tokenId:       r['token_id'] as String? ?? '',
          ownerAddress:  r['owner_address'] as String? ?? '',
          priceXRP:      (r['price_zar'] as num? ?? 0).toDouble() / 9.5,
          tier:          r['tier'] as String? ?? 'General',
          isUsed:        r['is_used'] as bool? ?? false,
          isForSale:     r['is_for_sale'] as bool? ?? false,
          resalePriceXRP: (r['resale_price_zar'] as num?)?.toDouble(),
          mintedAt:      DateTime.tryParse(r['minted_at'] as String? ?? '')
                          ?? DateTime.now(),
        );
      }).toList();
      state = tickets;
    } catch (_) {}
  }

  void add(NFTTicket ticket) => state = [ticket, ...state];

  void markUsed(String id) =>
    state = state.map((t) => t.id == id ? t.copyWith(isUsed: true) : t).toList();

  Future<void> listForSale(String id, double priceZAR) async {
    state = state.map((t) => t.id == id
      ? t.copyWith(isForSale: true, resalePriceXRP: priceZAR) : t).toList();
    try { await SupabaseService.listTicketForSale(id, priceZAR); } catch (_) {}
  }

  Future<void> cancelListing(String id) async {
    state = state.map((t) => t.id == id
      ? t.copyWith(isForSale: false, resalePriceXRP: 0) : t).toList();
    try { await SupabaseService.cancelTicketListing(id); } catch (_) {}
  }

  void removeTicket(String id) =>
    state = state.where((t) => t.id != id).toList();

  void clear() => state = [];
}

final ticketsProvider =
  StateNotifierProvider<TicketNotifier, List<NFTTicket>>((ref) {
    final notifier = TicketNotifier();
    final user = ref.read(authProvider);
    if (user != null) notifier.loadFromDB(user.id);
    ref.listen<UserModel?>(authProvider, (_, next) {
      if (next != null) notifier.loadFromDB(next.id);
      else notifier.clear();
    });
    return notifier;
  });

// ─── Events ───────────────────────────────────────────────────────────────────
class EventNotifier extends StateNotifier<List<EventModel>> {
  EventNotifier() : super([]) {
    _loadFromDB();
  }

  Future<void> _loadFromDB() async {
    try {
      final rows = await SupabaseService.getEvents();
      final events = rows.map<EventModel>((r) {
        final tiersRaw = r['ticket_tiers'];
        final tiersList = (tiersRaw is List) ? tiersRaw : <dynamic>[];
        return EventModel(
          id:            r['id'] as String,
          organizerId:   r['organizer_id'] as String? ?? '',
          organizerName: r['organizer_name'] as String? ?? '',
          title:         r['name'] as String? ?? 'Event',
          description:   r['description'] as String? ?? '',
          coverImageUrl: r['image_url'] as String?,
          venue:         r['venue'] as String? ?? '',
          city:          r['city'] as String? ?? '',
          country:       r['country'] as String? ?? 'ZA',
          date:          DateTime.tryParse(r['event_date'] as String? ?? '') ?? DateTime.now(),
          category:      r['category'] as String? ?? 'Music',
          ticketTiers:   tiersList.map((t) => TicketTier(
            id:           t['id'] as String? ?? '',
            name:         t['name'] as String? ?? 'General',
            priceXRP:     (t['priceXRP'] as num?)?.toDouble() ?? 0.0,
            totalTickets: (t['totalTickets'] as num?)?.toInt() ?? 0,
            soldTickets:  (t['soldTickets'] as num?)?.toInt() ?? 0,
            perks:        (t['perks'] as List?)?.cast<String>() ?? const [],
          )).toList(),
        );
      }).toList();
      state = events;
    } catch (_) {
      // Network/DB error — state stays as-is (empty on first load).
      // The events screen shows a genuine "couldn't load" / retry state,
      // never fabricated events.
    }
  }

  Future<void> refresh() => _loadFromDB();

  void add(EventModel event) => state = [event, ...state];
}

final eventsProvider =
  StateNotifierProvider<EventNotifier, List<EventModel>>(
    (ref) => EventNotifier());

final filteredEventsProvider =
  Provider.family<List<EventModel>, String>((ref, category) {
    final events = ref.watch(eventsProvider);
    if (category == 'All') return events;
    return events.where((e) => e.category == category).toList();
  });

// ─── Chat ─────────────────────────────────────────────────────────────────────
class ChatMessageNotifier
  extends StateNotifier<Map<String, List<Map<String, dynamic>>>> {
  ChatMessageNotifier() : super({});

  void addMessage(String convId, {
    required String senderId, required String senderName,
    required String text, required bool isMe, double? zarTip,
  }) {
    final existing = List<Map<String, dynamic>>.from(state[convId] ?? []);
    existing.add({
      'id':         'm_${DateTime.now().millisecondsSinceEpoch}',
      'senderId':   senderId,
      'senderName': senderName,
      'text':       text,
      'isMe':       isMe,
      'zarTip':     zarTip,
      'timestamp':  DateTime.now().toIso8601String(),
    });
    state = {...state, convId: existing};
  }

  List<Map<String, dynamic>> getMessages(String convId) =>
    List.from(state[convId] ?? []);
}

final chatMessagesProvider = StateNotifierProvider<
  ChatMessageNotifier, Map<String, List<Map<String, dynamic>>>>(
    (ref) => ChatMessageNotifier());

// ─── Event group chats ────────────────────────────────────────────────────────
class EventGroupChatNotifier extends StateNotifier<List<String>> {
  EventGroupChatNotifier() : super([]);
  void add(String eventId) {
    if (!state.contains(eventId)) state = [...state, eventId];
  }
}

final eventGroupChatProvider =
  StateNotifierProvider<EventGroupChatNotifier, List<String>>(
    (ref) => EventGroupChatNotifier());

// ─── Feed ─────────────────────────────────────────────────────────────────────
class FeedNotifier extends StateNotifier<List<SocialPost>> {
  FeedNotifier() : super([]) {
    _loadFromDB();
  }

  Future<void> _loadFromDB() async {
    try {
      final rows = await SupabaseService.getFeed();
      final likedIds = await SupabaseService.getLikedPostIds(
        rows.map((r) => r['id'] as String).toList());

      state = rows.map((r) => SocialPost(
        id:                 r['id'] as String,
        userId:             r['user_id'] as String? ?? '',
        userDisplayName:    r['user_display_name'] as String? ?? 'User',
        userAvatarUrl:      r['user_avatar_url'] as String?,
        eventId:            r['event_id'] as String?,
        eventName:          r['event_name'] as String?,
        content:            r['content'] as String? ?? '',
        imageUrls:          (r['image_urls'] as List?)?.cast<String>() ?? const [],
        nftTokenId:         r['nft_token_id'] as String?,
        isNftMemory:        r['is_nft_memory'] as bool? ?? false,
        memoryTokenId:      r['memory_token_id'] as String?,
        attendedEventName:  r['attended_event_name'] as String?,
        attendedEventVenue: r['attended_event_venue'] as String?,
        attendedTier:       r['attended_tier'] as String?,
        attendedTicketId:   r['attended_ticket_id'] as String?,
        eventDate:          r['event_date'] != null
          ? DateTime.tryParse(r['event_date'] as String) : null,
        hasVideo:           r['has_video'] as bool? ?? false,
        memoryStyle:        r['memory_style'] as String?,
        likesCount:         (r['likes_count'] as num?)?.toInt() ?? 0,
        commentsCount:      (r['comments_count'] as num?)?.toInt() ?? 0,
        isLiked:            likedIds.contains(r['id']),
        timestamp:          DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
      )).toList();
    } catch (_) {
      // Network/DB error — state stays empty. The feed screen shows a
      // genuine empty/retry state, never fabricated posts.
    }
  }

  Future<void> refresh() => _loadFromDB();

  /// Creates a REAL post in the database and adds it to local state using
  /// the row the server actually stored (real ID, real timestamp).
  Future<void> createRealPost({
    required String content,
    List<String> imageUrls = const [],
    String? eventId,
    String? eventName,
  }) async {
    final row = await SupabaseService.createPost(
      content: content, imageUrls: imageUrls,
      eventId: eventId, eventName: eventName);
    if (row == null) return;
    final newPost = SocialPost(
      id:              row['id'] as String,
      userId:          row['user_id'] as String? ?? '',
      userDisplayName: row['user_display_name'] as String? ?? 'You',
      userAvatarUrl:   row['user_avatar_url'] as String?,
      eventId:         row['event_id'] as String?,
      eventName:       row['event_name'] as String?,
      content:         row['content'] as String? ?? content,
      imageUrls:       (row['image_urls'] as List?)?.cast<String>() ?? imageUrls,
      timestamp:       DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
    );
    state = [newPost, ...state];
  }

  /// Kept for callers that already build a full SocialPost locally
  /// (e.g. Memory NFT minting). Those callers should also persist via
  /// createRealPost — this only updates local state.
  void add(SocialPost post) => state = [post, ...state];

  Future<void> toggleLike(String postId) async {
    final nowLiked = await SupabaseService.toggleLike(postId);
    state = state.map((p) {
      if (p.id != postId) return p;
      p.isLiked = nowLiked;
      p.likesCount = (p.likesCount + (nowLiked ? 1 : -1)).clamp(0, 1 << 30);
      return p;
    }).toList();
  }
}

final feedProvider = StateNotifierProvider<FeedNotifier, List<SocialPost>>(
  (ref) => FeedNotifier());

// ─── Price ────────────────────────────────────────────────────────────────────
final xrpPriceProvider = StateProvider<double>((ref) => 9.50);

// ─── Analytics ────────────────────────────────────────────────────────────────
class AnalyticsNotifier extends StateNotifier<Map<String, int>> {
  AnalyticsNotifier() : super({});
  void track(String event) {
    state = {...state, event: (state[event] ?? 0) + 1};
  }
}

final analyticsProvider =
  StateNotifierProvider<AnalyticsNotifier, Map<String, int>>(
    (ref) => AnalyticsNotifier());
