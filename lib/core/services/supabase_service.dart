// lib/core/services/supabase_service.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:uuid/uuid.dart';
import '../config/env.dart';
import '../models/models.dart';

class SupabaseService {
  static SupabaseClient get _client => Supabase.instance.client;
  static String get _fnUrl =>
    '${Env.supabaseUrl}/functions/v1';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );
  }

  static User?    get currentUser    => _client.auth.currentUser;
  static Session? get currentSession => _client.auth.currentSession;
  static String?  get authToken      => currentSession?.accessToken;

  // ── Auth ──────────────────────────────────────────────────────────────────
  static Future<({AuthResponse response, bool needsConfirmation})> signUp({
    required String email, required String password,
    required String displayName, required String username,
    required String role,
  }) async {
    final response = await _client.auth.signUp(
      email: email, password: password,
      data: {'display_name': displayName, 'username': username, 'role': role},
    );
    if (response.user == null) throw Exception('Sign up failed');
    return (response: response, needsConfirmation: response.session == null);
  }

  static Future<AuthResponse> signIn({
    required String email, required String password,
  }) async =>
    _client.auth.signInWithPassword(email: email, password: password);

  static Future<void> signOut() async => _client.auth.signOut();

  static Future<AuthResponse> signInWithGoogleMobile() async {
    final googleSignIn = GoogleSignIn(
      serverClientId: Env.googleWebClientId,
      scopes: ['email', 'profile'],
    );
    await googleSignIn.signOut();
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) throw Exception('Cancelled');
    final googleAuth  = await googleUser.authentication;
    final idToken     = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;
    if (idToken == null || accessToken == null) {
      throw Exception('Google auth tokens missing');
    }
    final response = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken, accessToken: accessToken,
    );
    if (response.user == null) throw Exception('Supabase sign-in failed');
    try {
      await _client.from('profiles').update({
        'display_name': googleUser.displayName,
        'avatar_url':   googleUser.photoUrl,
      }).eq('id', response.user!.id);
    } catch (_) {}
    return response;
  }

  // ── Profile ───────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getProfile(String userId) async {
    try {
      return await _client.from('profiles').select().eq('id', userId).single();
    } catch (_) { return null; }
  }

  static Future<void> updateProfile(
      String userId, Map<String, dynamic> updates) async {
    await _client.from('profiles').update(updates).eq('id', userId);
  }

  // ── Wallet ────────────────────────────────────────────────────────────────
  /// Fetch wallet row for user — returns null if not found
  static Future<Map<String, dynamic>?> getWallet(String userId) async {
    try {
      return await _client.from('wallets').select()
        .eq('user_id', userId).single();
    } catch (_) { return null; }
  }

  /// Custodial model: every user gets a simple ZAR/DC ledger balance, no
  /// on-chain keypair of their own. Creates the wallet row on first use —
  /// consumers never generate or back up a private key.
  static Future<Map<String, dynamic>> ensureWallet(String userId) async {
    final existing = await getWallet(userId);
    if (existing != null) return existing;
    try {
      return await _client.from('wallets')
        .insert({'user_id': userId, 'balance_dc': 0})
        .select().single();
    } catch (_) {
      final row = await getWallet(userId);
      if (row != null) return row;
      rethrow;
    }
  }

  /// Sync real XRP balance from ledger via edge function
  static Future<Map<String, dynamic>?> syncBalance(String userId) async {
    if (authToken == null) return null;
    try {
      final res = await _client.functions.invoke('balance_sync',
        headers: {'Authorization': 'Bearer $authToken'});
      return res.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('balance_sync error: $e');
      return null;
    }
  }

  /// Update wallet balance locally in Supabase (after local ops)
  static Future<void> updateWalletBalance(
      String userId, double newBalanceDC) async {
    await _client.from('wallets')
      .update({'balance_dc': newBalanceDC})
      .eq('user_id', userId);
  }

  // ── Transactions ──────────────────────────────────────────────────────────
  static Future<void> saveTransaction(Map<String, dynamic> txData) async {
    try {
      await _client.from('transactions').insert({
        'user_id':    txData['user_id'],
        'type':       txData['type'],
        'amount_dc':  txData['amount_dc'],
        'amount_zar': txData['amount_zar'],
        'fee_dc':     txData['fee_dc'] ?? 0,
        'status':     txData['status'] ?? 'completed',
        'reference':  txData['reference'],
        'metadata':   txData['metadata'],
      });
    } catch (e) {
      debugPrint('saveTransaction error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getTransactions(
      String userId, {int limit = 50}) async {
    try {
      return List<Map<String, dynamic>>.from(
        await _client.from('transactions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit));
    } catch (_) { return []; }
  }

  // ── Send Money (P2P via edge function) ───────────────────────────────────
  static Future<Map<String, dynamic>> sendPayment({
    required String recipientPhone,
    required double zarAmount,
    String? memo,
  }) async {
    final res = await _client.functions.invoke('send_payment',
      headers: {'Authorization': 'Bearer $authToken'},
      body: {
        'recipientPhone': recipientPhone,
        'zarAmount':      zarAmount,
        'memo':           memo,
      });
    return res.data as Map<String, dynamic>;
  }

  // ── Cash Out (via edge function → EFT) ───────────────────────────────────
  static Future<Map<String, dynamic>> cashOut({
    required double zarAmount,
    required String accountName,
    required String accountNumber,
    required String bankName,
  }) async {
    final res = await _client.functions.invoke('cashout',
      headers: {'Authorization': 'Bearer $authToken'},
      body: {
        'zarAmount':     zarAmount,
        'accountName':   accountName,
        'accountNumber': accountNumber,
        'bankName':      bankName,
      });
    return res.data as Map<String, dynamic>;
  }

  // ── Top Up — get EFT bank details ────────────────────────────────────────
  static Future<Map<String, dynamic>?> getEftDetails(String userId) async {
    try {
      // GET: the function reads the signed-in user from the token itself.
      final res = await _client.functions.invoke('topup',
        method: HttpMethod.get,
        headers: {'Authorization': 'Bearer $authToken'});
      return res.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('getEftDetails error: $e');
      return null;
    }
  }

  // ── Tickets ───────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getMyTickets(
      String userId) async {
    try {
      return List<Map<String, dynamic>>.from(
        await _client.from('tickets')
          .select('*, events(name, venue, city, event_date, image_url)')
          .eq('user_id', userId)
          .order('created_at', ascending: false));
    } catch (_) { return []; }
  }

  static Future<List<Map<String, dynamic>>> getTicketsForSale() async {
    try {
      return List<Map<String, dynamic>>.from(
        await _client.from('tickets')
          .select('*, events(name, venue, city, event_date, image_url)')
          .eq('is_for_sale', true)
          .order('created_at', ascending: false));
    } catch (_) { return []; }
  }

  static Future<void> listTicketForSale(
      String ticketId, double priceZAR) async {
    await _client.from('tickets').update({
      'is_for_sale':      true,
      'resale_price_zar': priceZAR,
      'status':           'listed_for_sale',
    }).eq('id', ticketId);
  }

  static Future<void> cancelTicketListing(String ticketId) async {
    await _client.from('tickets').update({
      'is_for_sale':      false,
      'resale_price_zar': null,
      'status':           'active',
    }).eq('id', ticketId);
  }

  static Future<void> mintTicket({
    required String eventId,
    required String tier,
    required double priceZAR,
  }) async {
    await _client.functions.invoke('mint_ticket',
      headers: {'Authorization': 'Bearer $authToken'},
      body: {'eventId': eventId, 'tier': tier, 'priceZAR': priceZAR});
  }

  // ── Events ────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getEvents({
    String? category, int limit = 30,
  }) async {
    try {
      var q = _client.from('events')
        .select()
        .eq('is_published', true)
        .order('event_date', ascending: true)
        .limit(limit);
      return List<Map<String, dynamic>>.from(await q);
    } catch (_) { return []; }
  }

  /// Events the signed-in user organizes — used to populate the gate
  /// dashboard's event picker so an organizer running several events can
  /// switch between them.
  static Future<List<Map<String, dynamic>>> getMyEvents() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    try {
      return List<Map<String, dynamic>>.from(
        await _client.from('events')
          .select()
          .eq('organizer_id', uid)
          .order('event_date', ascending: false));
    } catch (_) { return []; }
  }

  // ── Real-time balance subscription ────────────────────────────────────────
  static RealtimeChannel subscribeToWallet(
      String userId, void Function(double) onUpdate) {
    return _client
      .channel('wallet_$userId')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public', table: 'wallets',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id', value: userId),
        callback: (payload) {
          final balance = payload.newRecord['balance_dc'];
          if (balance != null) onUpdate(double.parse(balance.toString()));
        })
      .subscribe();
  }

  // ── Storage ───────────────────────────────────────────────────────────────
  static Future<String> uploadAvatar(
      String userId, Uint8List bytes) async {
    final path = 'avatars/$userId.jpg';
    await _client.storage.from('delight-images').uploadBinary(
      path, bytes,
      fileOptions: const FileOptions(
        contentType: 'image/jpeg', upsert: true),
    );
    return _client.storage.from('delight-images').getPublicUrl(path);
  }

  static Future<String> uploadEventImage(
      String eventId, Uint8List bytes, String ext) async {
    final path = 'events/$eventId.$ext';
    await _client.storage.from('delight-images').uploadBinary(
      path, bytes,
      fileOptions: FileOptions(contentType: 'image/$ext'),
    );
    return _client.storage.from('delight-images').getPublicUrl(path);
  }

  // ── Messaging ──────────────────────────────────────────────────────────────
  static List<Map<String, dynamic>> _list(dynamic r) => List<Map<String, dynamic>>.from(
    (r as List).map((e) => Map<String, dynamic>.from(e as Map)));

  /// Rows: conversation_id, name, is_group, avatar_emoji, avatar_url,
  /// event_id, last_message, last_message_at, unread_count.
  static Future<List<Map<String, dynamic>>> getConversations() async {
    if (currentUser == null) return [];
    try { return _list(await _client.rpc('get_my_conversations')); }
    catch (_) { return []; }
  }

  static Future<String> getOrCreateDM(String otherUserId) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    try {
      final id = await _client.rpc('get_or_create_dm',
        params: {'user_a': uid, 'user_b': otherUserId});
      return id as String;
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Oldest-first. Rows: id, content, created_at, sender_id, sender_name,
  /// sender_avatar.
  static Future<List<Map<String, dynamic>>> getMessages(
    String conversationId, {int limit = 50}) async {
    try {
      final rows = _list(await _client.rpc('get_conversation_messages',
        params: {'p_conv': conversationId, 'p_limit': limit}));
      return rows.reversed.toList();
    } catch (_) { return []; }
  }

  static Future<void> sendMessage({
    required String conversationId, required String content}) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not signed in');
    await _client.from('messages').insert({
      'conversation_id': conversationId, 'sender_id': uid, 'content': content,
    });
  }

  /// Live new-message feed for one conversation.
  static RealtimeChannel subscribeToMessages(
      String conversationId, void Function() onNew) {
    return _client.channel('msgs_$conversationId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public', table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'conversation_id', value: conversationId),
        callback: (_) => onNew())
      .subscribe();
  }

  static Future<void> markRead(String conversationId) async {
    final uid = currentUser?.id;
    if (uid == null) return;
    try {
      await _client.from('conversation_members')
        .update({'unread_count': 0})
        .eq('conversation_id', conversationId).eq('user_id', uid);
    } catch (_) {}
  }

  /// Find people by name / @username (phone numbers are not searchable).
  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.trim().length < 2) return [];
    try { return _list(await _client.rpc('search_people', params: {'p_query': query})); }
    catch (_) { return []; }
  }

  static Future<List<Map<String, dynamic>>> getRecentContacts() async {
    if (currentUser == null) return [];
    try { return _list(await _client.rpc('get_recent_contacts')); }
    catch (_) { return []; }
  }

  static Future<String?> uploadImage(String bucket, String path, List<int> bytes) async {
    try {
      await _client.storage.from(bucket).uploadBinary(path, bytes as Uint8List);
      return _client.storage.from(bucket).getPublicUrl(path);
    } catch (_) { return null; }
  }

  // ── Social feed ──────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getFeed({int limit = 30}) async {
    try {
      final rows = await _client.from('posts')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) { return []; }
  }

  static Future<Map<String, dynamic>?> createPost({
    required String content,
    List<String> imageUrls = const [],
    String? eventId,
    String? eventName,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) return null;
    try {
      final profile = await getProfile(uid);
      final row = await _client.from('posts').insert({
        'user_id':           uid,
        'user_display_name': profile?['display_name'],
        'user_avatar_url':   profile?['avatar_url'],
        'content':           content,
        'image_urls':        imageUrls,
        'event_id':          eventId,
        'event_name':        eventName,
      }).select().single();
      return row;
    } catch (_) { return null; }
  }

  static Future<bool> toggleLike(String postId) async {
    final uid = currentUser?.id;
    if (uid == null) return false;
    try {
      final existing = await _client.from('post_likes')
        .select('post_id').eq('post_id', postId).eq('user_id', uid).maybeSingle();
      if (existing != null) {
        await _client.from('post_likes').delete()
          .eq('post_id', postId).eq('user_id', uid);
        return false;
      } else {
        await _client.from('post_likes').insert({'post_id': postId, 'user_id': uid});
        return true;
      }
    } catch (_) { return false; }
  }

  static Future<Set<String>> getLikedPostIds(List<String> postIds) async {
    final uid = currentUser?.id;
    if (uid == null || postIds.isEmpty) return {};
    try {
      final rows = await _client.from('post_likes')
        .select('post_id').eq('user_id', uid).inFilter('post_id', postIds);
      return Set<String>.from((rows as List).map((r) => r['post_id'] as String));
    } catch (_) { return {}; }
  }

  // ── Ticket resale ────────────────────────────────────────────────────────
  /// Atomically transfers a listed resale ticket to the current user and
  /// moves ZAR between both wallets server-side (Postgres function — a
  /// buyer's own session can't update someone else's ticket/wallet row
  /// under RLS, so this has to run as a security-definer RPC).
  static Future<Map<String, dynamic>> buyResaleTicket(String ticketId) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not signed in');
    final row = await _client.rpc('buy_resale_ticket',
      params: {'p_ticket_id': ticketId, 'p_buyer_id': uid});
    return Map<String, dynamic>.from(row as Map);
  }

  // ── Gate staff (event check-in roster) ───────────────────────────────────
  /// All gate-staff rows for events the current user organizes. RLS already
  /// scopes this to the caller's own events — no separate Auth account
  /// needed per staffer, the PIN just identifies who's using the device.
  static Future<List<Map<String, dynamic>>> getGateStaff() async {
    try {
      // PINs are hashed server-side and never readable by the app.
      return List<Map<String, dynamic>>.from(
        await _client.from('gate_staff')
          .select('id, event_id, name, gate_name, events(name)')
          .order('gate_name'));
    } catch (_) { return []; }
  }

  static Future<void> addGateStaff({
    required String eventId, required String name,
    required String gateName, required String pin,
  }) async {
    try {
      await _client.rpc('add_gate_staff', params: {
        'p_event': eventId, 'p_name': name, 'p_gate': gateName, 'p_pin': pin});
    } on PostgrestException catch (e) { throw Exception(e.message); }
  }

  static Future<void> setGateStaffPin(String staffId, String pin) async {
    try {
      await _client.rpc('set_gate_staff_pin',
        params: {'p_staff': staffId, 'p_pin': pin});
    } on PostgrestException catch (e) { throw Exception(e.message); }
  }

  static Future<void> removeGateStaff(String staffId) async {
    try { await _client.rpc('remove_gate_staff', params: {'p_staff': staffId}); }
    on PostgrestException catch (e) { throw Exception(e.message); }
  }

  /// Returns the staff row, or throws with a readable message
  /// ('NO_STAFF' when the event has nobody set up yet).
  static Future<Map<String, dynamic>> gatePinLogin(String eventId, String pin) async {
    try {
      final r = Map<String, dynamic>.from(await _client.rpc('gate_pin_login',
        params: {'p_event': eventId, 'p_pin': pin}) as Map);
      if (r['error'] != null) throw Exception(r['error']);
      return r;
    } on PostgrestException catch (e) { throw Exception(e.message); }
  }

  /// Looks a ticket up by its token/ticket id scoped to one event, marks it
  /// used if it's a first scan, and always logs the attempt (admitted,
  /// already-used, or invalid) so the gate dashboard has a real audit trail.
  static Future<Map<String, dynamic>> checkInTicket({
    required String tokenOrTicketId,
    required String eventId,
    String? staffId,
    String? gateName,
  }) async {
    // Runs server-side (gate_check_in): the organiser's session cannot read
    // other people's tickets under RLS, and the row lock stops two gates
    // admitting the same ticket.
    try {
      final r = await _client.rpc('gate_check_in', params: {
        'p_event': eventId, 'p_token': tokenOrTicketId,
        'p_staff': staffId, 'p_gate': gateName,
      });
      return Map<String, dynamic>.from(r as Map);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Real aggregate numbers for the organizer's gate dashboard — replaces
  /// the old hardcoded per-gate demo data.
  static Future<Map<String, dynamic>> getGateDashboard(String eventId) async {
    final checkins = await _client.from('gate_checkins')
      .select('gate_name, result, scanned_at')
      .eq('event_id', eventId);

    final rows = List<Map<String, dynamic>>.from(checkins);
    final byGate = <String, Map<String, dynamic>>{};
    var totalAdmitted = 0, totalRejected = 0;
    final now = DateTime.now();

    for (final r in rows) {
      final gate = r['gate_name'] as String? ?? 'Unknown Gate';
      final result = r['result'] as String;
      final scannedAt = DateTime.tryParse(r['scanned_at'] as String? ?? '');
      final g = byGate.putIfAbsent(gate, () => {
        'name': gate, 'admitted': 0, 'rejected': 0, 'lastScan': null,
      });
      if (result == 'admitted') {
        g['admitted'] = (g['admitted'] as int) + 1;
        totalAdmitted++;
      } else {
        g['rejected'] = (g['rejected'] as int) + 1;
        totalRejected++;
      }
      final last = g['lastScan'] as DateTime?;
      if (scannedAt != null && (last == null || scannedAt.isAfter(last))) {
        g['lastScan'] = scannedAt;
      }
    }

    // A gate counts as "online" if it logged a scan in the last 10 minutes,
    // or hasn't scanned at all yet (nothing to say it's offline).
    for (final g in byGate.values) {
      final last = g['lastScan'] as DateTime?;
      g['isOnline'] = last == null || now.difference(last).inMinutes < 10;
    }

    int capacity = 0;
    try {
      final event = await _client.from('events')
        .select('ticket_tiers').eq('id', eventId).single();
      final tiers = event['ticket_tiers'] as List? ?? [];
      for (final t in tiers) {
        capacity += (t['totalTickets'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}

    return {
      'totalAdmitted': totalAdmitted,
      'totalRejected': totalRejected,
      'capacity':      capacity,
      'gates':         byGate.values.toList(),
    };
  }

  // ── Analytics (real usage telemetry) ───────────────────────────────────────
  //
  // One session id per app launch, generated client-side and kept for the
  // life of the process. Every screen navigation and the initial app-open
  // write a row — this is what the admin dashboard's Time Spent and Return
  // Visits tabs aggregate over, replacing numbers that used to be entirely
  // invented. Writes are fire-and-forget: analytics must never block or
  // crash the app it's trying to measure.
  static String? _sessionId;
  static String get sessionId => _sessionId ??= const Uuid().v4();

  static Future<void> logAppOpen() => _logEvent('app_open', null);
  static Future<void> logScreenView(String screen) => _logEvent('screen_view', screen);

  static Future<void> _logEvent(String eventType, String? screen) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _client.from('analytics_events').insert({
        'user_id': uid, 'session_id': sessionId,
        'event_type': eventType, 'screen': screen,
      });
    } catch (_) {
      // Never let telemetry failures affect the app itself.
    }
  }

  /// Real numbers for the admin Overview tab — total users, revenue,
  /// XRP volume, DAU, NFT tickets minted, plus the live transaction feed,
  /// top users by volume, revenue-by-day, and the revenue-stream split by
  /// transaction type. All computed from `profiles`/`transactions`/`tickets`,
  /// not simulated.
  static Future<Map<String, dynamic>> getAdminOverview() async {
    final now = DateTime.now();
    final since7d  = now.subtract(const Duration(days: 7)).toIso8601String();
    final since14d = now.subtract(const Duration(days: 14)).toIso8601String();
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();

    final totalUsers = (List<Map<String, dynamic>>.from(
      await _client.from('profiles').select('id'))).length;

    final tx7d = List<Map<String, dynamic>>.from(await _client
      .from('transactions').select('type,amount_zar,fee_dc,created_at')
      .gte('created_at', since7d).eq('status', 'completed'));
    final revenue7d = tx7d.fold(0.0, (s, t) => s + ((t['fee_dc'] as num?)?.toDouble() ?? 0));
    final xrpVolume7d = tx7d
      .where((t) => t['type'] == 'topup' || t['type'] == 'cashout')
      .fold(0.0, (s, t) => s + ((t['amount_zar'] as num?)?.toDouble() ?? 0));

    final dauRows = await _client.from('analytics_events')
      .select('user_id').eq('event_type', 'app_open').gte('created_at', todayStart);
    final dau = (List<Map<String, dynamic>>.from(dauRows))
      .map((r) => r['user_id']).toSet().length;

    final nftTickets = (List<Map<String, dynamic>>.from(await _client
      .from('tickets').select('id').neq('status', 'pending_mint'))).length;

    final recentTx = List<Map<String, dynamic>>.from(await _client
      .from('transactions')
      .select('type,amount_zar,status,created_at,profiles(display_name)')
      .order('created_at', ascending: false).limit(12));

    final tx14d = List<Map<String, dynamic>>.from(await _client
      .from('transactions').select('type,amount_zar,fee_dc,created_at')
      .gte('created_at', since14d).eq('status', 'completed'));
    final revenueByDay = List.generate(14, (i) {
      final dayStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: 13 - i));
      final dayEnd = dayStart.add(const Duration(days: 1));
      final dayTx = tx14d.where((t) {
        final ts = DateTime.tryParse(t['created_at'] as String? ?? '');
        return ts != null && !ts.isBefore(dayStart) && ts.isBefore(dayEnd);
      });
      return dayTx.fold(0.0, (s, t) => s + ((t['fee_dc'] as num?)?.toDouble() ?? 0));
    });

    final streamTotals = <String, double>{};
    for (final t in tx7d) {
      final type = t['type'] as String? ?? 'other';
      streamTotals[type] = (streamTotals[type] ?? 0) + ((t['fee_dc'] as num?)?.toDouble() ?? 0);
    }

    final topUsersRaw = await _client.rpc('get_top_users_by_volume', params: {'p_limit': 5})
      .then((r) => List<Map<String, dynamic>>.from(r as List))
      .catchError((_) => <Map<String, dynamic>>[]);

    return {
      'totalUsers': totalUsers,
      'revenue7d': revenue7d,
      'xrpVolume7d': xrpVolume7d,
      'dau': dau,
      'nftTickets': nftTickets,
      'recentTx': recentTx,
      'revenueByDay': revenueByDay,
      'revenueStreams': streamTotals,
      'topUsers': topUsersRaw,
    };
  }

  /// Real signup counts by city — "User Geography" used to be six hardcoded
  /// African cities with made-up percentages. `profiles.city` is optional
  /// (most users won't have set one yet pre-launch), so this returns however
  /// much real data exists rather than padding it out.
  static Future<List<Map<String, dynamic>>> getUserGeography() async {
    final rows = List<Map<String, dynamic>>.from(
      await _client.from('profiles').select('city').not('city', 'is', null));
    final counts = <String, int>{};
    for (final r in rows) {
      final city = (r['city'] as String?)?.trim();
      if (city == null || city.isEmpty) continue;
      counts[city] = (counts[city] ?? 0) + 1;
    }
    final total = counts.values.fold(0, (s, c) => s + c);
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(8).map((e) => {
      'city': e.key, 'count': e.value,
      'pct': total > 0 ? e.value / total : 0.0,
    }).toList();
  }

  /// Real screen-view share — "Feature Usage" used to be a fixed set of
  /// made-up percentages across six screens.
  static Future<List<Map<String, dynamic>>> getFeatureUsage() async {
    final since = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
    final rows = List<Map<String, dynamic>>.from(await _client
      .from('analytics_events').select('screen')
      .eq('event_type', 'screen_view').gte('created_at', since));
    final counts = <String, int>{};
    for (final r in rows) {
      final screen = r['screen'] as String?;
      if (screen == null) continue;
      counts[screen] = (counts[screen] ?? 0) + 1;
    }
    final total = counts.values.fold(0, (s, c) => s + c);
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(8).map((e) => {
      'screen': e.key, 'count': e.value,
      'pct': total > 0 ? e.value / total : 0.0,
    }).toList();
  }

  /// Real session-length stats, computed from first/last event per
  /// session id — replaces the old fixed "4m 32s avg session" style numbers.
  static Future<Map<String, dynamic>> getTimeSpentStats() async {
    final since = DateTime.now().subtract(const Duration(days: 14)).toIso8601String();
    final rows = List<Map<String, dynamic>>.from(await _client
      .from('analytics_events').select('session_id,created_at')
      .gte('created_at', since));

    final bySession = <String, List<DateTime>>{};
    for (final r in rows) {
      final sid = r['session_id'] as String?;
      final ts  = DateTime.tryParse(r['created_at'] as String? ?? '');
      if (sid == null || ts == null) continue;
      (bySession[sid] ??= []).add(ts);
    }

    final sessionLengths = <int>[]; // seconds
    for (final times in bySession.values) {
      if (times.length < 2) continue;
      times.sort();
      sessionLengths.add(times.last.difference(times.first).inSeconds);
    }

    double avgSeconds = 0;
    if (sessionLengths.isNotEmpty) {
      avgSeconds = sessionLengths.reduce((a, b) => a + b) / sessionLengths.length;
    }

    // Avg session length per day, for the last 14 days.
    final byDay = <String, List<int>>{};
    for (final entry in bySession.entries) {
      final times = entry.value..sort();
      if (times.length < 2) continue;
      final day = DateTime(times.first.year, times.first.month, times.first.day)
        .toIso8601String().substring(0, 10);
      (byDay[day] ??= []).add(times.last.difference(times.first).inSeconds);
    }
    final now = DateTime.now();
    final dailyAvg = List.generate(14, (i) {
      final day = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: 13 - i)).toIso8601String().substring(0, 10);
      final lens = byDay[day];
      if (lens == null || lens.isEmpty) return 0.0;
      return lens.reduce((a, b) => a + b) / lens.length;
    });

    return {
      'avgSessionSeconds': avgSeconds,
      'sessionCount': sessionLengths.length,
      'longestSessionSeconds': sessionLengths.isEmpty
        ? 0 : sessionLengths.reduce((a, b) => a > b ? a : b),
      'totalSecondsLogged': sessionLengths.fold(0, (s, v) => s + v),
      'dailyAvgSeconds': dailyAvg,
      'sessionLengths': sessionLengths.take(500).toList(),
      'featureUsage': await getFeatureUsage(),
    };
  }

  /// Real opens-per-day and opens-per-user, for the Return Visits tab.
  static Future<Map<String, dynamic>> getReturnVisitStats() async {
    final now = DateTime.now();
    final since14d = now.subtract(const Duration(days: 14)).toIso8601String();
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();

    final opens = List<Map<String, dynamic>>.from(await _client
      .from('analytics_events').select('user_id,created_at')
      .eq('event_type', 'app_open').gte('created_at', since14d));

    final opensByDay = List.generate(14, (i) {
      final dayStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: 13 - i));
      final dayEnd = dayStart.add(const Duration(days: 1));
      return opens.where((o) {
        final ts = DateTime.tryParse(o['created_at'] as String? ?? '');
        return ts != null && !ts.isBefore(dayStart) && ts.isBefore(dayEnd);
      }).length;
    });

    final opensToday = opens.where((o) {
      final ts = DateTime.tryParse(o['created_at'] as String? ?? '');
      return ts != null && !ts.isBefore(DateTime.parse(todayStart));
    }).toList();

    final opensPerUserToday = <String, int>{};
    for (final o in opensToday) {
      final uid = o['user_id'] as String?;
      if (uid == null) continue;
      opensPerUserToday[uid] = (opensPerUserToday[uid] ?? 0) + 1;
    }

    return {
      'opensByDay': opensByDay,
      'opensToday': opensToday.length,
      'activeUsersToday': opensPerUserToday.length,
      'opensPerUser': opensPerUserToday.values.toList(),
    };
  }

  /// Admin-entered business figures (e.g. customer-acquisition cost, NPS)
  /// that have no product-table source. Returns null for any key not yet set
  /// — the Scale Readiness tab shows "not set" rather than a fake default.
  static Future<Map<String, double?>> getAdminSettings(List<String> keys) async {
    try {
      final rows = List<Map<String, dynamic>>.from(
        await _client.from('admin_settings').select().inFilter('key', keys));
      final map = {for (final r in rows) r['key'] as String: (r['value'] as num?)?.toDouble()};
      return {for (final k in keys) k: map[k]};
    } catch (_) {
      return {for (final k in keys) k: null};
    }
  }

  static Future<void> setAdminSetting(String key, double value) async {
    await _client.from('admin_settings').upsert({'key': key, 'value': value});
  }

  /// Real operational alerts — replaces a hardcoded list of fake FICA/KYC/
  /// webhook warnings. Each is a genuine threshold check against live data.
  static Future<List<Map<String, dynamic>>> getAdminAlerts() async {
    final alerts = <Map<String, dynamic>>[];
    final since30d = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
    final since7d  = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();

    // FICA threshold — SA's R25,000 single-transaction / aggregated trigger.
    try {
      final tx30d = List<Map<String, dynamic>>.from(await _client
        .from('transactions').select('user_id,amount_zar')
        .gte('created_at', since30d).eq('status', 'completed'));
      final byUser = <String, double>{};
      for (final t in tx30d) {
        final uid = t['user_id'] as String?;
        if (uid == null) continue;
        byUser[uid] = (byUser[uid] ?? 0) + ((t['amount_zar'] as num?)?.toDouble() ?? 0);
      }
      final overThreshold = byUser.values.where((v) => v > 25000).length;
      if (overThreshold > 0) {
        alerts.add({
          'icon': '⚠️', 'title': 'FICA Trigger',
          'message': '$overThreshold user${overThreshold > 1 ? 's' : ''} crossed R25,000 '
            'in 30-day volume — KYC required',
          'level': 'error',
        });
      }
    } catch (_) {}

    // KYC queue — unverified profiles.
    try {
      final unverified = (List<Map<String, dynamic>>.from(await _client
        .from('profiles').select('id').eq('is_verified', false))).length;
      if (unverified > 0) {
        alerts.add({
          'icon': '🔔', 'title': 'KYC Queue',
          'message': '$unverified unverified profile${unverified > 1 ? 's' : ''}',
          'level': 'warning',
        });
      }
    } catch (_) {}

    // Inactive business/organizer accounts — zero transactions in 7 days.
    try {
      final agents = List<Map<String, dynamic>>.from(await _client
        .from('profiles').select('id').inFilter('role', ['business', 'organizer']));
      final activeIds = List<Map<String, dynamic>>.from(await _client
        .from('transactions').select('user_id')
        .gte('created_at', since7d).eq('status', 'completed'))
        .map((t) => t['user_id']).toSet();
      final inactive = agents.where((a) => !activeIds.contains(a['id'])).length;
      if (inactive > 0) {
        alerts.add({
          'icon': '💤', 'title': 'Agent Inactive',
          'message': '$inactive business/organizer account${inactive > 1 ? 's' : ''} with '
            'zero transactions in 7 days',
          'level': 'muted',
        });
      }
    } catch (_) {}

    if (alerts.isEmpty) {
      alerts.add({
        'icon': '✅', 'title': 'All Clear',
        'message': 'No threshold alerts right now', 'level': 'ok',
      });
    }
    return alerts;
  }

  /// Growth/retention metrics for the Scale Readiness tab — computed from
  /// real signup dates, transaction history, and app-open telemetry. CAC and
  /// NPS have no source table (they're business inputs) and are read
  /// separately via getAdminSettings.
  static Future<Map<String, dynamic>> getGrowthStats() async {
    final now = DateTime.now();

    final totalUsers = (List<Map<String, dynamic>>.from(
      await _client.from('profiles').select('id'))).length;

    // P-E-T: % of users with at least one completed transaction ever.
    final txUserRows = List<Map<String, dynamic>>.from(
      await _client.from('transactions').select('user_id').eq('status', 'completed'));
    final petUsers = txUserRows.map((t) => t['user_id']).toSet().length;
    final petScore = totalUsers > 0 ? petUsers / totalUsers * 100 : 0.0;

    // Month-on-month signup growth.
    final thisMonthStart = DateTime(now.year, now.month, 1).toIso8601String();
    final lastMonthStart = DateTime(now.year, now.month - 1, 1).toIso8601String();
    final thisMonthCount = (List<Map<String, dynamic>>.from(await _client
      .from('profiles').select('id').gte('created_at', thisMonthStart))).length;
    final lastMonthCount = (List<Map<String, dynamic>>.from(await _client
      .from('profiles').select('id')
      .gte('created_at', lastMonthStart).lt('created_at', thisMonthStart))).length;
    final momGrowth = lastMonthCount > 0
      ? (thisMonthCount - lastMonthCount) / lastMonthCount : null;

    // Retention: of users who signed up ≥30/≥90 days ago, % with an
    // app_open in the 30/90 days after signup. Approximated here as: %
    // with ANY app_open at all after their first week (a simple, honest
    // proxy given there's no cohort-window tracking yet).
    double? retention30d, retention90d;
    try {
      final cohort30 = List<Map<String, dynamic>>.from(await _client
        .from('profiles').select('id,created_at')
        .lt('created_at', now.subtract(const Duration(days: 30)).toIso8601String()));
      if (cohort30.isNotEmpty) {
        final activeUsers = List<Map<String, dynamic>>.from(await _client
          .from('analytics_events').select('user_id')
          .eq('event_type', 'app_open')
          .gte('created_at', now.subtract(const Duration(days: 30)).toIso8601String()))
          .map((e) => e['user_id']).toSet();
        final retained = cohort30.where((p) => activeUsers.contains(p['id'])).length;
        retention30d = retained / cohort30.length;
      }
      final cohort90 = List<Map<String, dynamic>>.from(await _client
        .from('profiles').select('id,created_at')
        .lt('created_at', now.subtract(const Duration(days: 90)).toIso8601String()));
      if (cohort90.isNotEmpty) {
        final activeUsers90 = List<Map<String, dynamic>>.from(await _client
          .from('analytics_events').select('user_id')
          .eq('event_type', 'app_open')
          .gte('created_at', now.subtract(const Duration(days: 90)).toIso8601String()))
          .map((e) => e['user_id']).toSet();
        final retained90 = cohort90.where((p) => activeUsers90.contains(p['id'])).length;
        retention90d = retained90 / cohort90.length;
      }
    } catch (_) {}

    // Revenue per user — an honest proxy for LTV (not a projected lifetime
    // value, just what's actually been earned per user so far).
    final allTx = List<Map<String, dynamic>>.from(
      await _client.from('transactions').select('amount_zar,fee_dc,user_id,created_at')
        .eq('status', 'completed'));
    final totalRevenue = allTx.fold(0.0, (s, t) => s + ((t['fee_dc'] as num?)?.toDouble() ?? 0));
    final revenuePerUser = totalUsers > 0 ? totalRevenue / totalUsers : 0.0;

    final since30 = now.subtract(const Duration(days: 30)).toIso8601String();
    final tx30 = allTx.where((t) {
      final ts = DateTime.tryParse(t['created_at'] as String? ?? '');
      return ts != null && ts.isAfter(DateTime.parse(since30));
    }).toList();
    final revenue30d = tx30.fold(0.0, (s, t) => s + ((t['fee_dc'] as num?)?.toDouble() ?? 0));
    final activeUsers30d = tx30.map((t) => t['user_id']).toSet().length;
    final monthlyRevenuePerActiveUser =
      activeUsers30d > 0 ? revenue30d / activeUsers30d : 0.0;

    return {
      'totalUsers': totalUsers,
      'petScore': petScore,
      'momGrowth': momGrowth,
      'retention30d': retention30d,
      'retention90d': retention90d,
      'revenuePerUser': revenuePerUser,
      'monthlyRevenuePerActiveUser': monthlyRevenuePerActiveUser,
    };
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Profile: followers / following / posts / events  (real, server-side)
  // ══════════════════════════════════════════════════════════════════════════

  static List<Map<String, dynamic>> _rows(dynamic r) =>
    List<Map<String, dynamic>>.from((r as List).map((e) => Map<String, dynamic>.from(e as Map)));

  /// {followers, following, posts, events} — computed live in Postgres.
  static Future<Map<String, int>> getProfileStats(String userId) async {
    try {
      final r = Map<String, dynamic>.from(
        await _client.rpc('get_profile_stats', params: {'p_user': userId}) as Map);
      int n(String k) => (r[k] as num?)?.toInt() ?? 0;
      return {'followers': n('followers'), 'following': n('following'),
              'posts': n('posts'), 'events': n('events')};
    } catch (_) {
      return {'followers': 0, 'following': 0, 'posts': 0, 'events': 0};
    }
  }

  static Future<List<Map<String, dynamic>>> getFollowers(String userId) async {
    try { return _rows(await _client.rpc('get_followers', params: {'p_user': userId})); }
    catch (_) { return []; }
  }

  static Future<List<Map<String, dynamic>>> getFollowing(String userId) async {
    try { return _rows(await _client.rpc('get_following', params: {'p_user': userId})); }
    catch (_) { return []; }
  }

  static Future<List<Map<String, dynamic>>> searchPeople(String query) async {
    try { return _rows(await _client.rpc('search_people', params: {'p_query': query})); }
    catch (_) { return []; }
  }

  static Future<List<Map<String, dynamic>>> getProfileEvents(String userId) async {
    try { return _rows(await _client.rpc('get_profile_events', params: {'p_user': userId})); }
    catch (_) { return []; }
  }

  static Future<List<Map<String, dynamic>>> getUserPosts(String userId,
      {int limit = 50}) async {
    try {
      return _rows(await _client.from('posts').select()
        .eq('user_id', userId)
        .order('created_at', ascending: false).limit(limit));
    } catch (_) { return []; }
  }

  /// Returns true if the follow/unfollow succeeded.
  static Future<bool> setFollowing(String targetId, bool follow) async {
    final uid = currentUser?.id;
    if (uid == null || uid == targetId) return false;
    try {
      if (follow) {
        await _client.from('follows')
          .upsert({'follower_id': uid, 'followee_id': targetId});
      } else {
        await _client.from('follows').delete()
          .eq('follower_id', uid).eq('followee_id', targetId);
      }
      return true;
    } catch (_) { return false; }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Rewards & leaderboard (tasks verified and credited server-side)
  // ══════════════════════════════════════════════════════════════════════════

  /// {tasks:[{id,title,description,emoji,reward,claimed,eligible}], streak,
  ///  week:[7 bools Mon..Sun], today_index, earned_today}. Null on failure.
  static Future<Map<String, dynamic>?> getRewardsToday() async {
    try {
      return Map<String, dynamic>.from(await _client.rpc('get_rewards_today') as Map);
    } catch (_) { return null; }
  }

  /// Claims a verified task. Throws a readable message on failure.
  static Future<double> claimRewardTask(String taskId) async {
    try {
      final r = Map<String, dynamic>.from(
        await _client.rpc('claim_reward_task', params: {'p_task_id': taskId}) as Map);
      return (r['reward'] as num).toDouble();
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  static Future<Map<String, dynamic>?> getMyStats() async {
    try {
      return Map<String, dynamic>.from(await _client.rpc('get_my_stats') as Map);
    } catch (_) { return null; }
  }

  static Future<List<Map<String, dynamic>>> getLeaderboard(
      {String? city, required String period}) async {
    try {
      return _rows(await _client.rpc('get_leaderboard',
        params: {'p_city': city, 'p_period': period}));
    } catch (_) { return []; }
  }

  static Future<List<String>> getLeaderboardCities() async {
    try {
      return List<String>.from(await _client.rpc('get_leaderboard_cities') as List);
    } catch (_) { return []; }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Event / Indoor insights
  // ══════════════════════════════════════════════════════════════════════════

  /// All aggregates for one event (organiser/admin only — enforced in SQL).
  /// Throws on failure so the screen can show an error instead of zeros.
  static Future<Map<String, dynamic>> getEventInsights(String eventId) async {
    try {
      return Map<String, dynamic>.from(
        await _client.rpc('get_event_insights', params: {'p_event_id': eventId}) as Map);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Pay a vendor at an event. Tags the payment so it shows up in insights.
  static Future<void> payEventVendor(String vendorId, double zar,
      {String? staffId}) async {
    try {
      await _client.rpc('pay_event_vendor', params: {
        'p_vendor_id': vendorId, 'p_zar': zar, 'p_staff': staffId});
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  static Future<List<Map<String, dynamic>>> getEventVendors(String eventId) async {
    try {
      return _rows(await _client.from('event_vendors').select()
        .eq('event_id', eventId).order('name'));
    } catch (_) { return []; }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Products, itemised sales and product insights
  // ══════════════════════════════════════════════════════════════════════════

  static Map<String, dynamic> _map(dynamic r) => Map<String, dynamic>.from(r as Map);

  static Future<List<Map<String, dynamic>>> getMyProducts() async {
    final uid = currentUser?.id;
    if (uid == null) return [];
    try {
      return _rows(await _client.from('business_products').select()
        .eq('owner_id', uid).order('category').order('name'));
    } catch (_) { return []; }
  }

  /// Insert (id == null) or update a catalogue item. Throws a readable message.
  static Future<void> saveProduct({
    String? id, required String name, required String category,
    required double priceZar, String? vendorId, bool active = true,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not signed in');
    final row = {
      'owner_id': uid, 'name': name.trim(), 'category': category,
      'price_zar': priceZar, 'vendor_id': vendorId, 'active': active,
    };
    try {
      if (id == null) {
        await _client.from('business_products').insert(row);
      } else {
        await _client.from('business_products').update(row).eq('id', id);
      }
    } on PostgrestException catch (e) { throw Exception(e.message); }
  }

  static Future<List<Map<String, dynamic>>> getBusinessMenu(
      String ownerId, {String? vendorId}) async {
    try {
      return _list(await _client.rpc('get_business_menu',
        params: {'p_owner': ownerId, 'p_vendor': vendorId}));
    } catch (_) { return []; }
  }

  /// Vendors the signed-in user runs at events (to attach products to).
  static Future<List<Map<String, dynamic>>> getMyVendors() async {
    final uid = currentUser?.id;
    if (uid == null) return [];
    try {
      return _rows(await _client.from('event_vendors')
        .select('id,name,event_id,events(name)').eq('owner_id', uid));
    } catch (_) { return []; }
  }

  /// items: [{'product_id': ..., 'qty': n}]. Prices come from the catalogue
  /// on the server; the client only says WHAT and HOW MANY.
  static Future<void> payBusinessAmount(String ownerId, double zar) async {
    try {
      await _client.rpc('pay_business_amount',
        params: {'p_owner': ownerId, 'p_zar': zar});
    } on PostgrestException catch (e) { throw Exception(e.message); }
  }

  static Future<void> payEventVendorItems(
      String vendorId, List<Map<String, dynamic>> items, {String? staffId}) async {
    try {
      await _client.rpc('pay_event_vendor', params: {
        'p_vendor_id': vendorId, 'p_items': items, 'p_staff': staffId});
    } on PostgrestException catch (e) { throw Exception(e.message); }
  }

  static Future<void> payBusinessItems(
      String ownerId, List<Map<String, dynamic>> items, {String? staffId}) async {
    try {
      await _client.rpc('pay_business_items', params: {
        'p_owner': ownerId, 'p_items': items, 'p_staff': staffId});
    } on PostgrestException catch (e) { throw Exception(e.message); }
  }

  static Future<Map<String, dynamic>> getBusinessProductInsights({int days = 30}) async {
    try { return _map(await _client.rpc('get_business_product_insights', params: {'p_days': days})); }
    on PostgrestException catch (e) { throw Exception(e.message); }
  }

  static Future<Map<String, dynamic>> getEventProductInsights(String eventId) async {
    try { return _map(await _client.rpc('get_event_product_insights', params: {'p_event_id': eventId})); }
    on PostgrestException catch (e) { throw Exception(e.message); }
  }

  static Future<Map<String, dynamic>> getPlatformProductTrends({int days = 30}) async {
    try { return _map(await _client.rpc('get_platform_product_trends', params: {'p_days': days})); }
    on PostgrestException catch (e) { throw Exception(e.message); }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // AI reports (generated by the ai_insights edge function)
  // ══════════════════════════════════════════════════════════════════════════

  /// scope: 'business' | 'event' | 'platform'. Returns the stored report:
  /// {summary, recommendations:[{title, detail, impact}], created_at, cached}.
  static Future<Map<String, dynamic>> generateAiReport({
    required String scope, String? eventId, int days = 30, bool force = false,
  }) async {
    try {
      final res = await _client.functions.invoke('ai_insights',
        body: {'scope': scope, 'eventId': eventId, 'days': days, 'force': force});
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception('${data['error']}');
      return _map(data);
    } on FunctionException catch (e) {
      final d = e.details;
      throw Exception(d is Map && d['error'] != null ? '${d['error']}' : 'AI report failed');
    }
  }

  static Future<Map<String, dynamic>?> getLatestAiReport(
      {required String scope, String? eventId}) async {
    final uid = currentUser?.id;
    if (uid == null) return null;
    try {
      var q = _client.from('ai_insight_reports').select()
        .eq('owner_id', uid).eq('scope', scope);
      if (eventId != null) q = q.eq('event_id', eventId);
      final rows = await q.order('created_at', ascending: false).limit(1);
      return (rows as List).isEmpty ? null : _map(rows.first);
    } catch (_) { return null; }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Admin → organiser recommendations
  // ══════════════════════════════════════════════════════════════════════════

  /// Admin only (RLS): recent published events with their organiser.
  static Future<List<Map<String, dynamic>>> getEventsForAdmin({int limit = 30}) async {
    try {
      return _rows(await _client.from('events')
        .select('id,name,event_date,city,organizer_id')
        .not('organizer_id', 'is', null)
        .order('event_date', ascending: false).limit(limit));
    } catch (_) { return []; }
  }

  static Future<void> pushRecommendation(String eventId, String body) async {
    try {
      await _client.rpc('push_recommendation',
        params: {'p_event': eventId, 'p_body': body});
    } on PostgrestException catch (e) { throw Exception(e.message); }
  }

  static Future<List<Map<String, dynamic>>> getMyRecommendations({String? eventId}) async {
    final uid = currentUser?.id;
    if (uid == null) return [];
    try {
      var q = _client.from('organiser_messages').select().eq('organiser_id', uid);
      if (eventId != null) q = q.eq('event_id', eventId);
      return _rows(await q.order('created_at', ascending: false).limit(20));
    } catch (_) { return []; }
  }

  static Future<void> markRecommendationRead(String id) async {
    try {
      await _client.from('organiser_messages')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Private events (weddings, birthdays …) — persisted, with public RSVP links
  // ══════════════════════════════════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> getMyPrivateEvents() async {
    final uid = currentUser?.id;
    if (uid == null) return [];
    try {
      return _rows(await _client.from('private_events')
        .select('*, private_event_guests(*)')
        .eq('host_id', uid).order('event_date'));
    } catch (_) { return []; }
  }

  /// Public invite (no sign-in needed). Null if not found.
  static Future<Map<String, dynamic>?> getPrivateEventInvite(String id) async {
    try {
      final r = await _client.rpc('get_private_event_invite', params: {'p_id': id});
      return r == null ? null : _map(r);
    } catch (_) { return null; }
  }

  static Future<Map<String, dynamic>> createPrivateEvent(Map<String, dynamic> row) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not signed in');
    try {
      return _map(await _client.from('private_events')
        .insert({...row, 'host_id': uid}).select().single());
    } on PostgrestException catch (e) { throw Exception(e.message); }
  }

  static Future<Map<String, dynamic>> addPrivateGuest(
      String eventId, String name, String phone, {String? emoji}) async {
    try {
      return _map(await _client.from('private_event_guests').insert({
        'event_id': eventId, 'name': name.trim(),
        'phone': phone.replaceAll(RegExp(r'[^0-9+]'), ''),
        'avatar_emoji': emoji}).select().single());
    } on PostgrestException catch (e) { throw Exception(e.message); }
  }

  /// Host deletes their private event (guests go with it via cascade).
  static Future<void> deletePrivateEvent(String eventId) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not signed in');
    try {
      await _client.from('private_events').delete()
        .eq('id', eventId).eq('host_id', uid);
    } on PostgrestException catch (e) { throw Exception(e.message); }
  }

  static Future<void> removePrivateGuest(String guestId) async {
    try { await _client.from('private_event_guests').delete().eq('id', guestId); }
    on PostgrestException catch (e) { throw Exception(e.message); }
  }

  /// Invite someone who is already on Delight. Their phone is read server-side
  /// and they get the invitation as an in-app message.
  static Future<Map<String, dynamic>> addPrivateGuestFromUser(
      String eventId, String userId, {String? link}) async {
    try {
      return _map(await _client.rpc('add_private_guest_from_user',
        params: {'p_event': eventId, 'p_user': userId, 'p_link': link}));
    } on PostgrestException catch (e) { throw Exception(e.message); }
  }

  /// Which of these phone numbers (from the address book) belong to Delight users.
  static Future<List<Map<String, dynamic>>> matchDelightContacts(List<String> phones) async {
    if (phones.isEmpty) return [];
    try {
      return _list(await _client.rpc('match_delight_contacts',
        params: {'p_phones': phones.take(500).toList()}));
    } catch (_) { return []; }
  }

  static Future<void> updatePrivateGuest(String guestId, Map<String, dynamic> updates) async {
    try { await _client.from('private_event_guests').update(updates).eq('id', guestId); }
    on PostgrestException catch (e) { throw Exception(e.message); }
  }

  static Future<void> submitPrivateRsvp({
    required String eventId, required String phone, required String name,
    required String rsvp, String? meal, List<String> plusNames = const [],
  }) async {
    try {
      await _client.rpc('submit_private_rsvp', params: {
        'p_event': eventId, 'p_phone': phone, 'p_name': name, 'p_rsvp': rsvp,
        'p_meal': meal, 'p_plus_names': plusNames});
    } on PostgrestException catch (e) { throw Exception(e.message); }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Comments + exclusive (ticket-gated) posts
  // ══════════════════════════════════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> getPostComments(String postId) async {
    try { return _list(await _client.rpc('get_post_comments', params: {'p_post': postId})); }
    catch (_) { return []; }
  }

  static Future<void> addPostComment(String postId, String content) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not signed in');
    try {
      await _client.from('post_comments').insert({
        'post_id': postId, 'user_id': uid, 'content': content.trim()});
    } on PostgrestException catch (e) { throw Exception(e.message); }
  }

  static Future<List<Map<String, dynamic>>> getExclusivePosts() async {
    if (currentUser == null) return [];
    try { return _list(await _client.rpc('get_exclusive_posts')); }
    catch (_) { return []; }
  }

  static Future<void> createExclusivePost({
    required String eventId, required String content,
    String? requiredTier, List<String> imageUrls = const [],
  }) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not signed in');
    try {
      await _client.from('exclusive_posts').insert({
        'event_id': eventId, 'organiser_id': uid, 'content': content.trim(),
        'required_tier': requiredTier, 'image_urls': imageUrls});
    } on PostgrestException catch (e) { throw Exception(e.message); }
  }
}
