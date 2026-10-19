// Where composer "+" menu contributions are registered.
//
// To add an entry to the "+" menu (a form, a game, a sticker pack ...), write
// a `ComposerMenuContribution` in your feature's own file and add it to
// [composerMenuExtensions] with one line. The built-in entries (see
// composer_menu_builtin.dart) occupy orders 100, 200, ... 1300; pick an
// `order` between two of them to place yours.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_polish/silent_send.dart';
import 'package:wecord/features/forms/forms_chat.dart';
import 'package:wecord/features/ai/assistant/assistant_chat.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu_builtin.dart';

/// Feature contributions to the "+" menu. Append yours here.
final List<ComposerMenuContribution> composerMenuExtensions = [
  // myFeatureComposerEntry,
  formComposerEntry,
  askAssistantEntry,
  silentSendComposerEntry,
];

/// The menu's registry. Tests can override it to add or drop entries.
final composerMenuRegistryProvider = Provider<ComposerMenuRegistry>(
  (ref) =>
      ComposerMenuRegistry([...builtInComposerMenu, ...composerMenuExtensions]),
);
