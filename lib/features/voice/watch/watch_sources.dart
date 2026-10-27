import 'package:flutter/foundation.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/safety/link_risk.dart';

/// The storage bucket chat files live in; only files from here are played.
const watchFileBucket = 'chat-files';

/// A title is cut to this many characters.
const maxWatchTitleChars = 80;

/// Extensions of media a person's device can stream from a plain https
/// address (E4). `m3u8` (HLS) plays on iPhone and Mac only.
const watchLinkVideoExtensions = {'mp4', 'm4v', 'mov', 'webm', 'm3u8'};
const watchLinkAudioExtensions = {
  'mp3',
  'm4a',
  'aac',
  'ogg',
  'oga',
  'opus',
  'wav',
  'flac',
};

/// The sites whose public videos are shown with their own embedded player.
enum WatchEmbedProvider {
  /// YouTube's embedded player. On the web it can be played, paused and
  /// moved from here; on iPhone and Mac it is opened in the browser.
  youtube('yt'),

  /// Bilibili's embedded player. It has no remote control: people press
  /// play themselves and the host sends "play now" hints.
  bilibili('bili');

  const WatchEmbedProvider(this.code);

  final String code;

  static WatchEmbedProvider? fromCode(Object? code) {
    for (final provider in values) {
      if (provider.code == code) {
        return provider;
      }
    }
    return null;
  }
}

final _youtubeId = RegExp(r'^[A-Za-z0-9_-]{11}$');
final _bilibiliId = RegExp(r'^(BV[0-9A-Za-z]{10}|av[0-9]{1,12})$');

/// What a call watches or listens to together. A source is only ever
/// *named* to the room (a stored file, an address, a site and a video id);
/// every device loads the media itself, and WeCord never downloads or
/// re-hosts anything from another site.
@immutable
sealed class WatchSource {
  const WatchSource();

  /// A name for the source when its sender gave no title.
  String get label;

  /// Listening, not watching: shows no picture.
  bool get isAudio;

  Map<String, Object?> toJson();

  /// The source in a packet, or null when it is not one a call plays: a
  /// file must be from [conversationId]'s own folder of the chat-files
  /// bucket, a link must be a plain https media address that does not look
  /// risky, an embed must be a known site with a well-formed video id.
  static WatchSource? fromJson(Object? json, {required String conversationId}) {
    if (json is! Map) {
      return null;
    }
    switch (json['t']) {
      case 'file':
        final path = json['p'];
        final name = json['n'];
        final mime = json['m'];
        if (json['b'] != watchFileBucket ||
            path is! String ||
            name is! String ||
            mime is! String ||
            !path.startsWith('$conversationId/') ||
            path.length > 400 ||
            path.split('/').any((part) => part == '..' || part == '.')) {
          return null;
        }
        final kind = previewKindFor(name: name, mimeType: mime);
        if (kind != PreviewKind.video && kind != PreviewKind.audio) {
          return null;
        }
        return WatchFileSource(
          path: path,
          name: tidyWatchTitle(name),
          mimeType: mime.length > 100 ? mime.substring(0, 100) : mime,
          size: (json['z'] as num?)?.toInt() ?? 0,
          isAudio: kind == PreviewKind.audio,
        );
      case 'link':
        final url = json['u'];
        if (url is! String || url.length > 1000) {
          return null;
        }
        return WatchLinkSource.tryParse(url);
      case 'emb':
        final provider = WatchEmbedProvider.fromCode(json['pr']);
        final id = json['id'];
        if (provider == null || id is! String) {
          return null;
        }
        return WatchEmbedSource.tryCreate(provider, id);
    }
    return null;
  }
}

/// A video or audio file from the call's chat.
@immutable
class WatchFileSource extends WatchSource {
  const WatchFileSource({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.isAudio,
  });

  /// Names [file] (a video or audio file from the chat).
  factory WatchFileSource.fromPreview(PreviewFile file) {
    return WatchFileSource(
      path: file.path,
      name: tidyWatchTitle(file.name),
      mimeType: file.mimeType,
      size: file.size,
      isAudio: file.kind == PreviewKind.audio,
    );
  }

  final String path;
  final String name;
  final String mimeType;
  final int size;

  @override
  final bool isAudio;

  @override
  String get label => name;

  PreviewFile toPreviewFile({String? conversationId}) {
    return PreviewFile(
      bucket: watchFileBucket,
      path: path,
      name: name,
      mimeType: mimeType,
      size: size,
      conversationId: conversationId,
    );
  }

  @override
  Map<String, Object?> toJson() => {
    't': 'file',
    'b': watchFileBucket,
    'p': path,
    'n': name,
    'm': mimeType,
    'z': size,
  };

  @override
  bool operator ==(Object other) =>
      other is WatchFileSource && other.path == path;

  @override
  int get hashCode => Object.hash('file', path);
}

/// A video or audio file at a plain https address.
@immutable
class WatchLinkSource extends WatchSource {
  const WatchLinkSource._(this.url, this.isAudio);

  /// [text] as a media link, or null when it is not an https address of a
  /// video or audio file, carries a user name, or looks risky (G5).
  static WatchLinkSource? tryParse(String text) {
    final Uri url;
    try {
      url = Uri.parse(text.trim());
    } on FormatException {
      return null;
    }
    if (url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.host.contains('%')) {
      return null;
    }
    final extension = _extensionOf(url.path);
    final isAudio = watchLinkAudioExtensions.contains(extension);
    if (!isAudio && !watchLinkVideoExtensions.contains(extension)) {
      return null;
    }
    if (assessLink(url.toString()).isHigh) {
      return null;
    }
    return WatchLinkSource._(url.removeFragment(), isAudio);
  }

  final Uri url;

  @override
  final bool isAudio;

  /// The file name at the end of the address.
  @override
  String get label {
    final last = url.pathSegments.isEmpty ? '' : url.pathSegments.last;
    if (last.isEmpty) {
      return url.host;
    }
    try {
      return Uri.decodeComponent(last);
    } on ArgumentError {
      return last;
    }
  }

  @override
  Map<String, Object?> toJson() => {'t': 'link', 'u': url.toString()};

  @override
  bool operator ==(Object other) =>
      other is WatchLinkSource && other.url == url;

  @override
  int get hashCode => Object.hash('link', url);
}

/// A public video of a site with an embeddable player.
@immutable
class WatchEmbedSource extends WatchSource {
  const WatchEmbedSource._(this.provider, this.id);

  static WatchEmbedSource? tryCreate(WatchEmbedProvider provider, String id) {
    final ok = switch (provider) {
      WatchEmbedProvider.youtube => _youtubeId.hasMatch(id),
      WatchEmbedProvider.bilibili => _bilibiliId.hasMatch(id),
    };
    return ok ? WatchEmbedSource._(provider, id) : null;
  }

  final WatchEmbedProvider provider;
  final String id;

  @override
  bool get isAudio => false;

  @override
  String get label => switch (provider) {
    WatchEmbedProvider.youtube => 'YouTube',
    WatchEmbedProvider.bilibili => 'Bilibili',
  };

  /// Whether the site's player has a remote control a page can use (play,
  /// pause, move, read the time). Bilibili's has none.
  bool get remoteControl => provider == WatchEmbedProvider.youtube;

  /// The page of the video, for "open in the browser".
  Uri get pageUri => switch (provider) {
    WatchEmbedProvider.youtube => Uri.https('www.youtube.com', '/watch', {
      'v': id,
    }),
    WatchEmbedProvider.bilibili => Uri.https('www.bilibili.com', '/video/$id'),
  };

  /// The site's own embedded player, built here from the id: an address
  /// in a packet is never used.
  Uri embedUri({String? origin}) => switch (provider) {
    WatchEmbedProvider.youtube =>
      Uri.https('www.youtube-nocookie.com', '/embed/$id', {
        'enablejsapi': '1',
        'controls': '0',
        'disablekb': '1',
        'playsinline': '1',
        'rel': '0',
        'modestbranding': '1',
        'origin': ?origin,
      }),
    WatchEmbedProvider.bilibili =>
      Uri.https('player.bilibili.com', '/player.html', {
        if (id.startsWith('BV')) 'bvid': id else 'aid': id.substring(2),
        'page': '1',
        'autoplay': '0',
        'danmaku': '0',
      }),
  };

  @override
  Map<String, Object?> toJson() => {'t': 'emb', 'pr': provider.code, 'id': id};

  @override
  bool operator ==(Object other) =>
      other is WatchEmbedSource && other.provider == provider && other.id == id;

  @override
  int get hashCode => Object.hash(provider, id);
}

/// Why a pasted address can not be watched together.
enum WatchLinkProblem {
  /// Not an address at all.
  notALink,

  /// Only https addresses.
  notHttps,

  /// A site with no embeddable player we know, or a page that is not a
  /// video.
  unsupported,

  /// A short link (b23.tv): paste the full address.
  shortLink,

  /// The link looks risky (G5).
  risky,
}

/// What [parseWatchLink] made of an address.
@immutable
class WatchLinkResult {
  const WatchLinkResult.ok(WatchSource this.source) : problem = null;
  const WatchLinkResult.problem(WatchLinkProblem this.problem) : source = null;

  final WatchSource? source;
  final WatchLinkProblem? problem;
}

/// Reads an address a person pasted: a YouTube or Bilibili video page, or a
/// plain https address of a video or audio file.
WatchLinkResult parseWatchLink(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) {
    return const WatchLinkResult.problem(WatchLinkProblem.notALink);
  }
  Uri? uri = Uri.tryParse(trimmed);
  if (uri != null && !uri.hasScheme) {
    // "youtu.be/abc" without a scheme is what people paste.
    uri = trimmed.contains('.') ? Uri.tryParse('https://$trimmed') : null;
  }
  if (uri == null || uri.host.isEmpty) {
    return const WatchLinkResult.problem(WatchLinkProblem.notALink);
  }
  if (uri.scheme != 'https') {
    return const WatchLinkResult.problem(WatchLinkProblem.notHttps);
  }
  var host = uri.host.toLowerCase();
  if (host.startsWith('www.')) {
    host = host.substring(4);
  }
  if (host == 'b23.tv' || host == 'bili2233.cn') {
    return const WatchLinkResult.problem(WatchLinkProblem.shortLink);
  }
  if (host == 'youtu.be') {
    final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    return _embed(WatchEmbedProvider.youtube, id);
  }
  if (host == 'youtube.com' ||
      host == 'm.youtube.com' ||
      host == 'music.youtube.com' ||
      host == 'youtube-nocookie.com') {
    final segments = uri.pathSegments;
    var id = '';
    if (segments.length > 1 &&
        (segments.first == 'shorts' ||
            segments.first == 'live' ||
            segments.first == 'embed')) {
      id = segments[1];
    } else if (segments.isNotEmpty && segments.first == 'watch') {
      id = uri.queryParameters['v'] ?? '';
    }
    return _embed(WatchEmbedProvider.youtube, id);
  }
  if (host == 'bilibili.com' || host == 'm.bilibili.com') {
    final segments = uri.pathSegments;
    if (segments.length >= 2 && segments.first == 'video') {
      var id = segments[1];
      if (id.toLowerCase().startsWith('bv')) {
        id = 'BV${id.substring(2)}';
      } else if (id.toLowerCase().startsWith('av')) {
        id = 'av${id.substring(2)}';
      }
      return _embed(WatchEmbedProvider.bilibili, id);
    }
    return const WatchLinkResult.problem(WatchLinkProblem.unsupported);
  }
  final extension = _extensionOf(uri.path);
  if (!watchLinkVideoExtensions.contains(extension) &&
      !watchLinkAudioExtensions.contains(extension)) {
    return const WatchLinkResult.problem(WatchLinkProblem.unsupported);
  }
  if (assessLink(uri.toString()).isHigh) {
    return const WatchLinkResult.problem(WatchLinkProblem.risky);
  }
  final source = WatchLinkSource.tryParse(uri.toString());
  return source == null
      ? const WatchLinkResult.problem(WatchLinkProblem.unsupported)
      : WatchLinkResult.ok(source);
}

WatchLinkResult _embed(WatchEmbedProvider provider, String id) {
  final source = WatchEmbedSource.tryCreate(provider, id);
  return source == null
      ? const WatchLinkResult.problem(WatchLinkProblem.unsupported)
      : WatchLinkResult.ok(source);
}

String _extensionOf(String path) {
  final last = path.split('/').last.toLowerCase();
  final dot = last.lastIndexOf('.');
  return dot < 0 ? '' : last.substring(dot + 1);
}

final _controlChars = RegExp(
  '[\\u0000-\\u0008\\u000b\\u000c\\u000e-\\u001f\\u007f-\\u009f'
  '\\u200b-\\u200f\\u202a-\\u202e\\u2066-\\u2069\\ufeff]',
);

/// A title with control and direction-changing characters removed, spaces
/// squeezed, cut to [maxWatchTitleChars].
String tidyWatchTitle(String text) {
  final tidy = text
      .replaceAll(_controlChars, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final runes = tidy.runes;
  return runes.length <= maxWatchTitleChars
      ? tidy
      : String.fromCharCodes(runes.take(maxWatchTitleChars));
}
