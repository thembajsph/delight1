import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../providers/app_providers.dart';
import '../../core/models/models.dart';

class ShellScaffold extends ConsumerWidget {
  final Widget child;
  const ShellScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final role = user?.role ?? UserRole.consumer;
    final loc  = GoRouterState.of(context).matchedLocation;
    final idx  = _index(loc, role);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(top: true, bottom: false, child: child),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: DelightColors.surfaceBorder))),
        child: BottomNavigationBar(
          currentIndex: idx,
          backgroundColor: DelightColors.background,
          selectedItemColor: DelightColors.emerald,
          unselectedItemColor: DelightColors.textMuted,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 10,
          unselectedFontSize: 10,
          iconSize: 22,
          onTap: (i) => _onTap(context, role, i),
          items: _items(role))));
  }

  int _index(String loc, UserRole role) {
    switch (role) {
      case UserRole.business:
        if (loc.startsWith('/feed'))            return 0;
        if (loc.startsWith('/business-home'))   return 1;
        if (loc.startsWith('/wallet'))          return 2;
        if (loc.startsWith('/profile'))         return 3;
        return 0;

      case UserRole.organizer:
        if (loc.startsWith('/feed'))     return 0;
        if (loc.startsWith('/payments')) return 1;
        if (loc.startsWith('/events'))   return 2;
        if (loc.startsWith('/wallet'))   return 3;
        if (loc.startsWith('/profile'))  return 4;
        return 0;

      case UserRole.admin:
        if (loc.startsWith('/feed'))     return 0;
        if (loc.startsWith('/events'))   return 1;
        if (loc.startsWith('/profile'))  return 2;
        return 0;

      case UserRole.consumer:
      default:
        if (loc.startsWith('/feed'))     return 0;
        if (loc.startsWith('/payments')) return 1;
        if (loc.startsWith('/wallet'))   return 2;
        if (loc.startsWith('/rewards'))  return 3;
        if (loc.startsWith('/profile'))  return 4;
        return 0;
    }
  }

  void _onTap(BuildContext context, UserRole role, int i) {
    switch (role) {
      case UserRole.business:
        ['/feed', '/business-home', '/wallet', '/profile']
          .elementAt(i).let((r) => context.go(r));
        break;
      case UserRole.organizer:
        ['/feed', '/payments', '/events', '/wallet', '/profile']
          .elementAt(i).let((r) => context.go(r));
        break;
      case UserRole.admin:
        ['/feed', '/events', '/profile']
          .elementAt(i).let((r) => context.go(r));
        break;
      case UserRole.consumer:
      default:
        ['/feed', '/payments', '/wallet', '/rewards', '/profile']
          .elementAt(i).let((r) => context.go(r));
        break;
    }
  }

  List<BottomNavigationBarItem> _items(UserRole role) {
    switch (role) {
      case UserRole.business:
        return const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home), label: 'Feed'),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_outlined),
            activeIcon: Icon(Icons.qr_code), label: 'Accept Pay'),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet), label: 'Money'),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person), label: 'Me'),
        ];

      case UserRole.organizer:
        return const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home), label: 'Feed'),
          BottomNavigationBarItem(
            icon: Icon(Icons.send_outlined),
            activeIcon: Icon(Icons.send), label: 'Pay'),
          BottomNavigationBarItem(
            icon: Icon(Icons.confirmation_number_outlined),
            activeIcon: Icon(Icons.confirmation_number), label: 'My Events'),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person), label: 'Me'),
        ];

      case UserRole.admin:
        return const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard), label: 'Overview'),
          BottomNavigationBarItem(
            icon: Icon(Icons.event_outlined),
            activeIcon: Icon(Icons.event), label: 'All Events'),
          BottomNavigationBarItem(
            icon: Icon(Icons.admin_panel_settings_outlined),
            activeIcon: Icon(Icons.admin_panel_settings), label: 'Admin'),
        ];

      case UserRole.consumer:
      default:
        return const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.send_outlined),
            activeIcon: Icon(Icons.send), label: 'Send Money'),
          BottomNavigationBarItem(
            icon: Icon(Icons.confirmation_number_outlined),
            activeIcon: Icon(Icons.confirmation_number), label: 'My Tickets'),
          BottomNavigationBarItem(
            icon: Icon(Icons.star_outline),
            activeIcon: Icon(Icons.star), label: 'Rewards'),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person), label: 'Me'),
        ];
    }
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
}
