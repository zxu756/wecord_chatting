import 'package:wecord/features/chats/media_send/pending_media_store.dart';

/// The web keeps what is waiting to be sent in memory only.
PendingMediaStore createPendingMediaStore() => MemoryPendingMediaStore();
