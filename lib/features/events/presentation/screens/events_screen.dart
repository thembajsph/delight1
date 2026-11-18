import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/models/models.dart';
import '../../../../core/services/xrpl_service.dart';
import '../../../../core/services/valr_service.dart';

class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});
  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  String _selectedCategory = 'All';
  final _categories = ['All', 'Music', 'Technology', 'Art', 'Food', 'Sports'];

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(filteredEventsProvider(_selectedCategory));

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Events', style: TextStyle(
                    fontFamily: 'Clash', fontSize: 28, fontWeight: FontWeight.w700,
                    color: DelightColors.textPrimary,
                  )),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                  GestureDetector(
                    onTap: () => context.push('/private-events'),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8B4D0).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE8B4D0).withOpacity(0.4)),
                      ),
                      child: const Row(children: [
                        Text('💍', style: TextStyle(fontSize: 14)),
                        SizedBox(width: 4),
                        Text('Private', style: TextStyle(fontFamily: 'Satoshi',
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: Color(0xFFE8B4D0))),
                      ]),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.push('/indoor-insights'),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: DelightColors.emerald.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: DelightColors.emerald.withOpacity(0.3)),
                      ),
                      child: const Row(children: [
                        Text('🏟', style: TextStyle(fontSize: 14)),
                        SizedBox(width: 4),
                        Text('Indoor', style: TextStyle(fontFamily: 'Satoshi',
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: DelightColors.emerald)),
                      ]),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.push('/event-insights'),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: DelightColors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: DelightColors.blue.withOpacity(0.3)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.insights_outlined, color: DelightColors.blue, size: 16),
                        SizedBox(width: 4),
                        Text('Insights', style: TextStyle(fontFamily: 'Satoshi',
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: DelightColors.blue)),
                      ]),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.push('/gate-scan'),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: DelightColors.goldGlow,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: DelightColors.gold.withOpacity(0.4)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.qr_code_scanner,
                          color: DelightColors.gold, size: 16),
                        SizedBox(width: 4),
                        Text('Scan Gate', style: TextStyle(
                          fontFamily: 'Satoshi', fontSize: 13,
                          fontWeight: FontWeight.w700, color: DelightColors.gold)),
                      ]),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.push('/events/create'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: DelightColors.emeraldGradient),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(children: [
                        Icon(Icons.add, color: DelightColors.textInverse, size: 16),
                        SizedBox(width: 4),
                        Text('Create', style: TextStyle(
                          fontFamily: 'Satoshi', fontSize: 13, fontWeight: FontWeight.w700,
                          color: DelightColors.textInverse,
                        )),
                      ]),
                    ),
                  ),
                    ])),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 52,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _categories.length,
                  itemBuilder: (_, i) {
                    final cat = _categories[i];
                    final selected = cat == _selectedCategory;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedCategory = cat),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          gradient: selected ? const LinearGradient(colors: DelightColors.emeraldGradient) : null,
                          color: selected ? null : DelightColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: selected ? Colors.transparent : DelightColors.surfaceBorder),
                        ),
                        alignment: Alignment.center,
                        child: Text(cat, style: TextStyle(
                          fontFamily: 'Satoshi', fontSize: 13, fontWeight: FontWeight.w600,
                          color: selected ? DelightColors.textInverse : DelightColors.textMuted,
                        )),
                      ),
                    );
                  },
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _EventCard(event: events[i]),
                  childCount: events.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final EventModel event;
  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('EEE, MMM d · HH:mm');
    return GestureDetector(
      onTap: () => context.push('/event/${event.id}', extra: event),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: DelightColors.surfaceBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Stack(children: [
              (event.coverImageUrl != null && event.coverImageUrl!.startsWith('http'))
                ? CachedNetworkImage(
                    imageUrl: event.coverImageUrl!,
                    width: double.infinity, height: 180, fit: BoxFit.cover,
                    placeholder: (_, __) => Container(height: 180, color: DelightColors.surfaceBorder),
                    errorWidget: (_, __, ___) => Container(height: 180, color: DelightColors.surfaceBorder,
                      child: const Icon(Icons.image_outlined, color: DelightColors.textMuted, size: 40)),
                  )
                : (event.coverImageUrl != null && event.coverImageUrl!.isNotEmpty)
                  ? Image.file(File(event.coverImageUrl!),
                      width: double.infinity, height: 180, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(height: 180, color: DelightColors.surfaceBorder,
                        child: const Icon(Icons.image_outlined, color: DelightColors.textMuted, size: 40)))
                  : Container(height: 180, color: DelightColors.surfaceBorder,
                      child: const Icon(Icons.image_outlined, color: DelightColors.textMuted, size: 40)),
              Positioned(top: 12, left: 12, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(8)),
                child: Text(event.category, style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 11, fontWeight: FontWeight.w700, color: DelightColors.emerald)),
              )),
              if (event.isSoldOut)
                Positioned(top: 12, right: 12, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: DelightColors.error.withOpacity(0.9), borderRadius: BorderRadius.circular(8)),
                  child: const Text('SOLD OUT', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                )),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(event.title, style: const TextStyle(
                fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.calendar_today_outlined, size: 13, color: DelightColors.textMuted),
                const SizedBox(width: 5),
                Text(dateFmt.format(event.date), style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 12, color: DelightColors.textMuted)),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.location_on_outlined, size: 13, color: DelightColors.textMuted),
                const SizedBox(width: 5),
                Expanded(child: Text('${event.venue}, ${event.city}', style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 12, color: DelightColors.textMuted),
                  overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: RichText(text: TextSpan(children: [
                  const TextSpan(text: 'From ', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 12, color: DelightColors.textMuted)),
                  TextSpan(text: DelightCurrency.formatZAR(event.lowestPrice * ValrService.cachedRateZAR),
                    style: const TextStyle(fontFamily: 'Clash', fontSize: 16,
                      fontWeight: FontWeight.w700, color: DelightColors.gold)),
                ]))),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${event.soldTickets}/${event.totalTickets} sold',
                    style: const TextStyle(fontFamily: 'Satoshi', fontSize: 11, color: DelightColors.textMuted)),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 100,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: event.totalTickets > 0 ? event.soldTickets / event.totalTickets : 0,
                        backgroundColor: DelightColors.surfaceBorder,
                        valueColor: AlwaysStoppedAnimation(
                          event.totalTickets > 0 && event.soldTickets / event.totalTickets > 0.8
                            ? DelightColors.error : DelightColors.emerald),
                        minHeight: 6,
                      ),
                    ),
                  ),
                ]),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
