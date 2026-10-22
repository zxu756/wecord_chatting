// The kinds of group tab and how each one opens, and the registry that holds
// them.
//
// A tab's kind is a row of `conversation_tab_kinds` on the server. The app
// opens it through a [GroupTabKindContribution]; a kind the app has no
// contribution for is left out of the strip. A package adds a kind by writing
// a contribution in its own file and adding it to `groupTabKindExtensions` in
// group_tab_kinds_registrations.dart (the group space of B6 does that when it
// is merged: kind 'space', no target).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/group_tabs/group_tab_models.dart';

/// What a contribution can look at when it opens a tab or is asked to add one.
class GroupTabContext {
  const GroupTabContext({
    required this.context,
    required this.conversationId,
    required this.title,
    this.circleId,
    this.canSend = true,
  });

  /// For navigation and sheets.
  final BuildContext context;
  final String conversationId;

  /// The chat's name.
  final String title;

  /// The circle, when the chat is one of its channels.
  final String? circleId;
  final bool canSend;

  /// The app's providers, for a contribution that needs to read one.
  ProviderContainer get container =>
      ProviderScope.containerOf(context, listen: false);
}

/// What a person picked for a new tab.
class GroupTabPick {
  const GroupTabPick({this.target, this.title});

  final String? target;

  /// A suggested name; the server takes the target's own when empty.
  final String? title;
}

/// One kind of tab.
class GroupTabKindContribution {
  const GroupTabKindContribution({
    required this.kind,
    required this.order,
    required this.label,
    required this.icon,
    required this.open,
    this.pick,
    this.canAdd,
    this.defaultTitle,
  });

  /// The kind's name on the server: 'note', 'list' ...
  final String kind;

  /// Where the kind sits in the "Add a tab" list, ascending.
  final int order;

  /// "Note", "Link" ...
  final String Function() label;
  final IconData icon;

  /// Opens the tab.
  final void Function(GroupTabContext ctx, GroupTab tab) open;

  /// Asks what the new tab should point at (a note, a link ...); null when
  /// the kind has no target and is added at once. Answers null when the
  /// person backs out.
  final Future<GroupTabPick?> Function(GroupTabContext ctx)? pick;

  /// Whether the kind can be added in this chat (the knowledge base needs a
  /// circle channel); everywhere when null.
  final bool Function(GroupTabContext ctx)? canAdd;

  /// The name of a new tab of a kind with no target.
  final String Function()? defaultTitle;
}

/// The kinds the app can open, by kind.
class GroupTabKindRegistry {
  GroupTabKindRegistry(Iterable<GroupTabKindContribution> contributions)
    : _contributions = _sorted(contributions);

  final List<GroupTabKindContribution> _contributions;

  GroupTabKindContribution? kindOf(String kind) {
    for (final contribution in _contributions) {
      if (contribution.kind == kind) {
        return contribution;
      }
    }
    return null;
  }

  /// Whether the app knows how to open [kind].
  bool opens(String kind) => kindOf(kind) != null;

  /// The kinds that can be added here, in order.
  List<GroupTabKindContribution> addable(GroupTabContext ctx) => [
    for (final contribution in _contributions)
      if (contribution.canAdd?.call(ctx) ?? true) contribution,
  ];

  /// The kinds in order (for tests).
  List<String> get kinds => [for (final c in _contributions) c.kind];

  static List<GroupTabKindContribution> _sorted(
    Iterable<GroupTabKindContribution> contributions,
  ) {
    final list = contributions.toList();
    assert(
      list.map((c) => c.kind).toSet().length == list.length,
      'Two group tab kinds share a name',
    );
    final indexed = list.indexed.toList()
      ..sort((a, b) {
        final byOrder = a.$2.order.compareTo(b.$2.order);
        return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
      });
    return [for (final (_, contribution) in indexed) contribution];
  }
}
