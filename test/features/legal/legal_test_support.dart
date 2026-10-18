import 'dart:io';

import 'package:flutter/services.dart';

/// Reads the bundled files from disk, like the app's assets. The real
/// `rootBundle` loads through the engine, outside the test clock, and its
/// cache would hand a half-finished load to the next test.
class DiskAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    return ByteData.sublistView(File(key).readAsBytesSync());
  }
}
