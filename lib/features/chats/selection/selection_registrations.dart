// Where selection bar contributions are registered.
//
// The bar that replaces the composer while messages are selected (Forward,
// Merge & forward, Save, Copy, Delete) has a few built-in buttons; a feature
// adds one by writing a [SelectionBarContribution] (selection_registry.dart)
// in its own file and listing it in [selectionBarExtensions] with one line.
// They sit after the built-in buttons, in `order`.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/actions/extract_actions_chat.dart';
import 'package:wecord/features/chats/selection/selection_registry.dart';

/// Feature contributions to the selection bar. Append yours here.
final List<SelectionBarContribution> selectionBarExtensions = [
  // myFeatureSelectionButton,
  extractActionsSelectionButton,
];

/// The registry. Tests can override it to add or drop buttons.
final selectionBarRegistryProvider = Provider<SelectionBarRegistry>(
  (ref) => SelectionBarRegistry(selectionBarExtensions),
);
