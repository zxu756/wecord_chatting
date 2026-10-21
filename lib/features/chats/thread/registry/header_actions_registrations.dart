// Where header actions are registered.
//
// To add a button to the thread header's More menu (and, with `primary: true`,
// to the wide header), write a `HeaderActionContribution` in your feature's
// own file and add it to [headerActionExtensions] with one line. The built-in
// actions (see header_actions_builtin.dart) occupy orders 100, 200, ... 1200,
// then the parent's extra actions at 1500, then Events at 2000. Pick an
// `order` to place yours.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/care_mode/care_registry_filters.dart';
import 'package:wecord/features/ai/auto_translate.dart';
import 'package:wecord/features/app_lock/chat_lock_actions.dart';
import 'package:wecord/features/chats/thread/registry/header_actions.dart';
import 'package:wecord/features/chats/thread/registry/header_actions_builtin.dart';
import 'package:wecord/features/circles/channel_types/qa_actions.dart';
import 'package:wecord/features/circles/mod_tools/thread_lock.dart';
import 'package:wecord/features/group_space/space_actions.dart';

/// Feature contributions to the header. Append yours here.
final List<HeaderActionContribution> headerActionExtensions = [
  // myFeatureHeaderAction,
  autoTranslateHeaderAction,
  chatLockHeaderAction,
  threadLockHeaderAction,
  qaSolvedHeaderAction,
  groupSpaceHeaderAction,
];

/// The header's registry. Tests can override it to add or drop actions.
final headerActionRegistryProvider = Provider<HeaderActionRegistry>((ref) {
  // Care mode's simple home keeps the everyday actions only.
  final simple = ref.watch(careModeProvider.select((s) => s.simplifies));
  return HeaderActionRegistry([
    for (final contribution in [
      ...builtInHeaderActions,
      ...headerActionExtensions,
    ])
      if (!simple || !careHiddenHeaderActionIds.contains(contribution.id))
        contribution,
  ]);
});
