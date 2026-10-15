import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/message_author.dart';
import 'package:wecord/features/circles/circle_settings_screen.dart';
import 'package:wecord/features/circles/circle_tag_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// A circle tag: its badge and text in a small pill.
class CircleTagChip extends StatelessWidget {
  const CircleTagChip({required this.tag, this.circleName, super.key});

  final CircleTag tag;

  /// Shown on hover or long press.
  final String? circleName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tag.badge.icon, size: 11, color: theme.colorScheme.primary),
          const SizedBox(width: 2),
          Text(
            tag.text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 10,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
    final name = circleName;
    if (name == null || name.isEmpty) {
      return chip;
    }
    return Tooltip(message: name, child: chip);
  }
}

/// What shows next to [userId]'s name: a BOT badge for bots and their
/// circle tag, if they chose one. Nothing while loading or without them.
class ProfileNameBadges extends ConsumerWidget {
  const ProfileNameBadges({
    required this.userId,
    this.leadingGap = 6,
    super.key,
  });

  final String userId;

  /// Space before the badges when there are any.
  final double leadingGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges =
        ref.watch(profileBadgesProvider(userId)).valueOrNull ??
        ProfileBadges.none;
    final tag = badges.tag;
    if (badges.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      key: ValueKey('profile-badges-$userId'),
      padding: EdgeInsetsDirectional.only(start: leadingGap),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badges.isBot) const MessageBotTag(),
          if (badges.isBot && tag != null) const SizedBox(width: 4),
          if (tag != null)
            CircleTagChip(tag: tag, circleName: badges.tagCircleName),
        ],
      ),
    );
  }
}

/// Circle settings → Tag: a short tag with a badge members can show next
/// to their names.
class CircleTagSection extends ConsumerStatefulWidget {
  const CircleTagSection({required this.circleId, super.key});

  final String circleId;

  @override
  ConsumerState<CircleTagSection> createState() => _CircleTagSectionState();
}

class _CircleTagSectionState extends ConsumerState<CircleTagSection> {
  final _controller = TextEditingController();
  var _badge = CircleTagBadge.star;
  var _loaded = false;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save({bool remove = false}) async {
    final text = remove ? '' : _controller.text.trim();
    final problem = circleTagProblem(text);
    if (problem != null) {
      setState(
        () => _error = problem == 'length'
            ? tr('A tag is 2 to 4 characters.')
            : tr('Use letters and digits only.'),
      );
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await ref
          .read(circleTagRepositoryProvider)
          .setCircleTag(circleId: widget.circleId, text: text, badge: _badge);
      if (!mounted) return;
      setState(() {
        _controller.text = saved?.text ?? '';
        _badge = saved?.badge ?? _badge;
      });
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            saved == null ? tr('Circle tag removed.') : tr('Circle tag saved.'),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = tr('Could not save the tag. Try again.'));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(circleTagProvider(widget.circleId));
    if (!_loaded && current.hasValue) {
      _loaded = true;
      _controller.text = current.value?.text ?? '';
      _badge = current.value?.badge ?? CircleTagBadge.star;
    }
    final theme = Theme.of(context);
    final previewText = _controller.text.trim();
    return Column(
      key: const ValueKey('circle-tag-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CircleSettingsHeader(
          tr('Circle tag'),
          subtitle: tr(
            'Members can show this tag next to their name everywhere. '
            'Leaving the circle removes it.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            key: const ValueKey('circle-tag-field'),
            controller: _controller,
            enabled: !_busy && current.hasValue,
            maxLength: CircleTag.maxLength,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: tr('Tag'),
              hintText: tr('2 to 4 characters'),
              errorText: _error,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(tr('Badge'), style: theme.textTheme.labelLarge),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final badge in CircleTagBadge.values)
                IconButton(
                  key: ValueKey('circle-tag-badge-${badge.value}'),
                  isSelected: badge == _badge,
                  style: IconButton.styleFrom(
                    backgroundColor: badge == _badge
                        ? theme.colorScheme.primaryContainer
                        : null,
                  ),
                  icon: Icon(badge.icon),
                  color: badge == _badge
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                  onPressed: _busy
                      ? null
                      : () => setState(() => _badge = badge),
                ),
            ],
          ),
        ),
        if (previewText.isNotEmpty && circleTagProblem(previewText) == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Text(tr('Preview'), style: theme.textTheme.bodySmall),
                const SizedBox(width: 8),
                CircleTagChip(
                  tag: CircleTag(text: previewText, badge: _badge),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                key: const ValueKey('circle-tag-save'),
                onPressed: _busy || !current.hasValue ? null : () => _save(),
                child: Text(tr('Save tag')),
              ),
              if (current.valueOrNull != null)
                OutlinedButton(
                  key: const ValueKey('circle-tag-remove'),
                  onPressed: _busy ? null : () => _save(remove: true),
                  child: Text(tr('Turn off tag')),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Settings → Profile: which circle's tag shows next to the current
/// user's name.
class CircleTagSettingTile extends ConsumerWidget {
  const CircleTagSettingTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(authRepositoryProvider).currentUser?.id;
    final badges = userId == null
        ? ProfileBadges.none
        : ref.watch(profileBadgesProvider(userId)).valueOrNull ??
              ProfileBadges.none;
    final tag = badges.tag;
    return ListTile(
      key: const ValueKey('circle-tag-setting'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.sell_outlined),
      title: Text(tr('Circle tag')),
      subtitle: Text(
        tag == null
            ? tr('Show the tag of one of your circles next to your name')
            : badges.tagCircleName ?? tag.text,
      ),
      trailing: tag == null ? null : CircleTagChip(tag: tag),
      onTap: () => unawaited(_choose(context, ref, userId)),
    );
  }

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    String? userId,
  ) async {
    final choice = await showModalBottomSheet<_TagChoice>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => const _CircleTagPickerSheet(),
    );
    if (choice == null || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(circleTagRepositoryProvider)
          .setDisplayTag(choice.circleId);
      if (userId != null) {
        refreshProfileBadges(ref, userId);
      }
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not change your tag. Try again.'))),
      );
    }
  }
}

class _TagChoice {
  const _TagChoice(this.circleId);

  final String? circleId;
}

class _CircleTagPickerSheet extends ConsumerWidget {
  const _CircleTagPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final circles = ref.watch(tagCirclesProvider);
    final list = circles.valueOrNull ?? const <TagCircle>[];
    final noneSelected = list.every((circle) => !circle.isSelected);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Text(tr('Circle tag'), style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              tr(
                'Only circles you are in that turned on a tag are listed. '
                'Leaving the circle removes it.',
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (circles.isLoading && !circles.hasValue)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (circles.hasError)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(tr('Could not load your circles.')),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    key: const ValueKey('circle-tag-none'),
                    leading: const Icon(Icons.block),
                    title: Text(tr('No tag')),
                    trailing: noneSelected ? const Icon(Icons.check) : null,
                    onTap: () =>
                        Navigator.of(context).pop(const _TagChoice(null)),
                  ),
                  for (final circle in list)
                    ListTile(
                      key: ValueKey('circle-tag-choice-${circle.circleId}'),
                      leading: CircleTagChip(tag: circle.tag),
                      title: Text(
                        circle.circleName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: circle.isSelected
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(_TagChoice(circle.circleId)),
                    ),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                      child: Text(
                        tr('None of your circles has a tag yet.'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
