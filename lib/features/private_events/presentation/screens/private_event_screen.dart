import '../../../../core/config/env.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/xrpl_service.dart';
import '../../../../core/services/supabase_service.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

enum PrivateEventType { wedding, birthday, babyShower, corporate, dinner, other }
enum RSVPStatus { pending, yes, no, maybe }

extension PET on PrivateEventType {
  String get label {
    switch (this) {
      case PrivateEventType.wedding: return 'Wedding';
      case PrivateEventType.birthday: return 'Birthday Party';
      case PrivateEventType.babyShower: return 'Baby Shower';
      case PrivateEventType.corporate: return 'Corporate Function';
      case PrivateEventType.dinner: return 'Dinner Party';
      case PrivateEventType.other: return 'Private Event';
    }
  }

  String get emoji {
    switch (this) {
      case PrivateEventType.wedding: return '💍';
      case PrivateEventType.birthday: return '🎂';
      case PrivateEventType.babyShower: return '👶';
      case PrivateEventType.corporate: return '💼';
      case PrivateEventType.dinner: return '🍽';
      case PrivateEventType.other: return '🎉';
    }
  }

  List<Color> get bgColors {
    switch (this) {
      case PrivateEventType.wedding: return [const Color(0xFF2A1A30), const Color(0xFF150D18)];
      case PrivateEventType.birthday: return [const Color(0xFF2A0A0A), const Color(0xFF150505)];
      case PrivateEventType.babyShower: return [const Color(0xFF001A2E), const Color(0xFF000D17)];
      case PrivateEventType.corporate: return [const Color(0xFF0D2A1A), const Color(0xFF061505)];
      case PrivateEventType.dinner: return [const Color(0xFF2A1000), const Color(0xFF150800)];
      case PrivateEventType.other: return [const Color(0xFF0D2A1A), const Color(0xFF061505)];
    }
  }

  Color get accent {
    switch (this) {
      case PrivateEventType.wedding: return const Color(0xFFE8B4D0);
      case PrivateEventType.birthday: return const Color(0xFFFF6B6B);
      case PrivateEventType.babyShower: return const Color(0xFF74B9FF);
      case PrivateEventType.corporate: return DelightColors.emerald;
      case PrivateEventType.dinner: return const Color(0xFFFF6B35);
      case PrivateEventType.other: return DelightColors.emerald;
    }
  }
}

class Guest {
  final String id, name, phone;
  final String? avatarEmoji;
  RSVPStatus rsvp;
  bool ticketMinted;
  bool inviteOpened;
  String? mealChoice;
  int plusOneCount;
  List<String> plusOneNames;

  Guest({
    required this.id,
    required this.name,
    required this.phone,
    this.avatarEmoji,
    this.rsvp = RSVPStatus.pending,
    this.ticketMinted = false,
    this.inviteOpened = false,
    this.mealChoice,
    this.plusOneCount = 0,
    this.plusOneNames = const [],
  });
}

class PrivateEvent {
  final String id, name, venue, city, message, hostName;
  final PrivateEventType type;
  final DateTime date;
  final bool isPaid;
  final List<String> mealOptions;
  final List<Guest> guests;
  final int maxPlusOnes;
  final String? coverImageUrl;  // photo attached by host
  final bool hasVideo;          // video attached

  PrivateEvent({
    required this.id,
    required this.name,
    required this.venue,
    required this.city,
    required this.message,
    required this.type,
    required this.date,
    required this.isPaid,
    required this.hostName,
    this.mealOptions = const [],
    List<Guest>? guests,
    this.maxPlusOnes = 2,
    this.coverImageUrl,
    this.hasVideo = false,
  }) : guests = guests ?? <Guest>[];
}

// ─── Row mapping ──────────────────────────────────────────────────────────────

RSVPStatus _rsvpFrom(String? v) => RSVPStatus.values.firstWhere(
  (r) => r.name == v, orElse: () => RSVPStatus.pending);

Guest guestFromRow(Map<String, dynamic> m) => Guest(
  id: '${m['id']}', name: m['name'] as String? ?? 'Guest',
  phone: m['phone'] as String? ?? '', avatarEmoji: m['avatar_emoji'] as String?,
  rsvp: _rsvpFrom(m['rsvp'] as String?),
  ticketMinted: m['ticket_minted'] as bool? ?? false,
  inviteOpened: m['invite_opened'] as bool? ?? false,
  mealChoice: m['meal_choice'] as String?,
  plusOneCount: (m['plus_one_count'] as num?)?.toInt() ?? 0,
  plusOneNames: List<String>.from((m['plus_one_names'] as List?) ?? const []));

PrivateEvent privateEventFromRow(Map<String, dynamic> m) => PrivateEvent(
  id: '${m['id']}', name: m['name'] as String? ?? 'Event',
  venue: m['venue'] as String? ?? '', city: m['city'] as String? ?? '',
  message: m['message'] as String? ?? '',
  type: PrivateEventType.values.firstWhere(
    (t) => t.name == m['event_type'], orElse: () => PrivateEventType.other),
  date: DateTime.tryParse('${m['event_date']}')?.toLocal() ?? DateTime.now(),
  isPaid: m['is_paid'] as bool? ?? false,
  hostName: m['host_name'] as String? ?? 'Host',
  mealOptions: List<String>.from((m['meal_options'] as List?) ?? const []),
  guests: ((m['private_event_guests'] as List?) ?? const [])
    .map((g) => guestFromRow(Map<String, dynamic>.from(g as Map))).toList(),
  maxPlusOnes: (m['max_plus_ones'] as num?)?.toInt() ?? 2,
  coverImageUrl: m['cover_image_url'] as String?,
  hasVideo: m['has_video'] as bool? ?? false);

// ─── Global private events store (backed by the database) ─────────────────────
class PrivateEventsNotifier extends StateNotifier<List<PrivateEvent>> {
  PrivateEventsNotifier() : super([]) { load(); }

  bool loading = true;

  Future<void> load() async {
    final rows = await SupabaseService.getMyPrivateEvents();
    state = rows.map(privateEventFromRow).toList();
    loading = false;
  }

  void add(PrivateEvent event) => state = [...state, event];

  void remove(String id) => state = state.where((e) => e.id != id).toList();

  PrivateEvent? findById(String id) {
    for (final e in state) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Guest fields mutate in place, so list identity doesn't change when a
  /// guest is added/updated — call this to force watchers to refresh.
  void touch() => state = [...state];
}

final privateEventsProvider =
  StateNotifierProvider<PrivateEventsNotifier, List<PrivateEvent>>(
    (ref) => PrivateEventsNotifier());

/// Resolves an event from its id alone (deep links / WhatsApp invites).
/// Hosts get their own event; anyone else gets the public invite.
class PrivateEventLoader extends ConsumerStatefulWidget {
  final String id;
  final bool rsvp;
  const PrivateEventLoader({super.key, required this.id, required this.rsvp});
  @override
  ConsumerState<PrivateEventLoader> createState() => _PELoaderState();
}

class _PELoaderState extends ConsumerState<PrivateEventLoader> {
  PrivateEvent? _ev;
  bool _done = false;

  @override
  void initState() { super.initState(); _resolve(); }

  Future<void> _resolve() async {
    var ev = ref.read(privateEventsProvider.notifier).findById(widget.id);
    if (ev == null && !widget.rsvp) {
      await ref.read(privateEventsProvider.notifier).load();
      ev = ref.read(privateEventsProvider.notifier).findById(widget.id);
    }
    if (ev == null) {
      final row = await SupabaseService.getPrivateEventInvite(widget.id);
      if (row != null) ev = privateEventFromRow(row);
    }
    if (!mounted) return;
    setState(() { _ev = ev; _done = true; });
  }

  @override
  Widget build(BuildContext context) {
    if (!_done) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_ev == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('This invitation could not be found.\n'
            'Ask the host to send the link again.',
            textAlign: TextAlign.center))));
    }
    return widget.rsvp
      ? GuestRSVPScreen(event: _ev!)
      : PrivateEventDetailScreen(event: _ev!);
  }
}

// ─── Private Events List Screen ───────────────────────────────────────────────

class PrivateEventsScreen extends ConsumerStatefulWidget {
  const PrivateEventsScreen({super.key});
  @override
  ConsumerState<PrivateEventsScreen> createState() => _PrivateEventsScreenState();
}

class _PrivateEventsScreenState extends ConsumerState<PrivateEventsScreen> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          _buildBody(context),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      backgroundColor: DelightColors.background,
      floating: true,
      snap: true,
      title: const Text('Private Events', style: TextStyle(
        fontFamily: 'Clash', fontSize: 24, fontWeight: FontWeight.w700,
        color: DelightColors.textPrimary)),
      actions: [
        GestureDetector(
          onTap: () => _showCreateSheet(context),
          child: Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: DelightColors.emeraldGradient),
              borderRadius: BorderRadius.circular(10)),
            child: const Row(children: [
              Icon(Icons.add, color: Colors.white, size: 16),
              SizedBox(width: 4),
              Text('Create', style: TextStyle(fontFamily: 'Satoshi',
                fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13)),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final events = ref.watch(privateEventsProvider);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHowItWorks(),
            const SizedBox(height: 20),
            const Text('Your Events', style: TextStyle(
              fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
              color: DelightColors.textPrimary)),
            const SizedBox(height: 12),
            ...events.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _EventCard(event: e))),
            if (events.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                alignment: Alignment.center,
                child: Column(children: [
                  const Text('🎉', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  const Text('No events yet', style: TextStyle(
                    fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
                    color: DelightColors.textPrimary)),
                  const SizedBox(height: 6),
                  const Text('Tap Create to set up your first private event.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                      color: DelightColors.textMuted)),
                ])),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Create event bottom sheet ─────────────────────────────────────────────

  void _showCreateSheet(BuildContext context) {
    final nameCtrl  = TextEditingController();
    final venueCtrl = TextEditingController();
    final cityCtrl  = TextEditingController();
    final msgCtrl   = TextEditingController();
    PrivateEventType type = PrivateEventType.wedding;
    DateTime date = DateTime.now().add(const Duration(days: 30));
    bool isPaid = false;
    bool creating = false;   // blocks double-taps that created duplicates
    int maxPlusOnes = 1;
    String? coverUrl;
    bool hasVideo = false;
    int photoIdx = 0;
    const samplePhotos = [
      'https://images.unsplash.com/photo-1519741497674-611481863552?w=800',
      'https://images.unsplash.com/photo-1530103862676-de8c9debad1d?w=800',
      'https://images.unsplash.com/photo-1464366400600-7168b8af9bc3?w=800',
      'https://images.unsplash.com/photo-1511795409834-ef04bbd61622?w=800',
      'https://images.unsplash.com/photo-1470229722913-7c0e2dbbafd3?w=800',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [

              // Handle
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: DelightColors.surfaceBorder,
                  borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),

              const Text('Create Private Event', style: TextStyle(
                fontFamily: 'Clash', fontSize: 22, fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary)),
              const SizedBox(height: 6),
              const Text('All fields except venue and message are required.',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                  color: DelightColors.textMuted)),
              const SizedBox(height: 20),

              // Event type selector
              const Align(alignment: Alignment.centerLeft,
                child: Text('Event Type', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 12,
                  fontWeight: FontWeight.w700, color: DelightColors.textMuted,
                  letterSpacing: 0.5))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8,
                children: PrivateEventType.values.map((t) {
                  final sel = t == type;
                  return GestureDetector(
                    onTap: () => setModal(() => type = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 130),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? DelightColors.gold.withOpacity(0.15)
                          : DelightColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel ? DelightColors.gold
                            : DelightColors.surfaceBorder,
                          width: sel ? 1.5 : 1)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(t.emoji, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 5),
                        Text(t.label, style: TextStyle(
                          fontFamily: 'Satoshi', fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: sel ? DelightColors.gold
                            : DelightColors.textMuted)),
                      ])));
                }).toList()),
              const SizedBox(height: 16),

              // Event name
              _field(nameCtrl, 'Event name *',
                "e.g. Thabo & Nomsa’s Wedding", Icons.celebration_outlined),
              const SizedBox(height: 10),

              // Date picker
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                    builder: (ctx, child) => Theme(
                      data: Theme.of(ctx).copyWith(
                        colorScheme: const ColorScheme.dark(
                          primary: DelightColors.emerald,
                          surface: DelightColors.surfaceHigh)),
                      child: child!));
                  if (picked != null) setModal(() => date = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: DelightColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: DelightColors.surfaceBorder)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_outlined,
                      color: DelightColors.textMuted, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      '${date.day}/${date.month}/${date.year}',
                      style: const TextStyle(fontFamily: 'Satoshi',
                        fontSize: 14, color: DelightColors.textPrimary))),
                    const Icon(Icons.chevron_right,
                      color: DelightColors.textMuted, size: 18),
                  ]))),
              const SizedBox(height: 10),

              // Venue + city
              _field(venueCtrl, 'Venue', 'e.g. Fairlawn Boutique Hotel',
                Icons.location_on_outlined),
              const SizedBox(height: 10),
              _field(cityCtrl, 'City *', 'e.g. Johannesburg',
                Icons.location_city_outlined),
              const SizedBox(height: 10),

              // Personal message
              TextField(
                controller: msgCtrl,
                maxLines: 3,
                style: const TextStyle(fontFamily: 'Satoshi',
                  color: DelightColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Personal message to guests',
                  labelStyle: const TextStyle(fontFamily: 'Satoshi',
                    color: DelightColors.textMuted, fontSize: 12),
                  alignLabelWithHint: true,
                  filled: true, fillColor: DelightColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: DelightColors.surfaceBorder)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: DelightColors.surfaceBorder)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: DelightColors.emerald)))),
              const SizedBox(height: 10),

              // Plus ones per guest
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: DelightColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: DelightColors.surfaceBorder)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Row(children: [
                    const Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Text('Plus Ones Per Guest', style: TextStyle(
                        fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                        fontSize: 14, color: DelightColors.textPrimary)),
                      Text('How many extra people each guest can bring',
                        style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                          color: DelightColors.textMuted)),
                    ])),
                    Text(maxPlusOnes == 0 ? 'None' : '+$maxPlusOnes max',
                      style: TextStyle(fontFamily: 'Clash', fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: maxPlusOnes == 0
                          ? DelightColors.textMuted
                          : DelightColors.emerald)),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [0, 1, 2, 3].map((n) {
                    final sel = n == maxPlusOnes;
                    return Expanded(child: GestureDetector(
                      onTap: () => setModal(() => maxPlusOnes = n),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: sel
                            ? DelightColors.emeraldGlow
                            : DelightColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: sel
                              ? DelightColors.emerald
                              : DelightColors.surfaceBorder,
                            width: sel ? 1.5 : 1)),
                        alignment: Alignment.center,
                        child: Text(
                          n == 0 ? 'None' : '+$n',
                          style: TextStyle(
                            fontFamily: 'Clash', fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: sel
                              ? DelightColors.emerald
                              : DelightColors.textMuted)))));
                  }).toList()),
                ])),
              const SizedBox(height: 10),

              // ── Cover Photo / Video ─────────────────────────────────
              const Align(alignment: Alignment.centerLeft,
                child: Text('Cover Photo or Video', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 12,
                  fontWeight: FontWeight.w700, color: DelightColors.textMuted,
                  letterSpacing: 0.5))),
              const SizedBox(height: 8),

              // Preview
              if (coverUrl != null)
                Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: coverUrl!.startsWith('http')
                      ? CachedNetworkImage(
                          imageUrl: coverUrl!,
                          width: double.infinity, height: 130, fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            height: 130, color: DelightColors.surfaceHigh,
                            child: const Icon(Icons.broken_image_outlined,
                              color: DelightColors.textMuted)))
                      : Image.file(File(coverUrl!),
                          width: double.infinity, height: 130, fit: BoxFit.cover)),
                  Positioned(top: 8, right: 8,
                    child: GestureDetector(
                      onTap: () => setModal(() { coverUrl = null; hasVideo = false; }),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close,
                          color: Colors.white, size: 14)))),
                ])
              else if (hasVideo)
                Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: DelightColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: DelightColors.gold.withOpacity(0.4))),
                  child: const Center(child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    Icon(Icons.play_circle_outline,
                      color: DelightColors.gold, size: 28),
                    SizedBox(width: 8),
                    Text('Video attached', style: TextStyle(
                      fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                      fontSize: 13, color: DelightColors.gold)),
                  ]))),

              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () async {
                    final xfile = await ImagePicker().pickImage(
                      source: ImageSource.gallery, imageQuality: 85);
                    if (xfile != null) {
                      setModal(() { coverUrl = xfile.path; hasVideo = false; });
                    }
                  },
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: DelightColors.blue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: coverUrl != null
                          ? DelightColors.blue
                          : DelightColors.blue.withOpacity(0.3))),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      Icon(Icons.add_photo_alternate_outlined,
                        color: DelightColors.blue, size: 18),
                      const SizedBox(width: 6),
                      Text(coverUrl != null ? '✓ Photo' : 'Add Photo',
                        style: const TextStyle(fontFamily: 'Satoshi',
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: DelightColors.blue)),
                    ])))),
                const SizedBox(width: 8),
                Expanded(child: GestureDetector(
                  onTap: () async {
                    final xfile = await ImagePicker().pickVideo(source: ImageSource.gallery);
                    if (xfile != null) {
                      setModal(() { hasVideo = true; coverUrl = null; });
                    }
                  },
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: DelightColors.gold.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: hasVideo
                          ? DelightColors.gold
                          : DelightColors.gold.withOpacity(0.3))),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      Icon(Icons.videocam_outlined,
                        color: DelightColors.gold, size: 18),
                      const SizedBox(width: 6),
                      Text(hasVideo ? '✓ Video' : 'Add Video',
                        style: const TextStyle(fontFamily: 'Satoshi',
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: DelightColors.gold)),
                    ])))),
              ]),
              const SizedBox(height: 10),

              // Paid event toggle
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: DelightColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: DelightColors.surfaceBorder)),
                child: Row(children: [
                  const Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text('Paid Event', style: TextStyle(
                      fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                      fontSize: 14, color: DelightColors.textPrimary)),
                    Text('Charge guests a ticket price',
                      style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                        color: DelightColors.textMuted)),
                  ])),
                  Switch(
                    value: isPaid,
                    onChanged: (v) => setModal(() => isPaid = v),
                    activeColor: DelightColors.emerald),
                ])),
              const SizedBox(height: 24),

              // Create button
              GestureDetector(
                onTap: () async {
                  if (creating) return;
                  final name = nameCtrl.text.trim();
                  final city = cityCtrl.text.trim();
                  if (name.isEmpty || city.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text(
                        'Please fill in event name and city.')));
                    return;
                  }
                  setModal(() => creating = true);
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    // Local photo → upload so guests on other phones can see it.
                    String? cover = coverUrl;
                    if (cover != null && !cover.startsWith('http')) {
                      final uid = SupabaseService.currentUser?.id ?? 'anon';
                      final bytes = await File(cover).readAsBytes();
                      cover = await SupabaseService.uploadImage(
                        'delight-images',
                        'private/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg',
                        bytes);
                    }
                    final me = SupabaseService.currentUser?.id;
                    final host = me == null ? null
                      : (await SupabaseService.getProfile(me))?['display_name'] as String?;
                    final row = await SupabaseService.createPrivateEvent({
                      'name': name, 'event_type': type.name,
                      'venue': venueCtrl.text.trim(), 'city': city,
                      'message': msgCtrl.text.trim(),
                      'host_name': host ?? 'Host',
                      'event_date': date.toUtc().toIso8601String(),
                      'is_paid': isPaid, 'max_plus_ones': maxPlusOnes,
                      'cover_image_url': cover, 'has_video': hasVideo,
                    });
                    ref.read(privateEventsProvider.notifier)
                      .add(privateEventFromRow(row));
                    if (context.mounted) Navigator.pop(context);
                    messenger.showSnackBar(SnackBar(
                      content: Text('$name created! Add guests next.'),
                      backgroundColor: DelightColors.emerald));
                  } catch (e) {
                    setModal(() => creating = false);
                    messenger.showSnackBar(SnackBar(content: Text(
                      "Couldn't create the event: ${e.toString().replaceFirst('Exception: ', '')}")));
                  }
                },
                child: Opacity(opacity: creating ? 0.5 : 1, child: Container(
                  height: 56, width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: DelightColors.emeraldGradient),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(
                      color: DelightColors.emerald.withOpacity(0.35),
                      blurRadius: 16, offset: const Offset(0, 4))]),
                  alignment: Alignment.center,
                  child: Text(creating ? 'Creating…' : 'Create Event', style: const TextStyle(
                    fontFamily: 'Satoshi', fontSize: 16,
                    fontWeight: FontWeight.w700, color: Colors.white))))),
            ])))));
  }

  Widget _field(TextEditingController ctrl, String label, String hint,
      IconData icon) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(fontFamily: 'Satoshi',
        color: DelightColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(fontFamily: 'Satoshi',
          color: DelightColors.textMuted, fontSize: 12),
        hintStyle: const TextStyle(fontFamily: 'Satoshi',
          color: DelightColors.textMuted, fontSize: 13),
        prefixIcon: Icon(icon, color: DelightColors.textMuted, size: 18),
        filled: true, fillColor: DelightColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: DelightColors.emerald, width: 1.5))));
  }

  Widget _buildHowItWorks() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          DelightColors.gold.withOpacity(0.1),
          DelightColors.emerald.withOpacity(0.05),
        ]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DelightColors.gold.withOpacity(0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Private Events on Delight', style: TextStyle(
            fontFamily: 'Clash', fontSize: 16, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary)),
          const SizedBox(height: 10),
          _howRow('💍', 'Weddings, birthdays, baby showers, corporates'),
          _howRow('📸', 'Design a beautiful invite with photos or video'),
          _howRow('📱', 'Send to contacts via WhatsApp, SMS or Delight'),
          _howRow('✅', 'Guests RSVP with plus ones, meal, dietary needs'),
          _howRow('🎟', 'Confirmed guests get a digital ticket automatically'),
          _howRow('🔐', 'Scan at the door — fraud-proof, works offline'),
        ],
      ),
    );
  }

  Widget _howRow(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(
            fontFamily: 'Satoshi', fontSize: 12,
            color: DelightColors.textSecondary, height: 1.4))),
        ],
      ),
    );
  }
}

// ─── Event Card ───────────────────────────────────────────────────────────────

class _EventCard extends StatelessWidget {
  final PrivateEvent event;
  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final confirmed = event.guests.where((g) => g.rsvp == RSVPStatus.yes).length;
    final plusOnes = event.guests
      .where((g) => g.rsvp == RSVPStatus.yes)
      .fold(0, (s, g) => s + g.plusOneCount);
    final pending = event.guests.where((g) => g.rsvp == RSVPStatus.pending).length;
    final declined = event.guests.where((g) => g.rsvp == RSVPStatus.no).length;
    final daysLeft = event.date.difference(DateTime.now()).inDays;

    return GestureDetector(
      onTap: () => context.push('/private-events/${event.id}', extra: event),
      onLongPress: () => _confirmDeleteEvent(context, event, goBack: false),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: event.type.bgColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: event.type.accent.withOpacity(0.4), width: 1.5),
          boxShadow: [BoxShadow(
            color: event.type.accent.withOpacity(0.15),
            blurRadius: 24, offset: const Offset(0, 8))]),
        child: Column(
          children: [
            _buildCardHeader(daysLeft, confirmed, plusOnes),
            _buildCardFooter(confirmed, pending, declined),
          ],
        ),
      ),
    );
  }

  Widget _buildCardHeader(int daysLeft, int confirmed, int plusOnes) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Text(event.type.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.name, style: const TextStyle(
                  fontFamily: 'Clash', fontSize: 19, fontWeight: FontWeight.w700,
                  color: Colors.white, height: 1.1)),
                Text('${event.venue} · ${event.city}', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 12,
                  color: event.type.accent.withOpacity(0.8))),
                const SizedBox(height: 4),
                Text('${confirmed + plusOnes} attending (incl. plus ones)',
                  style: const TextStyle(fontFamily: 'Satoshi',
                    fontSize: 11, color: Colors.white54)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: event.type.accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: event.type.accent.withOpacity(0.4))),
            child: Text(daysLeft > 0 ? '$daysLeft days' : 'Today!',
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                fontWeight: FontWeight.w700, color: event.type.accent)),
          ),
        ],
      ),
    );
  }

  Widget _buildCardFooter(int confirmed, int pending, int declined) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22))),
      child: Row(
        children: [
          _stat('$confirmed', 'Confirmed ✓', event.type.accent),
          _vd(),
          _stat('$pending', 'Pending ⏳', Colors.white54),
          _vd(),
          _stat('$declined', 'Declined ✗', Colors.white38),
          _vd(),
          _stat('${event.guests.length}', 'Invited', Colors.white70),
        ],
      ),
    );
  }

  Widget _stat(String v, String l, Color c) {
    return Expanded(child: Column(children: [
      Text(v, style: TextStyle(fontFamily: 'Clash', fontSize: 20,
        fontWeight: FontWeight.w700, color: c)),
      Text(l, style: TextStyle(fontFamily: 'Satoshi', fontSize: 9,
        color: c.withOpacity(0.8))),
    ]));
  }

  Widget _vd() => Container(width: 1, height: 28, color: Colors.white12);
}

// ─── Event Detail Screen ──────────────────────────────────────────────────────

class PrivateEventDetailScreen extends ConsumerStatefulWidget {
  final PrivateEvent event;
  const PrivateEventDetailScreen({super.key, required this.event});

  @override
  ConsumerState<PrivateEventDetailScreen> createState() => _PEDetailState();
}

class _PEDetailState extends ConsumerState<PrivateEventDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _tab.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ev = widget.event;
    final confirmed = ev.guests.where((g) => g.rsvp == RSVPStatus.yes).length;
    final plusOnes = ev.guests
      .where((g) => g.rsvp == RSVPStatus.yes)
      .fold(0, (s, g) => s + g.plusOneCount);
    final opened = ev.guests.where((g) => g.inviteOpened).length;
    final minted = ev.guests.where((g) => g.ticketMinted).length;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      floatingActionButton: _tab.index == 0
        ? FloatingActionButton.extended(
            onPressed: () => _showAddGuestDialog(ev),
            backgroundColor: ev.type.accent,
            icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
            label: const Text('Add Guest',
              style: TextStyle(fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                color: Colors.white)))
        : null,
      body: NestedScrollView(
        headerSliverBuilder: _buildHeader,
        body: TabBarView(
          controller: _tab,
          children: [
            _GuestTab(ev: ev, filter: _filter,
              onFilter: (f) => setState(() => _filter = f)),
            _InviteTab(ev: ev),
            _RSVPTab(ev: ev),
            _TicketTab(ev: ev),
          ],
        ),
      ),
    );
  }

  void _showAddGuestDialog(PrivateEvent ev) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _AddGuestSheet(
        ev: ev,
        onAdded: (g) {
          if (!mounted) return;
          setState(() => ev.guests.add(g));
          ref.read(privateEventsProvider.notifier).touch();
        },
        onSend: (g) => _notifyGuest(context, ev, g)));
  }

  List<Widget> _buildHeader(BuildContext context, bool innerBoxIsScrolled) {
    final ev = widget.event;
    final confirmed = ev.guests.where((g) => g.rsvp == RSVPStatus.yes).length;
    final plusOnes = ev.guests
      .where((g) => g.rsvp == RSVPStatus.yes)
      .fold(0, (s, g) => s + g.plusOneCount);
    final opened = ev.guests.where((g) => g.inviteOpened).length;
    final minted = ev.guests.where((g) => g.ticketMinted).length;

    return [
      SliverAppBar(
        expandedHeight: 190,
        pinned: true,
        backgroundColor: DelightColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop()),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: DelightColors.surfaceHigh,
            onSelected: (v) {
              if (v == 'delete') _confirmDeleteEvent(context, ev, goBack: true);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete',
                child: Text('Delete event',
                  style: TextStyle(color: DelightColors.error))),
            ]),
        ],
        flexibleSpace: FlexibleSpaceBar(
          background: _buildHeroBackground(ev)),
      ),
      SliverToBoxAdapter(
        child: _buildStats(context, ev, confirmed + plusOnes, opened, minted)),
      SliverPersistentHeader(
        pinned: true,
        delegate: _TabDel(_buildTabBar(ev))),
    ];
  }

  Widget _buildHeroBackground(PrivateEvent ev) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: ev.type.bgColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight)),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(ev.type.emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(height: 6),
              Text(ev.name, style: const TextStyle(
                fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
                color: Colors.white, letterSpacing: -0.3)),
              Text('${ev.venue} · ${ev.city}', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 12,
                color: ev.type.accent.withOpacity(0.8))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStats(BuildContext context, PrivateEvent ev,
      int total, int opened, int minted) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        children: [
          Row(children: [
            _qs('${ev.guests.length}', 'Invited', DelightColors.textPrimary),
            const SizedBox(width: 8),
            _qs('$opened', 'Opened', DelightColors.blue),
            const SizedBox(width: 8),
            _qs('$total', 'Attending', DelightColors.emerald),
            const SizedBox(width: 8),
            _qs('$minted', 'Tickets', DelightColors.gold),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _ab(context, Icons.send_outlined, 'Send Invites',
              DelightColors.emerald, () => _sendSheet(context)),
            const SizedBox(width: 8),
            _ab(context, Icons.qr_code_scanner, 'Scan Door',
              DelightColors.gold, () => context.push('/gate-scan')),
            const SizedBox(width: 8),
            _ab(context, Icons.card_giftcard_outlined, 'Gift Fund',
              DelightColors.blue, () => _giftSheet(context)),
          ]),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  TabBar _buildTabBar(PrivateEvent ev) {
    return TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      controller: _tab,
      indicatorColor: ev.type.accent,
      indicatorSize: TabBarIndicatorSize.label,
      labelColor: DelightColors.textPrimary,
      unselectedLabelColor: DelightColors.textMuted,
      labelStyle: const TextStyle(
        fontFamily: 'Satoshi', fontWeight: FontWeight.w700, fontSize: 12),
      tabs: const [
        Tab(text: 'Guests'),
        Tab(text: 'Invite'),
        Tab(text: 'RSVP Data'),
        Tab(text: 'Tickets'),
      ],
    );
  }

  Widget _qs(String v, String l, Color c) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: c.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withOpacity(0.2))),
        child: Column(children: [
          Text(v, style: TextStyle(fontFamily: 'Clash', fontSize: 18,
            fontWeight: FontWeight.w700, color: c)),
          Text(l, style: const TextStyle(fontFamily: 'Satoshi',
            fontSize: 9, color: DelightColors.textMuted)),
        ]),
      ),
    );
  }

  Widget _ab(BuildContext ctx, IconData icon, String label,
      Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.25))),
          child: Column(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontFamily: 'Satoshi', fontSize: 10,
              fontWeight: FontWeight.w700, color: color)),
          ]),
        ),
      ),
    );
  }

  void _sendSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Send Invites', style: TextStyle(
                fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary)),
              const SizedBox(height: 20),
              _sendOption(ctx, '💬', 'WhatsApp', 'Beautiful invite card to all guests'),
              _sendOption(ctx, '📱', 'SMS', 'Invite link via text message'),
              _sendOption(ctx, '🔗', 'Share Link', 'Copy private link to share'),
              _sendOption(ctx, '💬', 'WhatsApp Group', 'Create event group chat'),
            ],
          ),
        );
      });
  }

  Widget _sendOption(BuildContext ctx, String icon, String title, String sub) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Sending via $title...')));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: DelightColors.emerald.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DelightColors.emerald.withOpacity(0.2))),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontFamily: 'Satoshi',
                fontWeight: FontWeight.w700, fontSize: 14,
                color: DelightColors.emerald)),
              Text(sub, style: const TextStyle(fontFamily: 'Satoshi',
                fontSize: 12, color: DelightColors.textMuted)),
            ],
          ),
        ]),
      ),
    );
  }

  void _giftSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('💝 Gift Fund', style: TextStyle(
                fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary)),
              const SizedBox(height: 8),
              const Text('Guests contribute directly to your Delight wallet.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                  color: DelightColors.textMuted)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: DelightColors.emeraldGlow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
                child: const Column(children: [
                  Text('R2,400', style: TextStyle(fontFamily: 'Clash',
                    fontSize: 32, fontWeight: FontWeight.w700,
                    color: DelightColors.emerald)),
                  Text('received from 6 guests', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 12,
                    color: DelightColors.textMuted)),
                ]),
              ),
            ],
          ),
        );
      });
  }
}

// ─── Tab delegate ─────────────────────────────────────────────────────────────

class _TabDel extends SliverPersistentHeaderDelegate {
  final TabBar tab;
  const _TabDel(this.tab);

  @override double get minExtent => tab.preferredSize.height + 1;
  @override double get maxExtent => tab.preferredSize.height + 1;
  @override bool shouldRebuild(_) => false;

  @override
  Widget build(BuildContext ctx, double shrink, bool overlaps) {
    return Container(color: DelightColors.background, child: tab);
  }
}

// ─── Guest Tab ────────────────────────────────────────────────────────────────

Future<void> _notifyGuest(BuildContext context, PrivateEvent ev, Guest g) async {
  final rsvpLink = '${Env.linkHost}/rsvp/${ev.id}';
  final message = 'Hi ${g.name}! You\'re invited to ${ev.name} 🎉\n'
    'Tap to RSVP: https://$rsvpLink';

  // Try WhatsApp first (most common in SA), fall back to SMS
  final phone = g.phone.replaceAll(RegExp(r'[^0-9+]'), '');
  final waUri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
  final smsUri = Uri.parse('sms:$phone?body=${Uri.encodeComponent(message)}');

  try {
    if (await canLaunchUrl(waUri)) {
      await launchUrl(waUri, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri, mode: LaunchMode.externalApplication);
    } else {
      throw Exception('no messaging app available');
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not open WhatsApp/SMS — copy the link instead: $rsvpLink')));
    }
  }
}

class _GuestTab extends StatelessWidget {
  final PrivateEvent ev;
  final String filter;
  final Function(String) onFilter;

  const _GuestTab({required this.ev, required this.filter, required this.onFilter});

  List<Guest> get _list {
    switch (filter) {
      case 'Confirmed': return ev.guests.where((g) => g.rsvp == RSVPStatus.yes).toList();
      case 'Pending': return ev.guests.where((g) => g.rsvp == RSVPStatus.pending).toList();
      case 'Declined': return ev.guests.where((g) => g.rsvp == RSVPStatus.no).toList();
      default: return ev.guests;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFilters(),
        if (ev.guests.any((g) => g.rsvp == RSVPStatus.pending))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DelightColors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DelightColors.blue.withOpacity(0.25))),
              child: Row(children: [
                const Icon(Icons.info_outline, size: 16, color: DelightColors.blue),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'Status updates here the moment a guest RSVPs on their link. '
                  'Tap the WhatsApp icon on a pending guest to send them a reminder.',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                    color: DelightColors.blue.withOpacity(0.9)))),
              ]))),
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _list.length,
          itemBuilder: (_, i) => _GuestTile(g: _list[i], ev: ev))),
      ],
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: ['All', 'Confirmed', 'Pending', 'Declined'].map((f) {
            final sel = f == filter;
            return GestureDetector(
              onTap: () => onFilter(f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: sel ? ev.type.accent : DelightColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: sel ? Colors.transparent : DelightColors.surfaceBorder)),
                child: Text(f, style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 12, fontWeight: FontWeight.w600,
                  color: sel ? Colors.white : DelightColors.textMuted)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _GuestTile extends StatelessWidget {
  final Guest g;
  final PrivateEvent ev;
  const _GuestTile({required this.g, required this.ev});

  Color get _c {
    switch (g.rsvp) {
      case RSVPStatus.yes: return DelightColors.emerald;
      case RSVPStatus.no: return DelightColors.error;
      case RSVPStatus.maybe: return DelightColors.gold;
      case RSVPStatus.pending: return DelightColors.textMuted;
    }
  }

  String get _label {
    switch (g.rsvp) {
      case RSVPStatus.yes: return 'Confirmed ✓';
      case RSVPStatus.no: return 'Declined ✗';
      case RSVPStatus.maybe: return 'Maybe ?';
      case RSVPStatus.pending: return 'Pending…';
    }
  }

  Future<void> _remove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: DelightColors.surfaceHigh,
        title: Text('Remove ${g.name}?',
          style: const TextStyle(color: DelightColors.textPrimary)),
        content: const Text('They will no longer be on the guest list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true),
            child: const Text('Remove',
              style: TextStyle(color: DelightColors.error))),
        ]));
    if (ok != true || !context.mounted) return;
    try {
      await SupabaseService.removePrivateGuest(g.id);
      ev.guests.removeWhere((x) => x.id == g.id);
      ProviderScope.containerOf(context).read(privateEventsProvider.notifier).touch();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't remove the guest")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _remove(context),
      child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: g.rsvp == RSVPStatus.yes
            ? DelightColors.emerald.withOpacity(0.3)
            : DelightColors.surfaceBorder)),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _c.withOpacity(0.1),
              border: Border.all(color: _c.withOpacity(0.3))),
            alignment: Alignment.center,
            child: Text(g.avatarEmoji ?? g.name[0],
              style: const TextStyle(fontSize: 18))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.name, style: const TextStyle(
                  fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                  fontSize: 14, color: DelightColors.textPrimary)),
                Row(children: [
                  if (g.plusOneCount > 0)
                    Text('+${g.plusOneCount} · ', style: const TextStyle(
                      fontFamily: 'Satoshi', fontSize: 10, color: DelightColors.gold)),
                  if (g.mealChoice != null)
                    Text('${g.mealChoice} · ', style: const TextStyle(
                      fontFamily: 'Satoshi', fontSize: 10, color: DelightColors.textMuted)),
                  Text(g.phone, style: const TextStyle(
                    fontFamily: 'Satoshi', fontSize: 10, color: DelightColors.textMuted)),
                ]),
                if (g.plusOneNames.isNotEmpty)
                  Text('With: ${g.plusOneNames.join(", ")}',
                    style: const TextStyle(fontFamily: 'Satoshi',
                      fontSize: 10, color: DelightColors.gold)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: _c.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
            child: Text(_label, style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 9,
              fontWeight: FontWeight.w700, color: _c))),
          if (g.rsvp == RSVPStatus.pending) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _notifyGuest(context, ev, g),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: DelightColors.emerald.withOpacity(0.12),
                  shape: BoxShape.circle),
                child: const Icon(Icons.send_outlined,
                  size: 14, color: DelightColors.emerald))),
          ],
        ],
      ),
    ));
  }
}

// ─── Invite Tab ───────────────────────────────────────────────────────────────

class _InviteTab extends StatefulWidget {
  final PrivateEvent ev;
  const _InviteTab({required this.ev});
  @override
  State<_InviteTab> createState() => _InviteTabState();
}

class _InviteTabState extends State<_InviteTab> {
  String _style = 'Elegant';
  String? _coverUrl;     // attached photo URL
  bool _hasVideo = false;

  // Demo cover photos — in production: image_picker
  Future<void> _pickPrivateCoverPhoto() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (xfile != null && mounted) {
      setState(() { _coverUrl = xfile.path; _hasVideo = false; });
    }
  }

  static const _samplePhotos = [
    'https://images.unsplash.com/photo-1519741497674-611481863552?w=800', // wedding
    'https://images.unsplash.com/photo-1530103862676-de8c9debad1d?w=800', // birthday
    'https://images.unsplash.com/photo-1464366400600-7168b8af9bc3?w=800', // party
    'https://images.unsplash.com/photo-1511795409834-ef04bbd61622?w=800', // dinner
    'https://images.unsplash.com/photo-1470229722913-7c0e2dbbafd3?w=800', // event
  ];
  int _photoIdx = 0;

  // Each style defines its own full visual identity
  static const _styles = ['Elegant', 'Floral', 'Bold', 'Minimal', 'Luxury'];

  @override
  Widget build(BuildContext context) {
    final ev = widget.ev;
    final dateFmt = DateFormat('EEEE, d MMMM yyyy');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Style selector ──────────────────────────────────────────────
        const Text('Invite Style', style: TextStyle(
          fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('Pick a look. The invite guests receive will match this style.',
          style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
            color: DelightColors.textMuted)),
        const SizedBox(height: 12),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: _styles.map((s) {
            final sel = s == _style;
            return GestureDetector(
              onTap: () => setState(() => _style = s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: sel
                    ? ev.type.accent.withOpacity(0.15)
                    : DelightColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: sel ? ev.type.accent : DelightColors.surfaceBorder,
                    width: sel ? 1.5 : 1)),
                child: Text(s, style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: sel ? ev.type.accent : DelightColors.textMuted))));
          }).toList())),
        const SizedBox(height: 24),

        // ── The invite card preview ─────────────────────────────────────
        const Text('Preview', style: TextStyle(
          fontFamily: 'Satoshi', fontSize: 12, fontWeight: FontWeight.w700,
          color: DelightColors.textMuted, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Center(child: _InviteCard(ev: ev, style: _style, dateFmt: dateFmt, coverUrl: _coverUrl, hasVideo: _hasVideo)),
        const SizedBox(height: 12),

        // Premium upgrade nudge
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: DelightColors.goldGlow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DelightColors.gold.withOpacity(0.3))),
          child: Row(children: [
            const Text('✨', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Unlock Premium Invite Designs',
                style: TextStyle(fontFamily: 'Satoshi',
                  fontWeight: FontWeight.w700, fontSize: 13,
                  color: DelightColors.gold)),
              const Text('Custom photo, animated entrance, floral overlays. '
                'R49 one-time — your guests will screenshot it.',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                  color: DelightColors.textSecondary, height: 1.4)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: DelightColors.goldGradient),
                borderRadius: BorderRadius.circular(8)),
              child: const Text('R49', style: TextStyle(
                fontFamily: 'Clash', fontSize: 13, fontWeight: FontWeight.w800,
                color: Colors.white))),
          ])),
        const SizedBox(height: 24),

        // ── How it reaches guests ───────────────────────────────────────
        _buildRSVPSection(context, ev),
        const SizedBox(height: 32),
      ]));
  }

  // ── RSVP section with journey + link ───────────────────────────────────────

  Widget _buildMediaSection(BuildContext context, PrivateEvent ev) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // ── Section header ──────────────────────────────────────────
      Row(children: [
        const Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Cover Photo or Video', style: TextStyle(
            fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary)),
          SizedBox(height: 3),
          Text('Guests see this when they open your invite link.',
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
              color: DelightColors.textMuted)),
        ])),
        if (_coverUrl != null || _hasVideo)
          GestureDetector(
            onTap: () => setState(() { _coverUrl = null; _hasVideo = false; }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: DelightColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
              child: const Text('Remove', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 11,
                fontWeight: FontWeight.w700,
                color: DelightColors.error)))),
      ]),
      const SizedBox(height: 12),

      // ── Preview (shows when something attached) ──────────────────
      if (_coverUrl != null) ...[
        Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _coverUrl!.startsWith('http')
              ? CachedNetworkImage(
                  imageUrl: _coverUrl!,
                  width: double.infinity, height: 200, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    height: 200, color: DelightColors.surfaceHigh,
                    child: const Icon(Icons.broken_image_outlined,
                      color: DelightColors.textMuted, size: 40)))
              : Image.file(File(_coverUrl!),
                  width: double.infinity, height: 200, fit: BoxFit.cover)),
          Positioned(
            top: 10, right: 10,
            child: GestureDetector(
              onTap: _pickPrivateCoverPhoto,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(8)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.refresh, color: Colors.white, size: 12),
                  SizedBox(width: 4),
                  Text('Change', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 11,
                    fontWeight: FontWeight.w600, color: Colors.white)),
                ])))),
          Positioned(
            bottom: 10, left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(6)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.image_outlined, color: Colors.white70, size: 12),
                SizedBox(width: 4),
                Text('Cover Photo', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 10,
                  color: Colors.white70)),
              ]))),
        ]),
        const SizedBox(height: 10),
      ],

      if (_hasVideo && _coverUrl == null) ...[
        Container(
          height: 160,
          decoration: BoxDecoration(
            color: DelightColors.surfaceHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DelightColors.gold.withOpacity(0.4))),
          child: Center(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.play_circle_outlined,
              color: DelightColors.gold, size: 52),
            const SizedBox(height: 8),
            const Text('Video attached', style: TextStyle(
              fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
              fontSize: 13, color: DelightColors.gold)),
            const SizedBox(height: 4),
            Text('Guests will see this on your invite',
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                color: DelightColors.textMuted)),
          ]))),
        const SizedBox(height: 10),
      ],

      // ── Action buttons ────────────────────────────────────────────
      Row(children: [
        // From phone camera roll
        Expanded(child: GestureDetector(
          onTap: _pickPrivateCoverPhoto,
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: DelightColors.blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _coverUrl != null
                  ? DelightColors.blue
                  : DelightColors.blue.withOpacity(0.3),
                width: _coverUrl != null ? 1.5 : 1)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_photo_alternate_outlined,
                color: DelightColors.blue,
                size: _coverUrl != null ? 22 : 26),
              const SizedBox(height: 4),
              Text(_coverUrl != null ? '✓ Photo' : 'Photo',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                  fontWeight: FontWeight.w700, color: DelightColors.blue)),
            ])))),
        const SizedBox(width: 8),
        // Video
        Expanded(child: GestureDetector(
          onTap: () async {
            final xfile = await ImagePicker().pickVideo(source: ImageSource.gallery);
            if (xfile != null && mounted) {
              setState(() { _hasVideo = true; _coverUrl = null; });
            }
          },
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: DelightColors.gold.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _hasVideo
                  ? DelightColors.gold
                  : DelightColors.gold.withOpacity(0.3),
                width: _hasVideo ? 1.5 : 1)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.videocam_outlined,
                color: DelightColors.gold,
                size: _hasVideo ? 22 : 26),
              const SizedBox(height: 4),
              Text(_hasVideo ? '✓ Video' : 'Video',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                  fontWeight: FontWeight.w700, color: DelightColors.gold)),
            ])))),
        const SizedBox(width: 8),
        // Browse sample photos
        Expanded(child: GestureDetector(
          onTap: () {
            setState(() {
              _photoIdx = (_photoIdx + 1) % _samplePhotos.length;
              _coverUrl = _samplePhotos[_photoIdx];
              _hasVideo = false;
            });
          },
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: DelightColors.emeraldGlow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: DelightColors.emerald.withOpacity(0.4),
                width: 1)),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.collections_outlined,
                color: DelightColors.emerald, size: 24),
              SizedBox(height: 4),
              Text('Browse', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 11,
                fontWeight: FontWeight.w700,
                color: DelightColors.emerald)),
            ])))),
      ]),

      // ── The invite card now shows the cover ───────────────────────
      if (_coverUrl != null || _hasVideo) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: DelightColors.emeraldGlow,
            borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            const Icon(Icons.check_circle_outline,
              color: DelightColors.emerald, size: 14),
            const SizedBox(width: 8),
            const Expanded(child: Text(
              'Your cover is attached — scroll down to see it in the preview card',
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                color: DelightColors.emerald, height: 1.3))),
          ])),
      ],
    ]);
  }

  Widget _buildRSVPSection(BuildContext context, PrivateEvent ev) {
    final rsvpLink = '${Env.linkHost}/rsvp/${ev.id}';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      const Text('How Guests Get Their Tickets', style: TextStyle(
        fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
        color: DelightColors.textPrimary)),
      const SizedBox(height: 12),

      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DelightColors.surfaceBorder)),
        child: Column(children: [
          _step('1', '📨', 'You share the RSVP link',
            'Tap Send below — WhatsApp, SMS, or copy the link. '
            'Each guest sees your invite card exactly as shown above.',
            DelightColors.gold),
          _dividerLine(),
          _step('2', '📱', 'Guest opens the link',
            'They see your invite — no app download needed. '
            'Works on any phone, any browser.',
            DelightColors.blue),
          _dividerLine(),
          _step('3', '✅', 'Guest RSVPs',
            'Yes / No / Maybe. Meal choice. '
            'Plus ones${ev.maxPlusOnes > 0 ? " (up to +${ev.maxPlusOnes} per guest)" : " (none for this event)"}. '
            'All tracked in your dashboard.',
            DelightColors.emerald),
          _dividerLine(),
          _step('4', '🎟', 'Ticket minted automatically',
            'The moment they confirm Yes, a unique NFT ticket is '
            'created — one per person including plus ones. '
            'Sent to their Delight wallet instantly.',
            const Color(0xFFBF5FFF)),
          _dividerLine(),
          _step('5', '🚪', 'Scan at the door',
            'Guest shows their QR. You scan it. '
            'Green = valid. One ticket, one entry. Fraud-proof.',
            DelightColors.emerald),
        ])),
      const SizedBox(height: 16),

      // RSVP link card
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            ev.type.accent.withOpacity(0.1),
            DelightColors.background]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ev.type.accent.withOpacity(0.35))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('🔗', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            const Text('Your RSVP Link', style: TextStyle(
              fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
              fontSize: 13, color: DelightColors.textPrimary)),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: DelightColors.background,
              borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Expanded(child: Text(rsvpLink,
                style: TextStyle(fontFamily: 'Courier', fontSize: 11,
                  color: ev.type.accent),
                overflow: TextOverflow.ellipsis)),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(text: 'https://$rsvpLink'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('RSVP link copied!'),
                      backgroundColor: DelightColors.emerald));
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: ev.type.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6)),
                  child: Icon(Icons.copy, color: ev.type.accent, size: 14))),
            ])),
          const SizedBox(height: 12),
          Row(children: [
            _shareChip(context, '💬', 'WhatsApp', DelightColors.emerald),
            const SizedBox(width: 8),
            _shareChip(context, '📱', 'SMS', DelightColors.blue),
            const SizedBox(width: 8),
            _shareChip(context, '📧', 'Email', DelightColors.gold),
          ]),
          if (ev.maxPlusOnes > 0) ...[
            const SizedBox(height: 10),
            Text(
              'Each guest can bring up to +${ev.maxPlusOnes} plus one${ev.maxPlusOnes > 1 ? "s" : ""}. '
              'Every person gets their own ticket automatically.',
              style: const TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                color: DelightColors.textMuted, height: 1.4)),
          ],
        ])),
    ]);
  }

  Widget _step(String num, String emoji, String title, String body, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(num, style: TextStyle(fontFamily: 'Clash',
            fontSize: 11, fontWeight: FontWeight.w800, color: color))),
        const SizedBox(width: 10),
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontFamily: 'Satoshi',
            fontWeight: FontWeight.w700, fontSize: 13,
            color: DelightColors.textPrimary)),
          const SizedBox(height: 2),
          Text(body, style: const TextStyle(fontFamily: 'Satoshi',
            fontSize: 12, color: DelightColors.textMuted, height: 1.4)),
        ])),
      ]));
  }

  Widget _dividerLine() => const Divider(
    color: DelightColors.surfaceBorder, height: 1, indent: 42);

  Widget _shareChip(BuildContext context, String emoji, String label,
      Color color) {
    return Expanded(child: GestureDetector(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sending via $label...'),
          backgroundColor: color)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3))),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontFamily: 'Satoshi', fontSize: 10,
            fontWeight: FontWeight.w700, color: color)),
        ]))));
  }
}

// ── The invite card — 5 distinct styles ────────────────────────────────────────

class _InviteCard extends StatelessWidget {
  final PrivateEvent ev;
  final String style;
  final DateFormat dateFmt;
  final String? coverUrl;
  final bool hasVideo;
  const _InviteCard({required this.ev, required this.style,
    required this.dateFmt, this.coverUrl, this.hasVideo = false});

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case 'Elegant':  return _elegantCard();
      case 'Floral':   return _floralCard();
      case 'Bold':     return _boldCard();
      case 'Minimal':  return _minimalCard();
      case 'Luxury':   return _luxuryCard();
      default:         return _elegantCard();
    }
  }

  // ── ELEGANT — dark romance, gold accents, serif feel ─────────────────────
  Widget _elegantCard() {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: ev.type.bgColors,
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: ev.type.accent.withOpacity(0.4), width: 1.5),
        boxShadow: [BoxShadow(
          color: ev.type.accent.withOpacity(0.3),
          blurRadius: 40, offset: const Offset(0, 16))]),
      child: Column(children: [
        // Top — cover photo/video or decorative band
        if (coverUrl != null)
          Stack(children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: CachedNetworkImage(
                imageUrl: coverUrl!,
                width: double.infinity, height: 160, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  height: 160, color: ev.type.bgColors[0],
                  alignment: Alignment.center,
                  child: Text(ev.type.emoji,
                    style: const TextStyle(fontSize: 48))))),
            Positioned.fill(child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black.withOpacity(0.4)],
                  begin: Alignment.topCenter, end: Alignment.bottomCenter)))),
            Positioned(
              bottom: 8, left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(6)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.image_outlined, size: 10,
                    color: ev.type.accent),
                  const SizedBox(width: 4),
                  Text('Cover Photo', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 9,
                    color: ev.type.accent)),
                ]))),
          ])
        else if (hasVideo)
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: ev.type.bgColors[0],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
            child: Center(child: Column(
              mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.play_circle_outlined,
                color: Colors.white70, size: 44),
              const SizedBox(height: 4),
              const Text('Video', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 11,
                color: Colors.white54)),
            ])))
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: ev.type.accent.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24))),
            child: Center(child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 1,
                  color: ev.type.accent.withOpacity(0.4)),
                const SizedBox(width: 10),
                Text(ev.type.emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Container(width: 40, height: 1,
                  color: ev.type.accent.withOpacity(0.4)),
              ]))),

        // Main content
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(children: [
            Text('Together with their families', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 11,
              color: ev.type.accent.withOpacity(0.7),
              letterSpacing: 0.5)),
            const SizedBox(height: 6),
            Text(ev.hostName, textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Clash', fontSize: 26,
                fontWeight: FontWeight.w700, color: Colors.white,
                letterSpacing: -0.5, height: 1.1)),
            const SizedBox(height: 8),
            Text('joyfully invite you to', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 12,
              color: Colors.white.withOpacity(0.6),
              fontStyle: FontStyle.italic)),
            const SizedBox(height: 4),
            Text(ev.name, textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Clash', fontSize: 18,
                fontWeight: FontWeight.w700, color: Colors.white,
                height: 1.2)),

            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.25),
                borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Text(dateFmt.format(ev.date), style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 12,
                  fontWeight: FontWeight.w700, color: ev.type.accent)),
                if (ev.venue.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(ev.venue, style: const TextStyle(
                    fontFamily: 'Satoshi', fontSize: 11,
                    color: Colors.white60)),
                ],
                Text(ev.city, style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 11,
                  color: Colors.white38)),
              ])),

            if (ev.message.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('"${ev.message.length > 80 ? '${ev.message.substring(0, 80)}...' : ev.message}"',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                  color: Colors.white.withOpacity(0.55),
                  fontStyle: FontStyle.italic, height: 1.5)),
            ],

            const SizedBox(height: 20),
            _rsvpButtons(ev.type.accent),
          ])),
      ]));
  }

  // ── FLORAL — white, soft, feminine, floral emoji border ──────────────────
  Widget _floralCard() {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8B4A0), width: 1.5),
        boxShadow: [BoxShadow(
          color: const Color(0xFFE8A080).withOpacity(0.3),
          blurRadius: 32, offset: const Offset(0, 12))]),
      child: Column(children: [
        // Floral header
        Container(
          width: double.infinity, height: 70,
          decoration: const BoxDecoration(
            color: Color(0xFFFFF0EA),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: const Center(
            child: Text('🌸 🌺 🌷 🌼 🌸 🌺 🌷',
              style: TextStyle(fontSize: 16, letterSpacing: 4)))),

        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(children: [
            Text('You are cordially invited to', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 11,
              color: Colors.brown.shade400,
              letterSpacing: 0.5, fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
            Text(ev.name, textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Clash', fontSize: 22,
                fontWeight: FontWeight.w700, color: Color(0xFF5D3A3A),
                height: 1.2)),
            const SizedBox(height: 6),
            Text('hosted by ${ev.hostName}', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 12,
              color: Colors.brown.shade400)),

            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEDE5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE8B4A0))),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.calendar_today_outlined,
                    size: 12, color: Color(0xFF8B5E5E)),
                  const SizedBox(width: 5),
                  Text(dateFmt.format(ev.date), style: const TextStyle(
                    fontFamily: 'Satoshi', fontSize: 11,
                    fontWeight: FontWeight.w700, color: Color(0xFF8B5E5E))),
                ]),
                if (ev.venue.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.location_on_outlined,
                      size: 12, color: Color(0xFFA0766E)),
                    const SizedBox(width: 4),
                    Text('${ev.venue}, ${ev.city}', style: const TextStyle(
                      fontFamily: 'Satoshi', fontSize: 11,
                      color: Color(0xFFA0766E))),
                  ]),
                ],
              ])),

            if (ev.message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('"${ev.message.length > 80 ? '${ev.message.substring(0, 80)}...' : ev.message}"',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                  color: Color(0xFF9B7B6B),
                  fontStyle: FontStyle.italic, height: 1.5)),
            ],

            const SizedBox(height: 18),
            _rsvpButtons(const Color(0xFFD4826A)),
          ])),
      ]));
  }

  // ── BOLD — full bleed color, huge type, high energy ──────────────────────
  Widget _boldCard() {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: ev.type.accent,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(
          color: ev.type.accent.withOpacity(0.5),
          blurRadius: 40, offset: const Offset(0, 16))]),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6)),
              child: Text(ev.type.label.toUpperCase(), style: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 9, fontWeight: FontWeight.w800,
                color: Colors.white70, letterSpacing: 2))),
            const SizedBox(height: 12),
            Text(ev.name, style: const TextStyle(
              fontFamily: 'Clash', fontSize: 30, fontWeight: FontWeight.w800,
              color: Colors.white, height: 1.0, letterSpacing: -1)),
            const SizedBox(height: 6),
            Text('Hosted by ${ev.hostName}', style: const TextStyle(
              fontFamily: 'Satoshi', fontSize: 13,
              color: Colors.white70)),
            const SizedBox(height: 20),
            Container(
              width: double.infinity, height: 1,
              color: Colors.white.withOpacity(0.25)),
            const SizedBox(height: 16),
            Text(dateFmt.format(ev.date), style: const TextStyle(
              fontFamily: 'Satoshi', fontSize: 12,
              fontWeight: FontWeight.w700, color: Colors.white)),
            if (ev.venue.isNotEmpty)
              Text('${ev.venue} · ${ev.city}', style: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 11, color: Colors.white70)),
            const SizedBox(height: 24),
            _rsvpButtons(Colors.black),
          ])),
      ]));
  }

  // ── MINIMAL — white card, clean lines, no clutter ────────────────────────
  Widget _minimalCard() {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8E8E8)),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 32, offset: const Offset(0, 12))]),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: ev.type.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: Text(ev.type.emoji, style: const TextStyle(fontSize: 18))),
            const SizedBox(width: 10),
            Text(ev.type.label, style: const TextStyle(
              fontFamily: 'Satoshi', fontSize: 11,
              color: Color(0xFF888888), letterSpacing: 1)),
          ]),
          const SizedBox(height: 20),
          Text(ev.name, style: const TextStyle(
            fontFamily: 'Clash', fontSize: 22, fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A1A), height: 1.1)),
          const SizedBox(height: 4),
          Text('by ${ev.hostName}', style: const TextStyle(
            fontFamily: 'Satoshi', fontSize: 12,
            color: Color(0xFF888888))),
          const SizedBox(height: 16),
          Container(width: 40, height: 2, color: ev.type.accent),
          const SizedBox(height: 14),
          Text(dateFmt.format(ev.date), style: const TextStyle(
            fontFamily: 'Satoshi', fontSize: 12,
            fontWeight: FontWeight.w600, color: Color(0xFF333333))),
          if (ev.venue.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('${ev.venue}, ${ev.city}', style: const TextStyle(
              fontFamily: 'Satoshi', fontSize: 11,
              color: Color(0xFF888888))),
          ],
          if (ev.message.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('"${ev.message.length > 80 ? '${ev.message.substring(0, 80)}...' : ev.message}"',
              style: const TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                color: Color(0xFF666666),
                fontStyle: FontStyle.italic, height: 1.5)),
          ],
          const SizedBox(height: 20),
          _rsvpButtonsLight(ev.type.accent),
        ])));
  }

  // ── LUXURY — black, gold, premium ────────────────────────────────────────
  Widget _luxuryCard() {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: DelightColors.gold.withOpacity(0.4), width: 1),
        boxShadow: [BoxShadow(
          color: DelightColors.gold.withOpacity(0.2),
          blurRadius: 40, offset: const Offset(0, 16))]),
      child: Column(children: [
        // Gold top stripe
        Container(
          width: double.infinity, height: 4,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: DelightColors.goldGradient),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)))),

        Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 26),
          child: Column(children: [
            Text(ev.type.emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 14),
            Text(ev.hostName, textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Clash', fontSize: 20,
                fontWeight: FontWeight.w700, color: DelightColors.gold,
                letterSpacing: -0.3)),
            const SizedBox(height: 4),
            Text('invite you to', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 11,
              color: Colors.white.withOpacity(0.4), letterSpacing: 1)),
            const SizedBox(height: 4),
            Text(ev.name, textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Clash', fontSize: 18,
                fontWeight: FontWeight.w700, color: Colors.white,
                height: 1.2)),

            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(
                  color: DelightColors.gold.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Text(dateFmt.format(ev.date), style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 11,
                  fontWeight: FontWeight.w700, color: DelightColors.gold)),
                if (ev.venue.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('${ev.venue}', style: const TextStyle(
                    fontFamily: 'Satoshi', fontSize: 11,
                    color: Colors.white60)),
                  Text(ev.city, style: const TextStyle(
                    fontFamily: 'Satoshi', fontSize: 10,
                    color: Colors.white38)),
                ],
              ])),

            if (ev.message.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('"${ev.message.length > 80 ? '${ev.message.substring(0, 80)}...' : ev.message}"',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 10,
                  color: Colors.white.withOpacity(0.45),
                  fontStyle: FontStyle.italic, height: 1.5)),
            ],

            const SizedBox(height: 20),
            // Gold RSVP button
            GestureDetector(
              onTap: () {},
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: DelightColors.goldGradient),
                  borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: const Text("RSVP Now", style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 14,
                  fontWeight: FontWeight.w800, color: Colors.black,
                  letterSpacing: 1)))),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: DelightColors.gold.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: const Text("Decline", style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 13,
                color: Colors.white38))),
          ])),

        // Gold bottom stripe
        Container(
          width: double.infinity, height: 3,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: DelightColors.goldGradient),
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(24)))),
      ]));
  }

  // ── Shared RSVP buttons (dark background) ────────────────────────────────
  Widget _rsvpButtons(Color accent) {
    return Column(children: [
      GestureDetector(
        onTap: () {},
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accent, accent.withOpacity(0.75)]),
            borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: const Text("🎉  Yes, I'll be there!",
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 14,
              fontWeight: FontWeight.w800, color: Colors.white)))),
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24)),
        alignment: Alignment.center,
        child: const Text("Can't make it",
          style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
            color: Colors.white54))),
    ]);
  }

  // ── Shared RSVP buttons (light background) ───────────────────────────────
  Widget _rsvpButtonsLight(Color accent) {
    return Column(children: [
      GestureDetector(
        onTap: () {},
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: const Text("🎉  Yes, I'll be there!",
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 14,
              fontWeight: FontWeight.w800, color: Colors.white)))),
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDDDDDD)),
          borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        child: const Text("Can't make it",
          style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
            color: Color(0xFF999999)))),
    ]);
  }
}

// ─── RSVP Tab ─────────────────────────────────────────────────────────────────

class _RSVPTab extends StatelessWidget {
  final PrivateEvent ev;
  const _RSVPTab({required this.ev});

  @override
  Widget build(BuildContext context) {
    final yes = ev.guests.where((g) => g.rsvp == RSVPStatus.yes).toList();
    final plusTotal = yes.fold(0, (s, g) => s + g.plusOneCount);
    final total = yes.length + plusTotal;
    final pending = ev.guests.where((g) => g.rsvp == RSVPStatus.pending).length;
    final mealMap = <String, int>{};
    for (final g in ev.guests.where((g) => g.mealChoice != null)) {
      mealMap[g.mealChoice!] = (mealMap[g.mealChoice!] ?? 0) + 1;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTotalCard(total, yes.length, plusTotal, pending),
          const SizedBox(height: 20),
          const Text('Plus One Breakdown', style: TextStyle(
            fontFamily: 'Clash', fontSize: 16, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary)),
          const SizedBox(height: 10),
          ...yes.where((g) => g.plusOneCount > 0).map((g) => _buildPlusOneTile(g)),
          if (mealMap.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Meal Choices', style: TextStyle(
              fontFamily: 'Clash', fontSize: 16, fontWeight: FontWeight.w700,
              color: DelightColors.textPrimary)),
            const SizedBox(height: 10),
            ...mealMap.entries.map((e) => _buildMealTile(e.key, e.value, mealMap)),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildTotalCard(int total, int primary, int plusOnes, int pending) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D2A1A), Color(0xFF0A1F14)]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TOTAL ATTENDING', style: TextStyle(
            fontFamily: 'Satoshi', fontSize: 10,
            color: DelightColors.textMuted, letterSpacing: 1.5)),
          const SizedBox(height: 4),
          Text('$total', style: const TextStyle(
            fontFamily: 'Clash', fontSize: 52, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary, height: 1, letterSpacing: -1)),
          const SizedBox(height: 8),
          Row(children: [
            _pill('$primary', 'Primary', DelightColors.emerald),
            const SizedBox(width: 8),
            _pill('$plusOnes', 'Plus ones', DelightColors.gold),
            const SizedBox(width: 8),
            _pill('$pending', 'Pending', DelightColors.textMuted),
          ]),
        ],
      ),
    );
  }

  Widget _buildPlusOneTile(Guest g) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DelightColors.goldGlow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DelightColors.gold.withOpacity(0.3))),
      child: Row(
        children: [
          Text(g.avatarEmoji ?? g.name[0], style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.name, style: const TextStyle(fontFamily: 'Satoshi',
                  fontWeight: FontWeight.w700, fontSize: 13,
                  color: DelightColors.textPrimary)),
                if (g.plusOneNames.isNotEmpty)
                  Text(g.plusOneNames.join(', '), style: const TextStyle(
                    fontFamily: 'Satoshi', fontSize: 11,
                    color: DelightColors.textMuted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: DelightColors.gold.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8)),
            child: Text('+${g.plusOneCount}', style: const TextStyle(
              fontFamily: 'Clash', fontSize: 15, fontWeight: FontWeight.w700,
              color: DelightColors.gold))),
        ],
      ),
    );
  }

  Widget _buildMealTile(String meal, int count, Map<String, int> all) {
    final total = all.values.reduce((a, b) => a + b);
    final pct = count / total;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Column(
        children: [
          Row(children: [
            Text(_mealEmoji(meal), style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(child: Text(meal, style: const TextStyle(
              fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
              fontSize: 14, color: DelightColors.textPrimary))),
            Text('$count', style: const TextStyle(fontFamily: 'Clash',
              fontSize: 16, fontWeight: FontWeight.w700,
              color: DelightColors.emerald)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: DelightColors.surfaceBorder,
              valueColor: const AlwaysStoppedAnimation(DelightColors.emerald),
              minHeight: 5)),
        ],
      ),
    );
  }

  Widget _pill(String v, String l, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withOpacity(0.25))),
      child: Column(children: [
        Text(v, style: TextStyle(fontFamily: 'Clash', fontSize: 16,
          fontWeight: FontWeight.w700, color: c)),
        Text(l, style: const TextStyle(fontFamily: 'Satoshi',
          fontSize: 9, color: DelightColors.textMuted)),
      ]),
    );
  }

  String _mealEmoji(String m) {
    final s = m.toLowerCase();
    if (s.contains('chicken')) return '🍗';
    if (s.contains('beef')) return '🥩';
    if (s.contains('vegan')) return '🌱';
    if (s.contains('veg')) return '🥗';
    return '🍽';
  }
}

// ─── Ticket Tab ───────────────────────────────────────────────────────────────

class _TicketTab extends StatelessWidget {
  final PrivateEvent ev;
  const _TicketTab({required this.ev});

  @override
  Widget build(BuildContext context) {
    final withTickets = ev.guests.where((g) => g.ticketMinted).toList();
    final needTickets = ev.guests
      .where((g) => g.rsvp == RSVPStatus.yes && !g.ticketMinted)
      .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (needTickets.isNotEmpty) _buildMintBanner(context, needTickets.length),
          Text('Tickets Issued (${withTickets.length})',
            style: const TextStyle(fontFamily: 'Clash', fontSize: 16,
              fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
          const SizedBox(height: 10),
          ...withTickets.map((g) => _buildTicketTile(g)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildMintBanner(BuildContext context, int count) {
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Minting $count tickets...'))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: DelightColors.goldGradient),
          borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            const Icon(Icons.diamond_outlined, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Mint Pending Tickets', style: TextStyle(
                    fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                    fontSize: 14, color: Colors.white)),
                  Text('$count confirmed guests need tickets',
                    style: const TextStyle(fontFamily: 'Satoshi',
                      fontSize: 11, color: Colors.white70)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketTile(Guest g) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DelightColors.emeraldGlow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DelightColors.emerald.withOpacity(0.35))),
      child: Row(
        children: [
          Text(g.avatarEmoji ?? g.name[0], style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.name, style: const TextStyle(fontFamily: 'Satoshi',
                  fontWeight: FontWeight.w700, fontSize: 13,
                  color: DelightColors.textPrimary)),
                Row(children: [
                  const Icon(Icons.diamond_outlined, size: 10, color: DelightColors.gold),
                  const SizedBox(width: 3),
                  const Text('NFT Ticket', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 10, color: DelightColors.gold)),
                  if (g.plusOneCount > 0)
                    Text(' +${g.plusOneCount} extra', style: const TextStyle(
                      fontFamily: 'Satoshi', fontSize: 10, color: DelightColors.textMuted)),
                ]),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: DelightColors.emerald, size: 18),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GUEST RSVP SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class GuestRSVPScreen extends ConsumerStatefulWidget {
  final PrivateEvent event;
  const GuestRSVPScreen({super.key, required this.event});

  @override
  ConsumerState<GuestRSVPScreen> createState() => _GuestRSVPState();
}

class _GuestRSVPState extends ConsumerState<GuestRSVPScreen> {
  bool? _attending;
  String? _meal;
  int _plusOneCount = 0;
  final _plusOneNameCtrls = <TextEditingController>[];
  final _dietaryCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _dietaryCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    for (final c in _plusOneNameCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _setPlusOnes(int count) {
    setState(() {
      _plusOneCount = count;
      while (_plusOneNameCtrls.length < count) {
        _plusOneNameCtrls.add(TextEditingController());
      }
      while (_plusOneNameCtrls.length > count) {
        _plusOneNameCtrls.last.dispose();
        _plusOneNameCtrls.removeLast();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return _ThanksScreen(
        ev: widget.event,
        attending: _attending ?? false,
        plusOneCount: _plusOneCount);
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      body: CustomScrollView(
        slivers: [
          _buildHeroSliver(),
          _buildFormSliver(context),
        ],
      ),
    );
  }

  Widget _buildHeroSliver() {
    final ev = widget.event;
    return SliverAppBar(
      expandedHeight: 240,
      pinned: false,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: ev.type.bgColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              Text(ev.type.emoji, style: const TextStyle(fontSize: 64)),
              const SizedBox(height: 10),
              Text("You're invited to", style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 13,
                color: ev.type.accent.withOpacity(0.8), letterSpacing: 1)),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(ev.name, textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Clash', fontSize: 26,
                    fontWeight: FontWeight.w700, color: Colors.white,
                    height: 1.1, letterSpacing: -0.5))),
              const SizedBox(height: 4),
              Text('by ${ev.hostName}', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 13,
                color: ev.type.accent.withOpacity(0.7))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormSliver(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEventDetails(),
            const SizedBox(height: 14),
            _buildMessage(),
            const SizedBox(height: 24),
            _buildGuestIdentitySection(),
            const SizedBox(height: 20),
            _buildAttendingSection(),
            if (_attending == true && widget.event.maxPlusOnes > 0)
              _buildPlusOneSection(),
            if (_attending == true && widget.event.mealOptions.isNotEmpty)
              _buildMealSection(),
            if (_attending == false)
              _buildDeclineNote(),
            if (_attending != null)
              _buildSubmitButton(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildEventDetails() {
    final ev = widget.event;
    final dateFmt = DateFormat('EEEE, d MMMM yyyy');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Column(
        children: [
          _dr(Icons.calendar_today_outlined, dateFmt.format(ev.date)),
          const SizedBox(height: 8),
          _dr(Icons.access_time, DateFormat('HH:mm').format(ev.date)),
          const SizedBox(height: 8),
          _dr(Icons.location_on_outlined, '${ev.venue}, ${ev.city}'),
        ],
      ),
    );
  }

  Widget _buildMessage() {
    final ev = widget.event;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ev.type.accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ev.type.accent.withOpacity(0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ev.hostName, style: TextStyle(fontFamily: 'Satoshi',
            fontWeight: FontWeight.w700, fontSize: 12, color: ev.type.accent)),
          const SizedBox(height: 5),
          Text(ev.message, style: const TextStyle(fontFamily: 'Satoshi',
            fontSize: 13, color: DelightColors.textSecondary, height: 1.6)),
        ],
      ),
    );
  }

  Widget _buildGuestIdentitySection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Your Details', style: TextStyle(
        fontFamily: 'Clash', fontSize: 16, fontWeight: FontWeight.w700,
        color: DelightColors.textPrimary)),
      const SizedBox(height: 10),
      TextField(
        controller: _nameCtrl,
        style: const TextStyle(fontFamily: 'Satoshi', color: DelightColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Your full name',
          filled: true, fillColor: DelightColors.surfaceHigh,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: DelightColors.surfaceBorder)))),
      const SizedBox(height: 10),
      TextField(
        controller: _phoneCtrl,
        keyboardType: TextInputType.phone,
        style: const TextStyle(fontFamily: 'Satoshi', color: DelightColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Your phone number',
          filled: true, fillColor: DelightColors.surfaceHigh,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: DelightColors.surfaceBorder)))),
    ]);
  }

  Widget _buildAttendingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Will you be attending?', style: TextStyle(
          fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _attendBtn(true, '🎉', "Yes, I'll be there!")),
            const SizedBox(width: 10),
            Expanded(child: _attendBtn(false, '😢', "Can't make it")),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _attendBtn(bool value, String emoji, String label) {
    final sel = _attending == value;
    final color = value ? widget.event.type.accent : DelightColors.error;
    return GestureDetector(
      onTap: () => setState(() {
        _attending = value;
        if (!value) _setPlusOnes(0);
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: sel && value ? LinearGradient(colors: [
            widget.event.type.accent,
            widget.event.type.accent.withOpacity(0.7)]) : null,
          color: sel
            ? (value ? null : DelightColors.error.withOpacity(0.1))
            : DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: sel ? (value ? Colors.transparent : DelightColors.error)
              : DelightColors.surfaceBorder,
            width: 1.5)),
        alignment: Alignment.center,
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 5),
            Text(label, style: TextStyle(
              fontFamily: 'Satoshi', fontWeight: FontWeight.w700, fontSize: 13,
              color: sel ? (value ? Colors.white : DelightColors.error)
                : DelightColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlusOneSection() {
    final ev = widget.event;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Bringing anyone?', style: TextStyle(
          fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 4),
        Text('You can bring up to ${ev.maxPlusOnes} guest${ev.maxPlusOnes > 1 ? "s" : ""}',
          style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
            color: DelightColors.textMuted)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: DelightColors.surfaceHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DelightColors.surfaceBorder)),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _plusBtn(0, '🙋', 'Just me'),
                  const SizedBox(width: 10),
                  ...List.generate(ev.maxPlusOnes, (i) {
                    final n = i + 1;
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _plusBtn(n, '+$n', n == 1 ? 'guest' : 'guests'));
                  }),
                ],
              ),
              if (_plusOneCount > 0) ...[
                const SizedBox(height: 16),
                const Divider(color: DelightColors.surfaceBorder),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Who are they? (optional)", style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 12, fontWeight: FontWeight.w600,
                    color: DelightColors.textMuted))),
                const SizedBox(height: 10),
                ...List.generate(_plusOneCount, (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _plusOneNameCtrls[i],
                    style: const TextStyle(fontFamily: 'Satoshi',
                      color: DelightColors.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Guest ${i + 1} full name',
                      prefixIcon: const Icon(Icons.person_outline,
                        color: DelightColors.textMuted, size: 18),
                      filled: true, fillColor: DelightColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: DelightColors.surfaceBorder)))))),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: DelightColors.goldGlow,
                    borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: DelightColors.gold, size: 13),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                        'Each person gets their own ticket. '
                        'All ${_plusOneCount + 1} of you scan at the door.',
                        style: const TextStyle(fontFamily: 'Satoshi',
                          fontSize: 11, color: DelightColors.gold, height: 1.4))),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _plusBtn(int n, String label, String sub) {
    final sel = _plusOneCount == n;
    return GestureDetector(
      onTap: () => _setPlusOnes(n),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        width: 56, height: 56,
        decoration: BoxDecoration(
          color: sel ? widget.event.type.accent : DelightColors.surfaceHigh,
          shape: BoxShape.circle,
          border: Border.all(
            color: sel ? Colors.transparent : DelightColors.surfaceBorder)),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(n == 0 ? '🙋' : label, style: TextStyle(
              fontFamily: 'Clash', fontSize: n == 0 ? 22 : 17,
              fontWeight: FontWeight.w700,
              color: sel ? Colors.white : DelightColors.textPrimary)),
            Text(sub, style: TextStyle(fontFamily: 'Satoshi', fontSize: 8,
              color: sel ? Colors.white70 : DelightColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _buildMealSection() {
    final ev = widget.event;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Your meal preference', style: TextStyle(
          fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: ev.mealOptions.map((m) {
            final sel = _meal == m;
            return GestureDetector(
              onTap: () => setState(() => _meal = m),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: sel ? LinearGradient(colors: [
                    ev.type.accent, ev.type.accent.withOpacity(0.7)]) : null,
                  color: sel ? null : DelightColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: sel ? Colors.transparent : DelightColors.surfaceBorder)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_mealEmoji(m), style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(m, style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : DelightColors.textPrimary)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _dietaryCtrl,
          style: const TextStyle(fontFamily: 'Satoshi',
            color: DelightColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Any dietary requirements? (optional)',
            filled: true, fillColor: DelightColors.surfaceHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DelightColors.surfaceBorder)))),
        const SizedBox(height: 20),
      ],
    );
  }

  String _mealEmoji(String m) {
    final s = m.toLowerCase();
    if (s.contains('chicken')) return '🍗';
    if (s.contains('beef')) return '🥩';
    if (s.contains('vegan')) return '🌱';
    if (s.contains('veg')) return '🥗';
    return '🍽';
  }

  Widget _buildDeclineNote() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: const Text("We'll let the host know. You can change your mind anytime.",
        style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
          color: DelightColors.textMuted, height: 1.5)),
    );
  }

  Widget _buildSubmitButton() {
    final isYes = _attending == true;
    final ev = widget.event;
    return GestureDetector(
      onTap: () async {
        final name = _nameCtrl.text.trim();
        final phone = _phoneCtrl.text.trim();
        if (name.isEmpty || phone.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Please enter your name and phone number.')));
          return;
        }
        final plusOneNames = _plusOneNameCtrls
          .map((c) => c.text.trim())
          .where((n) => n.isNotEmpty)
          .toList();
        try {
          await SupabaseService.submitPrivateRsvp(
            eventId: ev.id, phone: phone, name: name,
            rsvp: isYes ? 'yes' : 'no', meal: isYes ? _meal : null,
            plusNames: isYes ? plusOneNames : const []);
          if (mounted) setState(() => _submitted = true);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
              e.toString().replaceFirst('Exception: ', ''))));
          }
        }
      },
      child: Container(
        height: 60, width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isYes
              ? [ev.type.accent, ev.type.accent.withOpacity(0.7)]
              : [DelightColors.error.withOpacity(0.8), DelightColors.error.withOpacity(0.5)]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(
            color: (isYes ? ev.type.accent : DelightColors.error).withOpacity(0.4),
            blurRadius: 16, offset: const Offset(0, 4))]),
        alignment: Alignment.center,
        child: Text(
          isYes
            ? 'Confirm RSVP${_plusOneCount > 0 ? " for ${_plusOneCount + 1} people" : ""}'
            : 'Send Decline',
          style: const TextStyle(fontFamily: 'Satoshi', fontSize: 17,
            fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }

  Widget _dr(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: DelightColors.textMuted),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(
          fontFamily: 'Satoshi', fontSize: 13, color: DelightColors.textSecondary))),
      ],
    );
  }
}

// ─── Thank you screen ─────────────────────────────────────────────────────────

class _ThanksScreen extends StatelessWidget {
  final PrivateEvent ev;
  final bool attending;
  final int plusOneCount;

  const _ThanksScreen({
    required this.ev, required this.attending, required this.plusOneCount});

  @override
  Widget build(BuildContext context) {
    final total = plusOneCount + 1;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(attending ? '🎉' : '😢',
                  style: const TextStyle(fontSize: 72)),
                const SizedBox(height: 20),
                Text(attending ? "You're confirmed!" : "We'll miss you!",
                  style: const TextStyle(fontFamily: 'Clash', fontSize: 28,
                    fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
                const SizedBox(height: 10),
                if (attending) ...[
                  Text(total > 1
                    ? '$total tickets sent to your Delight wallet'
                    : 'Your ticket is in your Delight wallet',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Satoshi', fontSize: 15,
                      color: DelightColors.textSecondary, height: 1.5)),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: ev.type.accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: ev.type.accent.withOpacity(0.3))),
                    child: Column(
                      children: [
                        Text(ev.type.emoji, style: const TextStyle(fontSize: 36)),
                        const SizedBox(height: 8),
                        Text(ev.name, textAlign: TextAlign.center,
                          style: const TextStyle(fontFamily: 'Clash', fontSize: 18,
                            fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.confirmation_number_outlined,
                              color: DelightColors.gold, size: 15),
                            const SizedBox(width: 6),
                            Text(total > 1 ? '$total tickets' : 'Ticket in your wallet',
                              style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                                fontWeight: FontWeight.w600, color: DelightColors.gold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else
                  const Text("The host has been notified.\nHope to see you next time!",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Satoshi', fontSize: 15,
                      color: DelightColors.textSecondary, height: 1.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


// ═════════════════════════════════════════════════════════════════════════════
// Delete event
// ═════════════════════════════════════════════════════════════════════════════
Future<void> _confirmDeleteEvent(BuildContext context, PrivateEvent ev,
    {required bool goBack}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      backgroundColor: DelightColors.surfaceHigh,
      title: Text('Delete "${ev.name}"?',
        style: const TextStyle(color: DelightColors.textPrimary)),
      content: Text(
        'The event and its guest list (${ev.guests.length} '
        '${ev.guests.length == 1 ? "guest" : "guests"}) will be removed. '
        'Invitation links will stop working. This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false),
          child: const Text('Keep it')),
        TextButton(onPressed: () => Navigator.pop(d, true),
          child: const Text('Delete',
            style: TextStyle(color: DelightColors.error))),
      ]));
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context);
  try {
    await SupabaseService.deletePrivateEvent(ev.id);
    container.read(privateEventsProvider.notifier).remove(ev.id);
    if (goBack && context.mounted) context.pop();
    messenger.showSnackBar(SnackBar(
      content: Text('"${ev.name}" deleted'),
      backgroundColor: DelightColors.emerald));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(
      "Couldn't delete: ${e.toString().replaceFirst('Exception: ', '')}")));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Add guest: people already on Delight first, then your contacts, then a number
// ═════════════════════════════════════════════════════════════════════════════
class _AddGuestSheet extends StatefulWidget {
  final PrivateEvent ev;
  final void Function(Guest) onAdded;
  final void Function(Guest) onSend;
  const _AddGuestSheet({required this.ev, required this.onAdded, required this.onSend});
  @override State<_AddGuestSheet> createState() => _AddGuestSheetState();
}

class _AddGuestSheetState extends State<_AddGuestSheet> {
  final _q = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  List<Map<String, dynamic>> _delight = [];          // people on Delight
  List<Contact> _book = [];                          // phone-book contacts
  Map<String, Map<String, dynamic>> _bookOnDelight = {}; // phone-book number -> Delight user
  bool _bookLoaded = false, _bookDenied = false, _busy = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _loadBook();
  }

  @override
  void dispose() { _q.dispose(); _nameCtrl.dispose(); _phoneCtrl.dispose(); super.dispose(); }

  Set<String> get _already => widget.ev.guests.map((g) => g.phone).toSet();
  bool _isOnList(String name) =>
    widget.ev.guests.any((g) => g.name.toLowerCase() == name.toLowerCase());

  Future<void> _loadRecent() async {
    final r = await SupabaseService.getRecentContacts();
    if (mounted && _q.text.trim().isEmpty) setState(() => _delight = r);
  }

  Future<void> _loadBook() async {
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) { if (mounted) setState(() { _bookDenied = true; _bookLoaded = true; }); return; }
      final all = await FlutterContacts.getContacts(withProperties: true);
      final withPhone = all.where((c) => c.phones.isNotEmpty).toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
      final numbers = <String>[for (final c in withPhone) for (final p in c.phones) p.number];
      final matches = await SupabaseService.matchDelightContacts(numbers);
      final map = <String, Map<String, dynamic>>{};
      for (final m in matches) { map[m['phone_in'] as String] = m; }
      if (mounted) setState(() { _book = withPhone; _bookOnDelight = map; _bookLoaded = true; });
    } catch (_) {
      if (mounted) setState(() { _bookLoaded = true; _bookDenied = true; });
    }
  }

  Future<void> _search(String v) async {
    final mine = ++_seq;
    final q = v.trim();
    if (q.length < 2) { _loadRecent(); return; }
    final r = await SupabaseService.searchUsers(q);
    if (mounted && mine == _seq) setState(() => _delight = r);
  }

  void _toast(String m, {bool ok = false}) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(m), backgroundColor: ok ? DelightColors.emerald : null));

  Future<void> _addDelightUser(Map<String, dynamic> u) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final link = 'https://${Env.linkHost}/rsvp/${widget.ev.id}';
      final g = guestFromRow(await SupabaseService.addPrivateGuestFromUser(
        widget.ev.id, u['id'] as String, link: link));
      widget.onAdded(g);
      if (!mounted) return;
      Navigator.pop(context);
      _toast('${g.name} invited in the app 🎉', ok: true);
    } catch (e) {
      final m = e.toString();
      _toast(m.contains('duplicate') ? 'Already on the guest list' : "Couldn't add guest");
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addByNumber(String name, String phone) async {
    if (_busy) return;
    name = name.trim(); phone = phone.trim();
    if (name.isEmpty || phone.isEmpty) { _toast('Enter a name and a number'); return; }
    setState(() => _busy = true);
    try {
      final g = guestFromRow(await SupabaseService.addPrivateGuest(widget.ev.id, name, phone));
      widget.onAdded(g);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$name added — send them the invite now?'),
        backgroundColor: DelightColors.emerald,
        action: SnackBarAction(label: 'Send', textColor: Colors.white,
          onPressed: () => widget.onSend(g))));
    } catch (e) {
      _toast(e.toString().contains('duplicate')
        ? 'That number is already on the list' : "Couldn't add guest");
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(t, style: const TextStyle(fontFamily: 'Satoshi', fontSize: 10,
      fontWeight: FontWeight.w700, letterSpacing: 1.2, color: DelightColors.textMuted)));

  Widget _row({required String title, String? sub, required Widget trailing,
      required VoidCallback onTap}) => ListTile(
    dense: true, contentPadding: EdgeInsets.zero, onTap: onTap,
    leading: CircleAvatar(radius: 18,
      backgroundColor: DelightColors.surfaceBorder,
      child: Text(title.isEmpty ? '?' : title[0].toUpperCase(),
        style: const TextStyle(color: DelightColors.textPrimary))),
    title: Text(title, style: const TextStyle(fontFamily: 'Satoshi',
      fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
    subtitle: sub == null ? null : Text(sub, style: const TextStyle(
      fontFamily: 'Satoshi', fontSize: 11, color: DelightColors.textMuted)),
    trailing: trailing);

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final bookMatches = _book.where((c) {
      if (q.length < 2) return false;
      return c.displayName.toLowerCase().contains(q) ||
        c.phones.any((p) => p.number.replaceAll(' ', '').contains(q.replaceAll(' ', '')));
    }).take(15).toList();

    final onDelight = <Widget>[
      for (final u in _delight)
        _row(
          title: (u['display_name'] as String?) ?? 'Delight user',
          sub: u['username'] != null ? '@${u['username']}' : null,
          trailing: _isOnList((u['display_name'] as String?) ?? '')
            ? const Text('Added', style: TextStyle(color: DelightColors.textMuted, fontSize: 11))
            : const Text('Invite in app',
                style: TextStyle(color: DelightColors.emerald, fontSize: 12,
                  fontWeight: FontWeight.w700)),
          onTap: () => _addDelightUser(u)),
    ];

    final fromBook = <Widget>[];
    for (final c in bookMatches) {
      final num = c.phones.first.number;
      Map<String, dynamic>? dl;
      for (final p in c.phones) { dl ??= _bookOnDelight[p.number]; }
      if (dl != null) {
        fromBook.add(_row(
          title: c.displayName, sub: 'On Delight · ${dl['display_name'] ?? ''}',
          trailing: const Text('Invite in app', style: TextStyle(
            color: DelightColors.emerald, fontSize: 12, fontWeight: FontWeight.w700)),
          onTap: () => _addDelightUser(dl!)));
      } else {
        fromBook.add(_row(
          title: c.displayName, sub: num,
          trailing: const Text('Add by number', style: TextStyle(
            color: DelightColors.gold, fontSize: 12, fontWeight: FontWeight.w700)),
          onTap: () => _addByNumber(c.displayName, num)));
      }
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: DelightColors.surfaceBorder,
                borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            const Text('Add guest', style: TextStyle(fontFamily: 'Clash',
              fontSize: 22, fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
            const SizedBox(height: 10),
            TextField(
              controller: _q, onChanged: (v) { setState(() {}); _search(v); },
              style: const TextStyle(color: DelightColors.textPrimary),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search people on Delight or your contacts')),

            _label(q.length < 2 ? 'ON DELIGHT · RECENT' : 'ON DELIGHT'),
            if (onDelight.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('Nobody found on Delight yet.',
                  style: TextStyle(fontSize: 12, color: DelightColors.textMuted)))
            else ...onDelight,

            _label('YOUR CONTACTS'),
            if (!_bookLoaded)
              const Padding(padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('Checking your contacts…',
                  style: TextStyle(fontSize: 12, color: DelightColors.textMuted)))
            else if (_bookDenied)
              Row(children: [
                const Expanded(child: Text('Allow contacts to find friends.',
                  style: TextStyle(fontSize: 12, color: DelightColors.textMuted))),
                TextButton(onPressed: _loadBook, child: const Text('Allow')),
              ])
            else if (q.length < 2)
              const Padding(padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('Type a name or number to search your contacts.',
                  style: TextStyle(fontSize: 12, color: DelightColors.textMuted)))
            else if (fromBook.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('No matching contacts.',
                  style: TextStyle(fontSize: 12, color: DelightColors.textMuted)))
            else ...fromBook,

            _label('NOT LISTED? ADD BY NUMBER'),
            TextField(controller: _nameCtrl,
              style: const TextStyle(color: DelightColors.textPrimary),
              decoration: const InputDecoration(hintText: 'Guest name')),
            const SizedBox(height: 8),
            TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone,
              style: const TextStyle(color: DelightColors.textPrimary),
              decoration: const InputDecoration(hintText: 'Phone number')),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, height: 46,
              child: ElevatedButton(
                onPressed: _busy ? null
                  : () => _addByNumber(_nameCtrl.text, _phoneCtrl.text),
                child: Text(_busy ? 'Adding…' : 'Add guest'))),
          ])),
      ));
  }
}
