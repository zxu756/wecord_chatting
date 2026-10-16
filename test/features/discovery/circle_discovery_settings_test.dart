import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/discovery/circle_discovery_settings_screen.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../circles/announcement_channels_test.dart' show RecordingRpc;

const _detail = CircleDetail(
  circle: CircleSummary(
    id: 'circle-1',
    name: 'Pixel Painters',
    memberCount: 3,
    channelCount: 2,
    currentUserRole: 'owner',
  ),
  members: [],
  channels: [],
  posts: [],
);

void main() {
  testWidgets('making a circle public needs a category, then saves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rpc = RecordingRpc({
      'get_circle_discovery': (_) => {
        'is_public': false,
        'description': null,
        'category': null,
        'language': null,
        'tags': <String>['old'],
        'listed_at': null,
      },
      'set_circle_discovery': (params) => {
        'is_public': params['make_public'],
        'description': params['about'],
        'category': params['category'],
        'language': params['language'],
        'tags': params['tag_list'],
        'listed_at': '2026-10-16T00:00:00Z',
      },
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [circleRpcProvider.overrideWithValue(rpc.call)],
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      openCircleDiscoverySettings(context, _detail),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Discovery'), findsOneWidget);
    expect(find.text('#old'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('discovery-public')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('discovery-settings-save')));
    await tester.pumpAndSettle();
    expect(
      find.text('Pick a category to make the circle public.'),
      findsOneWidget,
    );
    expect(rpc.calls.any((call) => call.$1 == 'set_circle_discovery'), isFalse);

    await tester.enterText(
      find.byKey(const ValueKey('discovery-description')),
      'Share pixel art and get friendly critique.',
    );
    await tester.tap(find.byKey(const ValueKey('discovery-settings-art')));
    await tester.tap(find.byKey(const ValueKey('discovery-language-zh')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('discovery-tag-field')),
      'a,b',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('discovery-tag-add')));
    await tester.pump();
    expect(find.text('Tags cannot have commas or #.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('discovery-tag-field')),
      '#Pixel Art',
    );
    await tester.tap(find.byKey(const ValueKey('discovery-tag-add')));
    await tester.pump();
    // Removing a tag.
    await tester.tap(find.byKey(const ValueKey('discovery-tag-old')));
    await tester.pump();
    // The preview card follows the edits.
    expect(
      find.text('Share pixel art and get friendly critique.'),
      findsNWidgets(2),
    );
    expect(find.text('#pixel art'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('discovery-settings-save')));
    await tester.pumpAndSettle();

    expect(
      rpc.calls.where((call) => call.$1 == 'set_circle_discovery').single.$2,
      {
        'target_circle_id': 'circle-1',
        'make_public': true,
        'about': 'Share pixel art and get friendly critique.',
        'category': 'art',
        'language': 'zh',
        'tag_list': ['pixel art'],
      },
    );
    expect(find.text('Your circle is now listed in Explore.'), findsOneWidget);
    // Back on the page it was opened from.
    expect(find.text('open'), findsOneWidget);
  });
}
