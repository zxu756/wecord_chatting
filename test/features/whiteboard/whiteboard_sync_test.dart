import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/whiteboard/whiteboard_history.dart';
import 'package:wecord/features/whiteboard/whiteboard_merge.dart';
import 'package:wecord/features/whiteboard/whiteboard_models.dart';
import 'package:wecord/features/whiteboard/whiteboard_sync.dart';

import 'whiteboard_fakes.dart';

class Client {
  Client(this.server, this.name) {
    remote = FakeWhiteboardRemote(server);
    engine = WhiteboardSyncEngine(boardId: 'board-1', remote: remote);
    engine.load(server.snapshot());
    server.listen((element) {
      if (!realtimeOff) {
        engine.receiveRemote(element);
      }
    });
  }

  final FakeWhiteboardServer server;
  final String name;
  late final FakeWhiteboardRemote remote;
  late final WhiteboardSyncEngine engine;
  var realtimeOff = false;

  String get texts =>
      engine.elements.map((e) => e.text).join('|');
}

FakeWhiteboardServer seeded() {
  final server = FakeWhiteboardServer();
  server.write(sticky('a', z: 'V', text: 'alpha', x: 10, y: 10));
  server.write(sticky('b', z: 'W', text: 'beta', x: 300, y: 10));
  return server;
}

void main() {
  group('merge', () {
    test('keys changed by one side each both survive', () {
      final base = sticky('a', text: 'x', x: 0, rev: 1);
      final mine = base.withData({'x': 50});
      final theirs = base.withData({'c': 0xFF00FF00}).copyWith(rev: 2);
      final merged = mergeElements(base: base, mine: mine, theirs: theirs);
      expect(merged.x, 50);
      expect(merged.color, 0xFF00FF00);
      expect(merged.rev, 2);
    });

    test('both moved the same element: mine is sent over theirs', () {
      final base = sticky('a', x: 0, rev: 1);
      final merged = mergeElements(
        base: base,
        mine: base.withData({'x': 5}),
        theirs: base.withData({'x': 9}).copyWith(rev: 2),
      );
      expect(merged.x, 5);
    });

    test('words typed in different places of a sticky both stay', () {
      final base = sticky('a', text: 'hello world', rev: 1);
      final merged = mergeElements(
        base: base,
        mine: base.withData({'t': 'hello big world'}),
        theirs: base.withData({'t': 'hello world!'}).copyWith(rev: 2),
      );
      expect(merged.text, 'hello big world!');
    });
  });

  group('sync engine', () {
    test('an edit is sent based on the stored revision', () async {
      final server = seeded();
      final ada = Client(server, 'ada');
      ada.engine.upsert(ada.engine.elementById('a')!.withData({'x': 99}));
      expect(ada.engine.pendingCount, 1);
      expect(await ada.engine.flush(), isTrue);
      expect(server.elements['a']!.x, 99);
      expect(server.batches.single.single['base_rev'], 1);
      expect(ada.engine.pendingCount, 0);
      expect(ada.engine.status, WhiteboardSyncStatus.saved);
    });

    test('a new element is sent without a base revision', () async {
      final server = seeded();
      final ada = Client(server, 'ada');
      ada.engine.upsert(sticky('c', z: 'X', text: 'new'));
      await ada.engine.flush();
      expect(server.batches.single.single['base_rev'], isNull);
      expect(server.elements['c']!.text, 'new');
      expect(ada.engine.baseOf('c')!.rev, 1);
    });

    test('moving and recoloring the same note both land', () async {
      final server = seeded();
      final ada = Client(server, 'ada');
      final bob = Client(server, 'bob');
      ada.realtimeOff = true;
      bob.realtimeOff = true;
      ada.engine.upsert(ada.engine.elementById('a')!.withData({'x': 70}));
      bob.engine.upsert(
        bob.engine.elementById('a')!.withData({'c': 0xFF112233}),
      );
      await ada.engine.flush();
      await bob.engine.flush();
      expect(server.elements['a']!.x, 70);
      expect(server.elements['a']!.color, 0xFF112233);
      expect(bob.engine.elementById('a')!.x, 70);
      expect(bob.engine.pendingCount, 0);
    });

    test('a rub-out beats an edit made at the same time', () async {
      final server = seeded();
      final ada = Client(server, 'ada');
      final bob = Client(server, 'bob');
      ada.realtimeOff = true;
      ada.engine.upsert(ada.engine.elementById('a')!.withData({'x': 70}));
      bob.engine.remove('a');
      await bob.engine.flush();
      await ada.engine.flush();
      expect(server.elements['a']!.deleted, isTrue);
      expect(ada.engine.elementById('a'), isNull);
      expect(ada.engine.pendingCount, 0);
    });

    test('an edit of an element somebody rubbed out meanwhile is dropped', () async {
      final server = seeded();
      final ada = Client(server, 'ada');
      final bob = Client(server, 'bob');
      ada.realtimeOff = true;
      bob.engine.remove('b');
      await bob.engine.flush();
      ada.engine.upsert(ada.engine.elementById('b')!.withData({'x': 1}));
      await ada.engine.flush();
      expect(ada.engine.elementById('b'), isNull);
      expect(server.elements['b']!.deleted, isTrue);
    });

    test('changes made offline stay queued and go out later', () async {
      final server = seeded();
      final ada = Client(server, 'ada');
      server.offline = true;
      ada.engine.upsert(sticky('c', z: 'X', text: 'drawn offline'));
      expect(await ada.engine.flush(), isFalse);
      expect(ada.engine.status, WhiteboardSyncStatus.offline);
      expect(ada.engine.pendingCount, 1);
      server.offline = false;
      expect(await ada.engine.flush(), isTrue);
      expect(server.elements['c']!.text, 'drawn offline');
      expect(ada.engine.status, WhiteboardSyncStatus.saved);
    });

    test('a draft survives a restart and merges with newer server state', () async {
      final server = seeded();
      final ada = Client(server, 'ada');
      ada.engine.upsert(ada.engine.elementById('a')!.withData({'x': 77}));
      ada.engine.upsert(sticky('c', z: 'X', text: 'unsent'));
      final draft = ada.engine.toDraft();
      expect(draft.local.map((e) => e.id).toSet(), {'a', 'c'});
      // Somebody else recolors "a" in the meantime.
      server.write(
        server.elements['a']!.withData({'c': 0xFF010203}),
      );
      final reopened = WhiteboardSyncEngine(
        boardId: 'board-1',
        remote: FakeWhiteboardRemote(server),
      )..load(server.snapshot(), draft: draft);
      expect(reopened.elementById('a')!.x, 77);
      expect(reopened.elementById('a')!.color, 0xFF010203);
      expect(reopened.elementById('c')!.text, 'unsent');
      await reopened.flush();
      expect(server.elements['a']!.x, 77);
      expect(server.elements['a']!.color, 0xFF010203);
      expect(server.elements['c']!.text, 'unsent');
    });

    test('a refused element goes back to the server\'s', () async {
      final server = seeded()..maxLive = 2;
      final ada = Client(server, 'ada');
      ada.engine.upsert(sticky('c', z: 'X'));
      await ada.engine.flush();
      expect(ada.engine.elementById('c'), isNull);
      expect(ada.engine.lastRejection, 'too many elements');
      expect(ada.engine.pendingCount, 0);
    });

    test('more than 200 changes are sent in several calls', () async {
      final server = FakeWhiteboardServer();
      final ada = Client(server, 'ada');
      for (var i = 0; i < 450; i++) {
        ada.engine.upsert(
          stroke('s${i.toString().padLeft(4, '0')}', z: 'V${i % 9}'),
        );
      }
      await ada.engine.flush();
      expect(server.batches.map((b) => b.length), [200, 200, 50]);
      expect(server.liveCount, 450);
    });

    test('our own change coming back by realtime is not a conflict', () async {
      final server = seeded();
      final ada = Client(server, 'ada');
      ada.engine.upsert(ada.engine.elementById('a')!.withData({'x': 5}));
      await ada.engine.flush();
      expect(ada.engine.pendingCount, 0);
      expect(ada.engine.elementById('a')!.x, 5);
    });
  });

  group('history', () {
    test('undo and redo of a creation, an edit and a rub-out', () async {
      final server = seeded();
      final ada = Client(server, 'ada');
      final history = WhiteboardHistory();
      final created = sticky('c', z: 'X', text: 'one');
      ada.engine.upsert(created);
      history.record([ElementChange(id: 'c', after: created)]);
      await ada.engine.flush();

      final before = ada.engine.elementById('a')!;
      final after = before.withData({'x': 200});
      ada.engine.upsert(after);
      history.record([ElementChange(id: 'a', before: before, after: after)]);

      final victim = ada.engine.elementById('b')!;
      ada.engine.remove('b');
      history.record([ElementChange(id: 'b', before: victim)]);
      await ada.engine.flush();
      expect(ada.engine.elementById('b'), isNull);

      history.undo(ada.engine);
      expect(ada.engine.elementById('b'), isNotNull);
      await ada.engine.flush();
      expect(server.elements['b']!.deleted, isFalse);
      expect(server.elements['b']!.text, 'beta');

      history.undo(ada.engine);
      expect(ada.engine.elementById('a')!.x, 10);
      history.undo(ada.engine);
      expect(ada.engine.elementById('c'), isNull);
      expect(history.canUndo, isFalse);
      await ada.engine.flush();
      expect(server.elements['c']!.deleted, isTrue);

      history.redo(ada.engine);
      expect(ada.engine.elementById('c')!.text, 'one');
      expect(history.canRedo, isTrue);
    });

    test('undoing an edit keeps a change somebody else made to another key', () {
      final server = seeded();
      final ada = Client(server, 'ada');
      final history = WhiteboardHistory();
      final before = ada.engine.elementById('a')!;
      final after = before.withData({'x': 200});
      ada.engine.upsert(after);
      history.record([ElementChange(id: 'a', before: before, after: after)]);
      ada.engine.upsert(
        ada.engine.elementById('a')!.withData({'c': 0xFF445566}),
      );
      history.undo(ada.engine);
      expect(ada.engine.elementById('a')!.x, 10);
      expect(ada.engine.elementById('a')!.color, 0xFF445566);
    });

    test('a new action clears redo, and the stack is capped', () {
      final server = seeded();
      final ada = Client(server, 'ada');
      final history = WhiteboardHistory(limit: 3);
      for (var i = 0; i < 5; i++) {
        final element = stroke('s$i');
        ada.engine.upsert(element);
        history.record([ElementChange(id: 's$i', after: element)]);
      }
      expect(history.undoDepth, 3);
      history.undo(ada.engine);
      expect(history.canRedo, isTrue);
      final extra = stroke('extra');
      ada.engine.upsert(extra);
      history.record([ElementChange(id: 'extra', after: extra)]);
      expect(history.canRedo, isFalse);
    });
  });
}
