import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wecord/features/chats/image_picker_service.dart';

void main() {
  test('pickImage maps a selected image into an upload payload', () async {
    final service = SystemImagePickerService.withPicker(
      pickImageFile: () async =>
          XFile('/Users/xu/Desktop/Photo.PNG', mimeType: 'image/png'),
      readImageFile: (_) async => Uint8List.fromList([1, 2, 3]),
    );

    final image = await service.pickImage();

    expect(image, isNotNull);
    expect(image!.bytes, Uint8List.fromList([1, 2, 3]));
    expect(image.fileName, 'Photo.PNG');
    expect(image.mimeType, 'image/png');
  });

  test(
    'pickImage wraps local file read failures with an actionable error',
    () async {
      final service = SystemImagePickerService.withPicker(
        pickImageFile: () async => XFile('/Users/xu/Desktop/photo.png'),
        readImageFile: (_) async {
          throw const FileSystemException(
            'readInto failed',
            '/Users/xu/Desktop/photo.png',
            OSError('Operation timed out', 60),
          );
        },
        fileReadAttempts: 1,
      );

      await expectLater(
        service.pickImage(),
        throwsA(
          isA<ImagePickerException>().having(
            (error) => error.message,
            'message',
            contains('Could not read the selected image from this Mac'),
          ),
        ),
      );
    },
  );
}
