import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/circles/circle_template_repository.dart';
import 'package:wecord/features/circles/circle_template_widgets.dart';
import 'package:wecord/shared/models/circle.dart';

import 'announcement_channels_test.dart' show RecordingRpc;

Map<String, dynamic> _templateJson({bool outline = false}) => {
  'id': 'template-1',
  'circle_id': 'circle-1',
  'circle_name': 'Study Hall',
  'code': 'abcd23efgh',
  'name': 'Study group',
  'description': 'Channels for a class',
  'creator_name': 'Ann',
  'created_at': '2026-10-16T08:00:00Z',
  'updated_at': '2026-10-16T09:00:00Z',
  'usage_count': 4,
  'role_count': 1,
  'category_count': 1,
  'channel_count': 3,
  if (outline) ...{
    'categories': [
      {'key': 'cat-1', 'name': 'Classes', 'position': 0},
    ],
    'channels': [
      {'name': 'welcome', 'kind': 'announcement', 'category_key': null},
      {'name': 'homework', 'kind': 'forum', 'category_key': 'cat-1'},
      {'name': 'Study room', 'kind': 'voice', 'category_key': 'cat-1'},
    ],
    'roles': [
      {'name': 'Tutors', 'color': 3447003},
    ],
  },
};

Widget _app(RecordingRpc rpc, Widget child) {
  return ProviderScope(
    overrides: [circleRpcProvider.overrideWithValue(rpc.call)],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  test('template codes come from codes and links', () {
    expect(parseCircleTemplateCode('abcd23efgh'), 'abcd23efgh');
    expect(parseCircleTemplateCode(' ABCD23EFGH '), 'abcd23efgh');
    expect(
      parseCircleTemplateCode('https://example.com/template/abcd23efgh'),
      'abcd23efgh',
    );
    expect(parseCircleTemplateCode('short'), isNull);
  });

  test('templates parse with and without their outline', () {
    final plain = CircleTemplate.fromJson(_templateJson());
    expect(plain.code, 'abcd23efgh');
    expect(plain.usageCount, 4);
    expect(plain.channels, isEmpty);

    final preview = CircleTemplate.fromJson(_templateJson(outline: true));
    expect(preview.channels.first.kind, CircleChannelKind.announcement);
    expect(preview.channels[1].categoryKey, 'cat-1');
    expect(preview.roles.single.color, 3447003);
  });

  test('the repository calls the template functions', () async {
    final rpc = RecordingRpc({
      'get_circle_template': (_) => null,
      'create_circle_template': (_) => _templateJson(),
      'sync_circle_template': (_) => _templateJson(),
      'delete_circle_template': (_) => null,
      'preview_circle_template': (_) => _templateJson(outline: true),
      'create_circle_from_template': (_) => 'circle-2',
    });
    final repository = CircleTemplateRepository(rpc.call);

    expect(await repository.getTemplate('circle-1'), isNull);
    await repository.createTemplate(
      circleId: 'circle-1',
      name: ' Study group ',
      description: 'Channels',
    );
    await repository.syncTemplate('template-1');
    await repository.deleteTemplate('template-1');
    await repository.previewTemplate('abcd23efgh');
    final circleId = await repository.createCircleFromTemplate(
      code: 'abcd23efgh',
      name: 'Mine',
    );

    expect(circleId, 'circle-2');
    expect(rpc.calls[1].$2, {
      'target_circle_id': 'circle-1',
      'template_name': 'Study group',
      'template_description': 'Channels',
    });
    expect(rpc.calls.last.$2, {
      'template_code': 'abcd23efgh',
      'circle_name': 'Mine',
    });
  });

  testWidgets('managers create, sync and delete the template', (tester) async {
    Map<String, dynamic>? stored;
    final rpc = RecordingRpc({
      'get_circle_template': (_) => stored,
      'create_circle_template': (params) {
        stored = _templateJson()..['name'] = params['template_name'];
        return stored;
      },
      'sync_circle_template': (_) => stored,
      'delete_circle_template': (_) {
        stored = null;
        return null;
      },
    });
    await tester.pumpWidget(
      _app(
        rpc,
        const SingleChildScrollView(
          child: CircleTemplateSection(circleId: 'circle-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('template-create-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('template-name-field')),
      'Study group',
    );
    await tester.tap(find.byKey(const ValueKey('template-details-submit')));
    await tester.pumpAndSettle();

    expect(find.text('abcd23efgh'), findsOneWidget);
    expect(
      find.textContaining('3 channels · 1 roles · used 4 times'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('template-sync-button')));
    await tester.pumpAndSettle();
    expect(find.text('Template synced with the circle.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('template-delete-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('template-delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('template-create-button')), findsOne);
    expect(
      rpc.calls.map((call) => call.$1),
      contains('delete_circle_template'),
    );
  });

  testWidgets('a code previews the layout and creates the circle', (
    tester,
  ) async {
    final rpc = RecordingRpc({
      'preview_circle_template': (params) =>
          params['template_code'] == 'abcd23efgh'
          ? _templateJson(outline: true)
          : throw StateError('not found'),
      'create_circle_from_template': (_) => 'circle-2',
    });
    String? created;
    await tester.pumpWidget(
      _app(
        rpc,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                created = await showUseCircleTemplateSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('template-code-field')),
      'zzzz00zzzz',
    );
    await tester.tap(find.byKey(const ValueKey('template-preview-button')));
    await tester.pumpAndSettle();
    expect(find.text('No template has this code.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('template-code-field')),
      'ABCD23EFGH',
    );
    await tester.tap(find.byKey(const ValueKey('template-preview-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('template-preview')), findsOneWidget);
    expect(find.text('From Study Hall'), findsOneWidget);
    expect(find.text('Classes'), findsOneWidget);
    expect(find.text('homework'), findsOneWidget);
    expect(find.text('Tutors'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('template-circle-name-field')),
      'Our class',
    );
    await tester.tap(
      find.byKey(const ValueKey('template-create-circle-button')),
    );
    await tester.pumpAndSettle();

    expect(created, 'circle-2');
    expect(rpc.calls.last.$2, {
      'template_code': 'abcd23efgh',
      'circle_name': 'Our class',
    });
  });
}
