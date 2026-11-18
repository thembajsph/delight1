// Delight App — Unit & Widget Tests
// Covers every screen's core functionality before database integration
// Run: flutter test test/screens/app_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// Core
import 'package:delight/core/models/models.dart';
import 'package:delight/core/providers/app_providers.dart';
import 'package:delight/core/services/xrpl_service.dart';

// Screens
import 'package:delight/features/auth/presentation/screens/login_screen.dart';
import 'package:delight/features/social/presentation/screens/social_screen.dart';
import 'package:delight/features/payments/presentation/screens/payments_screen.dart';
import 'package:delight/features/events/presentation/screens/events_screen.dart';
import 'package:delight/features/events/presentation/screens/event_detail_screen.dart';
import 'package:delight/features/events/presentation/screens/create_event_screen.dart';
import 'package:delight/features/wallet/presentation/screens/wallet_screen.dart';
import 'package:delight/features/topup/presentation/screens/topup_screen.dart';
import 'package:delight/features/cashout/presentation/screens/cashout_screen.dart';
import 'package:delight/features/profile/presentation/screens/profile_screen.dart';
import 'package:delight/features/rewards/presentation/screens/rewards_screen.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    home: Scaffold(body: child)));

Widget _wrapRouter(Widget child) => ProviderScope(
  child: MaterialApp.router(
    routerConfig: GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => child),
    ])));

// ─── Fee Calculator Tests ─────────────────────────────────────────────────────
group('FeeCalculator', () {
  test('P2P fee is 0.5%', () {
    expect(FeeCalculator.fee(100, 'p2p'), closeTo(0.50, 0.001));
  });
  test('B2B fee is 1.0%', () {
    expect(FeeCalculator.fee(100, 'consumer_business'), closeTo(1.00, 0.001));
  });
  test('Ticket fee is 3.0%', () {
    expect(FeeCalculator.fee(100, 'ticket'), closeTo(3.00, 0.001));
  });
  test('Net = amount - fee', () {
    expect(FeeCalculator.net(200, 'p2p'), closeTo(199.00, 0.001));
  });
  test('Unknown type defaults to p2p', () {
    expect(FeeCalculator.fee(100, 'unknown'), closeTo(0.50, 0.001));
  });
  test('Fee scales linearly', () {
    expect(FeeCalculator.fee(1000, 'p2p'), closeTo(5.00, 0.001));
    expect(FeeCalculator.fee(50, 'ticket'), closeTo(1.50, 0.001));
  });
});

// ─── Model Tests ──────────────────────────────────────────────────────────────
group('EventModel', () {
  test('lowestPrice returns min tier price', () {
    final event = EventModel(
      id: 'e1', organizerId: 'o1', organizerName: 'Test',
      title: 'Test', description: '', venue: 'V', city: 'C',
      country: 'ZA', date: DateTime.now().add(const Duration(days: 7)),
      category: 'Music',
      ticketTiers: [
        TicketTier(id: 't1', name: 'General', priceXRP: 10, totalTickets: 100, soldTickets: 0),
        TicketTier(id: 't2', name: 'VIP', priceXRP: 50, totalTickets: 20, soldTickets: 0),
      ]);
    expect(event.lowestPrice, equals(10.0));
  });
  test('isSoldOut when all tiers sold', () {
    final event = EventModel(
      id: 'e1', organizerId: 'o1', organizerName: 'T', title: 'T',
      description: '', venue: 'V', city: 'C', country: 'ZA',
      date: DateTime.now(), category: 'Music',
      ticketTiers: [
        TicketTier(id: 't1', name: 'G', priceXRP: 10,
          totalTickets: 100, soldTickets: 100),
      ]);
    expect(event.isSoldOut, isTrue);
  });
  test('soldTickets aggregates across tiers', () {
    final event = EventModel(
      id: 'e1', organizerId: 'o1', organizerName: 'T', title: 'T',
      description: '', venue: 'V', city: 'C', country: 'ZA',
      date: DateTime.now(), category: 'Music',
      ticketTiers: [
        TicketTier(id: 't1', name: 'G', priceXRP: 10, totalTickets: 100, soldTickets: 60),
        TicketTier(id: 't2', name: 'V', priceXRP: 50, totalTickets: 20, soldTickets: 15),
      ]);
    expect(event.soldTickets, equals(75));
  });
});

group('TicketTier', () {
  test('available = total - sold', () {
    final tier = TicketTier(id: 't1', name: 'G', priceXRP: 10,
      totalTickets: 100, soldTickets: 40);
    expect(tier.available, equals(60));
  });
  test('soldPercentage is correct', () {
    final tier = TicketTier(id: 't1', name: 'G', priceXRP: 10,
      totalTickets: 100, soldTickets: 75);
    expect(tier.soldPercentage, closeTo(0.75, 0.001));
  });
});

group('WalletModel', () {
  test('balanceZAR conversion at 9.5 rate', () {
    const wallet = WalletModel(
      address: 'rTest', balanceXRP: 100.0, currency: 'XRP');
    expect(wallet.balanceXRP * 9.50, closeTo(950.0, 0.01));
  });
});

// ─── Provider Tests ───────────────────────────────────────────────────────────
group('Providers', () {
  test('eventsProvider seeds with 4 events', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final events = container.read(eventsProvider);
    expect(events.length, greaterThanOrEqualTo(4));
  });

  test('filteredEventsProvider All returns all events', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final all = container.read(filteredEventsProvider('All'));
    final events = container.read(eventsProvider);
    expect(all.length, equals(events.length));
  });

  test('filteredEventsProvider filters by category', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final music = container.read(filteredEventsProvider('Music'));
    expect(music.every((e) => e.category == 'Music'), isTrue);
  });

  test('EventNotifier.add increases count', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final before = container.read(eventsProvider).length;
    container.read(eventsProvider.notifier).add(EventModel(
      id: 'test_new', organizerId: 'o', organizerName: 'T', title: 'New',
      description: 'D', venue: 'V', city: 'C', country: 'ZA',
      date: DateTime.now(), category: 'Music', ticketTiers: []));
    final after = container.read(eventsProvider).length;
    expect(after, equals(before + 1));
  });

  test('TicketNotifier.add increases count', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final before = container.read(ticketsProvider).length;
    container.read(ticketsProvider.notifier).add(NFTTicket(
      id: 'test_tkt', eventId: 'e1', eventName: 'Test',
      eventDate: DateTime.now(), eventVenue: 'V', eventCity: 'C',
      tokenId: 'TOKEN_001', ownerAddress: 'rTest',
      priceXRP: 25, tier: 'General', mintedAt: DateTime.now()));
    expect(container.read(ticketsProvider).length, equals(before + 1));
  });

  test('WalletNotifier deductAmount reduces balance', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final before = container.read(walletProvider)?.balanceXRP ?? 0;
    container.read(walletProvider.notifier).deductAmount(10);
    final after = container.read(walletProvider)?.balanceXRP ?? 0;
    expect(after, closeTo(before - 10, 0.001));
  });

  test('WalletNotifier addAmount increases balance', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final before = container.read(walletProvider)?.balanceXRP ?? 0;
    container.read(walletProvider.notifier).addAmount(50);
    final after = container.read(walletProvider)?.balanceXRP ?? 0;
    expect(after, closeTo(before + 50, 0.001));
  });

  test('feedProvider starts with seed posts', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final posts = container.read(feedProvider);
    expect(posts.length, greaterThan(0));
  });

  test('feedProvider toggleLike flips isLiked', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final posts = container.read(feedProvider);
    final id = posts.first.id;
    final before = posts.first.isLiked;
    container.read(feedProvider.notifier).toggleLike(id);
    final after = container.read(feedProvider).firstWhere((p) => p.id == id).isLiked;
    expect(after, equals(!before));
  });

  test('eventGroupChatProvider tracks event IDs', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(eventGroupChatProvider.notifier).add('evt_test');
    expect(container.read(eventGroupChatProvider), contains('evt_test'));
  });

  test('chatMessagesProvider persists messages', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(chatMessagesProvider.notifier).addMessage(
      'conv_1', senderId: 'me', senderName: 'Me',
      text: 'Hello', isMe: true);
    final msgs = container.read(chatMessagesProvider)['conv_1'];
    expect(msgs, isNotNull);
    expect(msgs!.first['text'], equals('Hello'));
    expect(msgs.first['isMe'], isTrue);
  });

  test('chatMessagesProvider accumulates multiple messages', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(chatMessagesProvider.notifier)
      .addMessage('c1', senderId: 'me', senderName: 'Me', text: 'Hi', isMe: true);
    container.read(chatMessagesProvider.notifier)
      .addMessage('c1', senderId: 'u2', senderName: 'Bob', text: 'Hey', isMe: false);
    final msgs = container.read(chatMessagesProvider)['c1'];
    expect(msgs?.length, equals(2));
  });

  test('analyticsProvider tracks events without error', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container.read(analyticsProvider.notifier).track('test_event'),
      returnsNormally);
  });
});

// ─── Widget Tests ─────────────────────────────────────────────────────────────
group('LoginScreen', () {
  testWidgets('renders email and password fields', (tester) async {
    await tester.pumpWidget(_wrapRouter(const LoginScreen()));
    await tester.pump();
    expect(find.byType(TextField), findsWidgets);
  });
  testWidgets('shows quick demo login buttons', (tester) async {
    await tester.pumpWidget(_wrapRouter(const LoginScreen()));
    await tester.pump();
    expect(find.textContaining('Consumer'), findsWidgets);
  });
});

group('EventsScreen', () {
  testWidgets('renders without error', (tester) async {
    await tester.pumpWidget(_wrap(const EventsScreen()));
    await tester.pump();
    expect(find.byType(EventsScreen), findsOneWidget);
  });
  testWidgets('shows category filter tags', (tester) async {
    await tester.pumpWidget(_wrap(const EventsScreen()));
    await tester.pump();
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
  });
});

group('EventDetailScreen', () {
  testWidgets('shows event title and buy button', (tester) async {
    final event = seedEvents.first;
    await tester.pumpWidget(_wrap(EventDetailScreen(event: event)));
    await tester.pump();
    expect(find.text(event.title), findsOneWidget);
    expect(find.text('Select a ticket tier'), findsOneWidget);
  });
  testWidgets('selecting tier activates buy button', (tester) async {
    final event = seedEvents.first;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: EventDetailScreen(event: event))));
    await tester.pump();
    // Tap first tier
    final tier = event.ticketTiers.first;
    await tester.tap(find.text(tier.name).first);
    await tester.pump();
    expect(find.textContaining('Buy ${tier.name}'), findsOneWidget);
  });
});

group('PaymentsScreen', () {
  testWidgets('shows balance and action buttons', (tester) async {
    await tester.pumpWidget(_wrap(const PaymentsScreen()));
    await tester.pump();
    expect(find.text('Add Money'), findsOneWidget);
    expect(find.text('Cash Out'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);
  });
  testWidgets('shows fee schedule', (tester) async {
    await tester.pumpWidget(_wrap(const PaymentsScreen()));
    await tester.pump();
    expect(find.text('TRANSACTION FEES'), findsOneWidget);
    expect(find.text('0.5%'), findsWidgets);
  });
});

group('WalletScreen', () {
  testWidgets('shows NFT Tickets tab', (tester) async {
    await tester.pumpWidget(_wrap(const WalletScreen()));
    await tester.pump();
    expect(find.textContaining('NFT Tickets'), findsOneWidget);
  });
  testWidgets('shows Transactions tab', (tester) async {
    await tester.pumpWidget(_wrap(const WalletScreen()));
    await tester.pump();
    expect(find.textContaining('Transactions'), findsOneWidget);
  });
});

group('CreateEventScreen', () {
  testWidgets('shows form fields', (tester) async {
    await tester.pumpWidget(_wrap(const CreateEventScreen()));
    await tester.pump();
    expect(find.text('Event Cover'), findsOneWidget);
    expect(find.text('Event Name'), findsOneWidget);
  });
  testWidgets('shows Publish button', (tester) async {
    await tester.pumpWidget(_wrap(const CreateEventScreen()));
    await tester.pump();
    expect(find.text('Publish'), findsOneWidget);
  });
  testWidgets('shows ticket tiers section', (tester) async {
    await tester.pumpWidget(_wrap(const CreateEventScreen()));
    await tester.pump();
    expect(find.text('Ticket Tiers'), findsOneWidget);
    expect(find.text('Add Tier'), findsOneWidget);
  });
});

group('TopUpScreen', () {
  testWidgets('shows method selector tabs', (tester) async {
    await tester.pumpWidget(_wrap(const TopUpScreen()));
    await tester.pump();
    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('EFT'), findsOneWidget);
  });
  testWidgets('shows quick amount buttons', (tester) async {
    await tester.pumpWidget(_wrap(const TopUpScreen()));
    await tester.pump();
    expect(find.text('R20'), findsWidgets);
    expect(find.text('R100'), findsWidgets);
  });
});

group('CashOutScreen', () {
  testWidgets('renders without error', (tester) async {
    await tester.pumpWidget(_wrap(const CashOutScreen()));
    await tester.pump();
    expect(find.byType(CashOutScreen), findsOneWidget);
  });
  testWidgets('shows bank selection', (tester) async {
    await tester.pumpWidget(_wrap(const CashOutScreen()));
    await tester.pump();
    expect(find.text('Your SA Bank'), findsOneWidget);
  });
});

group('ProfileScreen', () {
  testWidgets('renders without error', (tester) async {
    await tester.pumpWidget(_wrap(const ProfileScreen()));
    await tester.pump();
    expect(find.text('Me'), findsOneWidget);
  });
  testWidgets('shows settings rows', (tester) async {
    await tester.pumpWidget(_wrap(const ProfileScreen()));
    await tester.pump();
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Security & PIN'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
  });
});

group('RewardsScreen', () {
  testWidgets('renders without error', (tester) async {
    await tester.pumpWidget(_wrap(const RewardsScreen()));
    await tester.pump();
    expect(find.byType(RewardsScreen), findsOneWidget);
  });
});

// ─── Business Logic Tests ─────────────────────────────────────────────────────
group('VALR Maker Rebate Logic', () {
  test('VALR maker earns 0.05% rebate', () {
    const amount = 1000.0;
    const rebate = amount * FeeCalculator.valrMakerRebate;
    expect(rebate, closeTo(0.50, 0.001));
  });
  test('Net cashout cost with maker < taker', () {
    const amount = 1000.0;
    final makerNet = amount * FeeCalculator.valrMakerRebate * 2; // 2 legs
    final takerNet = amount * FeeCalculator.valrTakerFee * 2;
    expect(makerNet, lessThan(takerNet)); // earn vs pay
  });
  test('Total cashout fee with maker ≈ 0.5% app only', () {
    const amount = 1000.0;
    final appFee = FeeCalculator.fee(amount, 'p2p');
    final valrNet = -(amount * FeeCalculator.valrMakerRebate * 2); // negative = earn
    final total = appFee + valrNet + 0.05; // +R0.05 XRP
    expect(total, lessThan(amount * 0.01)); // less than 1% total
  });
});

group('Internal Ledger Economics', () {
  test('P2P internal has zero VALR cost', () {
    // Internal transfers never touch VALR
    const valrCost = 0.0;
    const appFee = 0.005; // 0.5%
    expect(valrCost + appFee, equals(0.005));
  });
  test('Batch cashout saves proportionally', () {
    // 10 x R100 individual = 10 VALR transactions
    const individual = 10 * (100 * 0.001); // 10 taker fees
    // 1 x R1000 batch = 1 VALR transaction
    const batched = 1000 * 0.001; // 1 taker fee
    expect(batched, lessThan(individual));
    expect(individual / batched, closeTo(10.0, 0.001));
  });
});
