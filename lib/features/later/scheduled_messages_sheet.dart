import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/sheet_rows.dart';
import 'package:wecord/features/later/later_time.dart';
import 'package:wecord/features/later/scheduled_messages_repository.dart';
import 'package:wecord/features/later/when_sheet.dart';
import 'package:wecord/features/push/push_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens a conversation's scheduled messages. [onSent] runs after "Send
/// now" delivered one (the thread reloads).
Future<void> showScheduledMessagesSheet(
  BuildContext context, {
  required String conversationId,
  VoidCallback? onSent,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Scheduled messages'),
    detents: const [0.5, 0.9],
    builder: (context, scrollController) => ScheduledMessagesSheet(
      conversationId: conversationId,
      scrollController: scrollController,
      onSent: onSent,
    ),
  );
}

/// What the server refused, in words for the owner.
String scheduleErrorText(Object error) {
  if (error is PostgrestException) {
    if (error.code == '22023') {
      return tr('Pick a time in the future.');
    }
    if (error.code == '53400') {
      return tr('You have too many scheduled messages.');
    }
    if (error.code == '42501') {
      return tr("You can't send messages here.");
    }
    if (error.message.trim().isNotEmpty && error.code == 'P0001') {
      final slowmode = SlowmodeException.fromPostgrest(error);
      if (slowmode != null) {
        return slowmode.toString();
      }
    }
  }
  return tr('Something went wrong. Try again.');
}

/// A conversation's scheduled messages: change the time or text, send one
/// now, or delete it.
class ScheduledMessagesSheet extends ConsumerStatefulWidget {
  const ScheduledMessagesSheet({
    required this.conversationId,
    this.scrollController,
    this.onSent,
    super.key,
  });

  final String conversationId;
  final ScrollController? scrollController;
  final VoidCallback? onSent;

  @override
  ConsumerState<ScheduledMessagesSheet> createState() =>
      _ScheduledMessagesSheetState();
}

class _ScheduledMessagesSheetState
    extends ConsumerState<ScheduledMessagesSheet> {
  String? _busyId;
  String? _error;

  void _refresh() {
    ref.invalidate(scheduledMessagesProvider(widget.conversationId));
  }

  Future<void> _run(String id, Future<void> Function() action) async {
    setState(() {
      _busyId = id;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _error = scheduleErrorText(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
      _refresh();
    }
  }

  Future<void> _sendNow(ScheduledMessage message) {
    return _run(message.id, () async {
      final sentId = await ref
          .read(scheduledMessagesRepositoryProvider)
          .sendNow(message.id);
      unawaited(ref.read(pushRepositoryProvider).notifySent(sentId));
      widget.onSent?.call();
    });
  }

  Future<void> _delete(ScheduledMessage message) {
    return _run(
      message.id,
      () => ref.read(scheduledMessagesRepositoryProvider).delete(message.id),
    );
  }

  Future<void> _edit(ScheduledMessage message) async {
    final saved = await showWeCordSheet<bool>(
      context,
      title: tr('Edit scheduled message'),
      builder: (context, _) => ScheduledEditSheet(message: message),
    );
    if (saved == true) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final messages = ref.watch(
      scheduledMessagesProvider(widget.conversationId),
    );
    final localizations = MaterialLocalizations.of(context);
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final now = clock.now();

    return messages.when(
      loading: () => const SheetSpinner(),
      error: (error, stackTrace) => SheetNote(
        text: tr('Could not load scheduled messages.'),
        error: true,
      ),
      data: (items) {
        if (items.isEmpty) {
          return SheetNote(text: tr('No scheduled messages'));
        }
        return ListView(
          controller: widget.scrollController,
          shrinkWrap: widget.scrollController == null,
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    key: const ValueKey('scheduled-error'),
                    style: TextStyle(fontSize: 13.5, color: c.dangerText),
                  ),
                ),
              ),
            for (final message in items) ...[
              _ScheduledCard(
                message: message,
                when: describeWhen(
                  localizations,
                  message.sendAt.toLocal(),
                  now,
                  alwaysUse24HourFormat: use24,
                ),
                busy: _busyId == message.id,
                onEdit: () => unawaited(_edit(message)),
                onSendNow: () => unawaited(_sendNow(message)),
                onDelete: () => unawaited(_delete(message)),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _ScheduledCard extends StatelessWidget {
  const _ScheduledCard({
    required this.message,
    required this.when,
    required this.busy,
    required this.onEdit,
    required this.onSendNow,
    required this.onDelete,
  });

  final ScheduledMessage message;
  final String when;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onSendNow;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final failed = message.isFailed;
    return Container(
      key: ValueKey('scheduled-${message.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SettingsIconTile(
                icon: failed ? Icons.error_outline_rounded : Icons.schedule,
                tone: failed ? SettingsTone.danger : SettingsTone.accent,
                size: 30,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  failed ? tr('Not sent · {time}', {'time': when}) : when,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: failed ? c.dangerText : c.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            message.body,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, height: 1.4, color: c.ink),
          ),
          if (message.failureReason case final reason?) ...[
            const SizedBox(height: 6),
            Text(
              reason,
              style: TextStyle(fontSize: 13, height: 1.35, color: c.dangerText),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              WeCordButton(
                key: ValueKey('scheduled-edit-${message.id}'),
                label: tr('Edit'),
                icon: Icons.edit_outlined,
                size: WeCordButtonSize.small,
                variant: WeCordButtonVariant.secondary,
                onPressed: busy ? null : onEdit,
              ),
              const SizedBox(width: 8),
              WeCordButton(
                key: ValueKey('scheduled-send-${message.id}'),
                label: failed ? tr('Try again') : tr('Send now'),
                icon: Icons.send_rounded,
                size: WeCordButtonSize.small,
                loading: busy,
                onPressed: busy ? null : onSendNow,
              ),
              const Spacer(),
              WeCordIconButton(
                key: ValueKey('scheduled-delete-${message.id}'),
                icon: Icons.delete_outline_rounded,
                tooltip: tr('Delete scheduled message'),
                variant: WeCordButtonVariant.ghost,
                size: 36,
                onPressed: busy ? null : onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Changes a scheduled message's text and time.
class ScheduledEditSheet extends ConsumerStatefulWidget {
  const ScheduledEditSheet({
    required this.message,
    this.customPicker,
    super.key,
  });

  final ScheduledMessage message;

  /// Replaces the date and time pickers (tests).
  final Future<DateTime?> Function(BuildContext context, DateTime now)?
  customPicker;

  @override
  ConsumerState<ScheduledEditSheet> createState() => _ScheduledEditSheetState();
}

class _ScheduledEditSheetState extends ConsumerState<ScheduledEditSheet> {
  late final _controller = TextEditingController(text: widget.message.body);
  late DateTime _sendAt = widget.message.sendAt.toLocal();
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showWhenSheet(
      context,
      title: tr('Send at'),
      picks: schedulePicks,
      initial: _sendAt,
    );
    if (picked != null && mounted) {
      setState(() => _sendAt = picked);
    }
  }

  Future<void> _save() async {
    final body = _controller.text.trim();
    if (body.isEmpty) {
      setState(() => _error = tr('Write a message to schedule.'));
      return;
    }
    if (!isUsableFuture(_sendAt, clock.now())) {
      setState(() => _error = tr('Pick a time in the future.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(scheduledMessagesRepositoryProvider)
          .update(
            widget.message.id,
            body: body,
            sendAt: _sendAt,
            mentions: retainMentions(
              oldBody: widget.message.body,
              newBody: body,
              mentions: widget.message.mentions,
            ),
          );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = scheduleErrorText(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final localizations = MaterialLocalizations.of(context);
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + keyboard),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WeCordTextField(
              fieldKey: const ValueKey('scheduled-edit-field'),
              controller: _controller,
              label: tr('Message'),
              minLines: 2,
              maxLines: 6,
              inputFormatters: [LengthLimitingTextInputFormatter(4000)],
              keyboardType: TextInputType.multiline,
            ),
            const SizedBox(height: 14),
            SettingsGroup(
              color: c.well,
              children: [
                SettingsRow(
                  key: const ValueKey('scheduled-edit-time'),
                  icon: Icons.schedule,
                  tone: SettingsTone.accent,
                  title: tr('Send at'),
                  value: describeWhen(
                    localizations,
                    _sendAt,
                    clock.now(),
                    alwaysUse24HourFormat: use24,
                  ),
                  onTap: _pickTime,
                ),
              ],
            ),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    key: const ValueKey('scheduled-edit-error'),
                    style: TextStyle(fontSize: 13.5, color: c.dangerText),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            WeCordButton(
              key: const ValueKey('scheduled-edit-save'),
              label: tr('Save'),
              size: WeCordButtonSize.large,
              expand: true,
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// The strip above the composer: how many messages wait, and when the
/// next goes out. Tapping opens the list. Nothing when there are none.
class ScheduledMessagesBanner extends ConsumerWidget {
  const ScheduledMessagesBanner({
    required this.conversationId,
    required this.onOpen,
    super.key,
  });

  final String conversationId;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(scheduledMessagesProvider(conversationId)).value;
    if (items == null || items.isEmpty) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final failed = items.where((message) => message.isFailed).length;
    final pending = items.length - failed;
    final localizations = MaterialLocalizations.of(context);
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final next = items.where((message) => !message.isFailed).firstOrNull;
    final summary = [
      if (pending > 0)
        pending == 1
            ? tr('1 scheduled message')
            : tr('{count} scheduled messages', {'count': pending}),
      if (failed > 0)
        failed == 1
            ? tr('1 not sent')
            : tr('{count} not sent', {'count': failed}),
    ].join(' · ');
    final nextText = next == null
        ? null
        : tr('Next: {time}', {
            'time': describeWhen(
              localizations,
              next.sendAt.toLocal(),
              clock.now(),
              alwaysUse24HourFormat: use24,
            ),
          });
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: WeCordGlass(
        key: const ValueKey('scheduled-banner'),
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
        padding: EdgeInsets.zero,
        child: WeCordPressable(
          onPressed: onOpen,
          hint: tr('Opens the scheduled messages'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WeCordRadii.xl),
          ),
          builder: (context, states) => Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: failed > 0 ? c.dangerSoft : c.accentSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    failed > 0 ? Icons.error_outline_rounded : Icons.schedule,
                    size: 16,
                    color: failed > 0 ? c.dangerText : c.accentText,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: c.ink,
                          ),
                        ),
                        if (nextText != null)
                          Text(
                            nextText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: c.muted),
                          ),
                      ],
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 20, color: c.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
