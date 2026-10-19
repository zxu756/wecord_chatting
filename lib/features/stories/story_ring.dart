import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/home/home_avatars.dart';
import 'package:wecord/features/stories/stories_models.dart';
import 'package:wecord/features/stories/stories_providers.dart';
import 'package:wecord/features/stories/story_viewer_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A ring around an avatar: the accent color while the person has a daily the
/// viewer has not seen, a faint thin ring once all are seen. Never red: red
/// is for what needs the person. The ring sits just outside [child], so the
/// avatar keeps its size and place.
class StoryRing extends StatelessWidget {
  const StoryRing({
    required this.entry,
    required this.child,
    this.gap = 2.5,
    this.stroke = 2.5,
    super.key,
  });

  /// The person's tray entry: [StoryTrayEntry.hasUnseen] picks the look.
  final StoryTrayEntry entry;
  final Widget child;
  final double gap;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final unseen = entry.hasUnseen;
    final outset = gap + stroke;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          left: -outset,
          top: -outset,
          right: -outset,
          bottom: -outset,
          child: IgnorePointer(
            child: DecoratedBox(
              key: ValueKey(
                unseen
                    ? 'story-ring-new-${entry.authorId}'
                    : 'story-ring-seen-${entry.authorId}',
              ),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: unseen ? c.accent : c.line,
                  width: unseen ? stroke : 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Opens the viewer for [authorId] from the current row of dailies.
void openStoriesOf(BuildContext context, WidgetRef ref, String authorId) {
  final tray = ref.read(storiesTrayProvider).value ?? const <StoryTrayEntry>[];
  unawaited(openStoryViewer(context, entries: tray, start: authorId));
}

/// A few friends with something new, as small ringed avatars, for the desktop
/// sidebar's Moments row. Tapping one opens that person's dailies.
class StoryRingCluster extends ConsumerWidget {
  const StoryRingCluster({this.max = 3, this.size = 22, super.key});

  final int max;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tray = ref.watch(storiesTrayProvider).value;
    if (tray == null) {
      return const SizedBox.shrink();
    }
    final fresh = [
      for (final entry in tray)
        if (!entry.isMe && entry.hasUnseen) entry,
    ];
    if (fresh.isEmpty) {
      return const SizedBox.shrink();
    }
    final shown = fresh.take(max).toList();
    return Row(
      key: const ValueKey('story-ring-cluster'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in shown)
          Padding(
            padding: const EdgeInsets.only(left: 7),
            child: Semantics(
              button: true,
              label: tr('New daily from {name}', {'name': entry.name}),
              excludeSemantics: true,
              child: GestureDetector(
                key: ValueKey('story-ring-${entry.authorId}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => openStoriesOf(context, ref, entry.authorId),
                child: Tooltip(
                  message: entry.name,
                  child: StoryRing(
                    entry: entry,
                    gap: 1.5,
                    stroke: 2,
                    child: ResolvedAvatar(
                      name: entry.name,
                      avatarUrl: entry.avatarUrl,
                      size: size,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (fresh.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              '+${fresh.length - shown.length}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.tokens.colors.muted,
              ),
            ),
          ),
      ],
    );
  }
}
