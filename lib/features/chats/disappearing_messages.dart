import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/privacy/option_picker.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The timers a conversation can have, in seconds; null is off.
const disappearingChoices = <int?>[null, 86400, 604800, 7776000];

/// "Off", "24 hours", "7 days" or "90 days".
String disappearingLabel(int? seconds) => switch (seconds) {
  null || 0 => tr('Off'),
  86400 => tr('24 hours'),
  604800 => tr('7 days'),
  7776000 => tr('90 days'),
  _ => tr('{count} days', {'count': (seconds / 86400).round()}),
};

/// The timer in one or two characters, for the small mark on a message:
/// "24h", "7d", "90d".
String disappearingShortLabel(int? seconds) => switch (seconds) {
  null || 0 => '',
  86400 => tr('24h'),
  604800 => tr('7d'),
  7776000 => tr('90d'),
  _ => tr('{count}d', {'count': (seconds / 86400).round()}),
};

/// What a disappearing message shows under it: "Disappears in 5h".
String disappearsInLabel(DateTime expiresAt, {DateTime? now}) {
  final left = expiresAt.difference((now ?? DateTime.now()).toUtc());
  if (left.inMinutes < 1) {
    return tr('Disappearing now');
  }
  if (left.inHours < 1) {
    return tr('Disappears in {count}m', {'count': left.inMinutes});
  }
  if (left.inDays < 1) {
    return tr('Disappears in {count}h', {'count': left.inHours});
  }
  return tr('Disappears in {count}d', {'count': left.inDays});
}

/// The line the chat shows when someone changed the timer, in the
/// reader's language ([actorName] is whoever did it).
String disappearingNoticeText(int seconds, String actorName) {
  return switch (seconds) {
    0 => tr('{name} turned off disappearing messages.', {'name': actorName}),
    _ => tr('{name} set messages to disappear after {time}.', {
      'name': actorName,
      'time': disappearingLabel(seconds),
    }),
  };
}

/// Reads and changes a conversation's disappearing-messages timer.
abstract interface class DisappearingRepository {
  /// The timer in seconds; null when messages stay.
  Future<int?> timer(String conversationId);

  /// Sets the timer; null turns it off.
  Future<void> setTimer(String conversationId, int? seconds);
}

class SupabaseDisappearingRepository implements DisappearingRepository {
  const SupabaseDisappearingRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<int?> timer(String conversationId) async {
    final row = await _client
        .from('conversations')
        .select('disappear_after_seconds')
        .eq('id', conversationId)
        .maybeSingle();
    return (row?['disappear_after_seconds'] as num?)?.toInt();
  }

  @override
  Future<void> setTimer(String conversationId, int? seconds) async {
    await _client.rpc<void>(
      'set_disappearing_messages',
      params: {'target_conversation_id': conversationId, 'seconds': seconds},
    );
  }
}

class _UninitializedDisappearingRepository implements DisappearingRepository {
  const _UninitializedDisappearingRepository();

  @override
  Future<int?> timer(String conversationId) async => null;

  @override
  Future<void> setTimer(String conversationId, int? seconds) {
    throw StateError('Supabase must be initialized before changing timers.');
  }
}

final disappearingRepositoryProvider = Provider<DisappearingRepository>((ref) {
  try {
    return SupabaseDisappearingRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _UninitializedDisappearingRepository();
  }
});

/// A conversation's timer in seconds (null: off). A server without the
/// feature reads as off.
final disappearingSecondsProvider = FutureProvider.autoDispose
    .family<int?, String>((ref, conversationId) async {
      try {
        return await ref
            .watch(disappearingRepositoryProvider)
            .timer(conversationId);
      } catch (_) {
        return null;
      }
    });

/// The timer sheet: Off / 24 hours / 7 days / 90 days. [canChange] is false
/// for group members who are not admins, who only read it.
Future<void> showDisappearingSheet(
  BuildContext context, {
  required String conversationId,
  required bool isGroup,
  required bool canChange,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Disappearing messages'),
    builder: (context, _) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: DisappearingPicker(
          conversationId: conversationId,
          isGroup: isGroup,
          canChange: canChange,
        ),
      ),
    ),
  );
}

class DisappearingPicker extends ConsumerStatefulWidget {
  const DisappearingPicker({
    required this.conversationId,
    required this.isGroup,
    required this.canChange,
    super.key,
  });

  final String conversationId;
  final bool isGroup;
  final bool canChange;

  @override
  ConsumerState<DisappearingPicker> createState() => _DisappearingPickerState();
}

class _DisappearingPickerState extends ConsumerState<DisappearingPicker> {
  /// The choice just made, shown until the server has it.
  ({int? value})? _pending;
  var _saving = false;
  String? _error;

  Future<void> _choose(int? seconds) async {
    if (_saving) {
      return;
    }
    setState(() {
      _pending = (value: seconds);
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(disappearingRepositoryProvider)
          .setTimer(widget.conversationId, seconds);
      ref.invalidate(disappearingSecondsProvider(widget.conversationId));
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _pending = null;
          _saving = false;
          _error = couldNotSaveText();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final current =
        _pending?.value ??
        ref.watch(disappearingSecondsProvider(widget.conversationId)).value;
    final note = widget.canChange
        ? (widget.isGroup
              ? tr(
                  'New messages in this group will be deleted for everyone after this time. Earlier messages stay.',
                )
              : tr(
                  'New messages in this chat will be deleted for both of you after this time. Earlier messages stay.',
                ))
        : tr('Only the owner and admins can change this.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        OptionPickerBody<int?>(
          enabled: widget.canChange && !_saving,
          selected: current,
          note:
              '$note\n${tr('Anyone in the chat can still copy or screenshot a message before it goes.')}',
          onPick: (value) => unawaited(_choose(value)),
          options: [
            for (final seconds in disappearingChoices)
              PickerOption<int?>(
                value: seconds,
                title: disappearingLabel(seconds),
              ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _error!,
              key: const ValueKey('disappearing-error'),
              style: TextStyle(fontSize: 13, color: c.dangerText),
            ),
          ),
      ],
    );
  }
}

/// The small timer mark after a disappearing message: "⏱ 24h".
class DisappearingMark extends StatelessWidget {
  const DisappearingMark({required this.expiresAt, this.color, super.key});

  final DateTime expiresAt;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final tint = color ?? c.subtle;
    final label = disappearsInLabel(expiresAt);
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Row(
          key: const ValueKey('disappearing-mark'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 12, color: tint),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: tint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
