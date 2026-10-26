// Where there is no browser: nothing to record with. The real one is
// video_note_camera_web.dart.
import 'package:wecord/features/chats/video_note/video_note_camera.dart';

/// The browser's recorder, or null off the web.
VideoNoteCamera? createWebVideoNoteCamera() => null;

/// Whether this browser can record a round video message.
bool browserCanRecordVideoNotes() => false;
