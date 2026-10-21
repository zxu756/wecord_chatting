import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/knowledge_base/kb_models.dart';
import 'package:wecord/features/knowledge_base/kb_repository.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/notes_repository.dart';

import '../../mobile/phone_test_support.dart';
import '../workspace/workspace_fakes.dart';

/// A page of the sample knowledge base: [parent] and [position] place it.
KbPage kbPage(
  String id,
  String title, {
  String? parent,
  int position = 1,
  String icon = '\u{1F4C4}',
  bool canEdit = false,
  bool restricted = false,
  bool required = false,
  bool read = false,
  String? by,
}) => KbPage(
  id: id,
  parentId: parent,
  title: title,
  icon: icon,
  position: position,
  updatedAt: DateTime(2026, 10, 27, 9),
  updatedByName: by,
  canEdit: canEdit,
  restricted: restricted,
  required: required,
  read: read,
);

/// The circle's pages used by the screens and tests:
///
///   Welcome (required, read)
///   Rules (required)
///     Posting (limited)
///     Moderation
///   Resources
///     Guides
///       Setup
KbTree sampleKbTree({bool canEdit = true}) => KbTree(sampleKbPages(canEdit));

List<KbPage> sampleKbPages([bool canEdit = true]) => [
  kbPage(
    'p-welcome',
    'Welcome',
    icon: '\u{1F44B}',
    position: 1,
    required: true,
    read: true,
    canEdit: canEdit,
    by: 'Ada Lovelace',
  ),
  kbPage(
    'p-rules',
    'Rules',
    icon: '\u{1F4DC}',
    position: 2,
    required: true,
    canEdit: canEdit,
  ),
  kbPage(
    'p-posting',
    'Posting',
    parent: 'p-rules',
    position: 1,
    restricted: true,
    canEdit: canEdit,
  ),
  kbPage(
    'p-moderation',
    'Moderation',
    parent: 'p-rules',
    position: 2,
    canEdit: canEdit,
  ),
  kbPage(
    'p-resources',
    'Resources',
    icon: '\u{1F4DA}',
    position: 3,
    canEdit: canEdit,
  ),
  kbPage(
    'p-guides',
    'Guides',
    parent: 'p-resources',
    position: 1,
    canEdit: canEdit,
  ),
  kbPage('p-setup', 'Setup', parent: 'p-guides', position: 1, canEdit: canEdit),
];

/// The knowledge base calls in memory. Moves, deletes and creates change the
/// pages the way the database functions do, so the screen shows the result.
class FakeKnowledgeBaseRepository implements KnowledgeBaseRepository {
  FakeKnowledgeBaseRepository({List<KbPage>? pages})
    : pages = pages ?? sampleKbPages();

  List<KbPage> pages;
  KbPageAccess access = const KbPageAccess(
    roles: [
      KbRole(id: 'role-mod', name: 'Moderators', color: 0x3366FF),
      KbRole(id: 'role-crew', name: 'Crew'),
    ],
  );
  List<KbSearchHit> hits = const [];
  final changesController = StreamController<void>.broadcast();

  /// Every call, as `name:argument`, for assertions.
  final calls = <String>[];

  /// What the last setAccess received.
  KbAccessCall? lastAccess;
  Object? failWith;
  var loadsFail = false;
  var _next = 0;

  void _maybeFail() {
    final error = failWith;
    if (error != null) {
      throw error;
    }
  }

  List<Override> get overrides => [
    knowledgeBaseRepositoryProvider.overrideWithValue(this),
  ];

  @override
  Future<List<KbPage>> listPages(String circleId) async {
    calls.add('list:$circleId');
    if (loadsFail) {
      throw StateError('offline');
    }
    return [...pages];
  }

  @override
  Future<NoteMeta> createPage(
    String circleId, {
    String? parentId,
    String title = '',
    String? icon,
    String? id,
  }) async {
    _maybeFail();
    final newId = id ?? 'p-new-${_next++}';
    calls.add('create:${parentId ?? 'top'}:$title');
    final siblings = pages.where((p) => p.parentId == parentId).length;
    pages = [
      ...pages,
      kbPage(
        newId,
        title,
        parent: parentId,
        position: siblings + 1,
        canEdit: true,
      ),
    ];
    return NoteMeta(
      id: newId,
      conversationId: '',
      title: title,
      icon: icon ?? KnowledgeBaseLimits.defaultIcon,
      canEdit: true,
      canManage: true,
      circleId: circleId,
      parentId: parentId,
    );
  }

  @override
  Future<void> movePage(
    String pageId, {
    String? parentId,
    String? beforeId,
  }) async {
    _maybeFail();
    calls.add('move:$pageId:${parentId ?? 'top'}:${beforeId ?? 'last'}');
    final moved = pages.firstWhere((p) => p.id == pageId);
    final siblings = [
      for (final p in pages)
        if (p.parentId == parentId && p.id != pageId) p,
    ]..sort((a, b) => a.position.compareTo(b.position));
    final at = beforeId == null
        ? siblings.length
        : siblings.indexWhere((p) => p.id == beforeId);
    final order = [...siblings];
    order.insert(at < 0 ? order.length : at, moved);
    pages = [
      for (final p in pages)
        if (p.id == pageId)
          KbPage(
            id: p.id,
            parentId: parentId,
            title: p.title,
            icon: p.icon,
            position: order.indexWhere((o) => o.id == p.id) + 1,
            canEdit: p.canEdit,
            restricted: p.restricted,
            required: p.required,
            read: p.read,
          )
        else if (p.parentId == parentId)
          KbPage(
            id: p.id,
            parentId: p.parentId,
            title: p.title,
            icon: p.icon,
            position: order.indexWhere((o) => o.id == p.id) + 1,
            canEdit: p.canEdit,
            restricted: p.restricted,
            required: p.required,
            read: p.read,
          )
        else
          p,
    ];
  }

  @override
  Future<void> deletePage(String pageId) async {
    _maybeFail();
    calls.add('delete:$pageId');
    final gone = pages.firstWhere((p) => p.id == pageId);
    pages = [
      for (final p in pages)
        if (p.id != pageId)
          p.parentId == pageId
              ? p.copyWith(
                  parentId: gone.parentId,
                  clearParent: gone.parentId == null,
                )
              : p,
    ];
  }

  @override
  Future<KbPageAccess> getAccess(String pageId) async {
    _maybeFail();
    calls.add('access:$pageId');
    return access;
  }

  @override
  Future<void> setAccess(
    String pageId, {
    required List<String> viewRoleIds,
    required List<String> editRoleIds,
  }) async {
    _maybeFail();
    calls.add('set-access:$pageId');
    lastAccess = KbAccessCall(pageId, viewRoleIds, editRoleIds);
  }

  @override
  Future<void> markRead(String pageId) async {
    calls.add('read:$pageId');
    pages = [
      for (final p in pages) p.id == pageId ? p.copyWith(read: true) : p,
    ];
  }

  @override
  Future<List<KbSearchHit>> search(String circleId, String query) async {
    calls.add('search:$query');
    return hits;
  }

  @override
  Stream<void> changes(String circleId) => changesController.stream;
}

class KbAccessCall {
  const KbAccessCall(this.pageId, this.viewRoleIds, this.editRoleIds);

  final String pageId;
  final List<String> viewRoleIds;
  final List<String> editRoleIds;
}

/// The phone test world with a knowledge base in it: the sample pages, a
/// notes repository that opens any page, and the signed-in person as the
/// owner of "circle-1" (a manager) unless [manager] is false.
class KbWorld {
  KbWorld({PhoneWorld? world, bool manager = true})
    : world = world ?? PhoneWorld() {
    SharedPreferences.setMockInitialValues({});
    if (!manager) {
      this.world.circles.detail = circleDetailWith(
        channelId: 'ch-general',
        permissions: 1 | 2,
      );
      knowledge.pages = sampleKbPages(false);
    }
    notes
      ..meta = NoteMeta(
        id: 'p-welcome',
        conversationId: '',
        circleId: 'circle-1',
        title: 'Welcome',
        icon: '\u{1F44B}',
        canEdit: manager,
        canManage: manager,
      )
      ..server.blocks.addAll({
        'blk-1': const NoteBlock(
          id: 'blk-1',
          pos: 'a',
          kind: NoteBlockKind.heading2,
          text: 'Start here',
          rev: 1,
        ),
        'blk-2': const NoteBlock(
          id: 'blk-2',
          pos: 'b',
          text: 'Say hello in the welcome channel, then read the rules.',
          rev: 1,
        ),
      });
  }

  final PhoneWorld world;
  final knowledge = FakeKnowledgeBaseRepository();
  final notes = FakeNotesRepository();

  List<Override> get overrides => [
    ...knowledge.overrides,
    notesRepositoryProvider.overrideWithValue(notes),
  ];

  /// Applies the overrides to [world] (call before opening anything).
  void install() {
    world.extraOverrides = [...world.extraOverrides, ...overrides];
  }
}
