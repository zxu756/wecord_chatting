import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/circles/circle_tag_repository.dart';
import 'package:wecord/features/circles/circle_tag_widgets.dart';

import 'announcement_channels_test.dart' show RecordingRpc;

Widget _app(RecordingRpc rpc, Widget child) {
  return ProviderScope(
    overrides: [circleRpcProvider.overrideWithValue(rpc.call)],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  test('tags are 2 to 4 letters or digits', () {
    expect(circleTagProblem(''), isNull);
    expect(circleTagProblem('GG'), isNull);
    expect(circleTagProblem('中文'), isNull);
    expect(circleTagProblem('ABCD'), isNull);
    expect(circleTagProblem('A'), 'length');
    expect(circleTagProblem('ABCDE'), 'length');
    expect(circleTagProblem('A B'), 'characters');
    expect(circleTagProblem('A-B'), 'characters');
    expect(CircleTagBadge.fromJson('gem'), CircleTagBadge.gem);
    expect(CircleTagBadge.fromJson('unknown'), CircleTagBadge.star);
    expect(CircleTag.maybeFromJson({'tag': null, 'badge': null}), isNull);
  });

  test('badges of names shown together load with one call', () async {
    final rpc = RecordingRpc({
      'list_profile_badges': (params) => [
        for (final id in params['user_ids'] as List<String>)
          {
            'user_id': id,
            'tag': id == 'a' ? 'GG' : null,
            'badge': id == 'a' ? 'bolt' : null,
            'circle_id': id == 'a' ? 'circle-1' : null,
            'circle_name': id == 'a' ? 'Gamers' : null,
          },
      ],
    });
    final loader = ProfileBadgeLoader(rpc.call);
    final results = await Future.wait([
      loader.load('a'),
      loader.load('b'),
      loader.load('a'),
    ]);

    expect(rpc.calls, hasLength(1));
    expect(rpc.calls.single.$2['user_ids'], ['a', 'b']);
    expect(results.first.tag?.text, 'GG');
    expect(results.first.tag?.badge, CircleTagBadge.bolt);
    expect(results.first.tagCircleName, 'Gamers');
    expect(results[1].isEmpty, isTrue);

    // Cached until forgotten.
    await loader.load('a');
    expect(rpc.calls, hasLength(1));
    loader.forget('a');
    await loader.load('a');
    expect(rpc.calls, hasLength(2));
  });

  test('failed loads show nothing and try again later', () async {
    var fail = true;
    final rpc = RecordingRpc({
      'list_profile_badges': (_) {
        if (fail) {
          throw StateError('offline');
        }
        return [
          {'user_id': 'a', 'tag': 'GG', 'badge': 'star'},
        ];
      },
    });
    final loader = ProfileBadgeLoader(rpc.call);
    expect((await loader.load('a')).isEmpty, isTrue);
    fail = false;
    expect((await loader.load('a')).tag?.text, 'GG');
  });

  testWidgets('names show the tag their user chose', (tester) async {
    final rpc = RecordingRpc({
      'list_profile_badges': (_) => [
        {
          'user_id': 'a',
          'tag': 'GG',
          'badge': 'bolt',
          'circle_id': 'c',
          'circle_name': 'Gamers',
        },
      ],
    });
    await tester.pumpWidget(
      _app(
        rpc,
        const Row(
          children: [
            Text('Ann'),
            ProfileNameBadges(userId: 'a'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('GG'), findsOneWidget);
    expect(find.byIcon(Icons.bolt), findsOneWidget);
  });

  testWidgets('circle settings save and turn off the tag', (tester) async {
    Map<String, dynamic> stored = {'tag': null, 'badge': null};
    final rpc = RecordingRpc({
      'get_circle_tag': (_) => stored,
      'set_circle_tag': (params) {
        final text = params['circle_tag'] as String;
        stored = text.isEmpty
            ? {'tag': null, 'badge': null}
            : {'tag': text, 'badge': params['badge']};
        return stored;
      },
    });
    await tester.pumpWidget(
      _app(
        rpc,
        const SingleChildScrollView(
          child: CircleTagSection(circleId: 'circle-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('circle-tag-field')),
      'A B',
    );
    await tester.tap(find.byKey(const ValueKey('circle-tag-save')));
    await tester.pumpAndSettle();
    expect(find.text('Use letters and digits only.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('circle-tag-field')),
      'GG',
    );
    await tester.tap(find.byKey(const ValueKey('circle-tag-badge-heart')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('circle-tag-save')));
    await tester.pumpAndSettle();

    expect(rpc.calls.last.$2, {
      'target_circle_id': 'circle-1',
      'circle_tag': 'GG',
      'badge': 'heart',
    });
    expect(find.text('Circle tag saved.'), findsOneWidget);
  });
}
