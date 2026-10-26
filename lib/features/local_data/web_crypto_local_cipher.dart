import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:wecord/features/local_data/local_cipher.dart';

/// AES-256-GCM through the browser's WebCrypto, with a key the browser made
/// and will not hand out (`extractable: false`): this page's code can ask
/// the browser to encrypt and decrypt with it but can never read its bytes.
/// The key sits in the browser's IndexedDB next to the data it protects, so
/// this keeps the data unreadable to anything that reads the stored values
/// (a backup, a look in the developer tools, a script that copies the
/// database), not to scripts running on this site, a browser extension with
/// access to it, or someone who copies the whole browser profile.
class WebCryptoLocalCipher extends FramedLocalCipher {
  WebCryptoLocalCipher([this._databaseName = 'wecord_local_key']);

  static const _storeName = 'keys';
  static const _recordName = 'device';

  final String _databaseName;
  Future<web.CryptoKey>? _key;

  @override
  LocalProtection get protection => LocalProtection.browserKey;

  web.SubtleCrypto get _subtle => web.window.crypto.subtle;

  Future<web.IDBDatabase> _open() {
    final request = web.window.indexedDB.open(_databaseName, 1);
    request.onupgradeneeded = ((web.Event _) {
      final db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
    }).toJS;
    return _await(request).then((result) => result! as web.IDBDatabase);
  }

  static Future<JSAny?> _await(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.complete(request.result);
      }
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('IndexedDB: ${request.error?.message ?? 'error'}'),
        );
      }
    }).toJS;
    return completer.future;
  }

  Future<web.CryptoKey> _loadKey() async {
    final db = await _open();
    try {
      final existing = await _await(
        db
            .transaction(_storeName.toJS, 'readonly')
            .objectStore(_storeName)
            .get(_recordName.toJS),
      );
      if (existing != null && existing.isA<web.CryptoKey>()) {
        return existing as web.CryptoKey;
      }
      final algorithm = JSObject()
        ..['name'] = 'AES-GCM'.toJS
        ..['length'] = 256.toJS;
      final generated =
          (await _subtle
                  .generateKey(
                    algorithm,
                    false,
                    <JSString>['encrypt'.toJS, 'decrypt'.toJS].toJS,
                  )
                  .toDart)!
              as web.CryptoKey;
      // Stored only if no other tab got there first, in one transaction, so
      // two tabs never end up with different keys.
      final completer = Completer<web.CryptoKey>();
      final transaction = db.transaction(_storeName.toJS, 'readwrite');
      final store = transaction.objectStore(_storeName);
      web.CryptoKey chosen = generated;
      final read = store.get(_recordName.toJS);
      read.onsuccess = ((web.Event _) {
        final found = read.result;
        if (found != null && found.isA<web.CryptoKey>()) {
          chosen = found as web.CryptoKey;
        } else {
          store.put(generated, _recordName.toJS);
        }
      }).toJS;
      transaction.oncomplete = ((web.Event _) {
        if (!completer.isCompleted) {
          completer.complete(chosen);
        }
      }).toJS;
      transaction.onerror = ((web.Event _) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('IndexedDB: ${transaction.error?.message ?? 'error'}'),
          );
        }
      }).toJS;
      transaction.onabort = transaction.onerror;
      return await completer.future;
    } finally {
      db.close();
    }
  }

  Future<web.CryptoKey> get _secret {
    return _key ??= _loadKey().catchError((Object error) {
      _key = null;
      throw error;
    });
  }

  @override
  Future<void> ensureReady() async {
    await _secret;
  }

  JSObject _params(Uint8List nonce) {
    return JSObject()
      ..['name'] = 'AES-GCM'.toJS
      ..['iv'] = nonce.toJS
      ..['tagLength'] = 128.toJS;
  }

  @override
  Future<Uint8List> encryptRaw(Uint8List plain, Uint8List nonce) async {
    final result = await _subtle
        .encrypt(_params(nonce), await _secret, plain.toJS)
        .toDart;
    return (result! as JSArrayBuffer).toDart.asUint8List();
  }

  @override
  Future<Uint8List?> decryptRaw(Uint8List nonce, Uint8List cipherAndTag) async {
    try {
      final result = await _subtle
          .decrypt(_params(nonce), await _secret, cipherAndTag.toJS)
          .toDart;
      return (result! as JSArrayBuffer).toDart.asUint8List();
    } on Object {
      // The tag does not fit: another key, or the value was changed.
      return null;
    }
  }

  @override
  Future<void> destroyKey() async {
    _key = null;
    final db = await _open();
    try {
      await _await(
        db
            .transaction(_storeName.toJS, 'readwrite')
            .objectStore(_storeName)
            .delete(_recordName.toJS),
      );
    } finally {
      db.close();
    }
  }
}
