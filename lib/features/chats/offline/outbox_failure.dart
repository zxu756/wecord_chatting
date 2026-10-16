import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/media_send/media_upload.dart';
import 'package:wecord/features/chats/media_send/outbox_media.dart';

/// Writes why a send failed as JSON, to keep with its outbox entry across
/// an app restart. Only the refusals whose reason the reader should see
/// again are kept (slowmode, AutoMod, the circle rules, a missing
/// permission, a file too big or gone, a refused upload); a network error
/// is nothing worth remembering, and sending again is the way on.
Map<String, dynamic>? outboxFailureToJson(Object? error) {
  return switch (error) {
    SlowmodeException(:final remainingSeconds) => {
      'kind': 'slowmode',
      'seconds': remainingSeconds,
    },
    AutoModBlockedException(:final reason) => {
      'kind': 'automod',
      'reason': ?reason,
    },
    CircleRulesNotAcceptedException() => {'kind': 'rules'},
    ChatFileTooLargeException() => {'kind': 'too_large'},
    PendingMediaMissingException() => {'kind': 'missing'},
    UploadException(:final statusCode, :final message) => {
      'kind': 'upload',
      'status': statusCode,
      'message': message,
    },
    PostgrestException(:final code, :final message) when code == '42501' => {
      'kind': 'permission',
      'message': message,
    },
    _ => null,
  };
}

/// The error [outboxFailureToJson] wrote, or null when there is none (or it
/// is not understood, as after a downgrade).
Object? outboxFailureFromJson(Object? json) {
  if (json is! Map) {
    return null;
  }
  switch (json['kind']) {
    case 'slowmode':
      return SlowmodeException((json['seconds'] as num?)?.toInt() ?? 0);
    case 'automod':
      return AutoModBlockedException(json['reason'] as String?);
    case 'rules':
      return const CircleRulesNotAcceptedException();
    case 'too_large':
      return const ChatFileTooLargeException();
    case 'missing':
      return PendingMediaMissingException();
    case 'upload':
      return UploadException(
        (json['status'] as num?)?.toInt() ?? 400,
        json['message'] as String? ?? '',
      );
    case 'permission':
      return PostgrestException(
        message: json['message'] as String? ?? 'permission denied',
        code: '42501',
      );
  }
  return null;
}
