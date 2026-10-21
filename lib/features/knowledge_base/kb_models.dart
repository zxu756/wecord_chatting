import 'package:flutter/foundation.dart';

/// Limits the server enforces (see `202610270100_kb_schema.sql` and
/// `202610270110_kb_rpcs.sql`).
abstract final class KnowledgeBaseLimits {
  static const pages = 500;
  static const depth = 5;
  static const pagesBelowOne = 100;
  static const rolesPerSetting = 10;
  static const titleLength = 200;

  /// The icon of a new page.
  static const defaultIcon = '\u{1F4C4}';
}

/// One page in the list of a circle's knowledge base (`kb_list_pages`).
@immutable
class KbPage {
  const KbPage({
    required this.id,
    required this.title,
    this.parentId,
    this.icon = KnowledgeBaseLimits.defaultIcon,
    this.position = 0,
    this.updatedAt,
    this.updatedByName,
    this.canEdit = false,
    this.restricted = false,
    this.required = false,
    this.read = false,
  });

  factory KbPage.fromJson(Map<String, dynamic> json) {
    return KbPage(
      id: json['id'] as String,
      parentId: json['parent_id'] as String?,
      title: json['title'] as String? ?? '',
      icon: (json['icon'] as String?)?.trim().isNotEmpty == true
          ? json['icon'] as String
          : KnowledgeBaseLimits.defaultIcon,
      position: (json['kb_position'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse('${json['updated_at']}'),
      updatedByName: json['updated_by_name'] as String?,
      canEdit: json['can_edit'] == true,
      restricted: json['restricted'] == true,
      required: json['required'] == true,
      read: json['read'] == true,
    );
  }

  final String id;
  final String? parentId;
  final String title;
  final String icon;
  final int position;
  final DateTime? updatedAt;
  final String? updatedByName;

  /// The caller may change the words of the page, and add pages below it.
  final bool canEdit;

  /// Reading or editing is limited to some roles.
  final bool restricted;

  /// The newcomer guide asks members to read it.
  final bool required;

  /// The caller has opened it.
  final bool read;

  KbPage copyWith({
    String? title,
    String? icon,
    String? parentId,
    bool clearParent = false,
    bool? read,
  }) {
    return KbPage(
      id: id,
      parentId: clearParent ? null : parentId ?? this.parentId,
      title: title ?? this.title,
      icon: icon ?? this.icon,
      position: position,
      updatedAt: updatedAt,
      updatedByName: updatedByName,
      canEdit: canEdit,
      restricted: restricted,
      required: required,
      read: read ?? this.read,
    );
  }
}

/// The pages of a circle as a tree. Pages whose parent is not in the list
/// (the caller cannot read it) are not shown: a limited section hides what
/// is in it.
@immutable
class KbTree {
  KbTree(Iterable<KbPage> pages) : pages = List.unmodifiable(pages) {
    for (final page in this.pages) {
      _byId[page.id] = page;
    }
    for (final page in this.pages) {
      final parent = page.parentId;
      if (parent == null) {
        _children.putIfAbsent(null, () => []).add(page);
      } else if (_byId.containsKey(parent)) {
        _children.putIfAbsent(parent, () => []).add(page);
      }
    }
    for (final siblings in _children.values) {
      siblings.sort((a, b) {
        final byPosition = a.position.compareTo(b.position);
        return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
      });
    }
  }

  final List<KbPage> pages;
  final Map<String, KbPage> _byId = {};
  final Map<String?, List<KbPage>> _children = {};

  bool get isEmpty => pages.isEmpty;

  KbPage? page(String? id) => id == null ? null : _byId[id];

  List<KbPage> get roots => _children[null] ?? const [];

  List<KbPage> childrenOf(String id) => _children[id] ?? const [];

  bool hasChildren(String id) => childrenOf(id).isNotEmpty;

  /// The pages above [id], the top one first (not [id] itself).
  List<KbPage> ancestorsOf(String id) {
    final result = <KbPage>[];
    var current = _byId[id]?.parentId;
    var guard = 0;
    while (current != null && guard < 12) {
      final parent = _byId[current];
      if (parent == null) {
        break;
      }
      result.insert(0, parent);
      current = parent.parentId;
      guard++;
    }
    return result;
  }

  /// 1 for a top-level page.
  int depthOf(String id) => ancestorsOf(id).length + 1;

  /// How many levels lie below [id] (0 for a page with no pages inside).
  int heightBelow(String id) {
    var deepest = 0;
    void visit(String page, int level) {
      deepest = level > deepest ? level : deepest;
      if (level > 12) {
        return;
      }
      for (final child in childrenOf(page)) {
        visit(child.id, level + 1);
      }
    }

    visit(id, 0);
    return deepest;
  }

  /// [id] and every page inside it.
  Set<String> subtreeOf(String id) {
    final ids = <String>{};
    void visit(String page) {
      if (!ids.add(page)) {
        return;
      }
      for (final child in childrenOf(page)) {
        visit(child.id);
      }
    }

    visit(id);
    return ids;
  }

  /// The rows of the list: pages in order, with the level they are on.
  /// Pages inside a collapsed page are left out.
  List<KbRow> rows({Set<String> collapsed = const {}}) {
    final rows = <KbRow>[];
    void visit(KbPage page, int depth) {
      final children = childrenOf(page.id);
      final isCollapsed = collapsed.contains(page.id);
      rows.add(
        KbRow(
          page: page,
          depth: depth,
          hasChildren: children.isNotEmpty,
          expanded: children.isNotEmpty && !isCollapsed,
        ),
      );
      if (!isCollapsed) {
        for (final child in children) {
          visit(child, depth + 1);
        }
      }
    }

    for (final root in roots) {
      visit(root, 1);
    }
    return rows;
  }

  /// The first page of the tree, in reading order.
  KbPage? get first => rows().firstOrNull?.page;

  /// Pages that are required reading and not read yet.
  int get unreadRequired => pages.where((p) => p.required && !p.read).length;
}

/// A row of the tree list.
@immutable
class KbRow {
  const KbRow({
    required this.page,
    required this.depth,
    required this.hasChildren,
    required this.expanded,
  });

  final KbPage page;

  /// 1 for a top-level page.
  final int depth;
  final bool hasChildren;
  final bool expanded;
}

/// A role to choose in the access settings of a page.
@immutable
class KbRole {
  const KbRole({required this.id, required this.name, this.color});

  factory KbRole.fromJson(Map<String, dynamic> json) => KbRole(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    color: (json['color'] as num?)?.toInt(),
  );

  final String id;
  final String name;

  /// 0xRRGGBB, or null.
  final int? color;
}

/// Who may read and edit a page (`kb_get_page_access`).
@immutable
class KbPageAccess {
  const KbPageAccess({
    this.viewRoleIds = const [],
    this.editRoleIds = const [],
    this.locked = false,
    this.roles = const [],
  });

  factory KbPageAccess.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? value) => [
      if (value is List)
        for (final item in value)
          if (item is String) item,
    ];
    return KbPageAccess(
      viewRoleIds: strings(json['view_role_ids']),
      editRoleIds: strings(json['edit_role_ids']),
      locked: json['locked'] == true,
      roles: [
        if (json['roles'] is List)
          for (final role in json['roles'] as List)
            if (role is Map) KbRole.fromJson(Map<String, dynamic>.from(role)),
      ],
    );
  }

  /// Empty: every member of the circle may read it.
  final List<String> viewRoleIds;

  /// Besides the people who manage channels. Empty: only them.
  final List<String> editRoleIds;

  /// A higher role limited the page: it can be looked at, not changed.
  final bool locked;

  /// The roles of the circle, highest first (not @everyone).
  final List<KbRole> roles;

  bool get isRestricted => viewRoleIds.isNotEmpty || editRoleIds.isNotEmpty;
}

/// One result of searching a circle's pages.
@immutable
class KbSearchHit {
  const KbSearchHit({
    required this.id,
    required this.title,
    this.parentId,
    this.icon = KnowledgeBaseLimits.defaultIcon,
    this.snippet = '',
  });

  factory KbSearchHit.fromJson(Map<String, dynamic> json) => KbSearchHit(
    id: json['id'] as String,
    parentId: json['parent_id'] as String?,
    title: json['title'] as String? ?? '',
    icon: (json['icon'] as String?)?.trim().isNotEmpty == true
        ? json['icon'] as String
        : KnowledgeBaseLimits.defaultIcon,
    snippet: json['snippet'] as String? ?? '',
  );

  final String id;
  final String? parentId;
  final String title;
  final String icon;
  final String snippet;
}
