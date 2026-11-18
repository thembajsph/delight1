import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/app_providers.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import 'shell_scaffold.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/signup_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/social/presentation/screens/social_screen.dart';
import '../../features/payments/presentation/screens/payments_screen.dart';
import '../../features/payments/presentation/screens/send_screen.dart';
import '../../features/payments/presentation/screens/receive_screen.dart';
import '../../features/events/presentation/screens/events_screen.dart';
import '../../features/events/presentation/screens/event_detail_screen.dart';
import '../../features/events/presentation/screens/create_event_screen.dart';
import '../../features/rewards/presentation/screens/rewards_screen.dart';
import '../../features/wallet/presentation/screens/wallet_screen.dart';
import '../../features/wallet/presentation/screens/ticket_detail_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/topup/presentation/screens/topup_screen.dart';
import '../../features/cashout/presentation/screens/cashout_screen.dart';
import '../../features/messaging/presentation/screens/messages_screen.dart';
import '../../features/business/presentation/screens/business_qr_screen.dart';
import '../../features/gate/presentation/screens/gate_scanner_screen.dart';
import '../../features/insights/presentation/screens/event_insights_screen.dart';
import '../../features/products/presentation/screens/product_insights_screen.dart';
import '../../features/products/presentation/screens/pay_business_screen.dart';
import '../../features/analytics/presentation/screens/admin_analytics_screen.dart';
import '../../features/analytics/presentation/screens/admin_dashboard_screen.dart';
import '../../features/private_events/presentation/screens/private_event_screen.dart';

// Logged once per real app launch, the first time a session becomes
// authenticated — not on every rebuild of the router provider.
bool _appOpenLogged = false;

/// Real screen-view telemetry: every route push is logged to Supabase.
/// This is what feeds the admin dashboard's Time Spent / Return Visits /
/// Feature Usage tabs — there is no other source of that data, and before
/// this there was none at all (those tabs just showed invented numbers).
class _AnalyticsRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previousRoute) {
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) SupabaseService.logScreenView(name);
  }
}

/// A deep link (e.g. a scanned business QR) opened while signed out; we send
/// the user there right after they sign in instead of dropping it.
String? _pendingPath;

final routerProvider = Provider<GoRouter>((ref) {
  final isAuth      = ref.watch(isAuthenticatedProvider);
  final isOnboarded = ref.watch(isOnboardedProvider);

  return GoRouter(
    initialLocation: '/feed',
    observers: [_AnalyticsRouteObserver()],
    redirect: (context, state) {
      final loc = state.matchedLocation;

      // If authenticated, always allow through (skip onboarding).
      // Consumers are custodial — no wallet-setup step to skip past; their
      // balance ledger row is created automatically on signup.
      if (isAuth) {
        if (_pendingPath != null) {
          final p = _pendingPath!;
          _pendingPath = null;
          return p;
        }
        if (!_appOpenLogged) {
          _appOpenLogged = true;
          SupabaseService.logAppOpen();
        }
        const authPages = ['/onboarding', '/login', '/signup'];
        if (authPages.any((r) => loc == r)) return '/feed';
        return null;
      }

      // Guests open WhatsApp RSVP links without an account.
      if (loc.startsWith('/rsvp/')) return null;

      // Remember where they were headed (pay links need an account).
      if (loc.startsWith('/pay/')) _pendingPath = state.uri.toString();

      // Not authenticated — show onboarding first time, then login
      if (!isOnboarded && loc != '/onboarding') return '/onboarding';
      if (!isAuth) {
        const authRoutes = ['/onboarding', '/signup', '/login'];
        if (authRoutes.any((r) => loc.startsWith(r))) return null;
        return '/login';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding',   builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/signup',       builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/login',        builder: (_, __) => const LoginScreen()),

      ShellRoute(
        builder: (_, __, child) => ShellScaffold(child: child),
        routes: [
          GoRoute(path: '/feed', name: 'Social Feed',
            builder: (_, __) => const SocialScreen()),
          GoRoute(path: '/payments', name: 'Payments',
            builder: (_, __) => const PaymentsScreen()),
          GoRoute(path: '/events', name: 'Events',
            builder: (_, __) => const EventsScreen()),
          GoRoute(path: '/rewards', name: 'Rewards',
            builder: (_, __) => const RewardsScreen()),
          GoRoute(path: '/wallet', name: 'Wallet',
            builder: (_, __) => const WalletScreen()),
          GoRoute(path: '/profile', name: 'Profile',
            builder: (_, __) => const ProfileScreen()),
          GoRoute(path: '/business-home', name: 'Business',
            builder: (_, __) => const BusinessQRScreen()),
        ],
      ),

      GoRoute(path: '/send', name: 'Send', builder: (_, state) => SendScreen(
        prefillAddress: state.extra as String?)),
      GoRoute(path: '/receive', name: 'Receive', builder: (_, __) => const ReceiveScreen()),
      GoRoute(path: '/scan', name: 'Scan', builder: (_, __) => const ScanScreen()),
      GoRoute(path: '/topup', name: 'Top Up', builder: (_, __) => const TopUpScreen()),
      GoRoute(path: '/cashout', name: 'Cash Out', builder: (_, __) => const CashOutScreen()),
      GoRoute(path: '/messages', name: 'Messages', builder: (_, __) => const MessagesScreen()),
      GoRoute(path: '/business-qr', name: 'Business QR', builder: (_, __) => const BusinessQRScreen()),
      GoRoute(path: '/gate-scan',   builder: (_, __) => const GateScannerScreen()),
      GoRoute(path: '/gate-dashboard', builder: (_, __) => const GateDashboardScreen()),
      GoRoute(path: '/event-insights', builder: (_, __) => const EventInsightsScreen()),
      GoRoute(path: '/product-insights', builder: (_, __) => const BusinessProductInsightsScreen()),
      GoRoute(path: '/pay/:id', builder: (_, state) => PayBusinessScreen(
        ownerId: state.pathParameters['id']!,
        vendorId: state.uri.queryParameters['v'])),
      GoRoute(path: '/my-products', builder: (_, __) => const ProductCatalogScreen()),
      GoRoute(path: '/market-trends', builder: (_, __) => const PlatformProductTrendsScreen()),
      GoRoute(path: '/indoor-insights', builder: (_, __) => const IndoorEventInsightsScreen()),
      GoRoute(path: '/admin-analytics', builder: (_, __) => const AdminAnalyticsScreen()),
      GoRoute(path: '/admin-dashboard', builder: (_, __) => const AdminDashboardScreen()),
      GoRoute(path: '/private-events', builder: (_, __) => const PrivateEventsScreen()),
      GoRoute(
        path: '/private-events/:id',
        builder: (_, state) {
          final fromExtra = state.extra as PrivateEvent?;
          return fromExtra != null
            ? PrivateEventDetailScreen(event: fromExtra)
            : PrivateEventLoader(id: state.pathParameters['id']!, rsvp: false);
        }),
      GoRoute(
        path: '/rsvp/:id',
        builder: (_, state) {
          final fromExtra = state.extra as PrivateEvent?;
          return fromExtra != null
            ? GuestRSVPScreen(event: fromExtra)
            : PrivateEventLoader(id: state.pathParameters['id']!, rsvp: true);
        }),
      GoRoute(path: '/chat/:id',
        builder: (_, state) => ChatScreen(conv: state.extra as Conversation)),
      GoRoute(path: '/events/create', builder: (_, __) => const CreateEventScreen()),
      GoRoute(path: '/event/:id',
        builder: (_, state) => EventDetailScreen(event: state.extra as EventModel)),
      GoRoute(path: '/ticket/:id',
        builder: (_, state) {
          final ticket = state.extra;
          if (ticket is! NFTTicket) return const Scaffold(body: Center(child: Text('Ticket not found')));
          return TicketDetailScreen(ticket: ticket);
        }),
    ],
  );
});

class _EventLinkNotFoundScreen extends StatelessWidget {
  const _EventLinkNotFoundScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🔗', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 16),
        const Text("This invite link isn't valid anymore",
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Satoshi', fontSize: 15,
            fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('Ask the host to send you a fresh invite.',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
            color: Colors.grey)),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () => context.go('/feed'),
          child: const Text('Go to Delight')),
      ]))));
}
