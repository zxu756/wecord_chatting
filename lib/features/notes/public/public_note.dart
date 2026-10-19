import 'package:flutter/foundation.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/shared/config/site_url.dart';

/// Where published notes open in the app (and on the web, after the site's
/// origin): `/n/<token>`. The token is the secret of the link: 48 lowercase
/// hex digits, made by the server when the note is published.
const publicNoteRoutePrefix = '/n';

final _tokenPattern = RegExp(r'^[0-9a-f]{48}$');

/// Whether [value] looks like the token of a published note.
bool isPublicNoteToken(String value) => _tokenPattern.hasMatch(value);

String publicNotePath(String token) => '$publicNoteRoutePrefix/$token';

/// The link to share for a published note (the site this build points at).
String publicNoteUrl(String token, {String? site}) {
  return '${site ?? authRedirectUrl()}${publicNotePath(token)}';
}

/// The route a browser's address (`https://site/n/<token>`) stands for, or
/// null for any other. The web app keeps its own routes after a `#`, so a
/// link without one (as people share it) needs this to find its page.
String? publicNoteLocationFor(Uri base) {
  if (base.fragment.isNotEmpty && base.fragment != '/') {
    return null;
  }
  final segments = base.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length == 2 &&
      '/${segments.first}' == publicNoteRoutePrefix &&
      isPublicNoteToken(segments[1])) {
    return publicNotePath(segments[1]);
  }
  return null;
}

/// A published note as the page shows it: what the note-public function
/// answers. Anything unexpected is left out rather than trusted.
@immutable
class PublicNote {
  const PublicNote({
    required this.title,
    required this.icon,
    required this.blocks,
    this.updatedAt,
    this.allowIndexing = false,
  });

  factory PublicNote.fromJson(Map<String, dynamic> json) {
    final blocks = <NoteBlock>[];
    final raw = json['blocks'];
    if (raw is List) {
      for (final (index, item) in raw.indexed) {
        if (item is! Map) {
          continue;
        }
        final map = Map<String, dynamic>.from(item);
        if ((map['id'] as String? ?? '').isEmpty) {
          map['id'] = 'public-$index';
        }
        map['pos'] = index.toString().padLeft(6, '0');
        map['marks'] = [
          for (final mark in (map['marks'] as List<dynamic>? ?? const []))
            if (mark is List && mark.length >= 3 && _safeMark(mark)) mark,
        ];
        try {
          blocks.add(NoteBlock.fromJson(map));
        } on Object {
          // A block of a shape we do not know is left out.
        }
      }
    }
    return PublicNote(
      title: json['title'] as String? ?? '',
      icon: json['icon'] as String? ?? NoteMeta.defaultIcon,
      updatedAt: DateTime.tryParse('${json['updated_at']}'),
      allowIndexing: json['allow_indexing'] == true,
      blocks: blocks,
    );
  }

  final String title;
  final String icon;
  final DateTime? updatedAt;

  /// The author let search engines list the page.
  final bool allowIndexing;
  final List<NoteBlock> blocks;
}

/// Whether a mark of the page is one we draw: formatting or a web link.
bool _safeMark(List<dynamic> mark) {
  final type = mark[2];
  if (type is! String) {
    return false;
  }
  if (type == 'b' || type == 'i' || type == 's' || type == 'c') {
    return true;
  }
  return type.startsWith(NoteMark.linkPrefix) &&
      isSafeWebLink(type.substring(NoteMark.linkPrefix.length));
}

/// Whether [url] is a link the page opens: http or https only.
bool isSafeWebLink(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      (uri.isScheme('http') || uri.isScheme('https')) &&
      uri.host.isNotEmpty;
}
