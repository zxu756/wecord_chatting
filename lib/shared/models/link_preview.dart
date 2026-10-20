/// Open Graph metadata for a link, as returned by the `link-preview` Edge
/// Function.
class LinkPreview {
  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    this.riskLevel,
    this.riskReasons = const [],
    this.finalHost,
  });

  factory LinkPreview.fromJson(Map<String, dynamic> json) {
    return LinkPreview(
      url: json['url'] as String,
      title: _text(json['title']),
      description: _text(json['description']),
      imageUrl: _httpUrl(json['image_url']),
      siteName: _text(json['site_name']),
      riskLevel: _risk(json['risk'], 'level'),
      riskReasons: [
        if (json['risk'] case {'reasons': final List reasons})
          for (final reason in reasons)
            if (reason is String) reason,
      ],
      finalHost: _text(json['final_host']),
    );
  }

  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;

  /// How risky the address looks ("none", "caution" or "high"), as the
  /// function judged it, with the reasons (see features/safety/link_risk.dart).
  /// Null from an older function.
  final String? riskLevel;
  final List<String> riskReasons;

  /// Where the link ended up, when it redirected somewhere else.
  final String? finalHost;

  /// A card needs at least a title or a description.
  bool get hasContent => title != null || description != null;
}

String? _risk(Object? risk, String key) {
  return risk is Map ? _text(risk[key]) : null;
}

String? _text(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _httpUrl(Object? value) {
  final text = _text(value);
  if (text == null) {
    return null;
  }
  final uri = Uri.tryParse(text);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  return text;
}
