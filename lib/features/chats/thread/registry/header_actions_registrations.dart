// Where header actions are registered.
//
// To add a button to the thread header's More menu (and, with `primary: true`,
// to the wide header), write a `HeaderActionContribution` in your feature's
// own file and add it to [headerActionExtensions] with one line. The built-in
// actions (see header_actions_builtin.dart) occupy orders 100, 200, ... 1200,
// then the parent's extra actions at 1500, then Events at 2000. Pick an
// `order` to place yours.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/auto_translate.dart';
import 'package:wecord/features/chats/thread/registry/header_actions.dart';
import 'package:wecord/features/chats/thread/registry/header_actions_builtin.dart';

/// Feature contributions to the header. Append yours here.
final List<HeaderActionContribution> headerActionExtensions = [
  // myFeatureHeaderAction,
  autoTranslateHeaderAction,
];

/// The header's registry. Tests can override it to add or drop actions.
final headerActionRegistryProvider = Provider<HeaderActionRegistry>(
  (ref) => HeaderActionRegistry([
    ...builtInHeaderActions,
    ...headerActionExtensions,
  ]),
);
