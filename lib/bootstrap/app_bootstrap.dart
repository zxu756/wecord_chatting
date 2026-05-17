import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/config/app_config.dart';
import 'package:wecord/shared/navigation/app_router.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

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

    return MaterialApp.router(
      title: 'WeCord',
      debugShowCheckedModeBanner: false,
      theme: WeCordTheme.light(),
      routerConfig: router,
    );
  }
}
