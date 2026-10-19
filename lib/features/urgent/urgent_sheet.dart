import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/sheet_rows.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/urgent/urgent_models.dart';
import 'package:wecord/features/urgent/urgent_repository.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Most people one message can be made urgent for at a time (the server's
/// limit too).
const maxUrgentPeople = 10;

/// Opens "Urgent": the sender picks who must see this message. Whoever it was
/// made urgent for before is listed with whether they confirmed.
Future<void> showUrgentSheet(BuildContext context, ChatMessage message) {
  return showWeCordSheet<void>(
    context,
    title: tr('Urgent message'),
    detents: const [0.6, 0.92],
    builder: (context, scrollController) =>
        UrgentSheet(message: message, scrollController: scrollController),
  );
}

/// Words for a refused call.
String urgentProblemText(Object error) {
  final problem = error is UrgentException
      ? error.problem
      : UrgentProblem.other;
  return switch (problem) {
    UrgentProblem.rateLimited => tr(
      'You can make 5 messages urgent in 24 hours. Try again later.',
    ),
    UrgentProblem.nobodyToUrgent => tr(
      'Nobody to notify. They may have been notified already, or turned off urgent messages from you.',
    ),
    UrgentProblem.tooManyPeople => tr('Pick up to {count} people.', {
      'count': maxUrgentPeople,
    }),
    UrgentProblem.unavailable => tr('This message can not be made urgent.'),
    _ => tr('Something went wrong. Try again.'),
  };
}

/// The content of the urgent sheet.
class UrgentSheet extends ConsumerStatefulWidget {
  const UrgentSheet({required this.message, this.scrollController, super.key});

  final ChatMessage message;
  final ScrollController? scrollController;

  @override
  ConsumerState<UrgentSheet> createState() => _UrgentSheetState();
}

class _UrgentSheetState extends ConsumerState<UrgentSheet> {
  final _picked = <String>{};
  var _sending = false;
  String? _error;

  String get _messageId => widget.message.id;

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final told = await ref
          .read(urgentRepositoryProvider)
          .sendUrgent(_messageId, _picked.toList());
      ref
        ..invalidate(urgentRecipientsProvider(_messageId))
        ..invalidate(urgentQuotaProvider);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            told == 1
                ? tr('Made urgent for 1 person')
                : tr('Made urgent for {count} people', {'count': told}),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = urgentProblemText(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final members = ref.watch(
      conversationMembersProvider(widget.message.conversationId),
    );
    final before =
        ref.watch(urgentRecipientsProvider(_messageId)).value ??
        const <UrgentRecipient>[];
    final quota =
        ref.watch(urgentQuotaProvider).value ?? const UrgentQuota.unknown();
    final already = {for (final person in before) person.userId};
    final bottom = MediaQuery.paddingOf(context).bottom;

    return members.when(
      loading: () => const SheetSpinner(),
      error: (error, stackTrace) =>
          SheetNote(text: tr('Could not load the members.'), error: true),
      data: (all) {
        final candidates = [
          for (final member in all)
            if (member.profile.id != widget.message.senderId &&
                !already.contains(member.profile.id))
              member,
        ];
        final out = quota.remaining == 0;
        return Column(
          children: [
            Expanded(
              child: ListView(
                controller: widget.scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                    child: Text(
                      tr(
                        'They get a notification that gets through quiet hours and mutes, and a red banner until they confirm. If they do not confirm within 10 minutes, they are notified once more.',
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: c.muted,
                      ),
                    ),
                  ),
                  if (before.isNotEmpty) ...[
                    _Heading(tr('Already urgent')),
                    for (final person in before)
                      SheetListRow(
                        key: ValueKey('urgent-before-${person.userId}'),
                        leading: ProfileAvatar(
                          name: person.name,
                          avatarUrl: person.avatarUrl,
                          size: 40,
                        ),
                        title: person.name,
                        trailing: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            person.confirmed ? tr('Confirmed') : tr('Waiting'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: person.confirmed ? c.successText : c.muted,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                  _Heading(tr('Choose who must see this')),
                  if (candidates.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 14,
                      ),
                      child: Text(
                        tr('There is nobody else to notify.'),
                        style: TextStyle(fontSize: 14, color: c.subtle),
                      ),
                    ),
                  for (final member in candidates)
                    _PersonRow(
                      member: member,
                      selected: _picked.contains(member.profile.id),
                      enabled:
                          _picked.contains(member.profile.id) ||
                          _picked.length < maxUrgentPeople,
                      onTap: () => setState(() {
                        final id = member.profile.id;
                        if (!_picked.remove(id)) {
                          _picked.add(id);
                        }
                      }),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12 + bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error case final error?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          error,
                          key: const ValueKey('urgent-error'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13.5, color: c.dangerText),
                        ),
                      ),
                    ),
                  WeCordButton(
                    key: const ValueKey('urgent-send'),
                    label: _picked.isEmpty
                        ? tr('Make urgent')
                        : tr('Make urgent for {count}', {
                            'count': _picked.length,
                          }),
                    icon: Icons.priority_high_rounded,
                    expand: true,
                    loading: _sending,
                    onPressed: _picked.isEmpty || _sending || out
                        ? null
                        : () => unawaited(_send()),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    out
                        ? tr(
                            'You used all {allowed} urgent messages of the last 24 hours.',
                            {'allowed': quota.allowed},
                          )
                        : tr('{remaining} of {allowed} left in 24 hours', {
                            'remaining': quota.remaining,
                            'allowed': quota.allowed,
                          }),
                    key: const ValueKey('urgent-quota'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: c.subtle),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: c.muted,
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.member,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final GroupMember member;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final name = member.profile.displayLabel;
    return Semantics(
      selected: selected,
      child: SheetListRow(
        key: ValueKey('urgent-person-${member.profile.id}'),
        leading: ProfileAvatar(
          name: name,
          avatarUrl: member.profile.avatarUrl,
          size: 40,
        ),
        title: name,
        enabled: enabled,
        onTap: onTap,
        trailing: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 22,
            color: selected ? c.accent : c.faint,
          ),
        ),
      ),
    );
  }
}
