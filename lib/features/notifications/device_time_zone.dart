import 'package:wecord/features/notifications/device_time_zone_stub.dart'
    if (dart.library.js_interop) 'package:wecord/features/notifications/device_time_zone_web.dart';

/// The IANA time zone of this device ('Asia/Shanghai'), which the server
/// needs to tell when its quiet hours are. Null when it can't be told.
String? deviceTimeZone() => platformDeviceTimeZone();

/// Whether [zone] has the shape of an IANA name (the server checks the same).
bool looksLikeTimeZone(String? zone) =>
    zone != null && RegExp(r'^[A-Za-z0-9_+./-]{1,64}$').hasMatch(zone);
