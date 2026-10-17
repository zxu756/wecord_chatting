// Saves the QR card's picture on the web; elsewhere the system's own save and
// share sheets do it.
export 'package:wecord/features/qr/qr_download_stub.dart'
    if (dart.library.js_interop) 'package:wecord/features/qr/qr_download_web.dart';
