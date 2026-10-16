import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// Why an Office file has no converted preview.
enum OfficePreviewFailure {
  /// The server has no converter set up (`preview_not_configured`).
  notConfigured,

  /// The converter can't read this kind of file.
  unsupported,

  /// Anything else (network, conversion error); worth a retry.
  failed,
}

class OfficePreviewException implements Exception {
  const OfficePreviewException(this.failure, [this.detail]);

  final OfficePreviewFailure failure;
  final String? detail;

  @override
  String toString() => 'OfficePreviewException($failure, $detail)';
}

/// Where the viewer gets links to files.
abstract interface class FilePreviewService {
  /// A short-lived signed link to [file]. With [download], the server
  /// sends it as an attachment named after the file.
  Future<Uri> fileUrl(PreviewFile file, {bool download = false});

  /// A signed link to a PDF rendering of an Office file, converted on the
  /// server (the web has no Quick Look). Throws [OfficePreviewException].
  Future<Uri> officePdfUrl(PreviewFile file);
}

final filePreviewServiceProvider = Provider<FilePreviewService>((ref) {
  return SupabaseFilePreviewService(() => ref.read(supabaseClientProvider));
});

/// Signs Storage links (reusing each for 50 minutes, so the browser's HTTP
/// cache and Flutter's image cache see the same URL) and calls the
/// office-preview Edge Function.
class SupabaseFilePreviewService implements FilePreviewService {
  SupabaseFilePreviewService(this._client, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SupabaseClient Function() _client;
  final DateTime Function() _now;
  final _signed = <String, ({Uri url, DateTime expires})>{};
  final _office = <String, ({Uri url, DateTime expires})>{};

  static const _lifetime = Duration(hours: 1);
  static const _reuseFor = Duration(minutes: 50);

  @override
  Future<Uri> fileUrl(PreviewFile file, {bool download = false}) async {
    final cached = _signed[file.key];
    Uri url;
    if (cached != null && cached.expires.isAfter(_now())) {
      url = cached.url;
    } else {
      final signed = await _client().storage
          .from(file.bucket)
          .createSignedUrl(file.path, _lifetime.inSeconds)
          .timeout(const Duration(seconds: 20));
      url = Uri.parse(signed);
      _signed[file.key] = (url: url, expires: _now().add(_reuseFor));
    }
    if (!download) {
      return url;
    }
    return url.replace(
      queryParameters: {...url.queryParameters, 'download': file.name},
    );
  }

  @override
  Future<Uri> officePdfUrl(PreviewFile file) async {
    final messageId = file.messageId;
    if (messageId == null) {
      throw const OfficePreviewException(OfficePreviewFailure.unsupported);
    }
    final cached = _office[messageId];
    if (cached != null && cached.expires.isAfter(_now())) {
      return cached.url;
    }
    Object? data;
    try {
      final response = await _client().functions
          .invoke('office-preview', body: {'message_id': messageId})
          .timeout(const Duration(seconds: 150));
      data = response.data;
    } on FunctionException catch (error) {
      throw officePreviewExceptionFor(error.status, error.details);
    } on TimeoutException {
      throw const OfficePreviewException(OfficePreviewFailure.failed);
    }
    final url = data is Map ? data['url'] : null;
    if (url is! String) {
      throw const OfficePreviewException(OfficePreviewFailure.failed);
    }
    final parsed = Uri.parse(url);
    _office[messageId] = (url: parsed, expires: _now().add(_reuseFor));
    return parsed;
  }
}

/// Maps the office-preview function's error responses.
OfficePreviewException officePreviewExceptionFor(int status, Object? details) {
  final code = details is Map ? details['error'] : null;
  if (status == 503 || code == 'preview_not_configured') {
    return OfficePreviewException(
      OfficePreviewFailure.notConfigured,
      code is String ? code : null,
    );
  }
  if (status == 415 || code == 'unsupported_type') {
    return const OfficePreviewException(OfficePreviewFailure.unsupported);
  }
  return OfficePreviewException(
    OfficePreviewFailure.failed,
    code is String ? code : '$status',
  );
}
