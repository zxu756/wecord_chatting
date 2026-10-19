import 'dart:typed_data';

/// Offers [bytes] as a file named [fileName]. Returns whether it did; only
/// browsers can.
bool downloadNoteFile(String fileName, Uint8List bytes, String mimeType) =>
    false;
