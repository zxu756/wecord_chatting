import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/privacy/option_picker.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The edit time limits a circle can set, in seconds; 0 is no limit.
const editWindowChoices = <int>[0, 900, 3600, 86400];

/// "No limit", "15 minutes", "1 hour" or "24 hours".
String editWindowLabel(int seconds) => switch (seconds) {
  900 => tr('15 minutes'),
  3600 => tr('1 hour'),
  86400 => tr('24 hours'),
  _ => tr('No limit'),
};

/// Reads and changes how long messages in a circle can be edited.
abstract interface class EditWindowRepository {
  /// The limit in seconds; 0 when there is none.
  Future<int> editWindow(String circleId);

  /// Sets the limit; 0 removes it.
  Future<void> setEditWindow(String circleId, int seconds);
}

class SupabaseEditWindowRepository implements EditWindowRepository {
  const SupabaseEditWindowRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<int> editWindow(String circleId) async {
    final row = await _client
        .from('circles')
        .select('edit_window_seconds')
        .eq('id', circleId)
        .maybeSingle();
    return (row?['edit_window_seconds'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> setEditWindow(String circleId, int seconds) async {
    await _client.rpc<void>(
      'set_circle_edit_window',
      params: {
        'target_circle_id': circleId,
        'seconds': seconds == 0 ? null : seconds,
      },
    );
  }
}

class _UninitializedEditWindowRepository implements EditWindowRepository {
  const _UninitializedEditWindowRepository();

  @override
  Future<int> editWindow(String circleId) async => 0;

  @override
  Future<void> setEditWindow(String circleId, int seconds) {
    throw StateError('Supabase must be initialized before changing limits.');
  }
}

final editWindowRepositoryProvider = Provider<EditWindowRepository>((ref) {
  try {
    return SupabaseEditWindowRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _UninitializedEditWindowRepository();
  }
});

/// A circle's edit time limit in seconds (0: none). A server without the
/// feature reads as no limit.
final circleEditWindowProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, circleId) async {
    try {
      return await ref.watch(editWindowRepositoryProvider).editWindow(circleId);
    } catch (_) {
      return 0;
    }
  },
);

/// Circle settings: "Edit time limit", for members who manage the circle.
/// After the limit, nobody in the circle can edit a message they sent
/// (deleting stays possible).
class CircleEditWindowSection extends ConsumerStatefulWidget {
  const CircleEditWindowSection({required this.circleId, super.key});

  final String circleId;

  @override
  ConsumerState<CircleEditWindowSection> createState() =>
      _CircleEditWindowSectionState();
}

class _CircleEditWindowSectionState
    extends ConsumerState<CircleEditWindowSection> {
  var _saving = false;

  Future<void> _pick(int current) async {
    if (_saving) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final picked = await showOptionPicker<int>(
      context,
      title: tr('Edit time limit'),
      selected: current,
      note: tr(
        'After this time, members can no longer edit a message they sent. Deleting stays possible. Earlier versions of an edited message stay visible to everyone in the chat.',
      ),
      options: [
        for (final seconds in editWindowChoices)
          PickerOption<int>(value: seconds, title: editWindowLabel(seconds)),
      ],
    );
    if (picked == null || picked == current || !mounted) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(editWindowRepositoryProvider)
          .setEditWindow(widget.circleId, picked);
      ref.invalidate(circleEditWindowProvider(widget.circleId));
      await ref.read(circleEditWindowProvider(widget.circleId).future);
    } on Object {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr("Couldn't save the time limit. Try again."))),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current =
        ref.watch(circleEditWindowProvider(widget.circleId)).value ?? 0;
    return SettingsGroup(
      key: const ValueKey('circle-edit-window-settings'),
      header: tr('Editing messages'),
      children: [
        SettingsRow(
          key: const ValueKey('circle-edit-window'),
          icon: Icons.history_toggle_off,
          tone: SettingsTone.warning,
          title: tr('Edit time limit'),
          subtitle: tr('How long members can edit what they sent'),
          value: editWindowLabel(current),
          onTap: _saving ? null : () => unawaited(_pick(current)),
        ),
      ],
    );
  }
}
