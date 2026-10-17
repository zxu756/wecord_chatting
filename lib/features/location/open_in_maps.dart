import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wecord/features/location/location_models.dart';

/// A maps app or site a place can be opened in.
enum MapsApp {
  apple('Apple Maps'),
  google('Google Maps'),
  openStreetMap('OpenStreetMap');

  const MapsApp(this.label);

  final String label;
}

/// Where a place can be opened on this platform: Apple Maps on iOS and
/// macOS, Google Maps and OpenStreetMap in a browser (and elsewhere).
List<MapsApp> mapsAppsFor({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (!isWeb &&
      (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS)) {
    return const [MapsApp.apple];
  }
  return const [MapsApp.google, MapsApp.openStreetMap];
}

/// The link that opens [place] in [app], pinned where it is.
Uri mapsUri(MapsApp app, PlaceInfo place) {
  final lat = place.point.latitude.toStringAsFixed(6);
  final lng = place.point.longitude.toStringAsFixed(6);
  switch (app) {
    case MapsApp.apple:
      return Uri.https('maps.apple.com', '/', {
        'll': '$lat,$lng',
        if (place.hasName) 'q': place.name,
      });
    case MapsApp.google:
      return Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': '$lat,$lng',
      });
    case MapsApp.openStreetMap:
      return Uri.https('www.openstreetmap.org', '/', {
        'mlat': lat,
        'mlon': lng,
      }).replace(fragment: 'map=17/$lat/$lng');
  }
}

/// What "Copy address" puts on the clipboard: the name and address, or the
/// coordinates when the place has neither.
String copyableAddress(PlaceInfo place) {
  final parts = [
    if (place.hasName) place.name.trim(),
    if (place.hasAddress) place.address.trim(),
  ];
  if (parts.isEmpty) {
    return '${place.point.latitude.toStringAsFixed(5)}, '
        '${place.point.longitude.toStringAsFixed(5)}';
  }
  return parts.join(', ');
}

/// Opens links and copies text; tests replace it to see what happened.
abstract interface class MapsLauncher {
  Future<bool> open(Uri uri);

  Future<void> copy(String text);
}

class SystemMapsLauncher implements MapsLauncher {
  const SystemMapsLauncher();

  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }

  @override
  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

final mapsLauncherProvider = Provider<MapsLauncher>(
  (ref) => const SystemMapsLauncher(),
);

/// Whether this build runs in a browser.
final mapsIsWebProvider = Provider<bool>((ref) => kIsWeb);
