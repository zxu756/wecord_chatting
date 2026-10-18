import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:wecord/features/legal/minimum_age.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Where the policy pages live in the app (`/legal/guidelines`, ...). They
/// are reachable without signing in, so sign-up can link to them.
abstract final class LegalRoutes {
  static const prefix = '/legal';
}

/// The three policy pages. Their text is Markdown bundled with the app
/// (`assets/legal/<name>.<en|zh>.md`).
enum LegalDocument {
  guidelines('guidelines'),
  privacy('privacy'),
  terms('terms');

  const LegalDocument(this.slug);

  final String slug;

  String get path => '${LegalRoutes.prefix}/$slug';

  String get title => switch (this) {
    guidelines => tr('Community Guidelines'),
    privacy => tr('Privacy Policy'),
    terms => tr('Terms of Service'),
  };

  /// The bundled file for [chinese] or English.
  String assetName({required bool chinese}) =>
      'assets/legal/$slug.${chinese ? 'zh' : 'en'}.md';

  static LegalDocument? fromSlug(String? slug) {
    for (final document in values) {
      if (document.slug == slug) {
        return document;
      }
    }
    return null;
  }

  /// The text in the app's language, with `{minimumAge}` filled in from
  /// [minimumAge].
  Future<String> load({AssetBundle? bundle, bool? chinese}) async {
    final text = await (bundle ?? rootBundle).loadString(
      assetName(chinese: chinese ?? AppStrings.isChinese),
    );
    return text.replaceAll('{minimumAge}', '$minimumAge');
  }
}
