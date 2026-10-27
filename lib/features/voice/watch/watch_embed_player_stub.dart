import 'package:wecord/features/voice/watch/watch_player.dart';
import 'package:wecord/features/voice/watch/watch_sources.dart';

/// Whether this build can show YouTube's and Bilibili's embedded players
/// inside the app: only the web build can (an iframe). On iPhone and Mac the
/// call offers "open in the browser" and the host's hints instead.
const embedPlayersSupported = false;

/// No embedded player here (see [embedPlayersSupported]).
Future<WatchPlayer?> createEmbedWatchPlayer(WatchEmbedSource source) async =>
    null;
