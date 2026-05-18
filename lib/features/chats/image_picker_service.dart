import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wecord/features/chats/chats_repository.dart';

final imagePickerServiceProvider = Provider<ImagePickerService>((ref) {
  return SystemImagePickerService(ImagePicker());
});

abstract interface class ImagePickerService {
  Future<ChatImageUpload?> pickImage();
}

typedef PickImageFile = Future<XFile?> Function();
typedef ReadImageFile = Future<Uint8List> Function(XFile file);

class SystemImagePickerService implements ImagePickerService {
  SystemImagePickerService(ImagePicker picker)
    : this.withPicker(
        pickImageFile: () => picker.pickImage(source: ImageSource.gallery),
      );

  SystemImagePickerService.withPicker({
    required PickImageFile pickImageFile,
    ReadImageFile? readImageFile,
    Duration fileReadTimeout = const Duration(seconds: 20),
    Duration retryDelay = const Duration(milliseconds: 250),
    int fileReadAttempts = 2,
  }) : assert(fileReadAttempts > 0),
       _pickImageFile = pickImageFile,
       _readImageFile = readImageFile ?? _readImageFileDefault,
       _fileReadTimeout = fileReadTimeout,
       _retryDelay = retryDelay,
       _fileReadAttempts = fileReadAttempts;

  final PickImageFile _pickImageFile;
  final ReadImageFile _readImageFile;
  final Duration _fileReadTimeout;
  final Duration _retryDelay;
  final int _fileReadAttempts;

  @override
  Future<ChatImageUpload?> pickImage() async {
    final file = await _pickImageFile();
    if (file == null) {
      return null;
    }

    return ChatImageUpload(
      bytes: await _readBytes(file),
      fileName: file.name,
      mimeType: file.mimeType ?? _mimeTypeFromName(file.name),
    );
  }

  Future<Uint8List> _readBytes(XFile file) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 1; attempt <= _fileReadAttempts; attempt += 1) {
      try {
        return await _readImageFile(file).timeout(
          _fileReadTimeout,
          onTimeout: () {
            throw TimeoutException(
              'Timed out reading selected image',
              _fileReadTimeout,
            );
          },
        );
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (error is TimeoutException || attempt == _fileReadAttempts) {
          break;
        }
        await Future<void>.delayed(_retryDelay);
      }
    }

    Error.throwWithStackTrace(
      ImagePickerException.localReadFailed(
        fileName: file.name,
        filePath: file.path,
        cause: lastError,
      ),
      lastStackTrace ?? StackTrace.current,
    );
  }
}

Future<Uint8List> _readImageFileDefault(XFile file) {
  return file.readAsBytes();
}

class ImagePickerException implements Exception {
  const ImagePickerException(this.message);

  factory ImagePickerException.localReadFailed({
    required String fileName,
    required String filePath,
    required Object? cause,
  }) {
    final location = filePath.isEmpty ? fileName : filePath;
    return ImagePickerException(
      'Could not read the selected image from this Mac. '
      'Try moving it to a local folder and choosing it again. '
      'File: $location. Cause: $cause',
    );
  }

  final String message;

  @override
  String toString() => message;
}

String _mimeTypeFromName(String fileName) {
  final lowerName = fileName.toLowerCase();
  if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (lowerName.endsWith('.png')) {
    return 'image/png';
  }
  if (lowerName.endsWith('.gif')) {
    return 'image/gif';
  }
  if (lowerName.endsWith('.webp')) {
    return 'image/webp';
  }
  return 'image/jpeg';
}
