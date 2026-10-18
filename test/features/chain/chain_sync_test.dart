import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chain/chain_models.dart';
import 'package:wecord/features/chain/chain_repository.dart';
import 'package:wecord/features/chain/chain_sync.dart';

Map<String, dynamic> _chainJson(String id, {String conversation = 'c1'}) => {
  'id': id,
  'conversation_id': conversation,
  'title': 'Chain $id',
  'created_by': 'user-2',
  'entries': <Object?>[],
};

void main() {
  group('ChainReadBatcher', () {
    test('chains asked for together are read with one request', () {
      fakeAsync((async) {
        final asked = <List<String>>[];
        final batcher = ChainReadBatcher<String>((ids) async {
          asked.add(ids);
          return {for (final id in ids) id: 'chain $id'};
        });
        final answers = <String>[];
        for (var i = 0; i < 40; i++) {
          unawaited(batcher.read('c$i').then(answers.add));
        }
        async.elapse(const Duration(milliseconds: 100));
        expect(asked, hasLength(1));
        expect(asked.single, hasLength(40));
        expect(answers, hasLength(40));
        expect(answers.first, 'chain c0');
      });
    });

    test('the same chain asked twice is read once, both get the answer', () {
      fakeAsync((async) {
        final asked = <List<String>>[];
        final batcher = ChainReadBatcher<String>((ids) async {
          asked.add(ids);
          return {for (final id in ids) id: 'chain $id'};
        });
        final answers = <String>[];
        unawaited(batcher.read('c1').then(answers.add));
        unawaited(batcher.read('c1').then(answers.add));
        async.elapse(const Duration(milliseconds: 100));
        expect(asked.single, ['c1']);
        expect(answers, ['chain c1', 'chain c1']);
      });
    });

    test('a big crowd is split into requests of at most 50', () {
      fakeAsync((async) {
        final sizes = <int>[];
        final batcher = ChainReadBatcher<String>((ids) async {
          sizes.add(ids.length);
          return {for (final id in ids) id: id};
        });
        for (var i = 0; i < 120; i++) {
          unawaited(batcher.read('c$i'));
        }
        async.elapse(const Duration(milliseconds: 100));
        expect(sizes..sort(), [20, 50, 50]);
      });
    });

    test('a chain missing from the answer is not available; a failed '
        'request fails everyone in it', () {
      fakeAsync((async) {
        var fail = false;
        final batcher = ChainReadBatcher<String>((ids) async {
          if (fail) {
            throw StateError('offline');
          }
          return {'c1': 'one'};
        });
        Object? missing;
        unawaited(batcher.read('c1'));
        unawaited(
          batcher.read('c2').then<void>((_) {}, onError: (e) => missing = e),
        );
        async.elapse(const Duration(milliseconds: 100));
        expect(missing, isA<ChainNotAvailable>());

        fail = true;
        Object? failed;
        unawaited(
          batcher.read('c3').then<void>((_) {}, onError: (e) => failed = e),
        );
        async.elapse(const Duration(milliseconds: 100));
        expect(failed, isA<StateError>());
        // Later reads start afresh.
        fail = false;
        String? later;
        unawaited(batcher.read('c1').then((v) => later = v));
        async.elapse(const Duration(milliseconds: 100));
        expect(later, 'one');
      });
    });
  });

  group('ChainChangeHub', () {
    late List<String> opened;
    late List<String> closed;
    late Map<String, void Function(String?)> notifiers;

    ChainChangeHub hub({Duration grace = const Duration(seconds: 3)}) {
      opened = [];
      closed = [];
      notifiers = {};
      return ChainChangeHub((conversationId, onChange) {
        opened.add(conversationId);
        notifiers[conversationId] = onChange;
        return () => closed.add(conversationId);
      }, grace: grace);
    }

    test('forty cards of two conversations share two channels', () {
      fakeAsync((async) {
        final h = hub();
        final subscriptions = <StreamSubscription<void>>[];
        for (var i = 0; i < 40; i++) {
          final conversation = i.isEven ? 'c-even' : 'c-odd';
          h.learn('chain-$i', conversation);
          subscriptions.add(h.changes('chain-$i').listen((_) {}));
        }
        async.flushMicrotasks();
        expect(opened..sort(), ['c-even', 'c-odd']);
        expect(h.openChannels, 2);
        for (final s in subscriptions) {
          unawaited(s.cancel());
        }
      });
    });

    test('a change reaches the card of that chain only', () {
      fakeAsync((async) {
        final h = hub();
        var one = 0;
        var two = 0;
        h.learn('chain-1', 'c1');
        h.learn('chain-2', 'c1');
        final a = h.changes('chain-1').listen((_) => one++);
        final b = h.changes('chain-2').listen((_) => two++);
        async.flushMicrotasks();
        notifiers['c1']!('chain-2');
        async.flushMicrotasks();
        expect((one, two), (0, 1));
        // A change that does not say which chain wakes them all.
        notifiers['c1']!(null);
        async.flushMicrotasks();
        expect((one, two), (1, 2));
        unawaited(a.cancel());
        unawaited(b.cancel());
      });
    });

    test('a card that listens before its chain is read joins the channel '
        'once the conversation is known', () {
      fakeAsync((async) {
        final h = hub();
        var changes = 0;
        final subscription = h.changes('chain-1').listen((_) => changes++);
        async.flushMicrotasks();
        expect(opened, isEmpty);
        h.learn('chain-1', 'c1');
        expect(opened, ['c1']);
        notifiers['c1']!('chain-1');
        async.flushMicrotasks();
        expect(changes, 1);
        unawaited(subscription.cancel());
      });
    });

    test('the channel closes after the last card scrolls away, not before', () {
      fakeAsync((async) {
        final h = hub();
        h.learn('chain-1', 'c1');
        h.learn('chain-2', 'c1');
        final a = h.changes('chain-1').listen((_) {});
        final b = h.changes('chain-2').listen((_) {});
        async.flushMicrotasks();
        unawaited(a.cancel());
        async.elapse(const Duration(seconds: 10));
        expect(closed, isEmpty, reason: 'one card is still there');
        unawaited(b.cancel());
        async.elapse(const Duration(seconds: 2));
        expect(closed, isEmpty, reason: 'a grace period for scrolling back');
        async.elapse(const Duration(seconds: 2));
        expect(closed, ['c1']);
        expect(h.openChannels, 0);
      });
    });

    test('a card that comes back within the grace keeps the channel', () {
      fakeAsync((async) {
        final h = hub();
        h.learn('chain-1', 'c1');
        final a = h.changes('chain-1').listen((_) {});
        async.flushMicrotasks();
        unawaited(a.cancel());
        async.elapse(const Duration(seconds: 1));
        final again = h.changes('chain-1').listen((_) {});
        async.elapse(const Duration(seconds: 10));
        expect(opened, ['c1']);
        expect(closed, isEmpty);
        unawaited(again.cancel());
        async.elapse(const Duration(seconds: 10));
        expect(closed, ['c1']);
      });
    });

    test('the topic is named for the conversation', () {
      expect(ChainChangeHub.topicFor('abc'), 'chains:abc');
    });
  });

  group('SupabaseChainRepository reads', () {
    late List<http.Request> requests;

    SupabaseChainRepository repositoryFor(
      Future<http.Response> Function(http.Request request) handler,
    ) {
      requests = [];
      final client = SupabaseClient(
        'https://x.supabase.co',
        'key',
        httpClient: MockClient((request) {
          requests.add(request);
          return handler(request);
        }),
      );
      addTearDown(client.dispose);
      return SupabaseChainRepository(client);
    }

    http.Response json(Object? body, http.Request request, [int status = 200]) {
      return http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }

    test('forty cards make one get_chains request', () async {
      final repository = repositoryFor((request) async {
        final ids =
            ((jsonDecode(request.body) as Map)['target_chain_ids'] as List)
                .cast<String>();
        return json([for (final id in ids) _chainJson(id)], request);
      });
      final snapshots = await Future.wait([
        for (var i = 0; i < 40; i++) repository.get('chain-$i'),
      ]);
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/rest/v1/rpc/get_chains');
      expect(snapshots.map((s) => s.id), [
        for (var i = 0; i < 40; i++) 'chain-$i',
      ]);
    });

    test('a chain the server does not return is gone', () async {
      final repository = repositoryFor((request) async {
        return json([_chainJson('chain-1')], request);
      });
      final results = await Future.wait([
        repository.get('chain-1'),
        repository.get('chain-2').then<Object?>((s) => s, onError: (e) => e),
      ]);
      expect((results[0]! as ChainSnapshot).id, 'chain-1');
      expect(results[1], isA<ChainException>());
      expect((results[1]! as ChainException).kind, ChainFailureKind.gone);
    });

    test('a server without get_chains is read one chain at a time', () async {
      final repository = repositoryFor((request) async {
        if (request.url.path.endsWith('/get_chains')) {
          return json(
            {'code': 'PGRST202', 'message': 'not found'},
            request,
            404,
          );
        }
        final id =
            (jsonDecode(request.body) as Map)['target_chain_id']! as String;
        return json(_chainJson(id), request);
      });
      final snapshots = await Future.wait([
        repository.get('chain-1'),
        repository.get('chain-2'),
      ]);
      expect(snapshots.map((s) => s.id), ['chain-1', 'chain-2']);
      expect(requests.map((r) => r.url.pathSegments.last), [
        'get_chains',
        'get_chain',
        'get_chain',
      ]);
      // It does not try the missing function again.
      await repository.get('chain-3');
      expect(requests.last.url.pathSegments.last, 'get_chain');
      expect(
        requests.where((r) => r.url.path.endsWith('/get_chains')),
        hasLength(1),
      );
    });

    test('a failed read is reported as an error to every card', () async {
      final repository = repositoryFor(
        (request) async =>
            json({'code': '500', 'message': 'boom'}, request, 500),
      );
      final results = await Future.wait([
        repository.get('chain-1').then<Object?>((s) => s, onError: (e) => e),
        repository.get('chain-2').then<Object?>((s) => s, onError: (e) => e),
      ]);
      expect(results, everyElement(isA<ChainException>()));
      expect(requests, hasLength(1));
    });
  });
}
