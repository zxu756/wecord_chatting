import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_channel_settings_screen.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/config/app_config.dart';
import 'package:wecord/shared/models/channel_webhook.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/profile.dart';

import 'circle_detail_screen_test.dart' as circle_fakes;

void main() {
  test('builds the webhook URL from the Supabase URL', () {
    final secret = ChannelWebhookSecret(
      webhook: ChannelWebhook(
        id: 'webhook-1',
        channelId: 'channel-1',
        name: 'CI',
        createdAt: DateTime.utc(2026, 10, 13),
      ),
      token: 'secret-token',
    );
    expect(
      secret.urlFor(Uri.parse('https://abc.supabase.co/')),
      'https://abc.supabase.co/functions/v1/webhook/webhook-1/secret-token',
    );
    final parsed = ChannelWebhook.fromJson({
      'id': 'webhook-1',
      'channel_id': 'channel-1',
      'name': 'CI',
      'created_by': 'user-1',
      'creator_name': 'Xu',
      'created_at': '2026-10-13T09:00:00Z',
      'last_used_at': null,
    });
    expect(parsed.creatorName, 'Xu');
    expect(parsed.lastUsedAt, isNull);
  });

  testWidgets('lists webhooks with their creator and last use', (tester) async {
    final world = _World()
      ..circles.webhooks = [
        ChannelWebhook(
          id: 'webhook-1',
          channelId: 'channel-1',
          name: 'Deploy bot',
          creatorName: 'Xu',
          createdAt: DateTime.utc(2026, 10, 1),
          lastUsedAt: DateTime.now().toUtc().subtract(
            const Duration(minutes: 5),
          ),
        ),
        ChannelWebhook(
          id: 'webhook-2',
          channelId: 'channel-1',
          name: 'Alerts',
          createdAt: DateTime.utc(2026, 10, 1),
        ),
      ];
    await tester.pumpWidget(world.app());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('webhook-create-button')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Integrations'), findsOneWidget);
    expect(find.text('Deploy bot'), findsOneWidget);
    expect(find.text('Created by Xu · Last used 5m ago'), findsOneWidget);
    expect(find.text('Never used'), findsOneWidget);
  });

  testWidgets('creating shows the URL once with a copy button', (tester) async {
    final world = _World();
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(world.app());
    await tester.pumpAndSettle();

    final create = find.byKey(const ValueKey('webhook-create-button'));
    await tester.scrollUntilVisible(
      create,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // Sections above load as they scroll into view; settle, then bring
    // the target back on screen.
    await tester.pumpAndSettle();
    await tester.ensureVisible(create);
    await tester.pumpAndSettle();
    expect(find.text('No webhooks yet.'), findsOneWidget);
    await tester.tap(create);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('webhook-name-field')),
      ' Deploy bot ',
    );
    await tester.tap(find.byKey(const ValueKey('webhook-name-submit')));
    await tester.pumpAndSettle();

    expect(world.circles.webhookCalls, ['create:channel-1:Deploy bot']);
    expect(find.text('Webhook created'), findsOneWidget);
    expect(find.textContaining('shown only once'), findsOneWidget);
    final url = tester
        .widget<SelectableText>(find.byKey(const ValueKey('webhook-url')))
        .data!;
    expect(
      url,
      startsWith(
        'https://project.supabase.co/functions/v1/webhook/created-webhook-1/tok',
      ),
    );
    await tester.tap(find.byKey(const ValueKey('webhook-copy-url')));
    await tester.pump();
    expect(copied, url);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Deploy bot'), findsOneWidget);
  });

  testWidgets('renames, regenerates after confirming and deletes', (
    tester,
  ) async {
    final world = _World()
      ..circles.webhooks = [
        ChannelWebhook(
          id: 'webhook-1',
          channelId: 'channel-1',
          name: 'Deploy bot',
          createdAt: DateTime.utc(2026, 10, 1),
        ),
      ];
    await tester.pumpWidget(world.app());
    await tester.pumpAndSettle();
    final menu = find.byKey(const ValueKey('webhook-menu-webhook-1'));
    await tester.scrollUntilVisible(
      menu,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // Sections above load as they scroll into view; settle, then bring
    // the target back on screen.
    await tester.pumpAndSettle();
    await tester.ensureVisible(menu);
    await tester.pumpAndSettle();

    Future<void> choose(String label) async {
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await choose('Rename');
    await tester.enterText(
      find.byKey(const ValueKey('webhook-name-field')),
      'Release bot',
    );
    await tester.tap(find.byKey(const ValueKey('webhook-name-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Release bot'), findsOneWidget);

    await choose('Regenerate URL');
    expect(find.textContaining('stops working'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(world.circles.webhookCalls, ['rename:webhook-1:Release bot']);

    await choose('Regenerate URL');
    await tester.tap(find.byKey(const ValueKey('webhook-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('New webhook URL'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await choose('Delete');
    await tester.tap(find.byKey(const ValueKey('webhook-confirm')));
    await tester.pumpAndSettle();

    expect(world.circles.webhookCalls, [
      'rename:webhook-1:Release bot',
      'regenerate:webhook-1',
      'delete:webhook-1',
    ]);
    expect(find.text('Release bot'), findsNothing);
  });

  testWidgets('needs manage webhooks and a text channel', (tester) async {
    final member = _World(role: 'member');
    await tester.pumpWidget(member.app());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('channel-integrations')), findsNothing);

    final forum = _World(kind: CircleChannelKind.forum);
    await tester.pumpWidget(forum.app());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('channel-integrations')), findsNothing);
  });

  testWidgets('announcement channels take webhooks too', (tester) async {
    final world = _World(kind: CircleChannelKind.announcement);
    await tester.pumpWidget(world.app());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('webhook-create-button')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Integrations'), findsOneWidget);
  });

  test('only webhook managers may open channel settings for it', () {
    final detail = _detail(
      role: 'member',
      permissions: CirclePermission.maskOf(const [
        CirclePermission.viewChannel,
        CirclePermission.manageWebhooks,
      ]),
    );
    expect(detail.canManageChannels, isFalse);
    expect(detail.canOpenChannelSettings, isTrue);
  });
}

CircleDetail _detail({
  String role = 'owner',
  int? permissions,
  CircleChannelKind kind = CircleChannelKind.text,
}) {
  final owner = Profile(
    id: 'user-1',
    username: 'xu',
    displayName: 'Xu',
    bio: '',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  return CircleDetail(
    circle: CircleSummary(
      id: 'circle-1',
      name: 'Close Friends',
      memberCount: 1,
      channelCount: 1,
      currentUserRole: role,
      currentUserPermissions: permissions,
    ),
    members: [CircleMember(profile: owner, role: role)],
    channels: [
      CircleChannel(
        id: 'channel-1',
        circleId: 'circle-1',
        conversationId: 'conversation-1',
        name: 'general',
        position: 0,
        kind: kind,
      ),
    ],
    posts: const [],
  );
}

class _World {
  _World({
    String role = 'owner',
    CircleChannelKind kind = CircleChannelKind.text,
  }) {
    circles.detail = _detail(role: role, kind: kind);
  }

  final circles = circle_fakes.FakeCirclesRepository();

  Widget app() {
    return ProviderScope(
      overrides: [
        circlesRepositoryProvider.overrideWithValue(circles),
        appConfigProvider.overrideWithValue(
          AppConfig(
            supabaseUrl: Uri.parse('https://project.supabase.co'),
            supabaseAnonKey: 'anon',
          ),
        ),
      ],
      child: const MaterialApp(
        home: CircleChannelSettingsScreen(
          circleId: 'circle-1',
          channelId: 'channel-1',
        ),
      ),
    );
  }
}
