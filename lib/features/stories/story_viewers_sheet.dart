import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/home/home_avatars.dart';
import 'package:wecord/features/stories/stories_models.dart';
import 'package:wecord/features/stories/stories_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Who viewed one of my dailies (only its author can open this).
Future<void> showStoryViewersSheet(BuildContext context, Story story) {
  return showWeCordSheet<void>(
    context,
    title: tr('Viewed by'),
    detents: const [0.55, 0.92],
    useRootNavigator: true,
    builder: (_, scroll) => StoryViewersSheet(story: story, scroll: scroll),
  );
}

final _storyViewersProvider = FutureProvider.autoDispose
    .family<List<StoryViewerEntry>, String>((ref, storyId) {
      return ref.watch(storiesRepositoryProvider).viewers(storyId);
    });

class StoryViewersSheet extends ConsumerWidget {
  const StoryViewersSheet({required this.story, this.scroll, super.key});

  final Story story;
  final ScrollController? scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final viewers = ref.watch(_storyViewersProvider(story.id));
    final now = DateTime.now();
    return SafeArea(
      top: false,
      child: viewers.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stackTrace) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Text(
            tr('Could not load who viewed this.'),
            key: const ValueKey('story-viewers-error'),
            style: TextStyle(fontSize: 14, color: c.muted),
          ),
        ),
        data: (entries) => ListView(
          controller: scroll,
          shrinkWrap: scroll == null,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
              child: Text(
                entries.isEmpty
                    ? tr('Nobody has viewed this yet.')
                    : tr('Only you can see this list.'),
                key: const ValueKey('story-viewers-note'),
                style: TextStyle(fontSize: 13.5, color: c.muted),
              ),
            ),
            if (entries.isNotEmpty)
              SettingsGroup(
                color: c.well,
                separatorIndent: 66,
                children: [
                  for (final entry in entries)
                    _ViewerRow(entry: entry, now: now),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ViewerRow extends StatelessWidget {
  const _ViewerRow({required this.entry, required this.now});

  final StoryViewerEntry entry;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final emoji = entry.emoji;
    return Semantics(
      container: true,
      label: emoji == null
          ? tr('{name}, viewed {when}', {
              'name': entry.name,
              'when': storyAgeLabel(entry.viewedAt, now),
            })
          : tr('{name}, viewed {when}, reacted {emoji}', {
              'name': entry.name,
              'when': storyAgeLabel(entry.viewedAt, now),
              'emoji': emoji,
            }),
      excludeSemantics: true,
      child: Padding(
        key: ValueKey('story-viewer-${entry.viewerId}'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            ResolvedAvatar(
              name: entry.name,
              avatarUrl: entry.avatarUrl,
              size: 40,
              ringColor: c.well,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  Text(
                    storyAgeLabel(entry.viewedAt, now),
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
                ],
              ),
            ),
            if (emoji != null)
              Text(emoji, style: const TextStyle(fontSize: 22)),
          ],
        ),
      ),
    );
  }
}
