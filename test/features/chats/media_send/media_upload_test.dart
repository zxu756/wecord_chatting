import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/media_send/media_upload.dart';
import 'package:wecord/features/chats/media_send/pending_media_store.dart';
import 'package:wecord/features/chats/media_send/pending_media_store_io.dart';

Stream<List<int>> _chunks(int total, {int size = 1000}) async* {
  for (var offset = 0; offset < total; offset += size) {
    final end = offset + size < total ? offset + size : total;
    yield Uint8List(end - offset);
  }
}

void main() {
  group('SupabaseChatMediaUploader', () {
    late SupabaseClient client;
    late http.BaseRequest seen;
    late List<int> body;

    setUp(() {
      client = SupabaseClient('http://localhost:54321', 'anon-key');
    });

    SupabaseChatMediaUploader uploader(
      Future<http.StreamedResponse> Function(
        http.BaseRequest request,
        List<int> body,
      )
      answer,
    ) {
      return SupabaseChatMediaUploader(
        client,
        anonKey: 'anon-key',
        clientFactory: () => MockClient.streaming((request, bodyStream) async {
          seen = request;
          body = [await for (final chunk in bodyStream) ...chunk];
          return answer(request, body);
        }),
      );
    }

    http.StreamedResponse reply(int status, [String text = '{}']) {
      return http.StreamedResponse(Stream.value(utf8.encode(text)), status);
    }

    test('streams the file to the bucket and counts it as it goes', () async {
      final progress = <double?>[];
      await uploader((_, _) async => reply(200)).upload(
        bucket: 'chat-images',
        path: 'conversation-1/client-1-My Photo.jpg',
        mimeType: 'image/jpeg',
        length: 3500,
        data: _chunks(3500),
        onProgress: progress.add,
      );

      expect(seen.method, 'POST');
      expect(
        seen.url.toString(),
        'http://localhost:54321/storage/v1/object/chat-images/'
        'conversation-1/client-1-My%20Photo.jpg',
      );
      expect(
        seen.headers['Content-Type'],
        startsWith('multipart/form-data; boundary='),
      );
      expect(seen.headers['x-upsert'], 'false');
      expect(seen.headers['apikey'], 'anon-key');
      expect(seen.headers['Authorization'], 'Bearer anon-key');
      // A cacheControl field, then the file as an unnamed part with its
      // type, as the Supabase client sends it.
      final boundary = seen.headers['Content-Type']!.split('boundary=').last;
      final text = latin1.decode(body);
      expect(text, startsWith('--$boundary\r\n'));
      expect(text, contains('name="cacheControl"\r\n\r\nmax-age=3600\r\n'));
      expect(text, contains('content-type: image/jpeg\r\n'));
      expect(
        text,
        contains(
          'content-disposition: form-data; name=""; filename=""\r\n\r\n',
        ),
      );
      expect(text, endsWith('\r\n--$boundary--\r\n'));
      // The announced length is the body's: the file plus the form around it.
      expect(seen.contentLength, body.length);
      expect(body.length, greaterThan(3500));
      expect(body.length, lessThan(3500 + 400));
      // 0, then a quarter at a time (never "done" before the answer), then 1.
      expect(progress.first, 0);
      expect(progress, containsAllInOrder([0.0, closeTo(0.2857, 0.001)]));
      expect(progress.last, 1);
      expect(
        progress.where((p) => p != null && p < 1).every((p) => p! <= 0.99),
        isTrue,
      );
      expect(
        progress,
        orderedEquals([...progress]..sort((a, b) => a!.compareTo(b!))),
      );
    });

    test('an object that is already there counts as uploaded', () async {
      await uploader(
        (_, _) async => reply(
          409,
          '{"statusCode":"409","error":"Duplicate","message":"The resource already exists"}',
        ),
      ).upload(
        bucket: 'chat-files',
        path: 'c/x.mp4',
        mimeType: 'video/mp4',
        length: 10,
        data: _chunks(10),
      );
    });

    test('a refusal says why and is not retried', () async {
      await expectLater(
        uploader(
          (_, _) async => reply(
            413,
            '{"statusCode":"413","error":"Payload too large","message":"The object exceeded the maximum allowed size"}',
          ),
        ).upload(
          bucket: 'chat-files',
          path: 'c/x.mp4',
          mimeType: 'video/mp4',
          length: 10,
          data: _chunks(10),
        ),
        throwsA(
          isA<UploadException>()
              .having((e) => e.statusCode, 'status', 413)
              .having((e) => e.isRefusal, 'refusal', isTrue)
              .having((e) => e.message, 'message', contains('maximum')),
        ),
      );
    });

    test('server errors can be retried', () async {
      await expectLater(
        uploader((_, _) async => reply(503, 'busy')).upload(
          bucket: 'b',
          path: 'p',
          mimeType: 'x/y',
          length: 1,
          data: _chunks(1),
        ),
        throwsA(
          isA<UploadException>().having((e) => e.isRefusal, 'r', isFalse),
        ),
      );
    });

    test('network errors pass through', () async {
      await expectLater(
        uploader((_, _) async => throw http.ClientException('reset')).upload(
          bucket: 'b',
          path: 'p',
          mimeType: 'x/y',
          length: 1,
          data: _chunks(1),
        ),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('cancelling aborts the request', () async {
      final token = UploadCancelToken();
      final gate = Completer<void>();
      final cancelled = uploader((_, _) async {
        await gate.future;
        return reply(200);
      });
      var closed = false;
      final cancellable = SupabaseChatMediaUploader(
        client,
        anonKey: 'anon-key',
        clientFactory: () => _ClosableClient(
          MockClient.streaming((request, bodyStream) async {
            await bodyStream.drain<void>();
            await gate.future;
            return reply(200);
          }),
          onClose: () {
            closed = true;
            if (!gate.isCompleted) {
              gate.completeError(http.ClientException('closed'));
            }
          },
        ),
      );
      expect(cancelled, isNotNull);

      final upload = cancellable.upload(
        bucket: 'b',
        path: 'p',
        mimeType: 'x/y',
        length: 5,
        data: _chunks(5),
        cancel: token,
      );
      await pumpEventQueue();
      token.cancel();

      await expectLater(upload, throwsA(isA<UploadCancelledException>()));
      expect(closed, isTrue);
    });

    test('a cancelled upload never starts', () async {
      final token = UploadCancelToken()..cancel();
      await expectLater(
        uploader((_, _) async => reply(200)).upload(
          bucket: 'b',
          path: 'p',
          mimeType: 'x/y',
          length: 1,
          data: _chunks(1),
          cancel: token,
        ),
        throwsA(isA<UploadCancelledException>()),
      );
    });
  });

  group('pending media stores', () {
    Future<void> exercise(PendingMediaStore store) async {
      final length = await store.put(
        'client-1',
        Stream.fromIterable([
          [1, 2, 3],
          [4, 5],
        ]),
      );
      expect(length, 5);
      expect(await store.length('client-1'), 5);
      expect(await store.length('missing'), isNull);

      final read = <int>[
        await for (final chunk in store.openRead('client-1')) ...chunk,
      ];
      expect(read, [1, 2, 3, 4, 5]);

      await store.putPreview('client-1', Uint8List.fromList([9, 9]));
      expect(await store.readPreview('client-1'), [9, 9]);
      expect(await store.readPreview('missing'), isNull);
      expect(await store.clientIds(), {'client-1'});

      await store.delete('client-1');
      expect(await store.length('client-1'), isNull);
      expect(await store.readPreview('client-1'), isNull);
      expect(await store.clientIds(), isEmpty);
      // Deleting twice is fine.
      await store.delete('client-1');
    }

    test('the in-memory store keeps and gives back files', () async {
      final store = MemoryPendingMediaStore();
      expect(store.persistent, isFalse);
      await exercise(store);
    });

    test('the in-memory store reads back in chunks', () async {
      final store = MemoryPendingMediaStore();
      await store.put('c', Stream.value(Uint8List(200 * 1024)));
      final sizes = [
        await for (final chunk in store.openRead('c')) chunk.length,
      ];
      expect(sizes, [65536, 65536, 65536, 200 * 1024 - 3 * 65536]);
    });

    test('the file store keeps files on disk and lists them', () async {
      final directory = Directory.systemTemp.createTempSync('wecord_media_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final store = FilePendingMediaStore(
        () async => Directory('${directory.path}/outbox_media'),
      );
      expect(store.persistent, isTrue);
      await exercise(store);

      // A second store over the same folder (the app after a restart) finds
      // what the first kept.
      await store.put('client-2', Stream.value([7, 7, 7]));
      final restarted = FilePendingMediaStore(
        () async => Directory('${directory.path}/outbox_media'),
      );
      expect(await restarted.clientIds(), {'client-2'});
      expect(await restarted.length('client-2'), 3);
    });

    test('a half written file is not taken for a whole one', () async {
      final directory = Directory.systemTemp.createTempSync('wecord_media_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final store = FilePendingMediaStore(() async => directory);
      final failing = Stream<List<int>>.multi((controller) {
        controller.add([1, 2, 3]);
        controller.addError(const FileSystemException('disk full'));
        controller.close();
      });

      await expectLater(
        store.put('client-1', failing),
        throwsA(isA<FileSystemException>()),
      );

      expect(await store.length('client-1'), isNull);
      expect(await store.clientIds(), isEmpty);
    });
  });

  group('UploadProgressTracker', () {
    test('tells waiting, running and finished apart', () {
      final tracker = UploadProgressTracker();
      addTearDown(tracker.dispose);
      final progress = tracker.of('a');
      expect(progress.value.running, isFalse);

      tracker.report('a', 0.4);
      expect(progress.value.running, isTrue);
      expect(progress.value.value, 0.4);

      tracker.report('a', null);
      expect(progress.value.running, isTrue);
      expect(progress.value.value, isNull);

      tracker.finish('a');
      expect(progress.value.running, isFalse);
      tracker.forget('a');
    });
  });
}

class _ClosableClient extends http.BaseClient {
  _ClosableClient(this._inner, {required this.onClose});

  final http.Client _inner;
  final void Function() onClose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() {
    onClose();
    _inner.close();
  }
}
