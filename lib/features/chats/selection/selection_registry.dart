// Extension point of the selection bar: the buttons features add after the
// built-in ones (Forward, Merge & forward, Save, Copy, Delete).
//
// A feature writes a [SelectionBarContribution] in its own file and lists it
// in `selection_registrations.dart` with one line. See "Chat page extension
// points" in docs/design/wecord-design-language.md.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/selection/selection_actions.dart';
import 'package:wecord/shared/models/message.dart';

/// What a contribution can look at: the chat and the messages ticked.
class SelectionBarContext {
  const SelectionBarContext({
    required this.context,
    required this.environment,
    required this.messages,
    required this.leaveSelection,
  });

  final BuildContext context;
  final SelectionEnvironment environment;

  /// The selected messages, oldest first.
  final List<ChatMessage> messages;

  /// Leaves selection mode (after the feature did its work).
  final VoidCallback leaveSelection;

  /// The app's providers, for a contribution that needs to read one.
  ProviderContainer get container =>
      ProviderScope.containerOf(context, listen: false);
}

/// One extra button of the selection bar.
class SelectionBarEntry {
  const SelectionBarEntry({
    required this.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.hint,
  });

  final Key key;
  final IconData icon;
  final String label;

  /// Null shows the button disabled.
  final VoidCallback? onPressed;
  final String? hint;
}

class SelectionBarContribution {
  const SelectionBarContribution({
    required this.id,
    required this.order,
    required this.build,
  });

  /// Unique and stable, e.g. `extract-actions`.
  final String id;

  /// Among the extra buttons, ascending.
  final int order;

  /// The button, or null when the feature does not apply.
  final SelectionBarEntry? Function(SelectionBarContext ctx) build;
}

/// The extra buttons' registry.
class SelectionBarRegistry {
  SelectionBarRegistry(Iterable<SelectionBarContribution> contributions)
    : _contributions = (contributions.toList()
        ..sort((a, b) => a.order.compareTo(b.order)));

  final List<SelectionBarContribution> _contributions;

  List<SelectionBarEntry> entriesFor(SelectionBarContext ctx) => [
    for (final contribution in _contributions) ?contribution.build(ctx),
  ];

  List<String> get ids => [for (final c in _contributions) c.id];
}
