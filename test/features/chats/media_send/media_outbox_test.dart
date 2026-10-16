import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/media_send/media_outbox.dart';
import 'package:wecord/features/chats/media_send/media_tray_controller.dart';
import 'package:wecord/features/chats/media_send/media_upload.dart';
import 'package:wecord/features/chats/media_send/outbox_media.dart';
import 'package:wecord/features/chats/media_send/pending_media_store.dart';
import 'package:wecord/features/chats/media_send/send_failure.dart';
import 'package:wecord/features/chats/message_history.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/chats/offline/connectivity.dart';
import 'package:wecord/features/chats/offline/outbox.dart';
import 'package:wecord/features/chats/offline/outbox_provider.dart';
import 'package:wecord/shared/models/message.dart';

import 'media_fakes.dart';

Future<OutboxEntry> _queued(
  MemoryPendingMediaStore store,
  String clientId, {
  OutboxMediaKind kind = OutboxMediaKind.image,
  String fileName = 'Photo 1.JPG',
  String mimeType = 'image/jpeg',
  int bytes = 200 * 1024,
  String? groupId,
  int groupIndex = 0,
  String caption = '',
}) async {
  final size = await store.put(clientId, Stream.value(Uint8List(bytes)));
  return OutboxEntry(
    clientId: clientId,
    conversationId: 'conversation-1',
    body: caption,
    createdAt: DateTime.utc(2026, 10, 17, 9),
    media: OutboxMedia(
      kind: kind,
      fileName: fileName,
      mimeType: mimeType,
      size: size,
      width: 800,
      height: 600,
      blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
      groupId: groupId,
      groupIndex: groupIndex,
    ),
  );
}

void main() {
  late MemoryPendingMediaStore store;
  late FakeChatMediaUploader uploader;
  late FakeMediaMessageSender sender;
  late UploadProgressTracker progress;
  late MediaSendPipeline pipeline;

  /// The queue the pipeline looks at to see whether more of an album waits.
  OutboxEngine? activeQueue;

  bool albumHasWaiting(OutboxEntry entry) {
    final queue = activeQueue;
    final groupId = entry.media?.groupId;
    if (queue == null || groupId == null) {
      return false;
    }
    return queue.entries.any(
      (other) =>
          other.clientId != entry.clientId &&
          other.media?.groupId == groupId &&
          other.state == OutboxState.sending,
    );
  }

  setUp(() {
    activeQueue = null;
    store = MemoryPendingMediaStore();
    uploader = FakeChatMediaUploader();
    sender = FakeMediaMessageSender();
    progress = UploadProgressTracker();
    pipeline = MediaSendPipeline(
      store: store,
      uploader: uploader,
      sender: sender,
      progress: progress,
      albumHasWaiting: albumHasWaiting,
    );
  });

  tearDown(() => progress.dispose());

  group('storage paths', () {
    test('are the same on every try and safe', () {
      String path(String name) => mediaStoragePath(
        conversationId: 'conv',
        clientId: 'abc',
        fileName: name,
      );
      expect(path('Photo 1.JPG'), 'conv/abc-photo-1.jpg');
      expect(path('Photo 1.JPG'), path('Photo 1.JPG'));
      expect(path('../../etc/passwd'), 'conv/abc-passwd');
      expect(path('   '), 'conv/abc-file');
      expect(path('日本語.png'), 'conv/abc-file.png');
      expect(path('Report (final).v2.PDF'), 'conv/abc-report-final-v2.pdf');
      final long = path('${'a' * 200}.mp4');
      expect(long.endsWith('.mp4'), isTrue);
      expect(long.length, lessThan('conv/abc-'.length + 81));
    });
  });

  group('sending one attachment', () {
    test('uploads the bytes, then stores the message', () async {
      final entry = await _queued(
        store,
        'client-1',
        groupId: 'group-1',
        groupIndex: 0,
        caption: 'Look at this',
      );
      final reported = <double?>[];
      progress.of('client-1').addListener(() {
        reported.add(progress.of('client-1').value.value);
      });

      final id = await pipeline.send(entry);

      expect(id, 'message-1');
      expect(uploader.uploads.single.bucket, 'chat-images');
      expect(
        uploader.uploads.single.path,
        'conversation-1/client-1-photo-1.jpg',
      );
      expect(uploader.uploads.single.length, 200 * 1024);
      final call = sender.calls.single;
      expect(call['type'], MessageType.image);
      expect(call['body'], 'Look at this');
      expect(call['group'], 'group-1');
      expect(call['notify'], isTrue);
      final attachment = call['attachment']! as Map<String, dynamic>;
      expect(attachment['path'], 'conversation-1/client-1-photo-1.jpg');
      expect(attachment['width'], 800);
      expect(attachment['blurhash'], 'LEHV6nWB2yk8pyo0adR*.7kCMdnj');
      // Rings saw 0, the steps of the upload, then it went quiet.
      expect(reported, containsAllInOrder([0.0, 1.0]));
      expect(progress.of('client-1').value.running, isFalse);
    });

    test(
      'videos and files go to chat-files, an album item with more to come stays quiet',
      () async {
        final video = await _queued(
          store,
          'client-2',
          kind: OutboxMediaKind.video,
          fileName: 'Clip.MOV',
          mimeType: 'video/quicktime',
          groupId: 'group-1',
          groupIndex: 1,
        );
        final queue = OutboxEngine(send: pipeline.send);
        activeQueue = queue;
        queue.enqueue(video);
        queue.enqueue(await _queued(store, 'client-3', groupId: 'group-1'));
        await pipeline.send(video);
        queue.dispose();
        expect(uploader.uploads.single.bucket, 'chat-files');
        final call = sender.calls.single;
        expect(call['type'], MessageType.file);
        expect(
          call['notify'],
          isFalse,
          reason: 'the last item of an album notifies',
        );
        final attachment = call['attachment']! as Map<String, dynamic>;
        expect(attachment['kind'], 'video');
        expect(attachment['name'], 'Clip.MOV');
      },
    );

    test(
      'a failed insert is retried without sending the bytes again',
      () async {
        final entry = await _queued(store, 'client-1');
        sender.failures.add(http.ClientException('offline'));

        await expectLater(
          pipeline.send(entry),
          throwsA(isA<http.ClientException>()),
        );
        expect(uploader.uploads, hasLength(1));

        await pipeline.send(entry);
        expect(uploader.uploads, hasLength(1), reason: 'already uploaded');
        expect(sender.calls, hasLength(1));
      },
    );

    test('a file that is gone is a refusal, not a retry', () async {
      final entry = await _queued(store, 'client-1');
      await store.delete('client-1');
      await expectLater(pipeline.send(entry), throwsStateError);
      expect(isSendRefusal(StateError('x')), isTrue);
      expect(uploader.uploads, isEmpty);
    });

    test('cancelling aborts the upload', () async {
      final entry = await _queued(store, 'client-1');
      uploader.hold = Completer<void>();

      final sending = pipeline.send(entry);
      sending.ignore();
      await pumpEventQueue();
      expect(progress.of('client-1').value.running, isTrue);
      pipeline.cancel('client-1');

      await expectLater(sending, throwsA(isA<UploadCancelledException>()));
      expect(sender.calls, isEmpty);
      expect(progress.of('client-1').value.running, isFalse);
    });
  });

  group('the queue', () {
    OutboxEngine engine({
      int maxAttempts = 3,
      DateTime Function()? clock,
      void Function(List<OutboxEntry>)? onChanged,
    }) {
      return activeQueue = OutboxEngine(
        send: pipeline.send,
        maxAttempts: maxAttempts,
        baseDelay: const Duration(seconds: 1),
        maxDelay: const Duration(seconds: 8),
        clock: clock,
        random: math.Random(1),
        onChanged: onChanged,
      );
    }

    test('an upload that fails on the network is tried again on its own', () {
      fakeAsync((async) {
        final queue = engine(
          clock: () => async.getClock(DateTime.utc(2026)).now(),
        );
        uploader.failures.addAll([
          http.ClientException('connection reset'),
          TimeoutException('stalled'),
        ]);
        unawaited(
          _queued(store, 'client-1').then((entry) {
            queue.enqueue(entry);
            unawaited(queue.sendNow('client-1'));
          }),
        );
        async.flushMicrotasks();
        expect(queue.entries.single.attempts, 1);
        expect(queue.entries.single.state, OutboxState.sending);

        async.elapse(const Duration(seconds: 1, milliseconds: 400));
        async.flushMicrotasks();
        expect(uploader.uploads, hasLength(2));
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        expect(uploader.uploads, hasLength(3));
        expect(queue.entries, isEmpty, reason: 'stored on the third try');
        expect(sender.calls, hasLength(1));
        // Every try wrote to the same place.
        expect(uploader.uploads.map((u) => u.path).toSet(), hasLength(1));
        queue.dispose();
      });
    });

    test(
      'after the last try it shows as failed, and tapping retries it',
      () async {
        final queue = engine(maxAttempts: 1);
        uploader.failures.add(http.ClientException('offline'));
        queue.enqueue(await _queued(store, 'client-1'));

        final result = await queue.sendNow('client-1');
        expect((result as OutboxWillRetry).gaveUp, isTrue);
        expect(queue.entries.single.state, OutboxState.failed);

        final retried = await queue.retry('client-1');
        expect(retried, isA<OutboxSent>());
        expect(queue.entries, isEmpty);
        queue.dispose();
      },
    );

    test('the server refusing a file is not retried', () async {
      final queue = engine();
      uploader.failures.add(const UploadException(413, 'Payload too large'));
      queue.enqueue(await _queued(store, 'client-1'));

      final result = await queue.sendNow('client-1');

      expect(result, isA<OutboxRefused>());
      expect(queue.entries.single.state, OutboxState.failed);
      expect(uploader.uploads, hasLength(1));
      queue.dispose();
    });

    test('server trouble and timeouts count as retryable', () {
      expect(const UploadException(503, 'busy').isRefusal, isFalse);
      expect(const UploadException(429, 'slow down').isRefusal, isFalse);
      expect(const UploadException(408, 'timeout').isRefusal, isFalse);
      expect(const UploadException(403, 'no').isRefusal, isTrue);
      expect(isSendRefusal(const UploadCancelledException()), isTrue);
    });

    test('an album goes up in order, one file at a time', () async {
      final queue = engine();
      for (final (index, id) in ['a', 'b', 'c'].indexed) {
        queue.enqueue(
          await _queued(
            store,
            id,
            fileName: '$id.jpg',
            groupId: 'group-1',
            groupIndex: index,
          ),
        );
      }

      await queue.drain();

      expect(uploader.uploads.map((u) => u.path), [
        'conversation-1/a-a.jpg',
        'conversation-1/b-b.jpg',
        'conversation-1/c-c.jpg',
      ]);
      // One push for the album, once all of it is stored.
      expect(sender.calls.map((c) => c['notify']), [false, false, true]);
      expect(sender.notified, isEmpty);
      expect(sender.calls.map((c) => c['group']).toSet(), {'group-1'});
      expect(queue.entries, isEmpty);
      queue.dispose();
    });

    test('a refused last item still sends the push for the rest', () async {
      final queue = engine();
      for (final (index, id) in ['a', 'b', 'c'].indexed) {
        queue.enqueue(
          await _queued(
            store,
            id,
            fileName: '$id.jpg',
            groupId: 'group-1',
            groupIndex: index,
          ),
        );
      }
      // Two uploads go through, the third is refused.
      var uploads = 0;
      uploader.beforeUpload = () {
        uploads += 1;
        if (uploads == 3) {
          throw const UploadException(403, 'not allowed');
        }
      };

      await queue.drain();

      expect(sender.calls.map((c) => c['notify']), [false, false]);
      expect(sender.notified, ['message-2']);
      expect(queue.entries.single.state, OutboxState.failed);
      queue.dispose();
    });

    test('a refused middle item leaves the push to the last one', () async {
      final queue = engine();
      for (final (index, id) in ['a', 'b', 'c'].indexed) {
        queue.enqueue(
          await _queued(
            store,
            id,
            fileName: '$id.jpg',
            groupId: 'group-1',
            groupIndex: index,
          ),
        );
      }
      var uploads = 0;
      uploader.beforeUpload = () {
        uploads += 1;
        if (uploads == 2) {
          throw const UploadException(403, 'not allowed');
        }
      };

      await queue.drain();

      expect(sender.calls.map((c) => c['notify']), [false, true]);
      expect(sender.notified, isEmpty);
      queue.dispose();
    });

    test('entries with media survive as JSON', () async {
      final entry = await _queued(
        store,
        'client-1',
        kind: OutboxMediaKind.video,
        groupId: 'g',
        groupIndex: 2,
        caption: 'hi',
      );
      final copy = OutboxEntry.fromJson(entry.toJson());
      expect(copy.media!.kind, OutboxMediaKind.video);
      expect(copy.media!.groupId, 'g');
      expect(copy.media!.groupIndex, 2);
      expect(copy.media!.size, 200 * 1024);
      expect(copy.media!.blurhash, 'LEHV6nWB2yk8pyo0adR*.7kCMdnj');
      expect(copy.body, 'hi');
      final pending = copy.toPendingMessage('me');
      expect(pending.type, MessageType.file);
      expect(pending.attachmentGroupId, 'g');
      expect(pending.id, pendingMessageIdFor('client-1'));
    });
  });

  group('the outbox provider', () {
    late KeyValueChatCache cache;
    late FakeMediaMessageSender providerSender;
    late FakeChatMediaUploader providerUploader;
    late MemoryPendingMediaStore providerStore;

    ProviderContainer container({bool online = true}) {
      final created = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(_Auth()),
          chatsRepositoryProvider.overrideWithValue(
            _Repository(providerSender),
          ),
          chatCacheProvider.overrideWithValue(cache),
          pendingMediaStoreProvider.overrideWithValue(providerStore),
          chatMediaUploaderProvider.overrideWithValue(providerUploader),
          deviceConnectivityProvider.overrideWith(
            (ref) => Stream<bool>.value(online),
          ),
        ],
      );
      addTearDown(created.dispose);
      // The app keeps the outbox listened to (offlineSessionGuardProvider);
      // Riverpod 3 pauses it, and its connection listener, otherwise.
      created.listen(outboxProvider, (previous, next) {});
      return created;
    }

    setUp(() {
      cache = KeyValueChatCache.memory();
      providerSender = FakeMediaMessageSender();
      providerUploader = FakeChatMediaUploader();
      providerStore = MemoryPendingMediaStore(persistent: true);
    });

    MediaToQueue item(String name, {OutboxMediaKind? kind}) => MediaToQueue(
      kind: kind ?? OutboxMediaKind.image,
      fileName: name,
      mimeType: 'image/jpeg',
      data: () => Stream.value(Uint8List.fromList([1, 2, 3, 4])),
      width: 400,
      height: 300,
      preview: Uint8List.fromList([9, 9]),
    );

    test(
      'several attachments share an album and the caption is the first\'s',
      () async {
        final c = container();
        c.read(outboxProvider);
        final outbox = c.read(outboxProvider.notifier);

        final entries = await outbox.enqueueMedia(
          conversationId: 'conversation-1',
          items: [item('a.jpg'), item('b.jpg'), item('c.jpg')],
          caption: 'Trip',
        );

        expect(entries, hasLength(3));
        expect(entries.map((e) => e.body), ['Trip', '', '']);
        final groups = entries.map((e) => e.media!.groupId).toSet();
        expect(groups, hasLength(1));
        expect(groups.single, isNotNull);
        expect(entries.map((e) => e.media!.groupIndex), [0, 1, 2]);
        expect(c.read(outboxProvider), hasLength(3));
        expect(
          await providerStore.readPreview(entries.first.clientId),
          isNotNull,
        );

        await outbox.startSending();

        expect(providerUploader.uploads, hasLength(3));
        expect(providerSender.calls.map((call) => call['body']), [
          'Trip',
          '',
          '',
        ]);
        expect(c.read(outboxProvider), isEmpty);
        // The files were let go once stored.
        await pumpEventQueue();
        expect(await providerStore.clientIds(), isEmpty);
      },
    );

    test('a single attachment is not an album', () async {
      final c = container();
      c.read(outboxProvider);
      final entries = await c
          .read(outboxProvider.notifier)
          .enqueueMedia(
            conversationId: 'conversation-1',
            items: [item('a.jpg')],
          );
      expect(entries.single.media!.groupId, isNull);
    });

    test('offline attachments wait and are sent after a restart', () async {
      final offline = container(online: false);
      offline.read(outboxProvider);
      await pumpEventQueue();
      await offline
          .read(outboxProvider.notifier)
          .enqueueMedia(
            conversationId: 'conversation-1',
            items: [item('a.jpg'), item('b.jpg')],
          );
      await offline.read(outboxProvider.notifier).startSending();
      await pumpEventQueue();
      expect(providerUploader.uploads, isEmpty);
      expect(await cache.readOutbox('user-1'), hasLength(2));
      offline.dispose();

      // The app starts again, online: what was queued goes out.
      final restarted = container();
      restarted.read(outboxProvider);
      await pumpEventQueue(times: 40);

      expect(providerUploader.uploads, hasLength(2));
      expect(providerSender.calls, hasLength(2));
      expect(restarted.read(outboxProvider), isEmpty);
      expect(await cache.readOutbox('user-1'), isEmpty);
    });

    test('attachments whose file is gone are dropped on restart', () async {
      final first = container(online: false);
      first.read(outboxProvider);
      await pumpEventQueue();
      final entries = await first
          .read(outboxProvider.notifier)
          .enqueueMedia(
            conversationId: 'conversation-1',
            items: [item('a.jpg')],
          );
      await pumpEventQueue();
      first.dispose();
      await providerStore.delete(entries.single.clientId);

      final restarted = container(online: false);
      restarted.read(outboxProvider);
      await pumpEventQueue(times: 40);
      expect(restarted.read(outboxProvider), isEmpty);
    });

    test(
      'a store that does not outlive the app keeps no attachments',
      () async {
        providerStore = MemoryPendingMediaStore();
        final c = container(online: false);
        c.read(outboxProvider);
        await pumpEventQueue();
        await c
            .read(outboxProvider.notifier)
            .enqueueMedia(
              conversationId: 'conversation-1',
              items: [item('a.jpg')],
            );
        await pumpEventQueue();
        expect(c.read(outboxProvider), hasLength(1));
        expect(await cache.readOutbox('user-1'), isEmpty);
      },
    );

    test('a failed album keeps its reason after a restart', () async {
      final first = container();
      first.read(outboxProvider);
      await pumpEventQueue();
      providerUploader.failures.addAll([
        const UploadException(413, 'too big'),
        const UploadException(413, 'too big'),
      ]);
      final outbox = first.read(outboxProvider.notifier);
      await outbox.enqueueMedia(
        conversationId: 'conversation-1',
        items: [item('a.jpg'), item('b.jpg')],
      );
      await outbox.startSending();
      await pumpEventQueue();
      expect(
        first.read(outboxProvider).map((e) => e.state),
        everyElement(OutboxState.failed),
      );
      first.dispose();

      final restarted = container();
      restarted.read(outboxProvider);
      await pumpEventQueue(times: 40);

      final entries = restarted.read(outboxProvider);
      expect(entries, hasLength(2));
      expect(entries.map((e) => e.state), everyElement(OutboxState.failed));
      expect(entries.map((e) => e.error), everyElement(isA<UploadException>()));
      expect(
        sendFailureReason(entries.first.error),
        'Files can be up to 50 MB.',
      );
      expect(isRetryableFailure(entries.first.error), isFalse);
      // Nothing was sent again on its own.
      expect(providerSender.calls, isEmpty);
    });

    test(
      'Edit and resend gives back the originals, posters and quality',
      () async {
        final c = container();
        c.read(outboxProvider);
        await pumpEventQueue();
        final outbox = c.read(outboxProvider.notifier);
        providerUploader.failures.addAll([
          const UploadException(413, 'too big'),
          const UploadException(413, 'too big'),
        ]);
        final chosen = testJpeg(40, 30);
        final poster = testJpeg(16, 9);
        final entries = await outbox.enqueueMedia(
          conversationId: 'conversation-1',
          caption: 'Trip',
          items: [
            MediaToQueue(
              kind: OutboxMediaKind.image,
              fileName: 'IMG_0001-scaled.jpg',
              mimeType: 'image/jpeg',
              // What was prepared for upload is not what was chosen.
              data: () => Stream.value(Uint8List.fromList([1, 2, 3])),
              width: 40,
              height: 30,
              original: () => Stream.value(chosen),
              originalFileName: 'IMG_0001.jpg',
              originalMimeType: 'image/jpeg',
              originalQuality: true,
            ),
            MediaToQueue(
              kind: OutboxMediaKind.video,
              fileName: 'clip.mp4',
              mimeType: 'video/mp4',
              data: () => Stream.value(Uint8List.fromList([4, 5, 6])),
              preview: poster,
              originalQuality: true,
            ),
          ],
        );
        await pumpEventQueue();
        // Kept while the album waits in the outbox.
        expect(await providerStore.hasOriginal(entries.first.clientId), isTrue);

        await outbox.startSending();
        await pumpEventQueue();
        expect(
          c.read(outboxProvider).map((e) => e.state),
          everyElement(OutboxState.failed),
        );
        expect(await providerStore.hasOriginal(entries.first.clientId), isTrue);

        // The open chat keeps its tray listened to.
        c.listen(mediaTrayProvider('conversation-1'), (previous, next) {});
        await outbox.editAndResendMedia(entries.first);
        await pumpEventQueue(times: 40);

        final tray = c.read(mediaTrayProvider('conversation-1'));
        expect(tray.items.map((item) => item.name), [
          'IMG_0001.jpg',
          'clip.mp4',
        ]);
        expect(await tray.items.first.file.length(), chosen.length);
        expect(tray.items.last.thumbnail, poster);
        expect(tray.original, isTrue);
        expect(tray.caption, 'Trip');
        // Out of the chat, and the kept files were let go.
        expect(c.read(outboxProvider), isEmpty);
        expect(
          await providerStore.hasOriginal(entries.first.clientId),
          isFalse,
        );
        expect(await providerStore.clientIds(), isEmpty);
      },
    );

    test('the originals go when the album is sent', () async {
      final c = container();
      c.read(outboxProvider);
      await pumpEventQueue();
      final outbox = c.read(outboxProvider.notifier);
      final entries = await outbox.enqueueMedia(
        conversationId: 'conversation-1',
        items: [
          MediaToQueue(
            kind: OutboxMediaKind.image,
            fileName: 'a.jpg',
            mimeType: 'image/jpeg',
            data: () => Stream.value(Uint8List.fromList([1])),
            original: () => Stream.value(Uint8List.fromList([2, 2])),
            originalFileName: 'a.heic',
            originalMimeType: 'image/heic',
          ),
        ],
      );
      expect(await providerStore.hasOriginal(entries.single.clientId), isTrue);
      await outbox.startSending();
      await pumpEventQueue();
      expect(c.read(outboxProvider), isEmpty);
      expect(await providerStore.hasOriginal(entries.single.clientId), isFalse);
    });

    test('cancelling one attachment of an album drops only that one', () async {
      final c = container(online: false);
      c.read(outboxProvider);
      await pumpEventQueue();
      final outbox = c.read(outboxProvider.notifier);
      final entries = await outbox.enqueueMedia(
        conversationId: 'conversation-1',
        items: [item('a.jpg'), item('b.jpg')],
      );

      outbox.cancelMedia(entries.first.clientId);
      await pumpEventQueue();

      expect(c.read(outboxProvider).map((e) => e.clientId), [
        entries.last.clientId,
      ]);
      expect(await providerStore.length(entries.first.clientId), isNull);
      expect(await providerStore.length(entries.last.clientId), isNotNull);
    });

    test('failed attachments of an album are retried together', () async {
      final c = container();
      c.read(outboxProvider);
      await pumpEventQueue();
      final outbox = c.read(outboxProvider.notifier);
      providerUploader.failures.addAll([
        const UploadException(413, 'too big'),
        const UploadException(413, 'too big'),
      ]);
      final entries = await outbox.enqueueMedia(
        conversationId: 'conversation-1',
        items: [item('a.jpg'), item('b.jpg')],
      );
      await outbox.startSending();
      await pumpEventQueue();
      expect(
        c.read(outboxProvider).map((e) => e.state),
        everyElement(OutboxState.failed),
      );

      await outbox.retryMedia(entries.first);

      expect(c.read(outboxProvider), isEmpty);
      expect(providerSender.calls, hasLength(2));
    });
  });
}

class _Auth implements AuthRepository {
  @override
  AuthUser? get currentUser => const AuthUser(id: 'user-1');

  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(currentUser);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// A repository that only takes part in the outbox.
class _Repository
    implements ChatsRepository, OutboxMessageSender, MediaMessageSender {
  _Repository(this._media);

  final MediaMessageSender _media;

  @override
  Future<void> notifyMessageSent(String messageId) =>
      _media.notifyMessageSent(messageId);

  @override
  Future<String?> sendQueuedMediaMessage({
    required String conversationId,
    required String clientId,
    required MessageType type,
    required Map<String, dynamic> attachment,
    String body = '',
    String? attachmentGroupId,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
    bool notify = true,
  }) {
    return _media.sendQueuedMediaMessage(
      conversationId: conversationId,
      clientId: clientId,
      type: type,
      attachment: attachment,
      body: body,
      attachmentGroupId: attachmentGroupId,
      replyToMessageId: replyToMessageId,
      replyPreview: replyPreview,
      notify: notify,
    );
  }

  @override
  Future<String?> sendQueuedTextMessage({
    required String conversationId,
    required String clientId,
    required String body,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
    List<MessageMention> mentions = const [],
  }) async => 'text-1';

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
