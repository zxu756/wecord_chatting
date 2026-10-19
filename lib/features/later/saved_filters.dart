import 'package:wecord/features/later/saved_messages_repository.dart';

/// Which saved entries the page lists: still to do, or marked done.
enum SavedFilter { active, done }

/// What is narrowed on the Saved page.
class SavedView {
  const SavedView({
    this.status = SavedFilter.active,
    this.folderId,
    this.tag,
    this.matchIds,
  });

  final SavedFilter status;

  /// Only this folder (null: all of them).
  final String? folderId;

  /// Only entries with this tag (any case).
  final String? tag;

  /// Only these entries (the result of a search); null: not searching.
  final Set<String>? matchIds;

  SavedView copyWith({
    SavedFilter? status,
    Object? folderId = _keep,
    Object? tag = _keep,
    Object? matchIds = _keep,
  }) {
    return SavedView(
      status: status ?? this.status,
      folderId: identical(folderId, _keep)
          ? this.folderId
          : folderId as String?,
      tag: identical(tag, _keep) ? this.tag : tag as String?,
      matchIds: identical(matchIds, _keep)
          ? this.matchIds
          : matchIds as Set<String>?,
    );
  }

  static const _keep = Object();
}

bool _sameTag(String a, String b) => a.toLowerCase() == b.toLowerCase();

/// The entries of [all] that [view] shows, in the order given.
List<SavedMessage> filterSaved(List<SavedMessage> all, SavedView view) {
  return [
    for (final item in all)
      // A search looks through everything, done or not.
      if ((view.matchIds != null ||
              (view.status == SavedFilter.done) == item.isDone) &&
          (view.folderId == null || item.folderId == view.folderId) &&
          (view.tag == null || item.tags.any((t) => _sameTag(t, view.tag!))) &&
          (view.matchIds == null || view.matchIds!.contains(item.id)))
        item,
  ];
}

/// How many entries are in each folder (ignoring the status and the tag),
/// for the folder chips.
Map<String, int> folderCounts(List<SavedMessage> all) {
  final counts = <String, int>{};
  for (final item in all) {
    final folder = item.folderId;
    if (folder != null) {
      counts[folder] = (counts[folder] ?? 0) + 1;
    }
  }
  return counts;
}

/// Every tag in use with how many entries carry it, most used first, then
/// alphabetical (any case). Each tag appears once, as first spelled.
List<({String tag, int count})> tagCounts(List<SavedMessage> all) {
  final counts = <String, ({String tag, int count})>{};
  for (final item in all) {
    for (final tag in item.tags) {
      final key = tag.toLowerCase();
      final known = counts[key];
      counts[key] = (tag: known?.tag ?? tag, count: (known?.count ?? 0) + 1);
    }
  }
  final out = counts.values.toList()
    ..sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0
          ? byCount
          : a.tag.toLowerCase().compareTo(b.tag.toLowerCase());
    });
  return out;
}

/// A tag as typed, tidied the way the server does: no leading "#", spaces
/// folded, at most [maxSavedTagLength] characters. Empty when nothing is
/// left.
String tidySavedTag(String raw) {
  final folded = raw
      .replaceFirst(RegExp(r'^\s*#+'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  final cut = String.fromCharCodes(folded.runes.take(maxSavedTagLength));
  return cut.trim();
}
