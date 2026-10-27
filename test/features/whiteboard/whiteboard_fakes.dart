import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:wecord/features/whiteboard/whiteboard_models.dart';
import 'package:wecord/features/whiteboard/whiteboard_repository.dart';
import 'package:wecord/features/whiteboard/whiteboard_sync.dart';

/// A [WhiteboardRepository] over [FakeWhiteboardServer]: what the screens
/// and the controller talk to in tests.
class FakeWhiteboardRepository implements WhiteboardRepository {
  FakeWhiteboardRepository(this.server, {WhiteboardMeta? meta})
    : meta =
          meta ??
          const WhiteboardMeta(
            id: 'board-1',
            conversationId: 'conversation-1',
            title: 'Plan',
            canEdit: true,
            canManage: true,
          ) {
    server.listen(_elements.add);
  }

  final FakeWhiteboardServer server;
  WhiteboardMeta meta;
  final _elements = StreamController<WhiteboardElement>.broadcast();
  final metas = StreamController<WhiteboardMetaChange>.broadcast();
  final lists = <WhiteboardSummary>[];
  final versions = <WhiteboardVersionSummary>[];
  final uploaded = <String, Uint8List>{};
  final live = FakeLive();
  var failLoad = false;
  var clears = 0;
  var deleted = false;
  var versionsCreated = 0;

  @override
  Future<WhiteboardSnapshot> getBoard(String boardId) async {
    if (failLoad) {
      throw StateError('offline');
    }
    return WhiteboardSnapshot(
      board: meta,
      elements: server.snapshot().elements,
    );
  }

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

  @override
  Future<List<WhiteboardSummary>> listBoards(String conversationId) async =>
      lists;

  @override
  Future<WhiteboardMeta> createBoard(
    String conversationId, {
    String title = '',
    String? id,
  }) async {
    final board = WhiteboardMeta(
      id: id ?? 'new-board',
      conversationId: conversationId,
      title: title,
      canEdit: true,
      canManage: true,
    );
    lists.add(
      WhiteboardSummary(
        id: board.id,
        conversationId: conversationId,
        title: title,
        canEdit: true,
      ),
    );
    return board;
  }

  @override
  Future<WhiteboardMeta> updateMeta(
    String boardId,
    Map<String, Object?> patch,
  ) async {
    meta = meta.copyWith(
      title: patch['title'] as String?,
      managersOnly: patch['managers_only'] as bool?,
    );
    return meta;
  }

  @override
  Future<void> clearBoard(String boardId) async {
    clears++;
    for (final e in server.elements.values.toList()) {
      if (!e.deleted) {
        server.write(e.copyWith(deleted: true, data: const {}));
      }
    }
  }

  @override
  Future<void> deleteBoard(String boardId) async => deleted = true;

  @override
  Future<List<WhiteboardVersionSummary>> listVersions(String boardId) async =>
      versions;

  @override
  Future<List<WhiteboardElement>> getVersionElements(String versionId) async =>
      server.snapshot().elements;

  @override
  Future<void> createVersion(String boardId, {String? label}) async =>
      versionsCreated++;

  @override
  Future<WhiteboardMeta> restoreVersion(String versionId) async => meta;

  @override
  Future<String> uploadImage(
    String boardId, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final path = '$boardId/${uploaded.length}.png';
    uploaded[path] = bytes;
    return path;
  }

  @override
  Future<Uint8List> downloadImage(String path) async =>
      uploaded[path] ?? (throw StateError('missing'));

  @override
  Stream<WhiteboardElement> elementChanges(String boardId) => _elements.stream;

  @override
  Stream<WhiteboardMetaChange> metaChanges(String boardId) => metas.stream;

  @override
  Stream<void> listChanges(String conversationId) => const Stream.empty();

  @override
  WhiteboardLive openLive(
    String boardId, {
    required String userId,
    required String name,
    String? avatarUrl,
    required int color,
  }) => live;
}

class FakeLive implements WhiteboardLive {
  final peersController = StreamController<List<WhiteboardPeer>>.broadcast();
  final pointersController = StreamController<WhiteboardPointer>.broadcast();
  final strokesController =
      StreamController<WhiteboardLiveStroke>.broadcast();
  final sentPointers = <Offset>[];
  final sentStrokes = <WhiteboardLiveStroke>[];
  var closed = false;

  @override
  Stream<List<WhiteboardPeer>> get peers => peersController.stream;

  @override
  Stream<WhiteboardPointer> get pointers => pointersController.stream;

  @override
  Stream<WhiteboardLiveStroke> get strokes => strokesController.stream;

  @override
  void sendPointer(double x, double y) => sentPointers.add(Offset(x, y));

  @override
  void sendStroke(WhiteboardLiveStroke stroke) => sentStrokes.add(stroke);

  @override
  Future<void> close() async => closed = true;
}

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
