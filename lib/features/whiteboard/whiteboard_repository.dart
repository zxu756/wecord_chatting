import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/whiteboard/whiteboard_models.dart';
import 'package:wecord/features/whiteboard/whiteboard_sync.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/realtime/private_channels.dart';

/// Somebody else on a board: shown in the header and by their pointer.
@immutable
class WhiteboardPeer {
  const WhiteboardPeer({
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.color = 0xFF3B6EF5,
  });

  factory WhiteboardPeer.fromJson(Map<String, dynamic> json) {
    return WhiteboardPeer(
      userId: json['user_id'] as String,
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      color: (json['color'] as num?)?.toInt() ?? 0xFF3B6EF5,
    );
  }

  final String userId;
  final String name;
  final String? avatarUrl;

  /// The color of their pointer and their live strokes.
  final int color;
}

/// Where somebody's pointer is on the board (board units).
@immutable
class WhiteboardPointer {
  const WhiteboardPointer({
    required this.userId,
    required this.x,
    required this.y,
  });

  final String userId;
  final double x;
  final double y;
}

/// A stroke somebody is drawing right now, before they lift the pen. Only a
/// preview: the stroke itself arrives as an element when it is done.
@immutable
class WhiteboardLiveStroke {
  const WhiteboardLiveStroke({
    required this.userId,
    required this.strokeId,
    required this.points,
    required this.color,
    required this.width,
    this.highlighter = false,
    this.done = false,
  });

  final String userId;
  final String strokeId;

  /// x, y pairs in board units.
  final List<double> points;
  final int color;
  final double width;
  final bool highlighter;

  /// The pen was lifted (the real element follows).
  final bool done;
}

/// Who is on a board, their pointers and live strokes, over a private
/// Realtime channel. Closing it leaves the channel.
abstract interface class WhiteboardLive {
  Stream<List<WhiteboardPeer>> get peers;
  Stream<WhiteboardPointer> get pointers;
  Stream<WhiteboardLiveStroke> get strokes;

  /// Tells the others where this person's pointer is (throttled).
  void sendPointer(double x, double y);

  /// Tells the others about the stroke being drawn (throttled; pass `done`
  /// to end the preview).
  void sendStroke(WhiteboardLiveStroke stroke);

  Future<void> close();
}

abstract interface class WhiteboardRepository implements WhiteboardRemote {
  Future<List<WhiteboardSummary>> listBoards(String conversationId);

  Future<WhiteboardMeta> createBoard(
    String conversationId, {
    String title = '',
    String? id,
  });

  Future<WhiteboardSnapshot> getBoard(String boardId);

  Future<WhiteboardMeta> updateMeta(String boardId, Map<String, Object?> patch);

  /// Rubs out everything (a version is kept first).
  Future<void> clearBoard(String boardId);

  /// Deletes the board and its pictures.
  Future<void> deleteBoard(String boardId);

  Future<List<WhiteboardVersionSummary>> listVersions(String boardId);

  /// The elements of a version, to look at before going back to it.
  Future<List<WhiteboardElement>> getVersionElements(String versionId);

  Future<void> createVersion(String boardId, {String? label});

  Future<WhiteboardMeta> restoreVersion(String versionId);

  /// Stores a picture for the board and returns its storage path.
  Future<String> uploadImage(
    String boardId, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  });

  /// The bytes of a stored picture.
  Future<Uint8List> downloadImage(String path);

  /// Elements of [boardId] as others change them.
  Stream<WhiteboardElement> elementChanges(String boardId);

  /// Title, lock and deletion of [boardId].
  Stream<WhiteboardMetaChange> metaChanges(String boardId);

  /// Changes to the boards of a conversation (a new board, a rename).
  Stream<void> listChanges(String conversationId);

  WhiteboardLive openLive(
    String boardId, {
    required String userId,
    required String name,
    String? avatarUrl,
    required int color,
  });
}

final whiteboardRepositoryProvider = Provider<WhiteboardRepository>((ref) {
  try {
    return SupabaseWhiteboardRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedWhiteboardRepository();
  }
});

String _extension(String fileName, String mimeType) {
  final dot = fileName.lastIndexOf('.');
  if (dot > 0 && dot < fileName.length - 1 && fileName.length - dot <= 6) {
    return fileName.substring(dot + 1).toLowerCase();
  }
  return switch (mimeType) {
    'image/png' => 'png',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    _ => 'jpg',
  };
}

class SupabaseWhiteboardRepository implements WhiteboardRepository {
  const SupabaseWhiteboardRepository(this._client);

  static const bucket = 'whiteboard-files';

  final SupabaseClient _client;

  Map<String, dynamic> _object(Object? data) {
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    if (data is List && data.isNotEmpty && data.first is Map) {
      return Map<String, dynamic>.from(data.first as Map);
    }
    throw StateError('Unexpected response.');
  }

  List<Map<String, dynamic>> _rows(Object? data) {
    return [
      if (data is List)
        for (final row in data)
          if (row is Map) Map<String, dynamic>.from(row),
    ];
  }

  @override
  Future<List<WhiteboardSummary>> listBoards(String conversationId) async {
    final data = await _client.rpc<Object?>(
      'list_whiteboards',
      params: {'p_conversation_id': conversationId},
    );
    return [
      for (final row in _rows(data))
        WhiteboardSummary.fromJson(row, conversationId: conversationId),
    ];
  }

  @override
  Future<WhiteboardMeta> createBoard(
    String conversationId, {
    String title = '',
    String? id,
  }) async {
    final data = await _client.rpc<Object?>(
      'create_whiteboard',
      params: {
        'p_conversation_id': conversationId,
        'p_title': title,
        'p_id': id,
      },
    );
    return WhiteboardMeta.fromJson(_object(data));
  }

  @override
  Future<WhiteboardSnapshot> getBoard(String boardId) async {
    final data = await _client.rpc<Object?>(
      'get_whiteboard',
      params: {'p_board_id': boardId},
    );
    return WhiteboardSnapshot.fromJson(_object(data));
  }

  @override
  Future<List<WhiteboardOpResult>> applyOps(
    String boardId,
    List<Map<String, Object?>> ops,
  ) async {
    final data = await _client.rpc<Object?>(
      'whiteboard_apply_ops',
      params: {'p_board_id': boardId, 'p_ops': ops},
    );
    return [
      for (final row in _rows(data)) WhiteboardOpResult.fromJson(row),
    ];
  }

  @override
  Future<WhiteboardMeta> updateMeta(
    String boardId,
    Map<String, Object?> patch,
  ) async {
    final data = await _client.rpc<Object?>(
      'update_whiteboard_meta',
      params: {'p_board_id': boardId, 'p_patch': patch},
    );
    return WhiteboardMeta.fromJson(_object(data));
  }

  @override
  Future<void> clearBoard(String boardId) async {
    await _client.rpc<Object?>(
      'clear_whiteboard',
      params: {'p_board_id': boardId},
    );
  }

  @override
  Future<void> deleteBoard(String boardId) async {
    final data = await _client.rpc<Object?>(
      'delete_whiteboard',
      params: {'p_board_id': boardId},
    );
    final paths = [
      for (final row in _rows(data))
        if (row['object_path'] is String) row['object_path'] as String,
    ];
    if (paths.isNotEmpty) {
      try {
        await _client.storage.from(bucket).remove(paths);
      } on Object {
        // The board is gone; leftover pictures are only wasted space.
      }
    }
  }

  @override
  Future<List<WhiteboardVersionSummary>> listVersions(String boardId) async {
    final data = await _client.rpc<Object?>(
      'list_whiteboard_versions',
      params: {'p_board_id': boardId},
    );
    return [
      for (final row in _rows(data)) WhiteboardVersionSummary.fromJson(row),
    ];
  }

  @override
  Future<List<WhiteboardElement>> getVersionElements(String versionId) async {
    final data = await _client.rpc<Object?>(
      'get_whiteboard_version',
      params: {'p_version_id': versionId},
    );
    final json = _object(data);
    return [
      for (final element in (json['elements'] as List<dynamic>? ?? const []))
        if (element is Map)
          WhiteboardElement.fromJson(Map<String, dynamic>.from(element)),
    ]..sort(compareElements);
  }

  @override
  Future<void> createVersion(String boardId, {String? label}) async {
    await _client.rpc<Object?>(
      'create_whiteboard_version',
      params: {'p_board_id': boardId, 'p_label': label},
    );
  }

  @override
  Future<WhiteboardMeta> restoreVersion(String versionId) async {
    final data = await _client.rpc<Object?>(
      'restore_whiteboard_version',
      params: {'p_version_id': versionId},
    );
    return WhiteboardMeta.fromJson(_object(data));
  }

  @override
  Future<String> uploadImage(
    String boardId, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final path = '$boardId/$id.${_extension(fileName, mimeType)}';
    await _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    return path;
  }

  @override
  Future<Uint8List> downloadImage(String path) {
    return _client.storage.from(bucket).download(path);
  }

  @override
  Stream<WhiteboardElement> elementChanges(String boardId) {
    late RealtimeChannel channel;
    late StreamController<WhiteboardElement> controller;
    controller = StreamController<WhiteboardElement>(
      onListen: () {
        channel = _client
            .channel('whiteboard-elements-$boardId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'whiteboard_elements',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'board_id',
                value: boardId,
              ),
              callback: (payload) {
                final record = payload.newRecord;
                if (record.isEmpty) {
                  return;
                }
                try {
                  controller.add(WhiteboardElement.fromJson(record));
                } on Object {
                  // A row of a shape we do not know; the next fetch has it.
                }
              },
            )
            .subscribe();
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }

  @override
  Stream<WhiteboardMetaChange> metaChanges(String boardId) {
    late RealtimeChannel channel;
    late StreamController<WhiteboardMetaChange> controller;
    controller = StreamController<WhiteboardMetaChange>(
      onListen: () {
        channel = _client
            .channel('whiteboard-meta-$boardId')
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'whiteboards',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'id',
                value: boardId,
              ),
              callback: (payload) {
                final record = payload.newRecord;
                if (record.isEmpty) {
                  return;
                }
                controller.add(
                  WhiteboardMetaChange(
                    title: record['title'] as String? ?? '',
                    managersOnly: record['managers_only'] == true,
                    deleted: record['deleted_at'] != null,
                  ),
                );
              },
            )
            .subscribe();
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }

  @override
  Stream<void> listChanges(String conversationId) {
    late RealtimeChannel channel;
    late StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        channel = _client
            .channel('whiteboards-$conversationId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'whiteboards',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'conversation_id',
                value: conversationId,
              ),
              callback: (_) => controller.add(null),
            )
            .subscribe();
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }

  @override
  WhiteboardLive openLive(
    String boardId, {
    required String userId,
    required String name,
    String? avatarUrl,
    required int color,
  }) {
    return _SupabaseWhiteboardLive(
      _client,
      boardId,
      userId: userId,
      name: name,
      avatarUrl: avatarUrl,
      color: color,
    );
  }
}

class _SupabaseWhiteboardLive implements WhiteboardLive {
  _SupabaseWhiteboardLive(
    SupabaseClient client,
    String boardId, {
    required this.userId,
    required this.name,
    required this.color,
    this.avatarUrl,
  }) : _client = client {
    _channel = client
        .channel(
          whiteboardLiveTopic(boardId),
          opts: privateChannelConfig(presenceKey: userId),
        )
        .onPresenceSync((_) => _emitPeers())
        .onPresenceJoin((_) => _emitPeers())
        .onPresenceLeave((_) => _emitPeers())
        .onBroadcast(event: 'ptr', callback: _onPointer)
        .onBroadcast(event: 'stroke', callback: _onStroke)
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            _subscribed = true;
            unawaited(
              _channel.track({
                'user_id': userId,
                'name': name,
                'avatar_url': avatarUrl,
                'color': color,
              }),
            );
          }
        });
  }

  final SupabaseClient _client;
  final String userId;
  final String name;
  final String? avatarUrl;
  final int color;
  late final RealtimeChannel _channel;
  final _peers = StreamController<List<WhiteboardPeer>>.broadcast();
  final _pointers = StreamController<WhiteboardPointer>.broadcast();
  final _strokes = StreamController<WhiteboardLiveStroke>.broadcast();
  var _subscribed = false;
  var _closed = false;

  Offset? _pendingPointer;
  Timer? _pointerTimer;
  WhiteboardLiveStroke? _pendingStroke;
  Timer? _strokeTimer;

  @override
  Stream<List<WhiteboardPeer>> get peers => _peers.stream;

  @override
  Stream<WhiteboardPointer> get pointers => _pointers.stream;

  @override
  Stream<WhiteboardLiveStroke> get strokes => _strokes.stream;

  void _emitPeers() {
    if (_closed) {
      return;
    }
    final peers = <WhiteboardPeer>[];
    for (final state in _channel.presenceState()) {
      if (state.key == userId) {
        continue;
      }
      for (final presence in state.presences) {
        try {
          peers.add(WhiteboardPeer.fromJson(presence.payload));
        } on Object {
          // A malformed presence is ignored.
        }
        break;
      }
    }
    _peers.add(peers);
  }

  void _onPointer(Map<String, dynamic> payload) {
    if (_closed) {
      return;
    }
    final who = payload['user_id'];
    final x = payload['x'];
    final y = payload['y'];
    if (who is! String || who == userId || x is! num || y is! num) {
      return;
    }
    _pointers.add(
      WhiteboardPointer(userId: who, x: x.toDouble(), y: y.toDouble()),
    );
  }

  void _onStroke(Map<String, dynamic> payload) {
    if (_closed) {
      return;
    }
    final who = payload['user_id'];
    final id = payload['id'];
    final points = payload['p'];
    if (who is! String || who == userId || id is! String || points is! List) {
      return;
    }
    _strokes.add(
      WhiteboardLiveStroke(
        userId: who,
        strokeId: id,
        points: [
          for (final v in points)
            if (v is num) v.toDouble(),
        ],
        color: (payload['c'] as num?)?.toInt() ?? 0xFF1B1B1F,
        width: (payload['sw'] as num?)?.toDouble() ?? 3,
        highlighter: payload['hl'] == true,
        done: payload['done'] == true,
      ),
    );
  }

  @override
  void sendPointer(double x, double y) {
    if (!_subscribed || _closed) {
      return;
    }
    _pendingPointer = Offset(x, y);
    // At most about ten a second.
    _pointerTimer ??= Timer(const Duration(milliseconds: 100), () {
      _pointerTimer = null;
      final at = _pendingPointer;
      _pendingPointer = null;
      if (at == null || _closed) {
        return;
      }
      unawaited(
        _channel
            .sendBroadcastMessage(
              event: 'ptr',
              payload: {'user_id': userId, 'x': at.dx, 'y': at.dy},
            )
            .then<void>((_) {}, onError: (Object _) {}),
      );
    });
  }

  @override
  void sendStroke(WhiteboardLiveStroke stroke) {
    if (!_subscribed || _closed) {
      return;
    }
    if (stroke.done) {
      _strokeTimer?.cancel();
      _strokeTimer = null;
      _pendingStroke = null;
      _sendStrokeNow(stroke);
      return;
    }
    _pendingStroke = stroke;
    _strokeTimer ??= Timer(const Duration(milliseconds: 120), () {
      _strokeTimer = null;
      final pending = _pendingStroke;
      _pendingStroke = null;
      if (pending != null && !_closed) {
        _sendStrokeNow(pending);
      }
    });
  }

  void _sendStrokeNow(WhiteboardLiveStroke stroke) {
    // Only the newest points of a long preview are worth the bytes.
    const keep = 400;
    final points = stroke.points.length > keep * 2
        ? stroke.points.sublist(stroke.points.length - keep * 2)
        : stroke.points;
    unawaited(
      _channel
          .sendBroadcastMessage(
            event: 'stroke',
            payload: {
              'user_id': userId,
              'id': stroke.strokeId,
              'p': points,
              'c': stroke.color,
              'sw': stroke.width,
              'hl': stroke.highlighter,
              'done': stroke.done,
            },
          )
          .then<void>((_) {}, onError: (Object _) {}),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _pointerTimer?.cancel();
    _strokeTimer?.cancel();
    await _peers.close();
    await _pointers.close();
    await _strokes.close();
    try {
      await _channel.untrack();
    } on Object {
      // Leaving anyway.
    }
    await _client.removeChannel(_channel);
  }
}

/// Used where Supabase is not set up (tests); every call fails.
class UninitializedWhiteboardRepository implements WhiteboardRepository {
  const UninitializedWhiteboardRepository();

  static Never _fail() =>
      throw StateError('Supabase must be initialized first.');

  @override
  Future<List<WhiteboardSummary>> listBoards(String conversationId) async =>
      _fail();

  @override
  Future<WhiteboardMeta> createBoard(
    String conversationId, {
    String title = '',
    String? id,
  }) async => _fail();

  @override
  Future<WhiteboardSnapshot> getBoard(String boardId) async => _fail();

  @override
  Future<List<WhiteboardOpResult>> applyOps(
    String boardId,
    List<Map<String, Object?>> ops,
  ) async => _fail();

  @override
  Future<WhiteboardMeta> updateMeta(
    String boardId,
    Map<String, Object?> patch,
  ) async => _fail();

  @override
  Future<void> clearBoard(String boardId) async => _fail();

  @override
  Future<void> deleteBoard(String boardId) async => _fail();

  @override
  Future<List<WhiteboardVersionSummary>> listVersions(String boardId) async =>
      _fail();

  @override
  Future<List<WhiteboardElement>> getVersionElements(String versionId) async =>
      _fail();

  @override
  Future<void> createVersion(String boardId, {String? label}) async => _fail();

  @override
  Future<WhiteboardMeta> restoreVersion(String versionId) async => _fail();

  @override
  Future<String> uploadImage(
    String boardId, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async => _fail();

  @override
  Future<Uint8List> downloadImage(String path) async => _fail();

  @override
  Stream<WhiteboardElement> elementChanges(String boardId) =>
      const Stream.empty();

  @override
  Stream<WhiteboardMetaChange> metaChanges(String boardId) =>
      const Stream.empty();

  @override
  Stream<void> listChanges(String conversationId) => const Stream.empty();

  @override
  WhiteboardLive openLive(
    String boardId, {
    required String userId,
    required String name,
    String? avatarUrl,
    required int color,
  }) => const _NoLive();
}

class _NoLive implements WhiteboardLive {
  const _NoLive();

  @override
  Stream<List<WhiteboardPeer>> get peers => const Stream.empty();

  @override
  Stream<WhiteboardPointer> get pointers => const Stream.empty();

  @override
  Stream<WhiteboardLiveStroke> get strokes => const Stream.empty();

  @override
  void sendPointer(double x, double y) {}

  @override
  void sendStroke(WhiteboardLiveStroke stroke) {}

  @override
  Future<void> close() async {}
}
