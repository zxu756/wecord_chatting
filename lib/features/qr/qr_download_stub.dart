import 'dart:typed_data';

/// Offers [bytes] as a file named [fileName]. Returns whether it did; only
/// browsers can.
bool downloadQrImage(String fileName, Uint8List bytes) => false;
