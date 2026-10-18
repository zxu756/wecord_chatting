import 'package:wecord/features/push/push_gateway_web.dart'
    show browserTimeZone;

/// The browser's own IANA zone, the one web push already reports.
String? platformDeviceTimeZone() => browserTimeZone();
