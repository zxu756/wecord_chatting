import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:wecord/features/chats/chats_repository.dart';

/// A file chosen to send in a chat.
class PickedChatFile {
  const PickedChatFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
}

abstract interface class ChatFilePickerService {
  /// Asks for a file; null when the user cancels. Throws
  /// [ChatFileTooLargeException] for files over [maxChatFileBytes], before
  /// reading them.
  Future<PickedChatFile?> pickFile();
}

final chatFilePickerServiceProvider = Provider<ChatFilePickerService>((ref) {
  return const SystemChatFilePickerService();
});

class SystemChatFilePickerService implements ChatFilePickerService {
  const SystemChatFilePickerService();

  @override
  Future<PickedChatFile?> pickFile() async {
    final file = await openFile();
    if (file == null) {
      return null;
    }
    if (await file.length() > maxChatFileBytes) {
      throw const ChatFileTooLargeException();
    }
    final bytes = await file.readAsBytes();
    return PickedChatFile(
      name: file.name,
      mimeType: chatFileMimeType(
        name: file.name,
        reported: file.mimeType,
        headerBytes: bytes.length > 32 ? bytes.sublist(0, 32) : bytes,
      ),
      bytes: bytes,
    );
  }
}

/// The file's type: what the picker reported, else guessed from its name
/// and first bytes, else generic binary. A generic "binary" report (browsers
/// give it for many files) counts as no report: a picture named `.png` must
/// reach the picture bucket as `image/png`, which only takes pictures.
String chatFileMimeType({
  required String name,
  String? reported,
  List<int>? headerBytes,
}) {
  final known = reported?.trim();
  if (known != null &&
      known.isNotEmpty &&
      known.toLowerCase() != 'application/octet-stream' &&
      known.toLowerCase() != 'binary/octet-stream') {
    return known;
  }
  return lookupMimeType(name, headerBytes: headerBytes) ??
      'application/octet-stream';
}
