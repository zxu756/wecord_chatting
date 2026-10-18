import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wecord/features/circles/join_requests/join_request_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What the join button does for a circle in a given state.
enum JoinButtonKind {
  /// Joins at once (also while the state is not known: the server decides).
  join,

  /// Sends a request with the answers.
  sendRequest,

  /// Nothing to press: waiting, closed, invite only, or told to wait.
  disabled,
}

/// The join button's label and what pressing it does.
class JoinButtonPlan {
  const JoinButtonPlan(this.kind, this.label);

  final JoinButtonKind kind;
  final String label;

  bool get enabled => kind != JoinButtonKind.disabled;
}

/// Plans the join button from [state] (null when unknown). [viaInvite] is
/// true on an invite page: an invite is the way into an invite-only circle.
JoinButtonPlan planJoinButton(
  CircleJoinState? state, {
  required bool viaInvite,
  required DateTime now,
}) {
  if (state == null) {
    return JoinButtonPlan(JoinButtonKind.join, tr('Join circle'));
  }
  if (state.closed) {
    return JoinButtonPlan(
      JoinButtonKind.disabled,
      tr('Not taking new members'),
    );
  }
  if (state.isPending) {
    return JoinButtonPlan(
      JoinButtonKind.disabled,
      trIn('join request', 'Request sent'),
    );
  }
  if (state.mode == CircleJoinMode.inviteOnly && !viaInvite) {
    return JoinButtonPlan(JoinButtonKind.disabled, tr('Invite only'));
  }
  if (state.needsReview) {
    if (state.isDenied && !state.canRetryAt(now)) {
      return JoinButtonPlan(JoinButtonKind.disabled, tr('Try again tomorrow'));
    }
    return JoinButtonPlan(JoinButtonKind.sendRequest, tr('Send request'));
  }
  return JoinButtonPlan(JoinButtonKind.join, tr('Join circle'));
}

/// What went wrong when a join or a request was refused for a reason worth
/// telling, or null for any other error.
String? joinErrorMessage(Object error) {
  final text = '$error';
  if (text.contains('Banned from this circle')) {
    return tr("You're banned from this circle.");
  }
  if (text.contains('invite only')) {
    return tr('This circle is invite only.');
  }
  if (text.contains('not accepting new members')) {
    return tr('This circle is not taking new members.');
  }
  if (text.contains('Your request was declined')) {
    return tr('Your request was turned down. You can ask again tomorrow.');
  }
  if (text.contains('Too many open requests')) {
    return tr('You have too many requests waiting. Wait for an answer first.');
  }
  if (text.contains('Answer the required questions') ||
      text.contains('answers_required')) {
    return tr('Answer the required questions first.');
  }
  return null;
}

/// The questions a circle asks, answered inline. Reports the answers by
/// question id on every change.
class JoinQuestionsForm extends StatefulWidget {
  const JoinQuestionsForm({
    required this.questions,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final List<JoinQuestion> questions;
  final ValueChanged<Map<String, String>> onChanged;
  final bool enabled;

  @override
  State<JoinQuestionsForm> createState() => _JoinQuestionsFormState();
}

class _JoinQuestionsFormState extends State<JoinQuestionsForm> {
  final _answers = <String, String>{};
  final _controllers = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _set(String id, String value) {
    setState(() => _answers[id] = value);
    widget.onChanged(Map.of(_answers));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Column(
      key: const ValueKey('join-questions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, question) in widget.questions.indexed) ...[
          if (index > 0) const SizedBox(height: 16),
          Semantics(
            container: true,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: question.prompt),
                  if (!question.required)
                    TextSpan(
                      text: '  ${tr('Optional')}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: c.subtle,
                      ),
                    ),
                ],
              ),
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (question.kind == JoinQuestionKind.text)
            WeCordTextField(
              fieldKey: ValueKey('join-answer-${question.id}'),
              controller: _controllers.putIfAbsent(
                question.id,
                TextEditingController.new,
              ),
              enabled: widget.enabled,
              minLines: 2,
              maxLines: 5,
              inputFormatters: [
                LengthLimitingTextInputFormatter(joinAnswerMaxLength),
              ],
              hint: tr('Your answer'),
              onChanged: (value) => _set(question.id, value),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in question.options)
                  WeCordChip(
                    key: ValueKey('join-option-${question.id}-$option'),
                    label: option,
                    selected: _answers[question.id] == option,
                    height: 40,
                    onPressed: widget.enabled
                        ? () => _set(
                            question.id,
                            _answers[question.id] == option ? '' : option,
                          )
                        : null,
                  ),
              ],
            ),
        ],
      ],
    );
  }
}

/// A soft box saying where the request stands: waiting, turned down, or
/// that the circle only takes invites.
class JoinStatusPanel extends StatelessWidget {
  const JoinStatusPanel({
    required this.state,
    required this.viaInvite,
    this.onCancel,
    this.cancelling = false,
    this.now,
    super.key,
  });

  final CircleJoinState state;
  final bool viaInvite;
  final VoidCallback? onCancel;
  final bool cancelling;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final current = now ?? DateTime.now().toUtc();
    final (icon, fill, foreground, title, message) = _content(c, current);
    if (title == null) {
      return const SizedBox.shrink();
    }
    return Container(
      key: const ValueKey('join-status'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: foreground,
                      ),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        message,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: c.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (state.isPending && onCancel != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: WeCordButton(
                key: const ValueKey('join-cancel-request'),
                label: tr('Cancel request'),
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.small,
                loading: cancelling,
                onPressed: cancelling ? null : onCancel,
              ),
            ),
          ],
        ],
      ),
    );
  }

  (IconData, Color, Color, String?, String?) _content(
    WeCordPalette c,
    DateTime current,
  ) {
    if (state.closed) {
      return (
        Icons.lock_outline_rounded,
        c.raised,
        c.ink,
        tr('This circle is not taking new members.'),
        null,
      );
    }
    if (state.isPending) {
      return (
        Icons.hourglass_top_rounded,
        c.warningSoft,
        c.warningText,
        tr('Waiting for review'),
        state.request?.invited ?? false
            ? tr(
                'A member invited you. The moderators decide whether you '
                'join, and you will be told here.',
              )
            : tr(
                'The moderators have your request. You will be told here '
                'when they decide.',
              ),
      );
    }
    if (state.isDenied && state.request != null) {
      final note = state.request!.note?.trim() ?? '';
      final wait = !state.canRetryAt(current);
      return (
        Icons.block_rounded,
        c.dangerSoft,
        c.dangerText,
        tr('Your request was turned down'),
        [
          if (note.isNotEmpty) tr('Their note: {note}', {'note': note}),
          if (wait) tr('You can ask again tomorrow.'),
        ].join('\n').ifEmpty,
      );
    }
    if (state.mode == CircleJoinMode.inviteOnly && !viaInvite) {
      return (
        Icons.mail_outline_rounded,
        c.raised,
        c.ink,
        tr('Invite only'),
        tr('Ask a member for an invite to join this circle.'),
      );
    }
    return (Icons.info_outline_rounded, c.raised, c.ink, null, null);
  }
}

extension on String {
  String? get ifEmpty => isEmpty ? null : this;
}
