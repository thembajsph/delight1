import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/providers/app_providers.dart';
import 'core/services/ad_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/supabase_service.dart';
import 'core/config/env.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: DelightColors.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Supabase
  try {
    await SupabaseService.initialize();
  } catch (e) {
    debugPrint('Supabase not configured — offline mode: $e');
  }

  // Firebase — skip gracefully if not configured
  // Add google-services.json to android/app/ and GoogleService-Info.plist
  // to ios/Runner/ to enable push notifications

  // Initialize AdMob (no-op on web)
  await AdService.initialize();

  // Initialize push notifications (no-op on web)
  await NotificationService.initialize();

  runApp(const ProviderScope(child: DelightApp()));
}

class DelightApp extends ConsumerWidget {
  const DelightApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Watch walletProvider at root so it's always active
    // and auto-inits the moment authProvider has a user
    ref.watch(walletProvider);
    return MaterialApp.router(
      title: Env.appName,
      theme: buildDelightTheme(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.noScaling),
        child: child!,
      ),
    );
  }
}
