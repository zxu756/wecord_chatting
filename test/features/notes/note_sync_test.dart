import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_sync.dart';

import 'note_fakes.dart';

/// A client: an engine wired to a fake server, getting realtime changes.
class Client {
  Client(this.server, this.name, {int? seed}) {
    var counter = 0;
    remote = FakeNoteRemote(server);
    engine = NoteSyncEngine(
      noteId: 'note-1',
      remote: remote,
      newId: () => '$name-${counter++}',
    );
    engine.load(server.snapshot());
    server.listen((block) {
      if (!realtimeOff) {
        engine.receiveRemote(block);
      }
    });
  }

  final FakeNoteServer server;
  final String name;
  late final FakeNoteRemote remote;
  late final NoteSyncEngine engine;
  var realtimeOff = false;

  String get text => engine.blocks.map((block) => block.text).join('|');

  void type(String blockId, String text) {
    engine.updateBlock(blockId, text: text);
  }
}

FakeNoteServer seeded(List<String> texts) {
  final server = FakeNoteServer();
  for (var i = 0; i < texts.length; i++) {
    server.blocks['seed-$i'] = NoteBlock(
      id: 'seed-$i',
      pos: String.fromCharCode('a'.codeUnitAt(0) + i),
      text: texts[i],
      rev: 1,
    );
  }
  return server;
}

void main() {
  test('local edits are sent as puts based on the stored revision', () async {
    final server = seeded(['hello']);
    final ada = Client(server, 'ada');
    ada.type('seed-0', 'hello world');
    expect(ada.engine.pendingCount, 1);
    expect(await ada.engine.flush(), isTrue);
    expect(server.blocks['seed-0']!.text, 'hello world');
    expect(server.blocks['seed-0']!.rev, 2);
    expect(server.batches.single.single['base_rev'], 1);
    expect(ada.engine.pendingCount, 0);
    expect(ada.engine.status, NoteSyncStatus.saved);
  });

  test('new blocks are created with no base revision and ordered', () async {
    final server = seeded(['one', 'three']);
    final ada = Client(server, 'ada');
    final inserted = ada.engine.insertBlock(afterId: 'seed-0', text: 'two');
    expect(ada.engine.blocks.map((b) => b.text), ['one', 'two', 'three']);
    expect(inserted.pos.compareTo('a'), greaterThan(0));
    expect(inserted.pos.compareTo('b'), lessThan(0));
    await ada.engine.flush();
    expect(server.batches.single.single['base_rev'], isNull);
    expect(server.text(), 'one|two|three');
  });

  test('two people editing different blocks both keep their changes', () async {
    final server = seeded(['alpha', 'beta']);
    final ada = Client(server, 'ada');
    final bob = Client(server, 'bob');
    ada.type('seed-0', 'alpha 1');
    bob.type('seed-1', 'beta 2');
    await Future.wait([ada.engine.flush(), bob.engine.flush()]);
    expect(server.text(), 'alpha 1|beta 2');
    expect(ada.text, 'alpha 1|beta 2');
    expect(bob.text, 'alpha 1|beta 2');
  });

  test(
    'typing in the same block at once merges through the conflict',
    () async {
      final server = seeded(['The quick fox jumps']);
      final ada = Client(server, 'ada');
      final bob = Client(server, 'bob');
      // Neither sees the other's realtime change before sending.
      ada.realtimeOff = true;
      bob.realtimeOff = true;
      ada.type('seed-0', 'The quick brown fox jumps');
      bob.type('seed-0', 'The quick fox jumps over');
      await ada.engine.flush();
      await bob.engine.flush();
      expect(server.blocks['seed-0']!.text, 'The quick brown fox jumps over');
      // Bob's engine merged on the conflict and resent.
      expect(bob.text, 'The quick brown fox jumps over');
      expect(bob.engine.pendingCount, 0);
      // Ada learns of it by realtime.
      ada.realtimeOff = false;
      ada.engine.receiveRemote(server.blocks['seed-0']!);
      expect(ada.text, 'The quick brown fox jumps over');
    },
  );

  test('a realtime change merges into a block being edited', () async {
    final server = seeded(['abc def']);
    final ada = Client(server, 'ada');
    final bob = Client(server, 'bob');
    ada.type('seed-0', 'abc def ghi');
    bob.type('seed-0', 'XYZ abc def');
    await ada.engine.flush();
    // Bob has not sent yet; Ada's change came in by realtime and merged.
    expect(bob.text, 'XYZ abc def ghi');
    expect(bob.engine.pendingCount, 1);
    await bob.engine.flush();
    expect(server.text(), 'XYZ abc def ghi');
  });

  test('our own change coming back by realtime is not a conflict', () async {
    final server = seeded(['abc']);
    final ada = Client(server, 'ada');
    ada.type('seed-0', 'abcd');
    // The server's realtime change arrives while the call is in flight,
    // and Ada keeps typing.
    ada.remote.beforeAnswer = () => ada.type('seed-0', 'abcde');
    await ada.engine.flush();
    expect(ada.text, 'abcde');
    expect(server.text(), 'abcde');
    expect(ada.engine.pendingCount, 0);
  });

  test('a block deleted by someone else while edited here lives on', () async {
    final server = seeded(['keep', 'doomed']);
    final ada = Client(server, 'ada');
    final bob = Client(server, 'bob');
    ada.realtimeOff = true;
    ada.type('seed-1', 'doomed but rewritten');
    bob.engine.deleteBlock('seed-1');
    await bob.engine.flush();
    ada.realtimeOff = false;
    await ada.engine.flush();
    expect(server.text(), 'keep|doomed but rewritten');
    expect(ada.text, 'keep|doomed but rewritten');
  });

  test(
    'deleting a block removes it for everyone; the last block empties',
    () async {
      final server = seeded(['one', 'two']);
      final ada = Client(server, 'ada');
      final bob = Client(server, 'bob');
      ada.engine.deleteBlock('seed-0');
      await ada.engine.flush();
      expect(bob.text, 'two');
      ada.engine.deleteBlock('seed-1');
      expect(ada.engine.blocks.single.text, '');
      expect(ada.engine.blocks.single.id, 'seed-1');
    },
  );

  test(
    'thousands of inserts into one gap renumber instead of overflowing',
    () async {
      final server = seeded(['first', 'last']);
      final ada = Client(server, 'ada');
      var after = 'seed-0';
      for (var i = 0; i < 600; i++) {
        after = ada.engine.insertBlock(afterId: after, text: '$i').id;
      }
      final blocks = ada.engine.blocks;
      expect(blocks.length, 602);
      expect(blocks.first.text, 'first');
      expect(blocks.last.text, 'last');
      expect(blocks[300].text, '299');
      for (final block in blocks) {
        expect(block.pos.length, lessThanOrEqualTo(64));
      }
      expect(blocks.map((b) => b.pos).toSet().length, blocks.length);
      await ada.engine.flush();
      expect(server.text().split('|').length, 602);
    },
  );

  test('moving a block changes only its key', () async {
    final server = seeded(['a', 'b', 'c']);
    final ada = Client(server, 'ada');
    ada.engine.moveBlock('seed-0', 'seed-2');
    expect(ada.engine.blocks.map((b) => b.text), ['b', 'c', 'a']);
    await ada.engine.flush();
    expect(server.text(), 'b|c|a');
  });

  group('offline', () {
    test('edits queue while offline and are sent when back', () async {
      final server = seeded(['one']);
      final ada = Client(server, 'ada');
      ada.remote.offline = true;
      ada.type('seed-0', 'one two');
      ada.engine.insertBlock(afterId: 'seed-0', text: 'three');
      expect(await ada.engine.flush(), isFalse);
      expect(ada.engine.status, NoteSyncStatus.offline);
      expect(ada.engine.pendingCount, 2);
      expect(server.text(), 'one');
      ada.remote.offline = false;
      expect(await ada.engine.flush(), isTrue);
      expect(server.text(), 'one two|three');
      expect(ada.engine.status, NoteSyncStatus.saved);
    });

    test('offline edits merge with what others wrote meanwhile', () async {
      final server = seeded(['Shopping list: milk', 'Notes']);
      final ada = Client(server, 'ada');
      final bob = Client(server, 'bob');
      ada.remote.offline = true;
      ada.realtimeOff = true;
      ada.type('seed-0', 'Shopping list: milk, eggs');
      ada.engine.insertBlock(afterId: 'seed-1', text: 'ada was here');
      bob.type('seed-0', 'Weekend shopping list: milk');
      bob.type('seed-1', 'Notes!');
      await bob.engine.flush();
      expect(await ada.engine.flush(), isFalse);
      ada.remote.offline = false;
      ada.realtimeOff = false;
      // Back online: the server's state arrives and everything merges.
      ada.engine.load(server.snapshot(), draft: ada.engine.toDraft());
      await ada.engine.flush();
      expect(
        server.text(),
        'Weekend shopping list: milk, eggs|Notes!|ada was here',
      );
      expect(ada.text, server.text());
    });

    test('edits survive a restart through the draft', () async {
      final server = seeded(['one']);
      final ada = Client(server, 'ada');
      ada.remote.offline = true;
      ada.type('seed-0', 'one!');
      await ada.engine.flush();
      final draft = NoteDraft.fromJson(
        Map<String, dynamic>.from(
          // As stored in shared preferences.
          ada.engine.toDraft().toJson(),
        ),
      );
      // Meanwhile Bob changes another part and a new block.
      final bob = Client(server, 'bob');
      bob.engine.insertBlock(afterId: 'seed-0', text: 'bob');
      await bob.engine.flush();

      final restarted = Client(server, 'ada2');
      restarted.engine.load(server.snapshot(), draft: draft);
      expect(restarted.text, 'one!|bob');
      expect(restarted.engine.pendingCount, 1);
      await restarted.engine.flush();
      expect(server.text(), 'one!|bob');
    });

    test('a draft for a block deleted meanwhile keeps the text', () async {
      final server = seeded(['keep', 'gone']);
      final ada = Client(server, 'ada');
      ada.remote.offline = true;
      ada.type('seed-1', 'gone but edited');
      await ada.engine.flush();
      final draft = ada.engine.toDraft();
      final bob = Client(server, 'bob');
      bob.engine.deleteBlock('seed-1');
      await bob.engine.flush();

      final restarted = Client(server, 'ada2');
      restarted.engine.load(server.snapshot(), draft: draft);
      await restarted.engine.flush();
      expect(server.text(), 'keep|gone but edited');
    });

    test('a note created offline is sent with its blocks', () async {
      final server = FakeNoteServer();
      final ada = Client(server, 'ada');
      ada.remote.offline = true;
      final first = ada.engine.blocks.single;
      ada.type(first.id, 'first line');
      ada.engine.insertBlock(afterId: first.id, text: 'second line');
      await ada.engine.flush();
      ada.remote.offline = false;
      await ada.engine.flush();
      expect(server.text(), 'first line|second line');
    });

    test('a repeated create after a lost answer does not duplicate', () async {
      final server = seeded(['x']);
      final ada = Client(server, 'ada');
      final block = ada.engine.insertBlock(afterId: 'seed-0', text: 'new');
      // The server stores it but the answer is lost.
      ada.remote.beforeAnswer = () {
        server.apply([block.toPutOp(null)]);
        ada.remote.offline = true;
      };
      await ada.engine.flush();
      ada.remote.beforeAnswer = null;
      ada.remote.offline = false;
      await ada.engine.flush();
      expect(server.text(), 'x|new');
      expect(ada.engine.pendingCount, 0);
    });
  });

  test('a refused change goes back to the server version', () async {
    final server = seeded(['ok']);
    final ada = Client(server, 'ada');
    ada.remote.beforeAnswer = null;
    ada.type('seed-0', 'changed');
    final rejecting = _RejectingRemote();
    final engine = NoteSyncEngine(
      noteId: 'n',
      remote: rejecting,
      newId: () => 'x',
    )..load(server.snapshot());
    engine.updateBlock('seed-0', text: 'too long');
    await engine.flush();
    expect(engine.blocks.single.text, 'ok');
    expect(engine.lastRejection, 'text too long');
  });

  test(
    'clients converge after random edits, going offline and online',
    () async {
      for (var seed = 0; seed < 12; seed++) {
        final random = Random(seed);
        final server = seeded(['alpha', 'beta', 'gamma']);
        final clients = [
          Client(server, 'ada'),
          Client(server, 'bob'),
          Client(server, 'cy'),
        ];
        final words = ['red', 'green', 'blue', 'sun', 'moon', 'star'];
        for (var step = 0; step < 60; step++) {
          final client = clients[random.nextInt(clients.length)];
          switch (random.nextInt(8)) {
            case 0:
              client.remote.offline = !client.remote.offline;
              client.realtimeOff = client.remote.offline;
            case 1:
              final blocks = client.engine.blocks;
              client.engine.insertBlock(
                afterId: blocks[random.nextInt(blocks.length)].id,
                text: words[random.nextInt(words.length)],
              );
            case 2:
              final blocks = client.engine.blocks;
              if (blocks.length > 2) {
                client.engine.deleteBlock(
                  blocks[random.nextInt(blocks.length)].id,
                );
              }
            case 3:
              await client.engine.flush();
            default:
              final blocks = client.engine.blocks;
              final block = blocks[random.nextInt(blocks.length)];
              final at = random.nextInt(block.text.length + 1);
              client.type(
                block.id,
                block.text.substring(0, at) +
                    words[random.nextInt(words.length)] +
                    block.text.substring(at),
              );
          }
        }
        // Everyone comes back online and catches up.
        for (final client in clients) {
          client.remote.offline = false;
          client.realtimeOff = false;
        }
        for (var round = 0; round < 3; round++) {
          for (final client in clients) {
            client.engine.load(
              server.snapshot(),
              draft: client.engine.toDraft(),
            );
            await client.engine.flush();
          }
        }
        for (final client in clients) {
          expect(
            client.engine.pendingCount,
            0,
            reason: 'seed $seed ${client.name}',
          );
          expect(
            client.text,
            server.text(),
            reason: 'seed $seed ${client.name}',
          );
        }
      }
    },
  );
}

class _RejectingRemote implements NoteRemote {
  @override
  Future<List<NoteOpResult>> applyOps(
    String noteId,
    List<Map<String, Object?>> ops,
  ) async {
    return [
      for (final op in ops)
        NoteOpResult(
          id: op['id']! as String,
          status: 'rejected',
          reason: 'text too long',
        ),
    ];
  }
}
