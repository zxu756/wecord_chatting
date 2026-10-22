import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/group_tabs/group_tab_models.dart';
import 'package:wecord/features/group_tabs/group_tabs_repository.dart';

/// The tabs of chats in memory, with the rules the server enforces (admins
/// only, at most 12, none twice).
class FakeGroupTabsRepository implements GroupTabsRepository {
  FakeGroupTabsRepository({
    List<GroupTab>? tabs,
    this.canManage = true,
    this.circleId,
  }) : items = [...?tabs];

  /// The tabs, in order.
  final List<GroupTab> items;
  bool canManage;
  final String? circleId;

  /// What the lists of forms and check-ins hold.
  final candidatesByKind = <String, List<GroupTabCandidate>>{};

  /// Makes the next call of this kind fail.
  Object? tabsError;
  Object? addError;

  final calls = <String>[];
  final added = <({String kind, String? target, String? title})>[];
  var _next = 100;

  @override
  Future<GroupTabs> tabs(
    String conversationId, {
    bool includeUnavailable = false,
  }) async {
    calls.add(includeUnavailable ? 'tabs-all' : 'tabs');
    if (tabsError != null) {
      throw tabsError!;
    }
    return GroupTabs(
      canManage: canManage,
      tabs: [
        for (final tab in items)
          if (includeUnavailable || tab.available) tab,
      ],
    );
  }

  @override
  Future<String> add(
    String conversationId, {
    required String kind,
    String? target,
    String? title,
  }) async {
    calls.add('add');
    if (addError != null) {
      throw addError!;
    }
    if (!canManage) {
      throw const GroupTabException(GroupTabFailureKind.notAllowed);
    }
    if (items.length >= maxGroupTabs) {
      throw const GroupTabException(GroupTabFailureKind.limit);
    }
    if (items.any((t) => t.kind == kind && t.target == target)) {
      throw const GroupTabException(GroupTabFailureKind.exists);
    }
    added.add((kind: kind, target: target, title: title));
    final id = 'tab-${_next++}';
    items.add(
      GroupTab(
        id: id,
        kind: kind,
        target: target,
        title: title ?? kind,
        sort: items.length,
        circleId: circleId,
      ),
    );
    return id;
  }

  @override
  Future<void> rename(String tabId, String title) async {
    calls.add('rename');
    final index = items.indexWhere((t) => t.id == tabId);
    final old = items[index];
    items[index] = GroupTab(
      id: old.id,
      kind: old.kind,
      target: old.target,
      title: title,
      icon: old.icon,
      sort: old.sort,
      available: old.available,
      closed: old.closed,
      circleId: old.circleId,
    );
  }

  @override
  Future<void> remove(String tabId) async {
    calls.add('remove');
    if (!canManage) {
      throw const GroupTabException(GroupTabFailureKind.notAllowed);
    }
    items.removeWhere((t) => t.id == tabId);
  }

  @override
  Future<void> reorder(String conversationId, List<String> tabIds) async {
    calls.add('reorder');
    final order = {for (final (i, id) in tabIds.indexed) id: i};
    items.sort((a, b) => (order[a.id] ?? 1000).compareTo(order[b.id] ?? 1000));
  }

  @override
  Future<List<GroupTabCandidate>> candidates(
    String conversationId,
    String kind,
  ) async => candidatesByKind[kind] ?? const [];
}

GroupTab sampleTab(
  String id,
  String kind,
  String title, {
  String? target,
  String? icon,
  bool available = true,
  bool closed = false,
  String? circleId,
}) => GroupTab(
  id: id,
  kind: kind,
  title: title,
  target: target,
  icon: icon,
  available: available,
  closed: closed,
  circleId: circleId,
);

List<Override> groupTabsOverrides(FakeGroupTabsRepository repository) => [
  groupTabsRepositoryProvider.overrideWithValue(repository),
];
