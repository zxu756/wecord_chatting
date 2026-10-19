import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// The private bucket the screenshots go to (migration 202610240640). Each
/// person writes only in their own folder, `<user id>/`.
const feedbackBucket = 'feedback-screenshots';

/// Sends feedback to the team.
abstract interface class FeedbackRepository {
  /// Sends [message] with the app's [platform] and [version] and, when given,
  /// a screenshot ([screenshot] is a JPEG). Nothing from the person's chats
  /// is ever attached. Throws when the server refuses (too many messages in
  /// an hour, say) and then no file is left behind.
  Future<void> submit({
    required String message,
    required String platform,
    required String version,
    Uint8List? screenshot,
  });
}

/// How the screenshot reaches Storage; tests swap in a fake.
abstract interface class FeedbackFiles {
  /// The signed-in person's id, the first part of every path.
  String? get userId;

  Future<void> upload(String path, Uint8List bytes);

  Future<void> remove(String path);
}

class SupabaseFeedbackFiles implements FeedbackFiles {
  const SupabaseFeedbackFiles(this._client);

  final SupabaseClient _client;

  @override
  String? get userId => _client.auth.currentUser?.id;

  @override
  Future<void> upload(String path, Uint8List bytes) async {
    await _client.storage
        .from(feedbackBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );
  }

  @override
  Future<void> remove(String path) async {
    await _client.storage.from(feedbackBucket).remove([path]);
  }
}

class SupabaseFeedbackRepository implements FeedbackRepository {
  SupabaseFeedbackRepository(this._rpc, this._files, {String Function()? newId})
    : _newId = newId ?? _randomUuid;

  final CircleRpc _rpc;
  final FeedbackFiles _files;
  final String Function() _newId;

  @override
  Future<void> submit({
    required String message,
    required String platform,
    required String version,
    Uint8List? screenshot,
  }) async {
    String? path;
    if (screenshot != null) {
      final userId = _files.userId;
      if (userId == null) {
        throw StateError('Sign in first.');
      }
      path = '$userId/${_newId()}.jpg';
      await _files.upload(path, screenshot);
    }
    try {
      await _rpc('submit_feedback', {
        'feedback_message': message.trim(),
        'client_platform': platform,
        'client_version': version,
        'screenshot_object_path': path,
      });
    } catch (_) {
      if (path != null) {
        // The feedback was not saved, so the file has no owner row: take it
        // back (best effort).
        try {
          await _files.remove(path);
        } catch (_) {}
      }
      rethrow;
    }
  }
}

final feedbackFilesProvider = Provider<FeedbackFiles>((ref) {
  try {
    return SupabaseFeedbackFiles(ref.watch(supabaseClientProvider));
  } on ProviderException {
    throw StateError('Supabase must be initialized first.');
  }
});

final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) {
  return SupabaseFeedbackRepository(
    ref.watch(circleRpcProvider),
    ref.watch(feedbackFilesProvider),
  );
});

/// A random version 4 UUID.
String _randomUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [
    for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
