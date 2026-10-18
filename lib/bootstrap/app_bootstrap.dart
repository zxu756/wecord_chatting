import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/chats/offline/connectivity.dart';
import 'package:wecord/features/chats/offline/offline_session.dart';
import 'package:wecord/features/chats/offline/platform_chat_cache.dart';
import 'package:wecord/features/error_reports/error_reporting_hooks.dart';
import 'package:wecord/features/error_reports/error_reporting_wiring.dart';
import 'package:wecord/features/presence/presence_activity_listener.dart';
import 'package:wecord/features/wallpapers/wallpaper_controller.dart';
import 'package:wecord/shared/config/app_config.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/navigation/app_router.dart';
import 'package:wecord/shared/state/no_retry.dart';
import 'package:wecord/shared/theme/density_controller.dart';
import 'package:wecord/shared/theme/glass_effects_controller.dart';
import 'package:wecord/shared/theme/theme_mode_controller.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';
import 'package:wecord/shared/ui/macos_title_bar.dart';

Future<void> runWeCordApp() async {
  final config = AppConfig.fromMap(const {
    'SUPABASE_URL': String.fromEnvironment('SUPABASE_URL'),
    'SUPABASE_ANON_KEY': String.fromEnvironment('SUPABASE_ANON_KEY'),
  });

  // Crash and error reports: the device's setting and queue first, so what
  // goes wrong from here on is counted.
  await startErrorReporting();

  await Supabase.initialize(
    url: config.supabaseUrl.toString(),
    publishableKey: config.supabaseAnonKey,
    // Notices RPC, Edge Function and sign-in calls that fail.
    httpClient: ErrorReportingHttpClient(http.Client(), errorReporter),
  );
  watchAuthEvents(Supabase.instance.client.auth, errorReporter);

  // The offline copy of chats (SQLite, or IndexedDB on the web) and the
  // device's connection; without them chats work online only.
  final chatCache = await openPlatformChatCache();
  runApp(
    ProviderScope(
      retry: noProviderRetry,
      observers: [ErrorReportingProviderObserver(errorReporter)],
      overrides: [
        if (chatCache != null) chatCacheProvider.overrideWithValue(chatCache),
        deviceConnectivityProvider.overrideWith(
          (ref) => platformDeviceConnectivity(),
        ),
      ],
      child: const WeCordApp(),
    ),
  );
}

class WeCordApp extends ConsumerWidget {
  const WeCordApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    // Route and lifecycle breadcrumbs for error reports.
    ref.watch(errorReportingWiringProvider);
    // Wipes the offline copy of chats on sign-out.
    ref.watch(offlineSessionGuardProvider);
    // Reads the wallpapers kept on this device now, so a chat paints with
    // its own the moment it opens.
    ref.listen(wallpapersLoadedProvider, (previous, next) {});
    final themeMode = ref.watch(themeModeProvider);
    final glassEffects = ref.watch(glassEffectsProvider);
    final density = ref.watch(densityProvider);
    final chinese = resolvesToChinese(ref.watch(appLanguageProvider));
    // Set before anything below builds, so every tr() sees it.
    AppStrings.isChinese = chinese;
    ref.listen(appLanguageProvider, (previous, next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          rebuildAllText(context);
        }
      });
    });

    return MaterialApp.router(
      title: 'WeCord',
      debugShowCheckedModeBanner: false,
      theme: WeCordTheme.light(),
      darkTheme: WeCordTheme.dark(),
      // "Increase contrast" in the platform's accessibility settings.
      highContrastTheme: WeCordTheme.light(highContrast: true),
      highContrastDarkTheme: WeCordTheme.dark(highContrast: true),
      themeMode: themeMode,
      locale: chinese ? const Locale('zh') : const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
      // Pages without an app bar draw under the system bars; keep their
      // icons readable in both themes.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: WeCordTheme.overlayStyleFor(Theme.of(context).brightness),
        child: WeCordAppearance(
          glassEffects: glassEffects,
          child: WeCordDensityScope(
            density: density,
            child: MacosTitleBarFrame(
              child: PresenceActivityListener(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
