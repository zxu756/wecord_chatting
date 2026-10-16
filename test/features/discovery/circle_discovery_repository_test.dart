import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/discovery/circle_discovery_repository.dart';
import 'package:wecord/shared/models/report_reason.dart';

import '../circles/announcement_channels_test.dart' show RecordingRpc;
import 'discovery_fakes.dart';

void main() {
  test(
    'lists a page and asks for one more to know if there are more',
    () async {
      final rpc = RecordingRpc({
        'list_discoverable_circles': (params) => [
          for (var i = 0; i < (params['page_size'] as int); i++)
            discoverableJson('c$i', isMember: i == 0),
        ],
      });
      final repository = CircleDiscoveryRepository(rpc.call);

      final page = await repository.list(
        query: '  pixel  ',
        category: DiscoveryCategory.art,
        sort: DiscoverySort.relevance,
        offset: 24,
        pageSize: 3,
      );

      expect(rpc.calls.single.$2, {
        'search_query': 'pixel',
        'category_filter': 'art',
        'sort_by': 'relevance',
        'page_size': 4,
        'page_offset': 24,
      });
      expect(page.circles, hasLength(3));
      expect(page.hasMore, isTrue);
      final first = page.circles.first;
      expect(first.isMember, isTrue);
      expect(first.category, DiscoveryCategory.gaming);
      expect(first.tags, ['pixel', 'retro']);
      expect(first.memberCount, 10);
      expect(first.onlineCount, 2);
      expect(first.lastActivityAt, DateTime.utc(2026, 10, 15, 10));
    },
  );

  test('a blank query and no category send nulls; short pages end', () async {
    final rpc = RecordingRpc({
      'list_discoverable_circles': (_) => [discoverableJson('only')],
    });
    final page = await CircleDiscoveryRepository(rpc.call).list();
    expect(rpc.calls.single.$2['search_query'], isNull);
    expect(rpc.calls.single.$2['category_filter'], isNull);
    expect(rpc.calls.single.$2['sort_by'], isNull);
    expect(page.hasMore, isFalse);
  });

  test('previews carry rules only when onboarding is on', () async {
    final rpc = RecordingRpc({
      'discoverable_circle_preview': (params) =>
          params['target_circle_id'] == 'with-rules'
          ? previewJson('with-rules')
          : {...previewJson('no-rules'), 'rules_enabled': false},
    });
    final repository = CircleDiscoveryRepository(rpc.call);
    final withRules = await repository.preview('with-rules');
    expect(withRules.rules, ['Be kind', 'No spam']);
    expect(withRules.channels.map((channel) => channel.name), [
      'general',
      'Lounge',
    ]);
    expect(withRules.channels.last.kind, 'voice');
    final noRules = await repository.preview('no-rules');
    expect(noRules.rules, isEmpty);
  });

  test('join failures say why', () async {
    Object? failure;
    final rpc = RecordingRpc({
      'join_public_circle': (params) {
        if (failure != null) {
          throw failure!;
        }
        return params['target_circle_id'];
      },
    });
    final repository = CircleDiscoveryRepository(rpc.call);
    expect(await repository.join('c1'), 'c1');

    Future<DiscoveryJoinProblem> problemFor(Object error) async {
      failure = error;
      try {
        await repository.join('c1');
      } on DiscoveryJoinException catch (exception) {
        return exception.problem;
      }
      fail('Expected a DiscoveryJoinException');
    }

    expect(
      await problemFor(Exception('Banned from this circle (42501)')),
      DiscoveryJoinProblem.banned,
    );
    expect(
      await problemFor(Exception('Too many circles joined (PB429)')),
      DiscoveryJoinProblem.rateLimited,
    );
    expect(
      await problemFor(Exception('Circle not found (P0002)')),
      DiscoveryJoinProblem.notFound,
    );
    expect(await problemFor(Exception('offline')), DiscoveryJoinProblem.other);
  });

  test('settings save trimmed text and normalized tags', () async {
    final rpc = RecordingRpc({
      'set_circle_discovery': (params) => {
        'is_public': params['make_public'],
        'description': params['about'],
        'category': params['category'],
        'language': params['language'],
        'tags': params['tag_list'],
        'listed_at': '2026-10-16T00:00:00Z',
      },
      'get_circle_discovery': (_) => {
        'is_public': false,
        'description': null,
        'category': null,
        'language': null,
        'tags': <String>[],
        'listed_at': null,
      },
    });
    final repository = CircleDiscoveryRepository(rpc.call);
    expect((await repository.settings('c1')).isPublic, isFalse);

    final saved = await repository.saveSettings(
      circleId: 'c1',
      isPublic: true,
      description: '  Pixel art  ',
      category: DiscoveryCategory.art,
      language: 'en',
      tags: ['#Pixel', ' ', 'Retro '],
    );
    expect(rpc.calls.last.$2, {
      'target_circle_id': 'c1',
      'make_public': true,
      'about': 'Pixel art',
      'category': 'art',
      'language': 'en',
      'tag_list': ['pixel', 'retro'],
    });
    expect(saved.isPublic, isTrue);
    expect(saved.category, DiscoveryCategory.art);
    expect(saved.listedAt, isNotNull);
  });

  test('reports send the reason and details', () async {
    final rpc = RecordingRpc({'report_circle': (_) => 'report-1'});
    await CircleDiscoveryRepository(
      rpc.call,
    ).report(circleId: 'c1', reason: ReportReason.spam, details: ' ads ');
    expect(rpc.calls.single.$2, {
      'target_circle_id': 'c1',
      'report_reason': 'spam',
      'report_details': 'ads',
    });
  });

  test('tags follow the server rules', () {
    expect(normalizeDiscoveryTag('  ##Pixel Art '), 'pixel art');
    expect(discoveryTagProblem('rust'), isNull);
    expect(discoveryTagProblem('编程'), isNull);
    expect(discoveryTagProblem('  '), 'empty');
    expect(discoveryTagProblem('a,b'), 'characters');
    expect(discoveryTagProblem('a' * 25), 'length');
    expect(
      DiscoveryCategory.fromJson('science_tech'),
      DiscoveryCategory.scienceTech,
    );
    expect(DiscoveryCategory.fromJson('unknown'), isNull);
    expect(DiscoveryCategory.values, hasLength(11));
  });
}
