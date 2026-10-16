import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/chats/offline/sqlite_chat_cache.dart';

Future<ChatCache?> openChatCache() async {
  if (!Platform.isIOS && !Platform.isMacOS && !Platform.isAndroid) {
    return null;
  }
  // Support files are kept with backups off the user's Documents.
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return SqliteChatCache.open('${directory.path}/chat_cache.sqlite');
}
