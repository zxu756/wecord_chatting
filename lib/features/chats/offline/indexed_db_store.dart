import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;
import 'package:wecord/features/chats/offline/chat_cache.dart';

/// The web's offline cache: string values in an IndexedDB object store.
class IndexedDbKeyValueStore implements KeyValueStore {
  IndexedDbKeyValueStore._(this._db);

  static const _storeName = 'kv';

  static Future<IndexedDbKeyValueStore> open(String name) async {
    final request = web.window.indexedDB.open(name, 1);
    request.onupgradeneeded = ((web.Event _) {
      final db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
    }).toJS;
    final result = await _complete(request);
    return IndexedDbKeyValueStore._(result as web.IDBDatabase);
  }

  final web.IDBDatabase _db;

  web.IDBObjectStore _store(String mode) {
    return _db.transaction(_storeName.toJS, mode).objectStore(_storeName);
  }

  static Future<JSAny?> _complete(web.IDBRequest request) {
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

  @override
  Future<String?> read(String key) async {
    final value = await _complete(_store('readonly').get(key.toJS));
    return value.isA<JSString>() ? (value as JSString).toDart : null;
  }

  @override
  Future<void> write(String key, String value) async {
    await _complete(_store('readwrite').put(value.toJS, key.toJS));
  }

  @override
  Future<void> delete(String key) async {
    await _complete(_store('readwrite').delete(key.toJS));
  }

  @override
  Future<List<String>> keys() async {
    final value = await _complete(_store('readonly').getAllKeys());
    if (!value.isA<JSArray>()) {
      return const [];
    }
    return [
      for (final key in (value as JSArray<JSAny?>).toDart)
        if (key.isA<JSString>()) (key as JSString).toDart,
    ];
  }

  @override
  Future<void> clear() async {
    await _complete(_store('readwrite').clear());
  }
}
