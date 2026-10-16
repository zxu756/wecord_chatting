import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:image/image.dart' as img;
import 'package:wecord/features/chats/media_send/media_picker.dart';
import 'package:wecord/features/chats/media_send/media_upload.dart';
import 'package:wecord/features/chats/message_history.dart';
import 'package:wecord/shared/models/message.dart';

/// A small JPEG with a gradient, for pictures to send in tests.
Uint8List testJpeg(
  int width,
  int height, {
  int orientation = 1,
  bool gps = false,
}) {
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    pixel
      ..r = (pixel.x * 255 / width).round()
      ..g = (pixel.y * 255 / height).round()
      ..b = 120;
  }
  image.exif.imageIfd.orientation = orientation;
  if (gps) {
    image.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(51, 1);
    image.exif.gpsIfd['GPSLongitude'] = img.IfdValueRational(7, 1);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 92));
}

/// A picked picture as the pickers return it.
XFile testPhoto(String name, {int width = 40, int height = 30}) {
  final bytes = testJpeg(width, height);
  return XFile.fromData(
    bytes,
    name: name,
    path: name,
    mimeType: 'image/jpeg',
    length: bytes.length,
  );
}

/// Records uploads; fails or holds them when told to.
class FakeChatMediaUploader implements ChatMediaUploader {
  final uploads = <({String bucket, String path, int length})>[];

  /// Thrown by the next uploads, in order, before any byte is read.
  final failures = <Object>[];

  /// Called at the start of every upload; may throw.
  void Function()? beforeUpload;

  /// While set, uploads wait for it (and abort when cancelled).
  Completer<void>? hold;

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
    uploads.add((bucket: bucket, path: path, length: length));
    beforeUpload?.call();
    if (failures.isNotEmpty) {
      throw failures.removeAt(0);
    }
    var read = 0;
    await for (final chunk in data) {
      read += chunk.length;
      onProgress?.call(read / length);
    }
    final gate = hold;
    if (gate != null) {
      final cancelled = Completer<void>();
      cancel?.onCancel(
        () => cancelled.completeError(const UploadCancelledException()),
      );
      await Future.any([gate.future, cancelled.future]);
    }
  }
}

/// Records the messages of uploaded attachments.
class FakeMediaMessageSender implements MediaMessageSender {
  final calls = <Map<String, Object?>>[];
  final failures = <Object>[];

  /// The messages a push was asked for after the fact.
  final notified = <String>[];

  @override
  Future<void> notifyMessageSent(String messageId) async {
    notified.add(messageId);
  }

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
  }) async {
    if (failures.isNotEmpty) {
      throw failures.removeAt(0);
    }
    calls.add({
      'clientId': clientId,
      'type': type,
      'attachment': attachment,
      'body': body,
      'group': attachmentGroupId,
      'notify': notify,
      'replyTo': replyToMessageId,
    });
    return 'message-${calls.length}';
  }
}

/// A chooser that returns what the test put in it.
class FakeChatMediaPicker implements ChatMediaPicker {
  List<XFile> photos = [];
  List<XFile> files = [];
  Object? error;
  Completer<List<XFile>>? hold;
  var photoCalls = 0;
  var fileCalls = 0;
  int? lastLimit;

  @override
  Future<List<XFile>> pickPhotosAndVideos({int limit = 10}) async {
    photoCalls += 1;
    lastLimit = limit;
    if (error case final error?) {
      throw error;
    }
    return hold?.future ?? photos;
  }

  @override
  Future<List<XFile>> pickFiles() async {
    fileCalls += 1;
    if (error case final error?) {
      throw error;
    }
    return hold?.future ?? files;
  }
}
