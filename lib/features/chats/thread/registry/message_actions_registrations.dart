// Where message menu contributions are registered.
//
// To add an entry to the message menu, write a `MessageActionContribution`
// in your feature's own file and add it to [messageActionExtensions] with one
// line. The built-in entries (see message_actions_builtin.dart) occupy orders
// 100, 200, ... 1700; pick an `order` between two of them to place yours.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/care_mode/care_registry_filters.dart';
import 'package:wecord/features/care_mode/read_aloud.dart';
import 'package:wecord/features/ai/assistant/assistant_chat.dart';
import 'package:wecord/features/chats/chat_polish/quote_reply.dart';
import 'package:wecord/features/chats/edit_history/edit_history_chat.dart';
import 'package:wecord/features/chats/read_status/read_status_chat.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/features/chats/thread/registry/message_actions_builtin.dart';
import 'package:wecord/features/reports/report_message_action.dart';
import 'package:wecord/features/stickers/add_to_stickers_action.dart';
import 'package:wecord/features/urgent/urgent_message_action.dart';

/// Feature contributions to the message menu. Append yours here.
final List<MessageActionContribution> messageActionExtensions = [
  // myFeatureMessageAction,
  reportMessageAction,
  editHistoryAction,
  messageInfoAction,
  addToStickersAction,
  makeTasksAction,
  askAssistantAction,
  quoteReplyAction,
  urgentMessageAction,
  readAloudAction,
];

/// The menu's registry. Tests can override it to add or drop entries.
final messageActionRegistryProvider = Provider<MessageActionRegistry>((ref) {
  // Care mode's simple home keeps the everyday entries only.
  final simple = ref.watch(careModeProvider.select((s) => s.simplifies));
  return MessageActionRegistry([
    for (final contribution in [
      ...builtInMessageActions,
      ...messageActionExtensions,
    ])
      if (!simple || !careHiddenMessageActionIds.contains(contribution.id))
        contribution,
  ]);
});
