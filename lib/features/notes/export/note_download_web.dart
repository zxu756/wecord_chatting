import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Offers [bytes] as a file named [fileName] through a temporary link.
/// Returns whether it did.
bool downloadNoteFile(String fileName, Uint8List bytes, String mimeType) {
  try {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName;
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return true;
  } catch (_) {
    return false;
  }
}
