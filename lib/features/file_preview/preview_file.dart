import 'package:flutter/material.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/media_attachment.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// How a file is shown in the viewer.
enum PreviewKind {
  image,

  /// A vector image (SVG), drawn as a zoomable image.
  svg,
  video,
  audio,
  pdf,

  /// Plain text and logs.
  text,

  /// Rendered Markdown.
  markdown,

  /// Source code, highlighted.
  code,

  /// Pretty-printed JSON.
  json,

  /// Comma or tab separated values, as a table.
  table,

  /// Word processing, spreadsheets and slides (also iWork): Quick Look on
  /// Apple platforms, converted to PDF on the web.
  office,

  /// Anything else: a card with Download / Open in.
  other;

  /// Images and videos page through a conversation's gallery together.
  bool get isGalleryMedia => this == image || this == video;

  /// Read as text (and capped at [maxTextPreviewBytes]).
  bool get isTextLike =>
      this == text ||
      this == markdown ||
      this == code ||
      this == json ||
      this == table;
}

/// Text-like files show at most this much; the rest is a download away.
const maxTextPreviewBytes = 5 * 1024 * 1024;

/// SVGs bigger than this are offered as a download instead of drawn.
const maxSvgPreviewBytes = 10 * 1024 * 1024;

const _officeExtensions = {
  'doc', 'docx', 'docm', 'dot', 'dotx', 'odt', 'ott', 'rtf', //
  'xls', 'xlsx', 'xlsm', 'xlsb', 'xlt', 'xltx', 'ods', 'ots', //
  'ppt', 'pptx', 'pptm', 'pps', 'ppsx', 'pot', 'potx', 'odp', 'otp', //
  'pages', 'numbers', 'key',
};

const _imageExtensions = {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'heic',
  'heif',
  'avif',
  'ico',
};
const _videoExtensions = {'mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi', '3gp'};
const _audioExtensions = {
  'mp3',
  'm4a',
  'wav',
  'ogg',
  'oga',
  'opus',
  'aac',
  'flac',
  'aiff',
  'aif',
  'weba',
};
const _markdownExtensions = {'md', 'markdown', 'mdown', 'mkd'};
const _jsonExtensions = {'json', 'geojson', 'jsonc', 'har', 'webmanifest'};
const _tableExtensions = {'csv', 'tsv', 'tab'};
const _textExtensions = {'txt', 'text', 'log', 'nfo', 'srt', 'vtt', 'env'};

/// Code file extensions and the highlighter language for each.
const codeLanguages = <String, String>{
  'dart': 'dart',
  'js': 'javascript',
  'mjs': 'javascript',
  'cjs': 'javascript',
  'jsx': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'py': 'python',
  'rb': 'ruby',
  'java': 'java',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'swift': 'swift',
  'm': 'objectivec',
  'mm': 'objectivec',
  'c': 'c',
  'h': 'c',
  'cc': 'cpp',
  'cpp': 'cpp',
  'cxx': 'cpp',
  'hpp': 'cpp',
  'cs': 'csharp',
  'go': 'go',
  'rs': 'rust',
  'php': 'php',
  'sh': 'bash',
  'bash': 'bash',
  'zsh': 'bash',
  'ps1': 'powershell',
  'sql': 'sql',
  'yaml': 'yaml',
  'yml': 'yaml',
  'toml': 'ini',
  'ini': 'ini',
  'cfg': 'ini',
  'conf': 'ini',
  'xml': 'xml',
  'plist': 'xml',
  'svg': 'xml',
  'html': 'xml',
  'htm': 'xml',
  'vue': 'xml',
  'css': 'css',
  'scss': 'scss',
  'less': 'less',
  'lua': 'lua',
  'r': 'r',
  'scala': 'scala',
  'gradle': 'gradle',
  'groovy': 'groovy',
  'pl': 'perl',
  'ex': 'elixir',
  'exs': 'elixir',
  'erl': 'erlang',
  'hs': 'haskell',
  'clj': 'clojure',
  'diff': 'diff',
  'patch': 'diff',
  'dockerfile': 'dockerfile',
  'makefile': 'makefile',
  'mk': 'makefile',
  'cmake': 'cmake',
  'proto': 'protobuf',
  'graphql': 'graphql',
  'gql': 'graphql',
  'tf': 'ini',
  'json': 'json',
};

/// The lower-case extension of [name] ("report.PDF" → "pdf"); a bare
/// "Dockerfile" or "Makefile" counts as its own extension.
String fileExtensionOf(String name) {
  final base = name.split('/').last.trim().toLowerCase();
  if (base == 'dockerfile' || base == 'makefile') {
    return base;
  }
  final dot = base.lastIndexOf('.');
  if (dot <= 0 || dot == base.length - 1) {
    return '';
  }
  return base.substring(dot + 1);
}

/// What kind of preview [name] / [mimeType] gets. The extension wins over
/// a generic MIME type (browsers report many files as octet-stream).
PreviewKind previewKindFor({required String name, required String mimeType}) {
  final ext = fileExtensionOf(name);
  final mime = mimeType.toLowerCase();
  if (ext == 'pdf' || mime == 'application/pdf') {
    return PreviewKind.pdf;
  }
  if (_officeExtensions.contains(ext)) {
    return PreviewKind.office;
  }
  if (ext == 'svg' || mime == 'image/svg+xml') {
    return PreviewKind.svg;
  }
  if (_imageExtensions.contains(ext) ||
      (mime.startsWith('image/') && mime != 'image/svg+xml')) {
    return PreviewKind.image;
  }
  if (_videoExtensions.contains(ext) || mime.startsWith('video/')) {
    return PreviewKind.video;
  }
  if (_audioExtensions.contains(ext) || mime.startsWith('audio/')) {
    return PreviewKind.audio;
  }
  if (_markdownExtensions.contains(ext) || mime == 'text/markdown') {
    return PreviewKind.markdown;
  }
  if (_jsonExtensions.contains(ext) || mime == 'application/json') {
    return PreviewKind.json;
  }
  if (_tableExtensions.contains(ext) ||
      mime == 'text/csv' ||
      mime == 'text/tab-separated-values') {
    return PreviewKind.table;
  }
  if (codeLanguages.containsKey(ext)) {
    return PreviewKind.code;
  }
  if (_textExtensions.contains(ext) || mime.startsWith('text/')) {
    return PreviewKind.text;
  }
  if (mime.contains('officedocument') ||
      mime.contains('opendocument') ||
      mime == 'application/msword' ||
      mime == 'application/vnd.ms-excel' ||
      mime == 'application/vnd.ms-powerpoint' ||
      mime == 'application/rtf') {
    return PreviewKind.office;
  }
  return PreviewKind.other;
}

/// A file someone sent, as the viewer needs it: where it is stored, what
/// it is, and who sent it when.
@immutable
class PreviewFile {
  const PreviewFile({
    required this.bucket,
    required this.path,
    required this.name,
    required this.mimeType,
    required this.size,
    this.messageId,
    this.conversationId,
    this.senderName,
    this.sentAt,
    this.width,
    this.height,
  });

  factory PreviewFile.fromFileAttachment(
    FileAttachment attachment, {
    String? messageId,
    String? conversationId,
    String? senderName,
    DateTime? sentAt,
  }) {
    return PreviewFile(
      bucket: attachment.bucket,
      path: attachment.path,
      name: attachment.name,
      mimeType: attachment.mimeType,
      size: attachment.size,
      messageId: messageId,
      conversationId: conversationId,
      senderName: senderName,
      sentAt: sentAt,
    );
  }

  factory PreviewFile.fromImageAttachment(
    ImageAttachment attachment, {
    String? messageId,
    String? conversationId,
    String? senderName,
    DateTime? sentAt,
  }) {
    return PreviewFile(
      bucket: attachment.bucket,
      path: attachment.path,
      name: _imageName(attachment.path, attachment.mimeType),
      mimeType: attachment.mimeType,
      size: attachment.size,
      width: attachment.width,
      height: attachment.height,
      messageId: messageId,
      conversationId: conversationId,
      senderName: senderName,
      sentAt: sentAt,
    );
  }

  /// The image or file of [message]; null for other messages.
  static PreviewFile? fromMessage(ChatMessage message, {String? senderName}) {
    if (message.recalledAt != null) {
      return null;
    }
    if (message.type == MessageType.image) {
      final image = _tryImage(message.attachment);
      return image == null
          ? null
          : PreviewFile.fromImageAttachment(
              image,
              messageId: message.id,
              conversationId: message.conversationId,
              senderName: senderName,
              sentAt: message.createdAt,
            );
    }
    final file = message.fileAttachment;
    return file == null
        ? null
        : PreviewFile.fromFileAttachment(
            file,
            messageId: message.id,
            conversationId: message.conversationId,
            senderName: senderName,
            sentAt: message.createdAt,
          );
  }

  /// The image or file of a media center row; null for voice messages.
  static PreviewFile? fromMediaItem(ConversationMediaItem item) {
    if (item.type == MessageType.image) {
      final image = _tryImage(item.attachment);
      return image == null
          ? null
          : PreviewFile.fromImageAttachment(
              image,
              messageId: item.messageId,
              conversationId: item.conversationId,
              senderName: item.senderName,
              sentAt: item.createdAt,
            );
    }
    if (item.type != MessageType.file) {
      return null;
    }
    final file = FileAttachment.maybeFromJson(item.attachment);
    return file == null
        ? null
        : PreviewFile.fromFileAttachment(
            file,
            messageId: item.messageId,
            conversationId: item.conversationId,
            senderName: item.senderName,
            sentAt: item.createdAt,
          );
  }

  static ImageAttachment? _tryImage(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    try {
      return ImageAttachment.fromJson(json);
    } on Object {
      return null;
    }
  }

  static String _imageName(String path, String mimeType) {
    final last = path.split('/').last;
    if (fileExtensionOf(last).isNotEmpty) {
      return last;
    }
    final subtype = mimeType.split('/').last;
    return 'image.${subtype == 'jpeg' ? 'jpg' : subtype}';
  }

  final String bucket;
  final String path;

  /// The name on the sender's device.
  final String name;
  final String mimeType;
  final int size;
  final String? messageId;
  final String? conversationId;
  final String? senderName;
  final DateTime? sentAt;
  final int? width;
  final int? height;

  PreviewKind get kind => previewKindFor(name: name, mimeType: mimeType);

  String get extension => fileExtensionOf(name);

  /// Identifies the stored object (the cache key).
  String get key => '$bucket/$path';

  /// The highlighter language for code and JSON.
  String? get codeLanguage =>
      kind == PreviewKind.json ? 'json' : codeLanguages[extension];

  /// Copies with the sender and time filled in when they were missing.
  PreviewFile withContext({
    String? messageId,
    String? conversationId,
    String? senderName,
    DateTime? sentAt,
  }) {
    return PreviewFile(
      bucket: bucket,
      path: path,
      name: name,
      mimeType: mimeType,
      size: size,
      width: width,
      height: height,
      messageId: this.messageId ?? messageId,
      conversationId: this.conversationId ?? conversationId,
      senderName: this.senderName ?? senderName,
      sentAt: this.sentAt ?? sentAt,
    );
  }

  @override
  bool operator ==(Object other) => other is PreviewFile && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// The typed icon of a file (tile and viewer).
IconData previewIconFor(PreviewFile file) {
  final ext = file.extension;
  return switch (file.kind) {
    PreviewKind.image || PreviewKind.svg => Icons.image_outlined,
    PreviewKind.video => Icons.movie_outlined,
    PreviewKind.audio => Icons.music_note_rounded,
    PreviewKind.pdf => Icons.picture_as_pdf_outlined,
    PreviewKind.markdown || PreviewKind.text => Icons.notes_rounded,
    PreviewKind.code || PreviewKind.json => Icons.code_rounded,
    PreviewKind.table => Icons.table_chart_outlined,
    PreviewKind.office when _isSheet(ext) => Icons.grid_on_rounded,
    PreviewKind.office when _isSlides(ext) => Icons.slideshow_rounded,
    PreviewKind.office => Icons.article_outlined,
    PreviewKind.other
        when ext == 'zip' ||
            ext == 'rar' ||
            ext == '7z' ||
            ext == 'gz' ||
            ext == 'tar' =>
      Icons.folder_zip_outlined,
    PreviewKind.other => Icons.insert_drive_file_outlined,
  };
}

bool _isSheet(String ext) => const {
  'xls',
  'xlsx',
  'xlsm',
  'xlsb',
  'xlt',
  'xltx',
  'ods',
  'ots',
  'numbers',
}.contains(ext);

bool _isSlides(String ext) => const {
  'ppt',
  'pptx',
  'pptm',
  'pps',
  'ppsx',
  'pot',
  'potx',
  'odp',
  'otp',
  'key',
}.contains(ext);

/// The tile colors for a file's type: documents accent, sheets success,
/// slides warning, PDFs danger, everything else neutral.
({Color fill, Color foreground}) previewToneFor(
  PreviewFile file,
  WeCordPalette c,
) {
  final ext = file.extension;
  return switch (file.kind) {
    PreviewKind.pdf => (fill: c.dangerSoft, foreground: c.dangerText),
    PreviewKind.office when _isSheet(ext) => (
      fill: c.successSoft,
      foreground: c.successText,
    ),
    PreviewKind.table => (fill: c.successSoft, foreground: c.successText),
    PreviewKind.office when _isSlides(ext) => (
      fill: c.warningSoft,
      foreground: c.warningText,
    ),
    PreviewKind.office => (fill: c.accentSoft, foreground: c.accentText),
    PreviewKind.audio => (fill: c.accentSoft, foreground: c.accentText),
    _ => (fill: c.raised, foreground: c.ink),
  };
}

/// "PDF", "DOCX", … for tiles; "FILE" without an extension.
String extensionLabel(PreviewFile file) {
  final ext = file.extension;
  return ext.isEmpty ? tr('FILE') : ext.toUpperCase();
}

/// "2.4 MB · Ada · 9:41" under the file name.
String previewSubtitle(PreviewFile file) {
  final parts = <String>[
    if (file.size > 0) formatFileSize(file.size),
    if (file.senderName case final name? when name.trim().isNotEmpty) name,
    if (file.sentAt case final at?) formatPreviewTime(at),
  ];
  return parts.join(' · ');
}

/// "Oct 14, 09:41" (this year) or "2025/10/14 09:41".
String formatPreviewTime(DateTime value, {DateTime? now}) {
  final local = value.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  if (local.year == today.year &&
      local.month == today.month &&
      local.day == today.day) {
    return '$hh:$mm';
  }
  if (local.year == today.year) {
    return '${local.month}/${local.day} $hh:$mm';
  }
  return '${local.year}/${local.month}/${local.day} $hh:$mm';
}
