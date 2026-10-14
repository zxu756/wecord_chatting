import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/file_picker_service.dart';
import 'package:wecord/shared/models/message.dart';

void main() {
  test('file attachments parse files and videos, not other kinds', () {
    final file = FileAttachment.maybeFromJson({
      'kind': 'file',
      'bucket': 'chat-files',
      'path': 'c/seed-notes.txt',
      'name': 'notes.txt',
      'mime_type': 'text/plain',
      'size': 12,
    })!;
    expect(file.name, 'notes.txt');
    expect(file.isVideo, isFalse);
    expect(file.toJson()['kind'], 'file');

    final video = FileAttachment.maybeFromJson({
      'kind': 'video',
      'bucket': 'chat-files',
      'path': 'c/seed-clip.mp4',
      'mime_type': 'video/mp4',
      'size': 1,
    })!;
    expect(video.isVideo, isTrue);
    expect(video.name, 'seed-clip.mp4');

    expect(FileAttachment.maybeFromJson({'kind': 'image'}), isNull);
    expect(FileAttachment.maybeFromJson(null), isNull);
    expect(FileAttachment.maybeFromJson({'kind': 'file'}), isNull);
  });

  test('sizes read as bytes, KB, MB and GB', () {
    expect(formatFileSize(512), '512 B');
    expect(formatFileSize(14 * 1024), '14 KB');
    expect(formatFileSize((3.25 * 1024 * 1024).round()), '3.3 MB');
    expect(formatFileSize(42 * 1024 * 1024), '42 MB');
    expect(formatFileSize(2 * 1024 * 1024 * 1024), '2.0 GB');
  });

  test('file types come from the picker, else the name, else binary', () {
    expect(
      chatFileMimeType(name: 'a.bin', reported: 'application/pdf'),
      'application/pdf',
    );
    expect(chatFileMimeType(name: 'clip.mp4'), 'video/mp4');
    expect(chatFileMimeType(name: 'mystery'), 'application/octet-stream');
  });
}
