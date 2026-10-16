import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Lets the sender stop an upload that is running.
class UploadCancelToken {
  final _listeners = <void Function()>[];
  var _cancelled = false;

  bool get isCancelled => _cancelled;

  /// Calls [listener] when the upload is cancelled (at once if it already
  /// was).
  void onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    final listeners = [..._listeners];
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }
}

/// The reader cancelled the upload.
class UploadCancelledException implements Exception {
  const UploadCancelledException();

  @override
  String toString() => 'Upload cancelled';
}

/// The storage server answered an upload with an error.
class UploadException implements Exception {
  const UploadException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  /// Sending the same file again cannot help: the server refused it (too
  /// big, not allowed) rather than failing to keep up.
  bool get isRefusal =>
      statusCode >= 400 &&
      statusCode < 500 &&
      statusCode != 408 &&
      statusCode != 429;

  @override
  String toString() =>
      tr('Could not upload the file ({code}).', {'code': statusCode});
}

/// Uploads one attachment to the storage buckets with progress and
/// cancelling. Storing the same path twice is not an error, so an upload
/// can be tried again after a lost answer.
abstract interface class ChatMediaUploader {
  /// Streams [data] ([length] bytes) to [bucket]/[path].
  ///
  /// [onProgress] gets 0..1 as bytes leave, or null when the platform cannot
  /// tell (the web). Throws [UploadCancelledException] after
  /// [cancel] fires, [UploadException] when the server refuses, and the
  /// network's own errors otherwise.
  Future<void> upload({
    required String bucket,
    required String path,
    required String mimeType,
    required int length,
    required Stream<List<int>> data,
    void Function(double? progress)? onProgress,
    UploadCancelToken? cancel,
  });
}

final chatMediaUploaderProvider = Provider<ChatMediaUploader>((ref) {
  try {
    final config = ref.watch(appConfigProvider);
    return SupabaseChatMediaUploader(
      ref.watch(supabaseClientProvider),
      anonKey: config?.supabaseAnonKey ?? '',
    );
  } on ProviderException {
    // Supabase is not set up (as in tests).
    return const _UnavailableUploader();
  }
});

class _UnavailableUploader implements ChatMediaUploader {
  const _UnavailableUploader();

  @override
  Future<void> upload({
    required String bucket,
    required String path,
    required String mimeType,
    required int length,
    required Stream<List<int>> data,
    void Function(double? progress)? onProgress,
    UploadCancelToken? cancel,
  }) {
    throw StateError('Uploads are not available');
  }
}

/// Talks to Supabase Storage's REST endpoint directly, so the body can be
/// streamed from disk (a 50 MB video is never held in memory) and counted
/// as it leaves.
class SupabaseChatMediaUploader implements ChatMediaUploader {
  SupabaseChatMediaUploader(
    this._client, {
    required this.anonKey,
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final SupabaseClient _client;
  final String anonKey;
  final http.Client Function() _clientFactory;

  @override
  Future<void> upload({
    required String bucket,
    required String path,
    required String mimeType,
    required int length,
    required Stream<List<int>> data,
    void Function(double? progress)? onProgress,
    UploadCancelToken? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) {
      throw const UploadCancelledException();
    }
    final client = _clientFactory();
    cancel?.onCancel(client.close);
    final token = _client.auth.currentSession?.accessToken ?? anonKey;
    final url = Uri.parse(
      '${_client.storage.url}/object/$bucket/'
      '${path.split('/').map(Uri.encodeComponent).join('/')}',
    );
    var sent = 0;
    // Browsers take the whole body before sending, so there is nothing
    // honest to count there.
    final counted = kIsWeb
        ? data
        : data.map((chunk) {
            sent += chunk.length;
            onProgress?.call(
              length <= 0 ? null : (sent / length).clamp(0, 0.99),
            );
            return chunk;
          });
    // The same multipart form the Supabase client's own uploadBinary sends
    // (a cacheControl field, then the file as a part with no name), only
    // written out here so the file can be streamed.
    final multipart = _MultipartBody(
      mimeType: mimeType,
      cacheControl: 'max-age=3600',
      length: length,
    );
    final request =
        _StreamedUploadRequest(
            'POST',
            url,
            multipart.wrap(counted),
            multipart.totalLength,
          )
          ..headers.addAll({
            'apikey': anonKey,
            'Authorization': 'Bearer $token',
            'Content-Type': multipart.contentType,
            'x-upsert': 'false',
          });
    onProgress?.call(kIsWeb ? null : 0);
    try {
      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        onProgress?.call(1);
        return;
      }
      final (status, message) = _errorOf(response);
      // The same object is already there: an earlier try got through.
      if (response.statusCode == 409 || status == 409) {
        onProgress?.call(1);
        return;
      }
      throw UploadException(status ?? response.statusCode, message);
    } on Object {
      if (cancel?.isCancelled ?? false) {
        throw const UploadCancelledException();
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  (int?, String) _errorOf(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map) {
        return (
          int.tryParse('${body['statusCode'] ?? ''}'),
          '${body['message'] ?? body['error'] ?? ''}',
        );
      }
    } on Object {
      // Not JSON.
    }
    return (null, response.body);
  }
}

/// The multipart/form-data body of an upload, in pieces: what comes before
/// the file's bytes, and what comes after.
class _MultipartBody {
  _MultipartBody({
    required String mimeType,
    required String cacheControl,
    required this.length,
  }) : boundary = 'wecord-${DateTime.now().microsecondsSinceEpoch}' {
    _prefix = utf8.encode(
      '--$boundary\r\n'
      'content-disposition: form-data; name="cacheControl"\r\n\r\n'
      '$cacheControl\r\n'
      '--$boundary\r\n'
      'content-type: $mimeType\r\n'
      'content-disposition: form-data; name=""; filename=""\r\n\r\n',
    );
    _suffix = utf8.encode('\r\n--$boundary--\r\n');
  }

  final String boundary;
  final int length;
  late final List<int> _prefix;
  late final List<int> _suffix;

  String get contentType => 'multipart/form-data; boundary=$boundary';

  int get totalLength => _prefix.length + length + _suffix.length;

  Stream<List<int>> wrap(Stream<List<int>> file) async* {
    yield _prefix;
    yield* file;
    yield _suffix;
  }
}

/// A request whose body is pulled from [_body] as the connection takes it,
/// so memory stays flat and the count follows the socket.
class _StreamedUploadRequest extends http.BaseRequest {
  _StreamedUploadRequest(super.method, super.url, this._body, int length) {
    contentLength = length;
  }

  final Stream<List<int>> _body;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body);
  }
}

/// How far each upload has got, for the progress rings in the chat.
///
/// A value of 0..1, or null for "running but cannot tell"; an upload that
/// has not started has no entry.
class UploadProgressTracker {
  final _values = <String, ValueNotifier<UploadProgress>>{};

  /// Listen to this for [clientId]'s upload.
  ValueListenable<UploadProgress> of(String clientId) {
    return _values.putIfAbsent(
      clientId,
      () => ValueNotifier(const UploadProgress.idle()),
    );
  }

  void report(String clientId, double? progress) {
    final notifier = _values.putIfAbsent(
      clientId,
      () => ValueNotifier(const UploadProgress.idle()),
    );
    notifier.value = UploadProgress.running(progress);
  }

  void finish(String clientId) {
    final notifier = _values[clientId];
    if (notifier != null) {
      notifier.value = const UploadProgress.idle();
    }
  }

  void forget(String clientId) {
    _values.remove(clientId)?.dispose();
  }

  void dispose() {
    for (final notifier in _values.values) {
      notifier.dispose();
    }
    _values.clear();
  }
}

/// One upload's state, see [UploadProgressTracker].
@immutable
class UploadProgress {
  const UploadProgress.idle() : running = false, value = null;
  const UploadProgress.running(this.value) : running = true;

  /// An upload is under way.
  final bool running;

  /// 0..1 while running, null when it cannot be told.
  final double? value;

  @override
  bool operator ==(Object other) =>
      other is UploadProgress &&
      other.running == running &&
      other.value == value;

  @override
  int get hashCode => Object.hash(running, value);
}

final uploadProgressTrackerProvider = Provider<UploadProgressTracker>((ref) {
  final tracker = UploadProgressTracker();
  ref.onDispose(tracker.dispose);
  return tracker;
});
