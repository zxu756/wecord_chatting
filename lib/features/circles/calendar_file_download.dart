// Saves an .ics file on the web; elsewhere there is nothing to save to and
// callers copy the event's details instead.
export 'package:wecord/features/circles/calendar_file_download_stub.dart'
    if (dart.library.js_interop) 'package:wecord/features/circles/calendar_file_download_web.dart';
