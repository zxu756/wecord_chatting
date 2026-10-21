import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/app_lock/app_lock_gate.dart';
import 'package:wecord/features/app_lock/lock_storage.dart';
import 'package:wecord/features/care_mode/care_mode_host.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/chats/offline/connectivity.dart';
import 'package:wecord/features/chats/offline/offline_session.dart';
import 'package:wecord/features/chats/offline/platform_chat_cache.dart';
import 'package:wecord/features/error_reports/error_reporting_hooks.dart';
import 'package:wecord/features/error_reports/error_reporting_wiring.dart';
import 'package:wecord/features/feature_flags/update_required_screen.dart';
import 'package:wecord/features/presence/presence_activity_listener.dart';
import 'package:wecord/features/pwa/pwa_overlay.dart';
import 'package:wecord/features/storage/storage_providers.dart';
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

  // The offline copy of chats (SQLite, or IndexedDB on the web) and the
  // device's connection; without them chats work online only. It opens
  // while Supabase reads the saved session, not after it: the first frame
  // waits for both.
  final chatCacheOpening = openPlatformChatCache();
  await Supabase.initialize(
    url: config.supabaseUrl.toString(),
    publishableKey: config.supabaseAnonKey,
    // Notices RPC, Edge Function and sign-in calls that fail.
    httpClient: ErrorReportingHttpClient(http.Client(), errorReporter),
  );
  watchAuthEvents(Supabase.instance.client.auth, errorReporter);

  final chatCache = await chatCacheOpening;
  // The app lock's settings, read before the first frame: a locked app must
  // never show its content for a moment before the lock covers it.
  final lockStorage = await SharedPreferencesLockStorage.open();
  // Care mode's choices, for the same reason: no flash of the normal sizes.
  final careStore = await SharedPreferencesCareModeStore.open();
  runApp(
    ProviderScope(
      retry: noProviderRetry,
      observers: [ErrorReportingProviderObserver(errorReporter)],
      overrides: [
        lockStorageProvider.overrideWithValue(lockStorage),
        careModeStoreProvider.overrideWithValue(careStore),
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
    // Forgets expired cached messages, and old media when the person chose.
    ref.watch(storageJanitorProvider);
    // Reads the wallpapers kept on this device now, so a chat paints with
    // its own the moment it opens.
    ref.listen(wallpapersLoadedProvider, (previous, next) {});
    final themeMode = ref.watch(themeModeProvider);
    final glassEffects = ref.watch(glassEffectsProvider);
    final density = ref.watch(densityProvider);
    final care = ref.watch(careModeProvider);
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
      // Care mode can ask for the high contrast colors itself.
      theme: WeCordTheme.light(highContrast: care.forcesHighContrast),
      darkTheme: WeCordTheme.dark(highContrast: care.forcesHighContrast),
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
        // Care mode: bigger text and tap areas for everything below. It is
        // always here, on or off, so switching it keeps the page as it is.
        child: CareModeHost(
          child: WeCordAppearance(
            glassEffects: glassEffects,
            child: WeCordDensityScope(
              // Care mode lists and messages sit comfortably.
              density: care.enabled ? WeCordDensity.comfortable : density,
              child: MacosTitleBarFrame(
                // Covers everything below while the app is locked (G2).
                child: AppLockGate(
                  child: PwaOverlayHost(
                    // "Please update" instead of the app while this version is
                    // older than the server allows (K4).
                    child: AppUpdateGate(
                      child: PresenceActivityListener(
                        child: child ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
