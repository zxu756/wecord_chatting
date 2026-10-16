import 'package:clock/clock.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/media_send/media_upload.dart';
import 'package:wecord/features/chats/media_send/outbox_media.dart';
import 'package:wecord/features/chats/offline/outbox.dart';
import 'package:wecord/features/circles/circle_moderation.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Why the server refused an attachment, in the words text sends use:
/// slowmode with the seconds left, AutoMod's reason, the circle rules, the
/// 50 MB limit, a timeout. Null when the reason is not known (the network
/// gave up, or the entry was kept from an earlier run).
///
/// [timedOutUntil] is when the sender's circle timeout ends, if they have
/// one: the server only says they may not send.
String? sendFailureReason(
  Object? error, {
  DateTime? timedOutUntil,
  DateTime? now,
}) {
  switch (error) {
    case null:
      return null;
    case SlowmodeException() ||
        SendRefusedException() ||
        ChatFileTooLargeException() ||
        PendingMediaMissingException():
      return error.toString();
    case UploadException(:final statusCode):
      return switch (statusCode) {
        413 => tr('Files can be up to 50 MB.'),
        401 || 403 => _noPermission(timedOutUntil, now),
        _ => error.toString(),
      };
    case PostgrestException(:final code) when code == '42501':
      return _noPermission(timedOutUntil, now);
    default:
      return null;
  }
}

String _noPermission(DateTime? timedOutUntil, DateTime? now) {
  final current = now ?? clock.now();
  if (timedOutUntil != null && timedOutUntil.isAfter(current)) {
    return tr(
      "You're timed out until {time}. "
      'You can read, but not send messages or react.',
      {'time': formatTimeoutEnd(timedOutUntil, now: current)},
    );
  }
  return tr("You don't have permission to send messages in this channel");
}

/// Whether sending the same attachment again could work. Network failures
/// can pass and slowmode ends; what the server refused outright (AutoMod,
/// the circle rules, a timeout, a file that is too big or gone) will be
/// refused again, so those are edited and sent anew rather than retried.
/// An entry kept from an earlier run (no error known) can be retried.
bool isRetryableFailure(Object? error) {
  if (error == null || error is SlowmodeException) {
    return true;
  }
  return !isSendRefusal(error);
}
