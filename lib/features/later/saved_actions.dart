import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/later/saved_messages_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Whether the person has kept [targetId] as a [kind] (a Moment or a post).
bool isSavedTarget(WidgetRef ref, SavedKind kind, String targetId) {
  return ref.watch(
    savedTargetKeysProvider.select(
      (keys) => keys.contains('${kind.wire}:$targetId'),
    ),
  );
}

/// "Save for later" / "Remove from Saved" for a Moment or a circle post:
/// keeps it, or takes it off the list when it is already there. Says what
/// happened in a snack bar.
Future<void> toggleSavedTarget(
  BuildContext context,
  WidgetRef ref, {
  required SavedKind kind,
  required String targetId,
}) async {
  final repository = ref.read(savedMessagesRepositoryProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  void say(String text) =>
      messenger?.showSnackBar(SnackBar(content: Text(text)));
  try {
    var known = const <SavedMessage>[];
    try {
      known = await ref.read(savedMessagesProvider.future);
    } catch (_) {
      // Not loaded: treat it as not kept; the server keeps it once anyway.
    }
    final key = '${kind.wire}:$targetId';
    final existing = known.where((saved) => saved.targetKey == key);
    if (existing.isNotEmpty) {
      await repository.remove(existing.first.id);
      ref.invalidate(savedMessagesProvider);
      say(tr('Removed from Saved'));
      return;
    }
    await repository.saveItem(kind, targetId);
    ref.invalidate(savedMessagesProvider);
    say(tr('Saved for later'));
  } catch (_) {
    say(tr('Could not update Saved. Try again.'));
  }
}
