import 'package:wecord/features/whiteboard/whiteboard_models.dart';
import 'package:wecord/features/whiteboard/whiteboard_sync.dart';

/// A stand-in for the table and `whiteboard_apply_ops`, with the same rules:
/// a put on a stored element needs its current revision (else a conflict
/// carrying the stored element), a put on a tombstone needs `revive` and the
/// tombstone's revision, deleting twice is fine.
class FakeWhiteboardServer {
  final elements = <String, WhiteboardElement>{};
  final batches = <List<Map<String, Object?>>>[];
  final _listeners = <void Function(WhiteboardElement)>[];

  /// Makes the next calls fail (an unreachable server).
  var offline = false;

  /// Refuses puts of new elements beyond this many live ones.
  int? maxLive;

  void listen(void Function(WhiteboardElement) listener) =>
      _listeners.add(listener);

  void _publish(WhiteboardElement element) {
    for (final listener in _listeners) {
      listener(element);
    }
  }

  WhiteboardSnapshot snapshot() {
    final live = [
      for (final element in elements.values)
        if (!element.deleted) element,
    ]..sort(compareElements);
    return WhiteboardSnapshot(
      board: const WhiteboardMeta(
        id: 'board-1',
        conversationId: 'conversation-1',
        title: 'Plan',
        canEdit: true,
        canManage: true,
      ),
      elements: live,
    );
  }

  int get liveCount => elements.values.where((e) => !e.deleted).length;

  /// Stores [element] directly, as another client's accepted write would.
  WhiteboardElement write(WhiteboardElement element) {
    final current = elements[element.id];
    final stored = element.copyWith(rev: (current?.rev ?? 0) + 1);
    elements[element.id] = stored;
    _publish(stored);
    return stored;
  }

  List<WhiteboardOpResult> apply(List<Map<String, Object?>> ops) {
    batches.add(ops);
    final results = <WhiteboardOpResult>[];
    for (final op in ops) {
      final id = op['id']! as String;
      final current = elements[id];
      if (op['op'] == 'del') {
        if (current != null && !current.deleted) {
          final stored = current.copyWith(
            deleted: true,
            data: const {},
            rev: current.rev + 1,
          );
          elements[id] = stored;
          _publish(stored);
          results.add(WhiteboardOpResult(id: id, status: 'ok', rev: stored.rev));
        } else {
          results.add(WhiteboardOpResult(id: id, status: 'ok'));
        }
        continue;
      }
      final incoming = WhiteboardElement(
        id: id,
        kind: WhiteboardKind.fromValue(op['kind'])!,
        z: op['z']! as String,
        data: Map<String, Object?>.from(op['data']! as Map),
      );
      final baseRev = op['base_rev'] as int?;
      if (current == null) {
        if (maxLive != null && liveCount >= maxLive!) {
          results.add(
            WhiteboardOpResult(
              id: id,
              status: 'rejected',
              reason: 'too many elements',
            ),
          );
          continue;
        }
        final stored = incoming.copyWith(rev: 1);
        elements[id] = stored;
        _publish(stored);
        results.add(WhiteboardOpResult(id: id, status: 'ok', rev: 1));
        continue;
      }
      if (!current.deleted && current.sameContent(incoming)) {
        results.add(WhiteboardOpResult(id: id, status: 'ok', rev: current.rev));
        continue;
      }
      final canRevive =
          current.deleted && op['revive'] == true && baseRev == current.rev;
      if (current.deleted ? !canRevive : baseRev != current.rev) {
        results.add(
          WhiteboardOpResult(id: id, status: 'conflict', element: current),
        );
        continue;
      }
      final stored = incoming.copyWith(rev: current.rev + 1);
      elements[id] = stored;
      _publish(stored);
      results.add(WhiteboardOpResult(id: id, status: 'ok', rev: stored.rev));
    }
    return results;
  }
}

class FakeWhiteboardRemote implements WhiteboardRemote {
  FakeWhiteboardRemote(this.server);

  final FakeWhiteboardServer server;

  @override
  Future<List<WhiteboardOpResult>> applyOps(
    String boardId,
    List<Map<String, Object?>> ops,
  ) async {
    if (server.offline) {
      throw StateError('offline');
    }
    return server.apply(ops);
  }
}

WhiteboardElement sticky(
  String id, {
  String z = 'V',
  String text = '',
  double x = 0,
  double y = 0,
  int color = 0xFFFFE08A,
  int rev = 0,
}) {
  return WhiteboardElement(
    id: id,
    kind: WhiteboardKind.sticky,
    z: z,
    rev: rev,
    data: {'x': x, 'y': y, 'w': 160.0, 'h': 120.0, 't': text, 'c': color},
  );
}

WhiteboardElement stroke(
  String id, {
  String z = 'V',
  List<double> points = const [0, 0, 10, 10],
  double width = 3,
}) {
  return WhiteboardElement(
    id: id,
    kind: WhiteboardKind.stroke,
    z: z,
    data: {'p': points, 'sw': width, 'c': 0xFF1B1B1F},
  );
}
