import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/sheet_rows.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';
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
    this.onAddOption,
  });

  /// Replaces the current user's votes on the poll.
  final Future<void> Function(ChatMessage message, List<String> optionIds)
  onVote;
  final Future<void> Function(ChatMessage message) onEnd;
  final void Function(ChatMessage message) onShowVoters;

  /// Whether the current user may end the poll early.
  final bool Function(ChatMessage message) canEnd;

  /// Adds an answer to a poll that lets members do so; null when this
  /// screen cannot.
  final Future<void> Function(ChatMessage message, String text)? onAddOption;
}

/// How a quiz answer reads after the right one is shown.
enum QuizMark { none, correct, wrong }

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

  Future<void> _addOption(PollActions actions) async {
    final add = actions.onAddOption;
    if (add == null) {
      return;
    }
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _AddOptionDialog(),
    );
    if (text == null || text.trim().isEmpty || !mounted) {
      return;
    }
    try {
      await add(widget.message, text.trim());
    } catch (_) {
      // The thread says why.
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
    // A quiz answer cannot be changed.
    final canVote =
        actions != null &&
        !closed &&
        !_voting &&
        !(poll.quiz && results.myVotes.isNotEmpty);
    final correct = poll.quiz ? results.correct : null;
    final showAnswer = correct != null;
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
            Icon(
              poll.quiz ? Icons.quiz_outlined : Icons.poll_outlined,
              size: 16,
              color: mutedColor,
            ),
            const SizedBox(width: 4),
            Text(
              poll.quiz ? tr('Quiz') : tr('Poll'),
              style: theme.textTheme.labelSmall?.copyWith(color: mutedColor),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          poll.question,
          style: TextStyle(
            fontSize: 15,
            height: 1.35,
            color: widget.textColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          closed
              ? tr('Final results')
              : poll.quiz
              ? (showAnswer
                    ? tr('Answer recorded')
                    : tr('Pick the right answer'))
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
              mark: !showAnswer
                  ? QuizMark.none
                  : option.id == correct
                  ? QuizMark.correct
                  : mine.contains(option.id)
                  ? QuizMark.wrong
                  : QuizMark.none,
              textColor: widget.textColor,
              onTap: canVote
                  ? () => unawaited(_vote(poll, mine, option.id))
                  : null,
            ),
          ),
        if (showAnswer && (results.explanation ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              key: ValueKey('poll-explanation-${message.id}'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: widget.textColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                results.explanation!,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: widget.textColor,
                ),
              ),
            ),
          ),
        if (poll.allowAdd &&
            !closed &&
            actions?.onAddOption != null &&
            poll.options.length < PollAttachment.maxOptions)
          _PollTextAction(
            key: ValueKey('poll-add-option-${message.id}'),
            label: tr('Add an answer'),
            color: widget.textColor,
            onPressed: () => unawaited(_addOption(actions!)),
          ),
        const SizedBox(height: 2),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text(
              [
                voters == 1
                    ? tr('1 vote')
                    : tr('{count} votes', {'count': voters}),
                if (poll.anonymous) tr('Anonymous'),
                ?status,
              ].join(' · '),
              key: ValueKey('poll-status-${message.id}'),
              style: theme.textTheme.labelSmall?.copyWith(color: mutedColor),
            ),
            if (actions != null && voters > 0 && !poll.anonymous)
              _PollTextAction(
                key: ValueKey('poll-view-votes-${message.id}'),
                label: tr('View votes'),
                color: widget.textColor,
                onPressed: () => actions.onShowVoters(message),
              ),
            if (actions != null && !closed && actions.canEnd(message))
              _PollTextAction(
                key: ValueKey('poll-end-${message.id}'),
                label: tr('End poll'),
                color: widget.textColor,
                onPressed: () => unawaited(actions.onEnd(message)),
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
    this.mark = QuizMark.none,
    super.key,
  });

  final QuizMark mark;
  final PollOption option;
  final bool multi;
  final double share;
  final int count;
  final bool selected;
  final Color textColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final percent = (share * 100).round();
    final icon = switch (mark) {
      QuizMark.correct => Icons.check_circle,
      QuizMark.wrong => Icons.cancel,
      QuizMark.none => switch ((multi, selected)) {
        (true, true) => Icons.check_box,
        (true, false) => Icons.check_box_outline_blank,
        (false, true) => Icons.check_circle,
        (false, false) => Icons.radio_button_unchecked,
      },
    };
    final accent = switch (mark) {
      QuizMark.correct => c.success,
      QuizMark.wrong => c.danger,
      QuizMark.none => c.accent,
    };
    final highlighted = selected || mark == QuizMark.correct;
    return Semantics(
      selected: selected,
      button: onTap != null,
      label: [
        count == 1
            ? tr('{option}, 1 vote', {'option': option.text})
            : tr('{option}, {count} votes', {
                'option': option.text,
                'count': count,
              }),
        if (mark == QuizMark.correct) tr('Right answer'),
        if (mark == QuizMark.wrong) tr('Your answer, not right'),
      ].join(', '),
      excludeSemantics: true,
      child: WeCordPressable(
        onPressed: onTap,
        pressedScale: 0.98,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        builder: (context, states) => Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: textColor.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlighted ? accent : textColor.withValues(alpha: 0),
              width: 1.5,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: share,
                  child: ColoredBox(
                    key: ValueKey('poll-bar-${option.id}'),
                    color: accent.withValues(alpha: highlighted ? 0.3 : 0.16),
                  ),
                ),
              ),
              ConstrainedBox(
                // Comfortable to tap on touch screens.
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: highlighted ? accent : textColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          option.text,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.35,
                            color: textColor,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$percent%',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
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

/// A small text action under a poll (View votes, End poll).
class _PollTextAction extends StatelessWidget {
  const _PollTextAction({
    required this.label,
    required this.color,
    required this.onPressed,
    super.key,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return WeCordPressable(
      onPressed: onPressed,
      builder: (context, states) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
              decoration: states.contains(WidgetState.hovered)
                  ? TextDecoration.underline
                  : null,
              decorationColor: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Who voted for each answer of a poll, inside a WeCord sheet titled
/// "Votes": the question, a chip per answer with its count, and the
/// selected answer's voters.
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
    final c = context.tokens.colors;
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
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (poll != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  poll.question,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, height: 1.35, color: c.muted),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in options)
                    _VoterOptionChip(
                      key: ValueKey('poll-voters-option-${option.id}'),
                      label: option.text,
                      count: results.countFor(option.id),
                      selected: option.id == optionId,
                      onPressed: () => setState(() => _optionId = option.id),
                    ),
                ],
              ),
            ),
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

/// An answer to pick in the votes sheet: its text (cut short when long)
/// and how many voted for it; ink when selected.
class _VoterOptionChip extends StatelessWidget {
  const _VoterOptionChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final fill = selected ? c.ink : c.raised;
    final foreground = selected ? c.onInk : c.ink;
    return WeCordPressable(
      selected: selected,
      semanticLabel: '$label, $count',
      excludeSemantics: true,
      onPressed: () {
        WeCordHaptics.selection();
        onPressed();
      },
      shape: const StadiumBorder(),
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered) && !selected;
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          curve: WeCordMotion.standard,
          height: 36,
          padding: const EdgeInsets.only(left: 14, right: 6),
          decoration: ShapeDecoration(
            color: hovered
                ? Color.alphaBlend(c.ink.withValues(alpha: 0.05), fill)
                : fill,
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 24),
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: selected ? c.onInk.withValues(alpha: 0.18) : c.panel,
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
      loading: () => const SheetSpinner(),
      error: (error, stackTrace) =>
          SheetNote(text: tr('Could not load votes.'), error: true),
      data: (profiles) {
        if (profiles.isEmpty) {
          return SheetNote(text: tr('No votes for this answer yet.'));
        }
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          children: [
            for (final profile in profiles)
              SheetListRow(
                key: ValueKey('poll-voter-${profile.id}'),
                leading: ProfileAvatar(
                  name: profile.displayLabel,
                  avatarUrl: profile.avatarUrl,
                  size: 40,
                ),
                title: profile.displayLabel,
                subtitle: '@${profile.username}',
              ),
          ],
        );
      },
    );
  }
}

/// Asks for the text of an answer to add to a poll.
class _AddOptionDialog extends StatefulWidget {
  const _AddOptionDialog();

  @override
  State<_AddOptionDialog> createState() => _AddOptionDialogState();
}

class _AddOptionDialogState extends State<_AddOptionDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(tr('Add an answer')),
      content: TextField(
        key: const ValueKey('poll-new-option-field'),
        controller: _controller,
        autofocus: true,
        maxLength: PollAttachment.maxOptionLength,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.of(context).pop(value),
        decoration: InputDecoration(labelText: tr('Answer')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          key: const ValueKey('poll-new-option-add'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(tr('Add')),
        ),
      ],
    );
  }
}
