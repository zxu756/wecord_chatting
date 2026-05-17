class AppConfig {
  const AppConfig({required this.supabaseUrl, required this.supabaseAnonKey});

  final Uri supabaseUrl;
  final String supabaseAnonKey;

  factory AppConfig.fromMap(Map<String, String> values) {
    final rawUrl = values['SUPABASE_URL']?.trim();
    final anonKey = values['SUPABASE_ANON_KEY']?.trim();

    if (rawUrl == null || rawUrl.isEmpty) {
      throw const ConfigException('SUPABASE_URL is required');
    }

    final parsedUrl = Uri.tryParse(rawUrl);
    if (parsedUrl == null || !parsedUrl.hasScheme || parsedUrl.host.isEmpty) {
      throw ConfigException(
        'SUPABASE_URL must be a valid absolute URL: $rawUrl',
      );
    }

    if (anonKey == null || anonKey.isEmpty) {
      throw const ConfigException('SUPABASE_ANON_KEY is required');
    }

    return AppConfig(supabaseUrl: parsedUrl, supabaseAnonKey: anonKey);
  }
}

class ConfigException implements Exception {
  const ConfigException(this.message);

  final String message;

  @override
  String toString() => 'ConfigException: $message';
}
