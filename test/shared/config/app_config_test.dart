import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/shared/config/app_config.dart';

void main() {
  group('AppConfig', () {
    test('creates config when Supabase values are present', () {
      final config = AppConfig.fromMap({
        'SUPABASE_URL': 'https://example.supabase.co',
        'SUPABASE_ANON_KEY': 'anon-key',
      });

      expect(config.supabaseUrl, Uri.parse('https://example.supabase.co'));
      expect(config.supabaseAnonKey, 'anon-key');
    });

    test('throws when Supabase URL is missing', () {
      expect(
        () => AppConfig.fromMap({'SUPABASE_ANON_KEY': 'anon-key'}),
        throwsA(isA<ConfigException>()),
      );
    });

    test('throws when Supabase URL is invalid', () {
      expect(
        () => AppConfig.fromMap({
          'SUPABASE_URL': 'not-a-url',
          'SUPABASE_ANON_KEY': 'anon-key',
        }),
        throwsA(isA<ConfigException>()),
      );
    });

    test('throws when Supabase anon key is missing', () {
      expect(
        () =>
            AppConfig.fromMap({'SUPABASE_URL': 'https://example.supabase.co'}),
        throwsA(isA<ConfigException>()),
      );
    });
  });
}
