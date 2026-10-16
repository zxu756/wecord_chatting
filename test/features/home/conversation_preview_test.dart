import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/media_send/album_label.dart';
import 'package:wecord/features/home/conversation_preview.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

ConversationSummary _summary({
  required MessageType type,
  String body = '[Image]',
  String? kind,
  Object? album,
  String sender = 'ada',
}) {
  return ConversationSummary.fromJson({
    'id': 'c1',
    'type': 'group',
    'unread_count': 0,
    'last_message_body': body,
    'last_message_type': type.toJson(),
    'last_message_sender_id': sender,
    'last_message_attachment_kind': kind,
    'last_message_album': album,
  });
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('album labels', () {
    test('say what an album holds', () {
      expect(albumLabel(images: 3), '3 photos');
      expect(albumLabel(images: 2, videos: 1), '2 photos, 1 video');
      expect(albumLabel(files: 4), '4 files');
      expect(
        albumLabel(images: 1, videos: 2, files: 1),
        '1 photo, 2 videos, 1 file',
      );
      expect(albumLabel(), '');
    });

    test('read in Chinese', () {
      AppStrings.isChinese = true;
      expect(albumLabel(images: 3), '3 张照片');
      expect(albumLabel(images: 2, videos: 1), '2 张照片，1 个视频');
      expect(albumLabel(files: 4), '4 个文件');
    });
  });

  group('the summary of the latest album', () {
    test('is read from the server', () {
      final summary = _summary(
        type: MessageType.image,
        album: {'images': 2, 'videos': 1, 'files': 0},
      );
      expect(
        summary.lastMessageAlbum,
        const ConversationAlbum(images: 2, videos: 1),
      );
      expect(summary.lastMessageAlbum!.total, 3);
    });

    test('is absent for one message, or from servers that do not say', () {
      expect(_summary(type: MessageType.image).lastMessageAlbum, isNull);
      expect(
        _summary(
          type: MessageType.image,
          album: {'images': 1, 'videos': 0, 'files': 0},
        ).lastMessageAlbum,
        isNull,
      );
      expect(
        _summary(type: MessageType.image, album: 'nonsense').lastMessageAlbum,
        isNull,
      );
    });

    test('survives copying, and can be cleared', () {
      final summary = _summary(
        type: MessageType.image,
        album: {'images': 3, 'videos': 0, 'files': 0},
      );
      expect(summary.copyWith(unreadCount: 2).lastMessageAlbum, isNotNull);
      expect(summary.copyWith(lastMessageAlbum: null).lastMessageAlbum, isNull);
    });
  });

  group('conversation previews', () {
    test('show "3 photos" for an album of pictures', () {
      final preview = conversationPreview(
        _summary(
          type: MessageType.image,
          album: {'images': 3, 'videos': 0, 'files': 0},
        ),
      )!;
      expect(preview.text, '3 photos');
      expect(preview.icon, Icons.photo_library_outlined);
    });

    test('show pictures and videos together', () {
      final preview = conversationPreview(
        _summary(
          type: MessageType.file,
          kind: 'video',
          album: {'images': 2, 'videos': 1, 'files': 0},
        ),
      )!;
      expect(preview.text, '2 photos, 1 video');
    });

    test('show "4 files" for an album of files, with the sender', () {
      final preview = conversationPreview(
        _summary(
          type: MessageType.file,
          body: '[File]',
          kind: 'file',
          album: {'images': 0, 'videos': 0, 'files': 4},
        ),
        currentUserId: 'ada',
      )!;
      expect(preview.text, 'You: 4 files');
      expect(preview.icon, Icons.attach_file_rounded);
    });

    test('keep the single item preview without an album', () {
      expect(
        conversationPreview(_summary(type: MessageType.image))!.text,
        'Image',
      );
      expect(
        conversationPreview(
          _summary(type: MessageType.file, kind: 'video', body: '[File]'),
        )!.text,
        'Video',
      );
    });

    test('read in Chinese', () {
      AppStrings.isChinese = true;
      expect(
        conversationPreview(
          _summary(
            type: MessageType.image,
            album: {'images': 2, 'videos': 1, 'files': 0},
          ),
        )!.text,
        '2 张照片，1 个视频',
      );
    });

    test('a deleted latest message stays deleted', () {
      expect(
        conversationPreview(
          _summary(
            type: MessageType.image,
            body: 'Message deleted',
            album: {'images': 2, 'videos': 0, 'files': 0},
          ),
        )!.text,
        'Message deleted',
      );
    });
  });
}
