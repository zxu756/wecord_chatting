import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/presence/presence_activity_listener.dart';
import 'package:wecord/shared/config/app_config.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/navigation/app_router.dart';
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

  await Supabase.initialize(
    url: config.supabaseUrl.toString(),
    anonKey: config.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: WeCordApp()));
}

class WeCordApp extends ConsumerWidget {
  const WeCordApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
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
