import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/config/app_config.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// The Supabase settings the app was built with, or null when they are
/// missing (as in tests).
final appConfigProvider = Provider<AppConfig?>((ref) {
  try {
    return AppConfig.fromMap(const {
      'SUPABASE_URL': String.fromEnvironment('SUPABASE_URL'),
      'SUPABASE_ANON_KEY': String.fromEnvironment('SUPABASE_ANON_KEY'),
    });
  } on ConfigException {
    return null;
  }
});
