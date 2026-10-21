import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/knowledge_base/kb_models.dart';

import 'kb_fakes.dart';

void main() {
  group('KbPage', () {
    test('reads what kb_list_pages returns', () {
      final page = KbPage.fromJson({
        'id': 'p-1',
        'parent_id': 'p-0',
        'title': 'Rules',
        'icon': '\u{1F4DC}',
        'kb_position': 3,
        'updated_at': '2026-10-27T09:00:00Z',
        'updated_by_name': 'Ada',
        'can_edit': true,
        'restricted': true,
        'required': true,
        'read': true,
      });
      expect(page.parentId, 'p-0');
      expect(page.position, 3);
      expect(
        page.canEdit && page.restricted && page.required && page.read,
        true,
      );
      expect(page.updatedByName, 'Ada');
    });

    test('a page with no icon gets the page icon', () {
      final page = KbPage.fromJson({'id': 'p-1', 'icon': ' '});
      expect(page.icon, KnowledgeBaseLimits.defaultIcon);
      expect(page.title, '');
      expect(page.canEdit, false);
    });
  });

  group('KbTree', () {
    final tree = sampleKbTree();

    test('top-level pages and the pages inside come in order', () {
      expect(
        [for (final p in tree.roots) p.title],
        ['Welcome', 'Rules', 'Resources'],
      );
      expect(
        [for (final p in tree.childrenOf('p-rules')) p.title],
        ['Posting', 'Moderation'],
      );
      expect(tree.hasChildren('p-welcome'), false);
    });

    test('rows are the tree in reading order with their level', () {
      final rows = tree.rows();
      expect(
        [for (final r in rows) '${r.depth}:${r.page.title}'],
        [
          '1:Welcome',
          '1:Rules',
          '2:Posting',
          '2:Moderation',
          '1:Resources',
          '2:Guides',
          '3:Setup',
        ],
      );
      expect(rows[1].hasChildren && rows[1].expanded, true);
      expect(rows[0].hasChildren, false);
    });

    test('a collapsed page hides what is inside it', () {
      final rows = tree.rows(collapsed: {'p-rules', 'p-guides'});
      expect(
        [for (final r in rows) r.page.title],
        ['Welcome', 'Rules', 'Resources', 'Guides'],
      );
      expect(rows[1].expanded, false);
      expect(rows[1].hasChildren, true);
    });

    test('depth, ancestors and what lies below', () {
      expect(tree.depthOf('p-setup'), 3);
      expect(tree.depthOf('p-welcome'), 1);
      expect(
        [for (final p in tree.ancestorsOf('p-setup')) p.title],
        ['Resources', 'Guides'],
      );
      expect(tree.ancestorsOf('p-welcome'), isEmpty);
      expect(tree.heightBelow('p-resources'), 2);
      expect(tree.heightBelow('p-setup'), 0);
      expect(tree.subtreeOf('p-rules'), {
        'p-rules',
        'p-posting',
        'p-moderation',
      });
    });

    test('a page whose parent cannot be read is not in the tree', () {
      final orphaned = KbTree([
        kbPage('a', 'Seen'),
        kbPage('b', 'Hidden child', parent: 'secret'),
      ]);
      expect([for (final r in orphaned.rows()) r.page.title], ['Seen']);
    });

    test('required pages not read yet are counted', () {
      expect(tree.unreadRequired, 1);
      expect(KbTree(const []).isEmpty, true);
      expect(KbTree(const []).first, isNull);
      expect(tree.first?.title, 'Welcome');
    });

    test('equal positions fall back to the id, the same on every device', () {
      final tied = KbTree([
        kbPage('b', 'B', position: 1),
        kbPage('a', 'A', position: 1),
      ]);
      expect([for (final p in tied.roots) p.id], ['a', 'b']);
    });
  });

  group('KbPageAccess', () {
    test('reads the limits and the roles to choose from', () {
      final access = KbPageAccess.fromJson({
        'view_role_ids': ['r-1'],
        'edit_role_ids': <String>[],
        'locked': true,
        'roles': [
          {'id': 'r-1', 'name': 'Staff', 'color': 255},
          {'id': 'r-2', 'name': 'Crew'},
        ],
      });
      expect(access.viewRoleIds, ['r-1']);
      expect(access.locked, true);
      expect(access.isRestricted, true);
      expect(access.roles.map((r) => r.name), ['Staff', 'Crew']);
      expect(access.roles.first.color, 255);
      expect(const KbPageAccess().isRestricted, false);
    });
  });

  test('a search hit reads its snippet', () {
    final hit = KbSearchHit.fromJson({
      'id': 'p-1',
      'title': 'Rules',
      'snippet': 'Be kind.',
    });
    expect(hit.snippet, 'Be kind.');
    expect(hit.icon, KnowledgeBaseLimits.defaultIcon);
  });
}
