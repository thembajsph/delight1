import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/models/models.dart';
import '../../../../core/services/xrpl_service.dart';
import '../../../../core/services/valr_service.dart';

class EventDetailScreen extends ConsumerStatefulWidget {
  final EventModel event;
  const EventDetailScreen({super.key, required this.event});
  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  TicketTier? _selectedTier;
  bool _purchasing = false;
  bool _purchased = false;

  Future<void> _buyTicket() async {
    if (_selectedTier == null) return;
    final wallet = ref.read(walletProvider);
    if (wallet == null) {
      _snack('Please set up your wallet first', isError: true); return;
    }
    final priceZAR = _selectedTier!.priceXRP * ValrService.cachedRateZAR;
    if ((wallet.balanceXRP * ValrService.cachedRateZAR) < priceZAR) {
      showModalBottomSheet(
        context: context,
        backgroundColor: DelightColors.surfaceHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('💸', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            const Text('Not enough balance', style: TextStyle(
              fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
              color: DelightColors.textPrimary)),
            const SizedBox(height: 8),
            Text(
              'You need ${DelightCurrency.formatZAR(priceZAR)} for this ticket.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                color: DelightColors.textMuted)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () { Navigator.pop(context); context.push('/topup'); },
              child: const Text('Add Money')),
          ])));
      return;
    }

    setState(() => _purchasing = true);
    try {
      await SupabaseService.mintTicket(
        eventId: widget.event.id,
        tier: _selectedTier!.name,
        priceZAR: priceZAR,
      );

      final user = ref.read(authProvider);
      if (user != null) {
        await ref.read(ticketsProvider.notifier).loadFromDB(user.id);
        await ref.read(transactionsProvider.notifier).loadFromDB(user.id);
      }
      await ref.read(walletProvider.notifier).refreshBalance();

      ref.read(analyticsProvider.notifier).track('ticket_purchased');
      setState(() { _purchasing = false; _purchased = true; });
      if (mounted) _showPurchaseCelebration();
    } catch (e) {
      setState(() => _purchasing = false);
      if (mounted) {
        _snack('Purchase failed: ${e.toString().split(']').last.trim()}',
          isError: true);
      }
    }
  }

  void _showPurchaseCelebration() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF060F0A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        final event = widget.event;
        final tier = _selectedTier!;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Celebratory header
            const Text('🎉', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 12),
            Text('You\'re going!',
              style: const TextStyle(fontFamily: 'Clash', fontSize: 28,
                fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 6),
            Text(event.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Satoshi', fontSize: 16,
                color: Color(0xFF9BBFAA), height: 1.3)),
            const SizedBox(height: 20),
            // Ticket preview card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  const Color(0xFF00C96A).withOpacity(0.15),
                  const Color(0xFF060F0A)]),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF00C96A).withOpacity(0.3))),
              child: Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C96A).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10)),
                  alignment: Alignment.center,
                  child: const Icon(Icons.confirmation_number_outlined,
                    color: Color(0xFF00C96A), size: 24)),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tier.name, style: const TextStyle(
                    fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                    fontSize: 15, color: Colors.white)),
                  Text('${event.venue}, ${event.city}',
                    style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                      color: Color(0xFF9BBFAA))),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C96A).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF00C96A).withOpacity(0.3))),
                  child: const Text('NFT', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 10,
                    fontWeight: FontWeight.w800, color: Color(0xFF00C96A),
                    letterSpacing: 0.8))),
              ])),
            const SizedBox(height: 16),
            // What next
            const Text('Your ticket is in your wallet.',
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                color: Color(0xFF9BBFAA))),
            const SizedBox(height: 4),
            const Text('Share the event with friends so they don\'t miss out.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                color: Color(0xFF5A8A6A), height: 1.4)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    Navigator.pop(context);
                    context.go('/wallet');
                  },
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00C96A), Color(0xFF00854A)]),
                      borderRadius: BorderRadius.circular(14)),
                    alignment: Alignment.center,
                    child: const Text('View My Ticket',
                      style: TextStyle(fontFamily: 'Satoshi', fontSize: 14,
                        fontWeight: FontWeight.w800, color: Colors.white)))))),
              const SizedBox(width: 10),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    Navigator.pop(context);
                    Share.share('I\'m going to ${widget.event.title} — '
                      '${widget.event.venue}, ${widget.event.city} 🔥\n'
                      'Get tickets on Delight 👉 delight.africa');
                  },
                  child: Container(
                    height: 52, width: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A3A25),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF00C96A).withOpacity(0.25))),
                    alignment: Alignment.center,
                    child: const Icon(Icons.share_outlined,
                      color: Color(0xFF00C96A), size: 20)))),
            ]),
          ]));
      });
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? DelightColors.error : DelightColors.emerald,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final dateFmt = DateFormat('EEEE, MMMM d yyyy · HH:mm');

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      body: Stack(children: [
        CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 280,
              pinned: true,
              backgroundColor: DelightColors.background,
              leading: GestureDetector(
                onTap: () => context.pop(),
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_back, color: Colors.white),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: (event.coverImageUrl != null &&
                    event.coverImageUrl!.startsWith('http'))
                  ? CachedNetworkImage(
                      imageUrl: event.coverImageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                        Container(color: DelightColors.surfaceBorder))
                  : (event.coverImageUrl != null &&
                      event.coverImageUrl!.isNotEmpty)
                    ? Image.file(File(event.coverImageUrl!), fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                          Container(color: DelightColors.surfaceBorder))
                    : Container(color: DelightColors.surfaceBorder),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: DelightColors.emeraldGlow,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: DelightColors.emerald.withOpacity(0.3)),
                      ),
                      child: Text(event.category, style: const TextStyle(
                        fontFamily: 'Satoshi', fontSize: 11, fontWeight: FontWeight.w700,
                        color: DelightColors.emerald)),
                    ),
                    const Spacer(),
                    Text('${event.soldTickets} attending', style: const TextStyle(
                      fontFamily: 'Satoshi', fontSize: 12, color: DelightColors.textMuted)),
                  ]),
                  const SizedBox(height: 12),
                  Text(event.title, style: const TextStyle(
                    fontFamily: 'Clash', fontSize: 26, fontWeight: FontWeight.w700,
                    color: DelightColors.textPrimary, height: 1.15)),
                  const SizedBox(height: 16),

                  _infoRow(Icons.person_outline, event.organizerName),
                  const SizedBox(height: 8),
                  _infoRow(Icons.calendar_today_outlined, dateFmt.format(event.date)),
                  const SizedBox(height: 8),
                  _infoRow(Icons.location_on_outlined, '${event.venue}, ${event.city}, ${event.country}'),
                  const SizedBox(height: 20),

                  const Divider(color: DelightColors.surfaceBorder),
                  const SizedBox(height: 16),

                  Text(event.description, style: const TextStyle(
                    fontFamily: 'Satoshi', fontSize: 14, color: DelightColors.textSecondary, height: 1.65)),
                  const SizedBox(height: 24),

                  const Text('Select Ticket Tier', style: TextStyle(
                    fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
                    color: DelightColors.textPrimary)),
                  const SizedBox(height: 12),

                  ...event.ticketTiers.map((tier) => GestureDetector(
                    onTap: tier.available > 0 ? () => setState(() => _selectedTier = tier) : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _selectedTier?.id == tier.id ? DelightColors.emeraldGlow : DelightColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _selectedTier?.id == tier.id ? DelightColors.emerald : DelightColors.surfaceBorder,
                          width: _selectedTier?.id == tier.id ? 1.5 : 1,
                        ),
                      ),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tier.name, style: const TextStyle(
                            fontFamily: 'Satoshi', fontWeight: FontWeight.w700,
                            color: DelightColors.textPrimary, fontSize: 15)),
                          if (tier.perks.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(tier.perks.join(' · '), style: const TextStyle(
                              fontFamily: 'Satoshi', fontSize: 11, color: DelightColors.textMuted)),
                          ],
                          const SizedBox(height: 6),
                          Text('${tier.available} remaining', style: TextStyle(
                            fontFamily: 'Satoshi', fontSize: 11,
                            color: tier.available < 20 ? DelightColors.error : DelightColors.textMuted)),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(DelightCurrency.formatZAR(tier.priceXRP * 9.50), style: const TextStyle(
                            fontFamily: 'Clash', fontSize: 16, fontWeight: FontWeight.w700,
                            color: DelightColors.gold)),
                          Text(DelightCurrency.formatZAR(tier.priceXRP * 9.50),
                            style: const TextStyle(fontFamily: 'Satoshi', fontSize: 11, color: DelightColors.textMuted)),
                        ]),
                      ]),
                    ),
                  )),

                  const SizedBox(height: 100), // Space for bottom button
                ]),
              ),
            ),
          ],
        ),

        // Buy button
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, DelightColors.background],
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
              ),
            ),
            child: _purchased
              ? GestureDetector(
                  onTap: () => context.go('/wallet'),
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00C96A), Color(0xFF00854A)]),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [BoxShadow(
                        color: const Color(0xFF00C96A).withOpacity(0.4),
                        blurRadius: 20, offset: const Offset(0, 4))]),
                    alignment: Alignment.center,
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('🎟', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 8),
                      Text('Ticket in your wallet — tap to view',
                        style: TextStyle(fontFamily: 'Satoshi', fontSize: 14,
                          fontWeight: FontWeight.w800, color: Colors.white)),
                    ])))
              : GestureDetector(
                  onTap: _selectedTier == null || _purchasing ? null : _buyTicket,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: _selectedTier != null
                        ? const LinearGradient(colors: DelightColors.goldGradient)
                        : null,
                      color: _selectedTier == null ? DelightColors.surfaceHigh : null,
                      borderRadius: BorderRadius.circular(18),
                      border: _selectedTier == null
                        ? Border.all(color: DelightColors.surfaceBorder) : null,
                      boxShadow: _selectedTier != null ? [BoxShadow(
                        color: DelightColors.gold.withOpacity(0.3),
                        blurRadius: 20, offset: const Offset(0, 6),
                      )] : [],
                    ),
                    alignment: Alignment.center,
                    child: _purchasing
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(
                          color: DelightColors.textInverse, strokeWidth: 2.5))
                      : Text(
                          _selectedTier == null
                            ? 'Select a ticket tier'
                            : 'Buy ${_selectedTier!.name} — ${DelightCurrency.formatZAR(_selectedTier!.priceXRP * 9.50)}',
                          style: TextStyle(
                            fontFamily: 'Satoshi', fontSize: 16, fontWeight: FontWeight.w700,
                            color: _selectedTier != null ? DelightColors.textInverse : DelightColors.textMuted,
                          ),
                        ),
                  ),
                ),
          ),
        ),
      ]),
    );
  }

  Widget _infoRow(IconData icon, String text) => Row(children: [
    Icon(icon, size: 15, color: DelightColors.emerald),
    const SizedBox(width: 8),
    Expanded(child: Text(text, style: const TextStyle(
      fontFamily: 'Satoshi', fontSize: 13, color: DelightColors.textSecondary))),
  ]);
}
