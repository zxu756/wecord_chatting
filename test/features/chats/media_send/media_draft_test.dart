import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/media_send/media_draft.dart';
import 'package:wecord/features/chats/media_send/media_prepare.dart';
import 'package:wecord/features/chats/media_send/outbox_media.dart';

import 'media_fakes.dart';

XFile _file(String name, String mime, {int length = 3, Uint8List? bytes}) {
  return XFile.fromData(
    bytes ?? Uint8List.fromList(List.filled(length < 3 ? length : 3, 1)),
    name: name,
    path: name,
    mimeType: mime,
    length: length,
  );
}

void main() {
  group('buildDraft', () {
    testWidgets('a photo gets its shape and a thumbnail', (tester) async {
      await tester.runAsync(() async {
        final draft = await buildDraft(
          testPhoto('Beach.JPG', width: 64, height: 32),
        );
        expect(draft.kind, DraftKind.image);
        expect(draft.mimeType, 'image/jpeg');
        expect(draft.width, 64);
        expect(draft.height, 32);
        expect(draft.thumbnail, isNotNull);
        expect(draft.overLimit, isFalse);
      });
    });

    testWidgets('a video gets the poster frame the reader makes', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final poster = testJpeg(48, 27);
        final draft = await buildDraft(
          _file('Clip.MOV', '', length: 5000),
          videoPoster: (file) async => poster,
        );
        expect(draft.kind, DraftKind.video);
        expect(draft.mimeType, 'video/quicktime');
        expect(draft.thumbnail, isNotNull);
        expect(draft.width, 48);
        expect(draft.height, 27);
      });
    });

    testWidgets('a video whose poster cannot be made is still a video', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final draft = await buildDraft(
          _file('Clip.mp4', 'video/mp4'),
          videoPoster: (file) async => throw StateError('no frame'),
        );
        expect(draft.kind, DraftKind.video);
        expect(draft.thumbnail, isNull);
      });
    });

    testWidgets('a file over 50 MB is flagged and never read', (tester) async {
      await tester.runAsync(() async {
        var posterAsked = false;
        final draft = await buildDraft(
          _file('Movie.mp4', 'video/mp4', length: maxChatFileBytes + 1),
          videoPoster: (file) async {
            posterAsked = true;
            return null;
          },
        );
        expect(draft.overLimit, isTrue);
        expect(posterAsked, isFalse);
        expect(draft.thumbnail, isNull);
        expect(
          _file('Fits.mp4', 'video/mp4', length: maxChatFileBytes).length(),
          completes,
        );
        final fits = await buildDraft(
          _file('Fits.mp4', 'video/mp4', length: maxChatFileBytes),
        );
        expect(fits.overLimit, isFalse);
        expect(fits.isLarge, isTrue);
      });
    });

    testWidgets('anything else is a file', (tester) async {
      await tester.runAsync(() async {
        final draft = await buildDraft(_file('Plan.pdf', 'application/pdf'));
        expect(draft.kind, DraftKind.file);
        expect(draft.thumbnail, isNull);
        final unknown = await buildDraft(_file('data.bin', ''));
        expect(unknown.kind, DraftKind.file);
        expect(unknown.mimeType, 'application/octet-stream');
      });
    });

    testWidgets('an image the device cannot decode is sent as a file', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final draft = await buildDraft(_file('weird.heic', 'image/heic'));
        expect(draft.kind, DraftKind.file);
      });
    });

    testWidgets('only as many as fit are looked at', (tester) async {
      await tester.runAsync(() async {
        final batch = await buildDrafts([
          for (var i = 0; i < 5; i++) _file('f$i.txt', 'text/plain'),
        ], room: 3);
        expect(batch.drafts, hasLength(3));
        expect(batch.leftOut, 2);
      });
    });
  });

  group('prepareDrafts', () {
    testWidgets('scales photos, passes videos and files on', (tester) async {
      await tester.runAsync(() async {
        final photo = await buildDraft(
          testPhoto('big.jpg', width: 3000, height: 1500),
        );
        final video = await buildDraft(
          _file('Clip.mp4', 'video/mp4', length: 100),
          videoPoster: (file) async => testJpeg(32, 18),
        );
        final doc = await buildDraft(_file('Plan.pdf', 'application/pdf'));
        final steps = <(int, int)>[];

        final items = await prepareDrafts(
          [photo, video, doc],
          original: false,
          onProgress: (done, total) => steps.add((done, total)),
        );

        expect(steps, [(0, 3), (1, 3), (2, 3), (3, 3)]);
        expect(items.map((item) => item.kind), [
          OutboxMediaKind.image,
          OutboxMediaKind.video,
          OutboxMediaKind.file,
        ]);
        expect(items[0].width, 2560);
        expect(items[0].height, 1280);
        expect(items[0].blurhash, isNotNull);
        expect(items[0].preview, isNotNull);
        expect(items[1].blurhash, isNotNull, reason: 'from the poster');
        expect(items[1].width, 32);
        expect(items[2].blurhash, isNull);
        // Files are read when queued, not before.
        expect(await items[2].data().expand((chunk) => chunk).length, 3);
      });
    });

    testWidgets('Original quality keeps the size', (tester) async {
      await tester.runAsync(() async {
        final photo = await buildDraft(
          testPhoto('big.jpg', width: 3000, height: 1500),
        );
        final items = await prepareDrafts([photo], original: true);
        expect(items.single.width, 3000);
        expect(items.single.height, 1500);
      });
    });
  });
}
