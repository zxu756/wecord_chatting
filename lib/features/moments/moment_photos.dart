import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wecord/features/chats/media_send/photo_compression.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_repository.dart';

/// The longest side of a Moment's picture and of its thumbnail.
const momentPhotoEdge = 1920;
const momentThumbEdge = 480;
const momentCoverEdge = 1600;

/// Scales a picked picture down and compresses it (the chat's photo code:
/// HEIC, PNG and WebP become JPEG, metadata such as the position is gone,
/// the orientation is applied) and makes its thumbnail. Null when the
/// picture cannot be read.
Future<MomentPhotoDraft?> prepareMomentPhoto({
  required String id,
  required Uint8List bytes,
  required String fileName,
}) async {
  final full = await prepareJpegPhoto(
    bytes: bytes,
    fileName: fileName,
    maxEdge: momentPhotoEdge,
    quality: 82,
  );
  if (full == null) {
    return null;
  }
  final thumb = await prepareJpegPhoto(
    bytes: full.bytes,
    fileName: fileName,
    maxEdge: momentThumbEdge,
    quality: 72,
  );
  if (thumb == null) {
    return null;
  }
  return MomentPhotoDraft(
    id: id,
    full: full.bytes,
    thumb: thumb.bytes,
    width: full.width,
    height: full.height,
  );
}

/// Chooses pictures for a Moment and for the cover.
abstract interface class MomentPhotoPicker {
  /// Up to [limit] pictures from the library, prepared; empty when cancelled.
  /// Ones that cannot be read are left out.
  Future<List<MomentPhotoDraft>> pickPhotos({required int limit});

  /// One picture as a JPEG for the cover; null when cancelled.
  Future<Uint8List?> pickCover();
}

class SystemMomentPhotoPicker implements MomentPhotoPicker {
  SystemMomentPhotoPicker(this._picker);

  final ImagePicker _picker;
  var _counter = 0;

  @override
  Future<List<MomentPhotoDraft>> pickPhotos({required int limit}) async {
    final files = await _picker.pickMultiImage(limit: limit < 2 ? null : limit);
    final drafts = <MomentPhotoDraft>[];
    for (final file in files.take(limit)) {
      final draft = await prepareMomentPhoto(
        id: 'pick-${DateTime.now().microsecondsSinceEpoch}-${_counter++}',
        bytes: await file.readAsBytes(),
        fileName: file.name,
      );
      if (draft != null) {
        drafts.add(draft);
      }
    }
    return drafts;
  }

  @override
  Future<Uint8List?> pickCover() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) {
      return null;
    }
    final prepared = await prepareJpegPhoto(
      bytes: await file.readAsBytes(),
      fileName: file.name,
      maxEdge: momentCoverEdge,
      quality: 80,
    );
    return prepared?.bytes;
  }
}

final momentPhotoPickerProvider = Provider<MomentPhotoPicker>((ref) {
  return SystemMomentPhotoPicker(ImagePicker());
});

/// How many more pictures a Moment with [count] can take.
int momentPhotoRoom(int count) => maxMomentPhotos - count;
