import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/read_status/read_status_models.dart';
import 'package:wecord/features/chats/read_status/read_status_repository.dart';
import 'package:wecord/features/chats/sheet_rows.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The sheet is two columns (Read, Unread) from this width, a switch between
/// the two below it.
const readStatusColumnsWidth = 560.0;

/// Opens the read list of [message]: who has read it, who has not, and the
/// button that reminds the ones who have not. Only the sender gets here.
Future<void> showReadStatusSheet(BuildContext context, ChatMessage message) {
  return showWeCordSheet<void>(
    context,
    title: tr('Message info'),
    builder: (context, _) => ReadStatusView(message: message),
  );
}

/// The content of the read list sheet.
class ReadStatusView extends ConsumerStatefulWidget {
  const ReadStatusView({required this.message, super.key});

  final ChatMessage message;

  @override
  ConsumerState<ReadStatusView> createState() => _ReadStatusViewState();
}

class _ReadStatusViewState extends ConsumerState<ReadStatusView> {
  var _showUnread = false;
  var _reminding = false;
  var _reminded = false;

  String get _id => widget.message.id;

  Future<void> _remind() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _reminding = true);
    try {
      await ref.read(readStatusRepositoryProvider).remind(_id);
      if (!mounted) {
        return;
      }
      setState(() => _reminded = true);
      ref.invalidate(readReminderSentProvider(_id));
      messenger?.showSnackBar(SnackBar(content: Text(tr('Reminder sent'))));
    } on ReadStatusException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _reminded = error.problem == ReadStatusProblem.alreadyReminded;
      });
      messenger?.showSnackBar(
        SnackBar(content: Text(_remindProblemText(error.problem))),
      );
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not send the reminder. Try again.'))),
      );
    } finally {
      if (mounted) {
        setState(() => _reminding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(messageReadStatusProvider(_id));
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: list.when(
          loading: () => const SheetSpinner(),
          error: (error, stackTrace) => _Problem(
            problem: error is ReadStatusException
                ? error.problem
                : ReadStatusProblem.other,
            onRetry: () => ref.invalidate(messageReadStatusProvider(_id)),
          ),
          data: _content,
        ),
      ),
    );
  }

  Widget _content(ReadList list) {
    final c = context.tokens.colors;
    final sent =
        _reminded || (ref.watch(readReminderSentProvider(_id)).value ?? false);
    final wide = MediaQuery.sizeOf(context).width >= readStatusColumnsWidth;
    final canRemind = list.unread.isNotEmpty && !sent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            children: [
              if (list.read.isEmpty &&
                  list.unread.isEmpty &&
                  list.unknown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    tr('Nobody else is in this group yet.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14.5, color: c.muted),
                  ),
                )
              else if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _Column(
                        key: const ValueKey('read-status-read'),
                        title: tr('Read'),
                        members: list.read,
                        empty: tr('Nobody has read this yet.'),
                        state: ReadState.read,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Column(
                        key: const ValueKey('read-status-unread'),
                        title: tr('Unread'),
                        members: list.unread,
                        empty: tr('Everyone has read this.'),
                        state: ReadState.unread,
                      ),
                    ),
                  ],
                )
              else ...[
                WeCordSegmented<bool>(
                  semanticLabel: tr('Message info'),
                  expand: true,
                  selected: _showUnread,
                  onChanged: (value) => setState(() => _showUnread = value),
                  segments: [
                    WeCordSegment(
                      key: const ValueKey('read-status-tab-read'),
                      value: false,
                      label: '${tr('Read')} ${list.read.length}',
                    ),
                    WeCordSegment(
                      key: const ValueKey('read-status-tab-unread'),
                      value: true,
                      label: '${tr('Unread')} ${list.unread.length}',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_showUnread)
                  _Column(
                    key: const ValueKey('read-status-unread'),
                    members: list.unread,
                    empty: tr('Everyone has read this.'),
                    state: ReadState.unread,
                  )
                else
                  _Column(
                    key: const ValueKey('read-status-read'),
                    members: list.read,
                    empty: tr('Nobody has read this yet.'),
                    state: ReadState.read,
                  ),
              ],
              if (list.unknown.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Column(
                  key: const ValueKey('read-status-unknown'),
                  title: tr('Unknown'),
                  note: tr('They turned off read receipts.'),
                  members: list.unknown,
                  empty: '',
                  state: ReadState.unknown,
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WeCordButton(
                key: const ValueKey('read-status-remind'),
                label: sent ? tr('Reminder sent') : tr('Remind unread'),
                icon: sent
                    ? Icons.check_rounded
                    : Icons.notifications_active_outlined,
                expand: true,
                loading: _reminding,
                onPressed: canRemind ? () => unawaited(_remind()) : null,
              ),
              const SizedBox(height: 8),
              Text(
                sent
                    ? tr('You can remind once for each message.')
                    : tr(
                        'Sends a reminder to the people who have not read this. You can do it once for each message.',
                      ),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: c.subtle),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _remindProblemText(ReadStatusProblem problem) => switch (problem) {
  ReadStatusProblem.alreadyReminded => tr(
    'You already reminded about this message.',
  ),
  ReadStatusProblem.nobodyToRemind => tr('Nobody needs a reminder.'),
  ReadStatusProblem.rateLimited => tr(
    'You have sent many reminders today. Try again tomorrow.',
  ),
  ReadStatusProblem.receiptsOff => tr(
    'Turn on read receipts in Settings to use this.',
  ),
  _ => tr('Could not send the reminder. Try again.'),
};

/// Why there is no list, in the sheet's place.
class _Problem extends StatelessWidget {
  const _Problem({required this.problem, required this.onRetry});

  final ReadStatusProblem problem;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = switch (problem) {
      ReadStatusProblem.receiptsOff => tr(
        'Read receipts are off. Turn them on in Settings → Privacy & Safety to see who has read your messages.',
      ),
      ReadStatusProblem.unavailable => tr(
        'There is no read list for this message.',
      ),
      _ => tr('Could not load who has read this.'),
    };
    final retry = problem == ReadStatusProblem.other;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetNote(
          key: const ValueKey('read-status-problem'),
          text: text,
          error: retry,
        ),
        if (retry)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: WeCordButton(
              key: const ValueKey('read-status-retry'),
              label: tr('Retry'),
              variant: WeCordButtonVariant.secondary,
              onPressed: onRetry,
            ),
          ),
      ],
    );
  }
}

/// One list of members under a heading.
class _Column extends StatelessWidget {
  const _Column({
    required this.members,
    required this.empty,
    required this.state,
    this.title,
    this.note,
    super.key,
  });

  final String? title;
  final String? note;
  final List<MemberReadStatus> members;
  final String empty;
  final ReadState state;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final title = this.title;
    final note = this.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            child: Semantics(
              header: true,
              child: Text(
                '$title · ${members.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: c.muted,
                ),
              ),
            ),
          ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text(
              note,
              style: TextStyle(fontSize: 12.5, color: c.subtle),
            ),
          ),
        if (members.isEmpty && empty.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
            child: Text(
              empty,
              style: TextStyle(fontSize: 13.5, color: c.subtle),
            ),
          ),
        for (final member in members)
          SheetListRow(
            key: ValueKey('read-status-member-${member.userId}'),
            leading: ProfileAvatar(
              name: member.name,
              avatarUrl: member.avatarUrl,
              size: 40,
            ),
            title: member.name,
            trailing: state == ReadState.read
                ? Icon(Icons.done_all_rounded, size: 18, color: c.accent)
                : null,
          ),
      ],
    );
  }
}
