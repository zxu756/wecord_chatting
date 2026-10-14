import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/poll.dart';
import 'package:wecord/shared/models/profile.dart';

typedef PollVotersKey = ({String messageId, String optionId});

final pollVotersProvider = FutureProvider.autoDispose
    .family<List<Profile>, PollVotersKey>((ref, key) {
      return ref
          .watch(chatsRepositoryProvider)
          .listPollVoters(messageId: key.messageId, optionId: key.optionId);
    });

/// What a poll bubble can do; the thread handles requests and errors.
class PollActions {
  const PollActions({
    required this.onVote,
    required this.onEnd,
    required this.onShowVoters,
    required this.canEnd,
  });

  /// Replaces the current user's votes on the poll.
  final Future<void> Function(ChatMessage message, List<String> optionIds)
  onVote;
  final Future<void> Function(ChatMessage message) onEnd;
  final void Function(ChatMessage message) onShowVoters;

  /// Whether the current user may end the poll early.
  final bool Function(ChatMessage message) canEnd;
}

/// A poll inside its message bubble: the question, one row per option with
/// its share of voters (tap to vote), the voter count, when it ends, and
/// the links to see votes or end it early.
class PollMessageContent extends StatefulWidget {
  const PollMessageContent({
    required this.message,
    required this.textColor,
    this.actions,
    this.now,
    super.key,
  });

  final ChatMessage message;
  final Color textColor;

  /// Null shows the poll read-only.
  final PollActions? actions;

  /// The current time, for tests; defaults to the clock.
  final DateTime? now;

  @override
  State<PollMessageContent> createState() => _PollMessageContentState();
}

class _PollMessageContentState extends State<PollMessageContent> {
  /// The votes just chosen, shown until the thread reloads with them.
  Set<String>? _pending;
  var _voting = false;

  @override
  void didUpdateWidget(covariant PollMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.message.pollResults, widget.message.pollResults)) {
      _pending = null;
    }
  }

  Future<void> _vote(
    PollAttachment poll,
    Set<String> current,
    String id,
  ) async {
    final actions = widget.actions;
    if (actions == null || _voting) {
      return;
    }
    final Set<String> next;
    if (poll.multi) {
      next = {...current};
      if (!next.remove(id)) {
        next.add(id);
      }
    } else {
      next = current.contains(id) ? <String>{} : {id};
    }
    setState(() {
      _pending = next;
      _voting = true;
    });
    try {
      await actions.onVote(widget.message, [
        for (final option in poll.options)
          if (next.contains(option.id)) option.id,
      ]);
    } catch (_) {
      if (mounted) {
        setState(() => _pending = null);
      }
    } finally {
      if (mounted) {
        setState(() => _voting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = widget.message;
    final poll = message.pollAttachment;
    if (poll == null) {
      return Text(
        pollPreviewText(message.body),
        style: TextStyle(color: widget.textColor),
      );
    }
    final now = (widget.now ?? DateTime.now()).toUtc();
    final results = message.pollResults ?? const PollResults();
    final closed =
        results.closed || message.recalledAt != null || poll.hasEndedAt(now);
    final mine = _pending ?? results.myVotes;
    final actions = widget.actions;
    final canVote = actions != null && !closed && !_voting;
    final mutedColor = widget.textColor.withValues(alpha: 0.72);
    final voters = results.totalVoters;
    final endsAt = poll.endsAt;
    final status = closed
        ? tr('Closed')
        : endsAt != null
        ? pollEndsInLabel(endsAt, now: now)
        : null;

    return Column(
      key: ValueKey('poll-${message.id}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.poll_outlined, size: 16, color: mutedColor),
            const SizedBox(width: 4),
            Text(
              tr('Poll'),
              style: theme.textTheme.labelSmall?.copyWith(color: mutedColor),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          poll.question,
          style: theme.textTheme.titleSmall?.copyWith(
            color: widget.textColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          closed
              ? tr('Final results')
              : poll.multi
              ? tr('Select one or more answers')
              : tr('Select one answer'),
          style: theme.textTheme.labelSmall?.copyWith(color: mutedColor),
        ),
        const SizedBox(height: 8),
        for (final option in poll.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _PollOptionRow(
              key: ValueKey('poll-option-${message.id}-${option.id}'),
              option: option,
              multi: poll.multi,
              share: results.shareOf(option.id),
              count: results.countFor(option.id),
              selected: mine.contains(option.id),
              textColor: widget.textColor,
              onTap: canVote
                  ? () => unawaited(_vote(poll, mine, option.id))
                  : null,
            ),
          ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Text(
              [
                voters == 1
                    ? tr('1 vote')
                    : tr('{count} votes', {'count': voters}),
                ?status,
              ].join(' · '),
              key: ValueKey('poll-status-${message.id}'),
              style: theme.textTheme.labelSmall?.copyWith(color: mutedColor),
            ),
            if (actions != null && voters > 0)
              TextButton(
                key: ValueKey('poll-view-votes-${message.id}'),
                style: TextButton.styleFrom(
                  foregroundColor: widget.textColor,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => actions.onShowVoters(message),
                child: Text(tr('View votes')),
              ),
            if (actions != null && !closed && actions.canEnd(message))
              TextButton(
                key: ValueKey('poll-end-${message.id}'),
                style: TextButton.styleFrom(
                  foregroundColor: widget.textColor,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => unawaited(actions.onEnd(message)),
                child: Text(tr('End poll')),
              ),
          ],
        ),
      ],
    );
  }
}

class _PollOptionRow extends StatelessWidget {
  const _PollOptionRow({
    required this.option,
    required this.multi,
    required this.share,
    required this.count,
    required this.selected,
    required this.textColor,
    required this.onTap,
    super.key,
  });

  final PollOption option;
  final bool multi;
  final double share;
  final int count;
  final bool selected;
  final Color textColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final percent = (share * 100).round();
    final icon = switch ((multi, selected)) {
      (true, true) => Icons.check_box,
      (true, false) => Icons.check_box_outline_blank,
      (false, true) => Icons.check_circle,
      (false, false) => Icons.radio_button_unchecked,
    };
    return Semantics(
      selected: selected,
      button: onTap != null,
      label: count == 1
          ? tr('{option}, 1 vote', {'option': option.text})
          : tr('{option}, {count} votes', {
              'option': option.text,
              'count': count,
            }),
      excludeSemantics: true,
      child: Material(
        color: textColor.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: selected
                ? colorScheme.primary
                : textColor.withValues(alpha: 0.18),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: share,
                  child: ColoredBox(
                    key: ValueKey('poll-bar-${option.id}'),
                    color: colorScheme.primary.withValues(
                      alpha: selected ? 0.28 : 0.14,
                    ),
                  ),
                ),
              ),
              ConstrainedBox(
                // Comfortable to tap on touch screens.
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: selected ? colorScheme.primary : textColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          option.text,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: textColor,
                            fontWeight: selected ? FontWeight.w700 : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$percent%',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: textColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Who voted for each option of a poll, one option at a time.
class PollVotersSheet extends ConsumerStatefulWidget {
  const PollVotersSheet({required this.message, super.key});

  final ChatMessage message;

  @override
  ConsumerState<PollVotersSheet> createState() => _PollVotersSheetState();
}

class _PollVotersSheetState extends ConsumerState<PollVotersSheet> {
  String? _optionId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final poll = widget.message.pollAttachment;
    final options = poll?.options ?? const <PollOption>[];
    final results = widget.message.pollResults ?? const PollResults();
    final optionId =
        _optionId ??
        options
            .where((option) => results.countFor(option.id) > 0)
            .firstOrNull
            ?.id ??
        options.firstOrNull?.id;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Votes'), style: theme.textTheme.titleLarge),
            if (poll != null)
              Text(
                poll.question,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in options)
                  ChoiceChip(
                    key: ValueKey('poll-voters-option-${option.id}'),
                    label: Text(
                      '${option.text} (${results.countFor(option.id)})',
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: option.id == optionId,
                    onSelected: (_) => setState(() => _optionId = option.id),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: optionId == null
                  ? const SizedBox.shrink()
                  : _PollVoterList(
                      key: ValueKey('poll-voters-$optionId'),
                      votersKey: (
                        messageId: widget.message.id,
                        optionId: optionId,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PollVoterList extends ConsumerWidget {
  const _PollVoterList({required this.votersKey, super.key});

  final PollVotersKey votersKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voters = ref.watch(pollVotersProvider(votersKey));
    return voters.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(tr('Could not load votes.')),
      ),
      data: (profiles) {
        if (profiles.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(tr('No votes for this answer yet.')),
          );
        }
        return ListView(
          shrinkWrap: true,
          children: [
            for (final profile in profiles)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text(_initials(profile))),
                title: Text(
                  profile.displayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('@${profile.username}'),
              ),
          ],
        );
      },
    );
  }
}

String _initials(Profile profile) {
  final label = profile.displayLabel.trim();
  return label.isEmpty ? '?' : label.characters.first.toUpperCase();
}
