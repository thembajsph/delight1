import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/models/models.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/valr_service.dart';

// ─── Ticket Tier Model ────────────────────────────────────────────────────────

class _Tier {
  String name;
  double priceZAR;
  int capacity;
  String description;

  _Tier({
    required this.name,
    required this.priceZAR,
    required this.capacity,
    this.description = '',
  });
}

// ─── Create Event Screen ──────────────────────────────────────────────────────

class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key});

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _titleCtrl  = TextEditingController();
  final _descCtrl   = TextEditingController();
  final _venueCtrl  = TextEditingController();
  final _cityCtrl   = TextEditingController();
  DateTime _date    = DateTime.now().add(const Duration(days: 30));
  String _category  = 'Music';
  bool _isPrivate   = false;

  // Media
  String? _coverUrl;
  bool _hasVideo = false;
  int _photoIdx = 0;
  Future<void> _pickCoverPhoto() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (xfile != null && mounted) {
      setState(() { _coverUrl = xfile.path; _hasVideo = false; });
    }
  }

  Future<void> _pickPromoVideo() async {
    final picker = ImagePicker();
    final xfile = await picker.pickVideo(source: ImageSource.gallery);
    if (xfile != null && mounted) {
      setState(() { _hasVideo = true; _coverUrl = null; _videoPath = xfile.path; });
    }
  }

  String? _videoPath;

  static const _sampleCovers = [
    'https://images.unsplash.com/photo-1540575467063-178a50c2df87?w=800',
    'https://images.unsplash.com/photo-1470229722913-7c0e2dbbafd3?w=800',
    'https://images.unsplash.com/photo-1501281668745-f7f57925c3b4?w=800',
    'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=800',
    'https://images.unsplash.com/photo-1505373877841-8d25f7d46678?w=800',
    'https://images.unsplash.com/photo-1578926375605-eaf7559b1458?w=800',
  ];

  final _tiers = [
    _Tier(name: 'General', priceZAR: 250, capacity: 500, description: 'Standing area access'),
    _Tier(name: 'VIP', priceZAR: 750, capacity: 100, description: 'VIP lounge + premium bar'),
    _Tier(name: 'Table', priceZAR: 2000, capacity: 20, description: 'Reserved table for 4 + bottle service'),
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _venueCtrl.dispose();
    _cityCtrl.dispose();
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
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop()),
        title: const Text('Create Event', style: TextStyle(
          fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        actions: [
          TextButton(
            onPressed: _submit,
            child: const Text('Publish', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 14, fontWeight: FontWeight.w700,
              color: DelightColors.emerald))),
        ]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cover Photo / Video ─────────────────────────────────
            _buildMediaPicker(),
            const SizedBox(height: 20),

            _field('Event Name', _titleCtrl, Icons.event_outlined),
            const SizedBox(height: 14),
            _field('Description', _descCtrl, Icons.description_outlined, maxLines: 3),
            const SizedBox(height: 14),
            _field('Venue', _venueCtrl, Icons.location_on_outlined),
            const SizedBox(height: 14),
            _field('City', _cityCtrl, Icons.location_city_outlined),
            const SizedBox(height: 20),

            // Date picker
            const Text('Date & Time', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 13, fontWeight: FontWeight.w700,
              color: DelightColors.textMuted, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: DelightColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: DelightColors.surfaceBorder)),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined,
                    color: DelightColors.emerald, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    '${_date.day}/${_date.month}/${_date.year}  '
                    '${_date.hour.toString().padLeft(2, "0")}:${_date.minute.toString().padLeft(2, "0")}',
                    style: const TextStyle(fontFamily: 'Satoshi', fontSize: 14,
                      color: DelightColors.textPrimary)),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: DelightColors.textMuted, size: 18),
                ]))),
            const SizedBox(height: 20),

            // Category
            const Text('Category', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 13, fontWeight: FontWeight.w700,
              color: DelightColors.textMuted, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: ['Music', 'Sport', 'Arts', 'Food', 'Business', 'Festival', 'Church', 'Other']
                .map((cat) {
                  final sel = cat == _category;
                  return GestureDetector(
                    onTap: () => setState(() => _category = cat),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? DelightColors.emeraldGlow : DelightColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel ? DelightColors.emerald : DelightColors.surfaceBorder)),
                      child: Text(cat, style: TextStyle(
                        fontFamily: 'Satoshi', fontSize: 13, fontWeight: FontWeight.w600,
                        color: sel ? DelightColors.emerald : DelightColors.textMuted))));
                }).toList()),
            const SizedBox(height: 20),

            // Private toggle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: DelightColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DelightColors.surfaceBorder)),
              child: Row(children: [
                const Icon(Icons.lock_outline, color: DelightColors.textMuted, size: 18),
                const SizedBox(width: 10),
                const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Private Event', style: TextStyle(
                      fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                      fontSize: 14, color: DelightColors.textPrimary)),
                    Text('Only invited guests can buy tickets',
                      style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                        color: DelightColors.textMuted)),
                  ])),
                Switch(
                  value: _isPrivate,
                  onChanged: (v) => setState(() => _isPrivate = v),
                  activeColor: DelightColors.emerald),
              ])),
            const SizedBox(height: 24),

            // Ticket tiers
            Row(children: [
              const Expanded(child: Text('Ticket Tiers', style: TextStyle(
                fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary))),
              GestureDetector(
                onTap: _addTier,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: DelightColors.emeraldGlow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
                  child: const Row(children: [
                    Icon(Icons.add, color: DelightColors.emerald, size: 16),
                    SizedBox(width: 4),
                    Text('Add Tier', style: TextStyle(fontFamily: 'Satoshi',
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: DelightColors.emerald)),
                  ]))),
            ]),
            const SizedBox(height: 12),
            ..._tiers.asMap().entries.map((e) => _buildTierCard(e.key, e.value)),
            const SizedBox(height: 16),

            // NFT info
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: DelightColors.goldGlow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: DelightColors.gold.withOpacity(0.3))),
              child: const Row(children: [
                Icon(Icons.diamond_outlined, color: DelightColors.gold, size: 20),
                SizedBox(width: 10),
                Expanded(child: Text(
                  'Each ticket is minted as an NFT on the XRP Ledger. '
                  'A 3% platform fee applies per sale. '
                  'Resale royalties are locked on-chain at 3%.',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                    color: DelightColors.gold, height: 1.5))),
              ])),
            const SizedBox(height: 32),

            // Publish button
            GestureDetector(
              onTap: _submit,
              child: Container(
                height: 60, width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: DelightColors.emeraldGradient),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(
                    color: DelightColors.emerald.withOpacity(0.4),
                    blurRadius: 16, offset: const Offset(0, 4))]),
                alignment: Alignment.center,
                child: const Text('Publish Event', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 17,
                  fontWeight: FontWeight.w700, color: Colors.white)))),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildTierCard(int index, _Tier tier) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: DelightColors.emeraldGlow,
                shape: BoxShape.circle,
                border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
              alignment: Alignment.center,
              child: const Icon(Icons.confirmation_number_outlined,
                color: DelightColors.emerald, size: 16)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tier.name, style: const TextStyle(
                  fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                  fontSize: 15, color: DelightColors.textPrimary)),
                Text(tier.description, style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 11, color: DelightColors.textMuted)),
              ])),
            Text('R${tier.priceZAR.toStringAsFixed(0)}', style: const TextStyle(
              fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
              color: DelightColors.emerald)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _editTier(index, tier),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: DelightColors.surfaceBorder,
                  borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.edit_outlined,
                  color: DelightColors.textMuted, size: 14))),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => setState(() => _tiers.removeAt(index)),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: DelightColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.delete_outline,
                  color: DelightColors.error.withOpacity(0.7), size: 14))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.people_outline, size: 13, color: DelightColors.textMuted),
            const SizedBox(width: 4),
            Text('${tier.capacity} capacity', style: const TextStyle(
              fontFamily: 'Satoshi', fontSize: 11, color: DelightColors.textMuted)),
            const Spacer(),
            Text('Delight fee: R${(tier.priceZAR * 0.03).toStringAsFixed(0)} · '
              'You earn: R${(tier.priceZAR * 0.97).toStringAsFixed(0)}',
              style: const TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                color: DelightColors.textSecondary)),
          ]),
        ],
      ),
    );
  }

  void _editTier(int index, _Tier tier) {
    final nameCtrl  = TextEditingController(text: tier.name);
    final priceCtrl = TextEditingController(text: tier.priceZAR.toStringAsFixed(0));
    final capCtrl   = TextEditingController(text: tier.capacity.toString());
    final descCtrl  = TextEditingController(text: tier.description);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DelightColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Edit Ticket Tier', style: TextStyle(
              fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
              color: DelightColors.textPrimary)),
            const SizedBox(height: 20),
            _sheetField('Tier Name', nameCtrl, Icons.label_outline),
            const SizedBox(height: 12),
            _sheetField('Price (ZAR)', priceCtrl, Icons.attach_money,
              keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            _sheetField('Capacity', capCtrl, Icons.people_outline,
              keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            _sheetField('Description', descCtrl, Icons.description_outlined),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                setState(() {
                  _tiers[index] = _Tier(
                    name: nameCtrl.text.isEmpty ? tier.name : nameCtrl.text,
                    priceZAR: double.tryParse(priceCtrl.text) ?? tier.priceZAR,
                    capacity: int.tryParse(capCtrl.text) ?? tier.capacity,
                    description: descCtrl.text,
                  );
                });
                Navigator.pop(context);
              },
              child: Container(
                height: 54, width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: DelightColors.emeraldGradient),
                  borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: const Text('Save Changes', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 16, fontWeight: FontWeight.w700,
                  color: Colors.white)))),
          ])));
  }

  void _addTier() {
    setState(() {
      _tiers.add(_Tier(name: 'New Tier', priceZAR: 150, capacity: 50));
    });
    _editTier(_tiers.length - 1, _tiers.last);
  }

  Widget _sheetField(String label, TextEditingController ctrl, IconData icon,
      {TextInputType keyboardType = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(fontFamily: 'Satoshi',
        color: DelightColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Satoshi',
          color: DelightColors.textMuted, fontSize: 13),
        prefixIcon: Icon(icon, color: DelightColors.textMuted, size: 18),
        filled: true, fillColor: DelightColors.background,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DelightColors.emerald))));
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: DelightColors.emerald)),
        child: child!));
    if (picked != null) setState(() => _date = picked);
  }

  bool _submitting = false;

  Future<void> _submit() async {
    if (_titleCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an event name')));
      return;
    }
    if (_tiers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one ticket tier')));
      return;
    }
    final user = ref.read(authProvider);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in first')));
      return;
    }

    setState(() => _submitting = true);
    final db = Supabase.instance.client;

    try {
      // 1. Insert the event row first so we have a real DB-generated ID —
      //    that ID is what we use for the storage path and what every
      //    other screen (detail, tickets, insights) will reference.
      final ticketTiersJson = _tiers.map((t) => {
        'id':       't_${DateTime.now().microsecondsSinceEpoch}_${_tiers.indexOf(t)}',
        'name':     t.name,
        'priceXRP': t.priceZAR / ValrService.cachedRateZAR,
        'totalTickets': t.capacity,
        'soldTickets':  0,
        'perks':    t.description.isEmpty ? <String>[] : [t.description],
      }).toList();

      final row = await db.from('events').insert({
        'organizer_id': user.id,
        'name':         _titleCtrl.text.trim(),
        'description':  _descCtrl.text.trim().isEmpty
          ? 'An amazing event on Delight.' : _descCtrl.text.trim(),
        'venue':        _venueCtrl.text.trim().isEmpty ? 'TBC' : _venueCtrl.text.trim(),
        'city':         _cityCtrl.text.trim().isEmpty ? 'South Africa' : _cityCtrl.text.trim(),
        'event_date':   _date.toIso8601String(),
        'category':     _category,
        'ticket_tiers': ticketTiersJson,
        'is_published': true,
      }).select().single();

      final eventId = row['id'] as String;

      // 2. Upload the real cover photo now that we have a real event ID
      String? finalImageUrl;
      if (_coverUrl != null && !_coverUrl!.startsWith('http')) {
        final bytes = await File(_coverUrl!).readAsBytes();
        finalImageUrl = await SupabaseService.uploadEventImage(
          eventId, Uint8List.fromList(bytes), 'jpg');
        await db.from('events').update({'image_url': finalImageUrl}).eq('id', eventId);
      } else {
        finalImageUrl = _coverUrl;
      }

      // 3. Reflect the real saved event in local state immediately so the
      //    UI updates without waiting for a full re-fetch.
      final newEvent = EventModel(
        id: eventId,
        organizerId: user.id,
        organizerName: user.displayName,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty
          ? 'An amazing event on Delight.' : _descCtrl.text.trim(),
        coverImageUrl: finalImageUrl,
        venue: _venueCtrl.text.trim().isEmpty ? 'TBC' : _venueCtrl.text.trim(),
        city: _cityCtrl.text.trim().isEmpty ? 'South Africa' : _cityCtrl.text.trim(),
        country: 'South Africa',
        date: _date,
        category: _category,
        ticketTiers: _tiers.asMap().entries.map((e) => TicketTier(
          id: (ticketTiersJson[e.key]['id'] as String),
          name: e.value.name,
          priceXRP: e.value.priceZAR / ValrService.cachedRateZAR,
          totalTickets: e.value.capacity,
          soldTickets: 0,
          perks: e.value.description.isEmpty ? [] : [e.value.description],
        )).toList(),
      );
      ref.read(eventsProvider.notifier).add(newEvent);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${newEvent.title} is live and saved! 🎉'),
            backgroundColor: DelightColors.emerald));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not create event: ${e.toString().split(']').last.trim()}'),
          backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildMediaPicker() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Event Cover', style: TextStyle(fontFamily: 'Satoshi',
        fontSize: 13, fontWeight: FontWeight.w700, color: DelightColors.textMuted,
        letterSpacing: 0.5)),
      const SizedBox(height: 8),

      // Preview
      if (_coverUrl != null)
        Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: _coverUrl!.startsWith('http')
              ? CachedNetworkImage(
                  imageUrl: _coverUrl!,
                  width: double.infinity, height: 160, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    height: 160, color: DelightColors.surfaceHigh,
                    child: const Icon(Icons.broken_image_outlined,
                      color: DelightColors.textMuted)))
              : Image.file(File(_coverUrl!),
                  width: double.infinity, height: 160, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 160, color: DelightColors.surfaceHigh,
                    child: const Icon(Icons.broken_image_outlined,
                      color: DelightColors.textMuted)))),
          Positioned(top: 8, right: 8,
            child: GestureDetector(
              onTap: () => setState(() { _coverUrl = null; _hasVideo = false; }),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close,
                  color: Colors.white, size: 14)))),
          Positioned(bottom: 8, left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.auto_awesome, color: DelightColors.gold, size: 12),
                SizedBox(width: 4),
                Text('Event cover', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 10,
                  color: Colors.white70)),
              ]))),
        ])
      else if (_hasVideo)
        Container(
          height: 100,
          decoration: BoxDecoration(
            color: DelightColors.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DelightColors.gold.withOpacity(0.4))),
          child: const Center(child: Row(
            mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.play_circle_outline,
              color: DelightColors.gold, size: 32),
            SizedBox(width: 8),
            Text('Promo video attached', style: TextStyle(
              fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
              fontSize: 13, color: DelightColors.gold)),
          ])))
      else
        // Placeholder
        GestureDetector(
          onTap: _pickCoverPhoto,
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              color: DelightColors.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: DelightColors.surfaceBorder,
                style: BorderStyle.solid)),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_photo_alternate_outlined,
                color: DelightColors.textMuted, size: 32),
              SizedBox(height: 6),
              Text('Tap to add event cover photo',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                  color: DelightColors.textMuted)),
            ]))),

      const SizedBox(height: 8),

      // Action buttons
      Row(children: [
        Expanded(child: GestureDetector(
          onTap: _pickCoverPhoto,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: DelightColors.blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _coverUrl != null
                  ? DelightColors.blue
                  : DelightColors.blue.withOpacity(0.3))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_photo_alternate_outlined,
                color: DelightColors.blue, size: 16),
              const SizedBox(width: 6),
              Text(_coverUrl != null ? '✓ Photo' : 'Add Photo',
                style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                  fontWeight: FontWeight.w700, color: DelightColors.blue)),
            ])))),
        const SizedBox(width: 8),
        Expanded(child: GestureDetector(
          onTap: _pickPromoVideo,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: DelightColors.gold.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _hasVideo
                  ? DelightColors.gold
                  : DelightColors.gold.withOpacity(0.3))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.videocam_outlined,
                color: DelightColors.gold, size: 16),
              const SizedBox(width: 6),
              Text(_hasVideo ? '✓ Video' : 'Add Video',
                style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                  fontWeight: FontWeight.w700, color: DelightColors.gold)),
            ])))),
        const SizedBox(width: 8),
        Expanded(child: GestureDetector(
          onTap: _pickCoverPhoto,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: DelightColors.emeraldGlow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: DelightColors.emerald.withOpacity(0.3))),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.collections_outlined,
                color: DelightColors.emerald, size: 16),
              SizedBox(width: 6),
              Text('Browse', style: TextStyle(fontFamily: 'Satoshi',
                fontSize: 12, fontWeight: FontWeight.w700,
                color: DelightColors.emerald)),
            ])))),
      ]),
    ]);
  }

  Widget _field(String label, TextEditingController ctrl, IconData icon,
      {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
          fontWeight: FontWeight.w700, color: DelightColors.textMuted,
          letterSpacing: 0.5)),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: const TextStyle(fontFamily: 'Satoshi',
            color: DelightColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: DelightColors.textMuted, size: 18),
            filled: true, fillColor: DelightColors.surfaceHigh,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DelightColors.emerald)))),
      ]);
  }
}
