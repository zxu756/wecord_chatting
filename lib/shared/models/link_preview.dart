/// Open Graph metadata for a link, as returned by the `link-preview` Edge
/// Function.
class LinkPreview {
  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
  });

  factory LinkPreview.fromJson(Map<String, dynamic> json) {
    return LinkPreview(
      url: json['url'] as String,
      title: _text(json['title']),
      description: _text(json['description']),
      imageUrl: _httpUrl(json['image_url']),
      siteName: _text(json['site_name']),
    );
  }

  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;

  /// A card needs at least a title or a description.
  bool get hasContent => title != null || description != null;
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
