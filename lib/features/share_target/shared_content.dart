import 'package:flutter/foundation.dart';

/// A file another app shared with WeCord ("Share to WeCord" on Android and
/// ChromeOS). The bytes are read when it is sent, not before.
@immutable
class SharedFile {
  const SharedFile({
    required this.name,
    required this.mimeType,
    required this.size,
    required this.read,
  });

  final String name;

  /// What the sharing app said it is; empty when it did not say.
  final String mimeType;
  final int size;

  /// Reads the file's bytes.
  final Future<Uint8List> Function() read;

  bool get isImage => sharedImageTypes.contains(mimeType.toLowerCase());
}

/// The pictures sent as chat pictures (the rest go as files).
const sharedImageTypes = {'image/jpeg', 'image/png', 'image/webp', 'image/gif'};

/// What was shared: a title, text, a link and files, any of them or none.
@immutable
class SharedContent {
  const SharedContent({
    this.title = '',
    this.text = '',
    this.url = '',
    this.files = const [],
    this.skippedFiles = 0,
  });

  final String title;
  final String text;
  final String url;
  final List<SharedFile> files;

  /// Files that were left out: too many, or over the chat's size limit.
  final int skippedFiles;

  /// The message to send for the title, text and link, or null when there is
  /// none. Apps put the link into the text as often as into [url], and the
  /// title is often the first words of the text, so nothing is said twice.
  String? get messageText =>
      sharedMessageText(title: title, text: text, url: url);

  bool get hasText => messageText != null;

  bool get isEmpty => !hasText && files.isEmpty;
}

/// The one message a share's title, text and link make: each present part on
/// its own line, leaving out a title or link the text already contains.
/// Null when all three are empty.
String? sharedMessageText({
  String title = '',
  String text = '',
  String url = '',
}) {
  final cleanTitle = title.trim();
  final cleanText = text.trim();
  final cleanUrl = url.trim();
  final lines = <String>[];
  if (cleanTitle.isNotEmpty && !cleanText.contains(cleanTitle)) {
    lines.add(cleanTitle);
  }
  if (cleanText.isNotEmpty) {
    lines.add(cleanText);
  }
  if (cleanUrl.isNotEmpty && !cleanText.contains(cleanUrl)) {
    lines.add(cleanUrl);
  }
  return lines.isEmpty ? null : lines.join('\n');
}
