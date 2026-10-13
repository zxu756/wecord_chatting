import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Offers [contents] as a file named [fileName] through a temporary link.
/// Returns whether it did.
bool downloadCalendarFile(String fileName, String contents) {
  try {
    final blob = web.Blob(
      [contents.toJS].toJS,
      web.BlobPropertyBag(type: 'text/calendar;charset=utf-8'),
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
