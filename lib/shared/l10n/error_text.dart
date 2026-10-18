import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException, StorageException;
import 'package:wecord/shared/l10n/l10n.dart';

/// What to tell the reader about [error], in the current language.
///
/// For failures nothing closer to the action has put into words: the server's
/// own messages (their English is the key in `lib/shared/l10n/zh/`), a
/// dropped connection, a bad state. Errors that already read well, because
/// they carry a [tr]-ed message of their own, pass through unchanged.
///
/// A Postgres or storage error with no Chinese wording says so plainly rather
/// than showing English (or a stack of codes) to a Chinese reader.
String errorText(Object error) {
  if (error is TimeoutException || _isNetworkFailure(error)) {
    return tr('Check your connection and try again.');
  }
  final message = switch (error) {
    AuthException(:final message) => message,
    PostgrestException(:final message) => message,
    StorageException(:final message) => message,
    StateError(:final message) => message,
    UnsupportedError(:final message) => message ?? '',
    _ => _withoutExceptionPrefix(error.toString()),
  };
  final translated = tr(message);
  final fromServer = error is PostgrestException || error is StorageException;
  if (fromServer &&
      AppStrings.isChinese &&
      translated == message &&
      !_staysAsIs(message)) {
    return tr('Something went wrong. Try again.');
  }
  return translated;
}

String _withoutExceptionPrefix(String text) {
  const prefix = 'Exception: ';
  return text.startsWith(prefix) ? text.substring(prefix.length) : text;
}

/// Failures whose class names tell a lost connection, without importing
/// `dart:io` (which the web build does not have).
bool _isNetworkFailure(Object error) {
  final name = error.runtimeType.toString();
  if (name == 'SocketException' || name == 'HandshakeException') {
    return true;
  }
  if (name == 'ClientException' || name == '_ClientSocketException') {
    return true;
  }
  return false;
}

/// Messages with no letters to translate (a bare code, say).
bool _staysAsIs(String message) => !RegExp(r'[A-Za-z]{2}').hasMatch(message);
