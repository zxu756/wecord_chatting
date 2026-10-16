import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/message_author.dart';
import 'package:wecord/features/circles/circle_settings_screen.dart';
import 'package:wecord/features/circles/circle_tag_repository.dart';
import 'package:wecord/features/circles/circle_ui.dart' hide CircleTag;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A circle tag: its badge and text in a small rounded tag.
class CircleTagChip extends StatelessWidget {
  const CircleTagChip({required this.tag, this.circleName, super.key});

  final CircleTag tag;

  /// Shown on hover or long press.
  final String? circleName;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: c.successSoft,
        borderRadius: BorderRadius.circular(WeCordRadii.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tag.badge.icon, size: 11, color: c.successText),
          const SizedBox(width: 3),
          Text(
            tag.text,
            style: TextStyle(
              color: c.successText,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              height: 1.3,
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
    final c = context.tokens.colors;
    final previewText = _controller.text.trim();
    final labelStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: c.muted,
    );
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
        CircleCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WeCordTextField(
                fieldKey: const ValueKey('circle-tag-field'),
                controller: _controller,
                enabled: !_busy && current.hasValue,
                maxLength: CircleTag.maxLength,
                label: tr('Tag'),
                hint: tr('2 to 4 characters'),
                errorText: _error,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 8),
                child: Text(tr('Badge'), style: labelStyle),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final badge in CircleTagBadge.values)
                    WeCordIconButton(
                      key: ValueKey('circle-tag-badge-${badge.value}'),
                      tooltip: tr('Badge'),
                      icon: badge.icon,
                      size: 40,
                      iconSize: 20,
                      variant: badge == _badge
                          ? WeCordButtonVariant.primary
                          : WeCordButtonVariant.secondary,
                      selected: badge == _badge,
                      onPressed: _busy
                          ? null
                          : () => setState(() => _badge = badge),
                    ),
                ],
              ),
              if (previewText.isNotEmpty &&
                  circleTagProblem(previewText) == null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Text(tr('Preview'), style: labelStyle),
                      const SizedBox(width: 8),
                      CircleTagChip(
                        tag: CircleTag(text: previewText, badge: _badge),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  WeCordButton(
                    key: const ValueKey('circle-tag-save'),
                    label: tr('Save tag'),
                    onPressed: _busy || !current.hasValue
                        ? null
                        : () => _save(),
                  ),
                  if (current.valueOrNull != null)
                    WeCordButton(
                      key: const ValueKey('circle-tag-remove'),
                      label: tr('Turn off tag'),
                      variant: WeCordButtonVariant.secondary,
                      onPressed: _busy ? null : () => _save(remove: true),
                    ),
                ],
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
    return SettingsRow(
      key: const ValueKey('circle-tag-setting'),
      icon: Icons.sell_outlined,
      title: tr('Circle tag'),
      subtitle: tag == null
          ? tr('Show the tag of one of your circles next to your name')
          : badges.tagCircleName ?? tag.text,
      trailing: tag == null ? null : CircleTagChip(tag: tag),
      showChevron: true,
      onTap: () => unawaited(_choose(context, ref, userId)),
    );
  }

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    String? userId,
  ) async {
    final choice = await showWeCordSheet<_TagChoice>(
      context,
      title: tr('Circle tag'),
      builder: (context, _) => const _CircleTagPickerSheet(),
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
    final c = context.tokens.colors;
    final circles = ref.watch(tagCirclesProvider);
    final list = circles.valueOrNull ?? const <TagCircle>[];
    final noneSelected = list.every((circle) => !circle.isSelected);
    Widget? check(bool selected) =>
        selected ? Icon(Icons.check_rounded, size: 20, color: c.accent) : null;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              tr(
                'Only circles you are in that turned on a tag are listed. '
                'Leaving the circle removes it.',
              ),
              style: TextStyle(fontSize: 14, color: c.muted, height: 1.4),
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
          else ...[
            SettingsGroup(
              color: c.well,
              children: [
                SettingsRow(
                  key: const ValueKey('circle-tag-none'),
                  icon: Icons.block,
                  title: tr('No tag'),
                  trailing: check(noneSelected),
                  showChevron: false,
                  onTap: () =>
                      Navigator.of(context).pop(const _TagChoice(null)),
                ),
                for (final circle in list)
                  SettingsRow(
                    key: ValueKey('circle-tag-choice-${circle.circleId}'),
                    icon: circle.tag.badge.icon,
                    tone: SettingsTone.success,
                    title: circle.circleName,
                    subtitle: circle.tag.text,
                    trailing: check(circle.isSelected),
                    showChevron: false,
                    onTap: () =>
                        Navigator.of(context).pop(_TagChoice(circle.circleId)),
                  ),
              ],
            ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                child: Text(
                  tr('None of your circles has a tag yet.'),
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
