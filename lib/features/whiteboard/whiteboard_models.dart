import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// What the whiteboard holds and the limits the database keeps (migration
/// 202610281400_whiteboard_schema.sql). The app stops a person before the
/// server would refuse, with a plain message, but the server is the one that
/// decides.
abstract final class WhiteboardLimits {
  static const maxElements = 3000;

  /// Characters of element data in a whole board.
  static const maxDataSize = 6000000;

  /// A stroke has at most this many points (the pen splits a longer line).
  static const maxStrokePoints = 2000;
  static const maxStickyText = 1000;
  static const maxTextLength = 2000;
  static const maxTitle = 100;
  static const maxBoardsPerChat = 20;
  static const maxPictures = 60;

  /// How far from the middle anything may sit.
  static const maxCoordinate = 100000.0;

  /// A picture is scaled down to this many pixels on its longer side before
  /// it is uploaded (and to at most 5 MB).
  static const maxPictureSide = 1600;
  static const maxPictureBytes = 5 * 1024 * 1024;

  /// Most operations one call carries.
  static const opsPerCall = 200;
}

/// What an element is. The names are the values stored in
/// `whiteboard_elements.kind`.
enum WhiteboardKind {
  stroke('stroke'),
  shape('shape'),
  sticky('sticky'),
  text('text'),
  image('image');

  const WhiteboardKind(this.value);

  final String value;

  static WhiteboardKind? fromValue(Object? value) {
    for (final kind in values) {
      if (kind.value == value) {
        return kind;
      }
    }
    return null;
  }
}

/// The shapes (`data.s`).
enum WhiteboardShape {
  rect('rect'),
  ellipse('ellipse'),
  triangle('triangle'),
  diamond('diamond'),
  line('line'),
  arrow('arrow');

  const WhiteboardShape(this.value);

  final String value;

  /// A line or an arrow has two ends instead of a box.
  bool get isSegment => this == line || this == arrow;

  static WhiteboardShape fromValue(Object? value) {
    for (final shape in values) {
      if (shape.value == value) {
        return shape;
      }
    }
    return rect;
  }
}

/// How well [a] and [b] (decoded JSON) say the same thing.
bool deepEquals(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) {
      return false;
    }
    for (final key in a.keys) {
      if (!b.containsKey(key) || !deepEquals(a[key], b[key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  if (a is num && b is num) {
    return a == b;
  }
  return a == b;
}

/// One thing on a board. Immutable: every change makes a new one, which is
/// what the undo history, the sync engine and the painter's caches rely on.
@immutable
class WhiteboardElement {
  WhiteboardElement({
    required this.id,
    required this.kind,
    required this.z,
    Map<String, Object?> data = const {},
    this.rev = 0,
    this.deleted = false,
  }) : data = Map<String, Object?>.unmodifiable(data);

  factory WhiteboardElement.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return WhiteboardElement(
      id: json['id'] as String,
      kind: WhiteboardKind.fromValue(json['kind']) ?? WhiteboardKind.shape,
      z: json['z'] as String? ?? 'V',
      data: data is Map ? Map<String, Object?>.from(data) : const {},
      rev: (json['rev'] as num?)?.toInt() ?? 0,
      deleted: json['deleted'] == true,
    );
  }

  final String id;
  final WhiteboardKind kind;

  /// The fractional ordering key: elements are drawn in (z, id) order.
  final String z;

  /// What the kind needs, see the schema migration.
  final Map<String, Object?> data;

  /// The server's revision; 0 for an element not stored yet.
  final int rev;
  final bool deleted;

  // ------------------------------------------------------------ accessors

  double number(String key, [double fallback = 0]) {
    final value = data[key];
    return value is num ? value.toDouble() : fallback;
  }

  double get x => number('x');
  double get y => number('y');
  double get w => number('w');
  double get h => number('h');

  /// Rotation in radians.
  double get rotation => number('r');
  double get strokeWidth => number('sw', 3);
  double get fontSize => number('fs', 24);

  /// ARGB of the line, the pen, the text or the sticky note.
  int get color => (data['c'] as num?)?.toInt() ?? 0xFF1B1B1F;

  /// ARGB of a shape's fill; null for none.
  int? get fill => (data['f'] as num?)?.toInt();
  String get text => data['t'] as String? ?? '';
  bool get highlighter => data['hl'] == true;
  String get align => data['a'] as String? ?? 'l';
  String get path => data['path'] as String? ?? '';
  WhiteboardShape get shape => WhiteboardShape.fromValue(data['s']);

  /// A stroke's offset since it was drawn (moving one does not rewrite its
  /// points).
  double get offsetX => number('ox');
  double get offsetY => number('oy');

  /// A stroke's points as x, y pairs, as drawn (before the offset).
  late final Float32List points = _readPoints();

  Float32List _readPoints() {
    final raw = data['p'];
    if (raw is! List) {
      return Float32List(0);
    }
    final out = Float32List(raw.length - raw.length % 2);
    for (var i = 0; i < out.length; i++) {
      final v = raw[i];
      out[i] = v is num ? v.toDouble() : 0;
    }
    return out;
  }

  /// A stroke's pressure per point (0 to 1), or null for a mouse.
  late final Float32List? pressures = _readPressures();

  Float32List? _readPressures() {
    final raw = data['pr'];
    if (raw is! List || raw.isEmpty) {
      return null;
    }
    final out = Float32List(raw.length);
    for (var i = 0; i < raw.length; i++) {
      final v = raw[i];
      out[i] = v is num ? (v.toDouble() / 100).clamp(0.0, 1.0) : 0.5;
    }
    return out;
  }

  /// The box the element covers on the board, rotation and line width
  /// included, for hit tests and for skipping what is off screen.
  late final Rect bounds = _computeBounds();

  /// The box before any rotation and without the line width: a shape, a
  /// sticky note, a text or a picture. A stroke's is its points'.
  Rect get box {
    switch (kind) {
      case WhiteboardKind.stroke:
        final pts = points;
        if (pts.length < 2) {
          return Rect.fromLTWH(offsetX, offsetY, 0, 0);
        }
        var minX = pts[0];
        var maxX = pts[0];
        var minY = pts[1];
        var maxY = pts[1];
        for (var i = 2; i < pts.length; i += 2) {
          minX = math.min(minX, pts[i]);
          maxX = math.max(maxX, pts[i]);
          minY = math.min(minY, pts[i + 1]);
          maxY = math.max(maxY, pts[i + 1]);
        }
        return Rect.fromLTRB(
          minX + offsetX,
          minY + offsetY,
          maxX + offsetX,
          maxY + offsetY,
        );
      case WhiteboardKind.shape:
        if (shape.isSegment) {
          return Rect.fromPoints(Offset(x, y), Offset(x + w, y + h));
        }
        return Rect.fromLTWH(x, y, w.abs(), h.abs());
      case WhiteboardKind.text:
        // The writer measures the text and keeps its box (w, h); an older
        // or foreign one without is guessed.
        final width = number('w', 0) > 0 ? number('w') : textWidthGuess;
        final height = number('h', 0) > 0 ? number('h') : textHeight(width);
        return Rect.fromLTWH(x, y, width, height);
      case WhiteboardKind.sticky:
      case WhiteboardKind.image:
        return Rect.fromLTWH(x, y, w.abs(), h.abs());
    }
  }

  /// A text with no set width is as wide as its longest line (a guess that
  /// the painter replaces with the measured size only for drawing).
  double get textWidthGuess {
    var longest = 1;
    for (final line in text.split('\n')) {
      longest = math.max(longest, line.length);
    }
    return math.max(24.0, longest * fontSize * 0.62);
  }

  double textHeight(double width) {
    final charsPerLine = math.max(1, (width / (fontSize * 0.55)).floor());
    var lines = 0;
    for (final line in (text.isEmpty ? ' ' : text).split('\n')) {
      lines += math.max(1, (line.length / charsPerLine).ceil());
    }
    return lines * fontSize * 1.3;
  }

  Rect _computeBounds() {
    var rect = box;
    if (kind == WhiteboardKind.stroke) {
      return rect.inflate(strokeWidth / 2 + 1);
    }
    if (kind == WhiteboardKind.shape) {
      rect = rect.inflate(strokeWidth / 2 + 1);
    }
    if (rotation != 0 && !(kind == WhiteboardKind.shape && shape.isSegment)) {
      final center = rect.center;
      final cosine = math.cos(rotation).abs();
      final sine = math.sin(rotation).abs();
      final halfW = (rect.width * cosine + rect.height * sine) / 2;
      final halfH = (rect.width * sine + rect.height * cosine) / 2;
      rect = Rect.fromCenter(
        center: center,
        width: halfW * 2,
        height: halfH * 2,
      );
    }
    if (kind == WhiteboardKind.shape && shape == WhiteboardShape.arrow) {
      rect = rect.inflate(strokeWidth * 3 + 6);
    }
    return rect;
  }

  /// Characters this element's data takes on the server (an estimate that
  /// is close enough for the app's own warning).
  int get approximateSize {
    var size = 2;
    for (final MapEntry(:key, :value) in data.entries) {
      size += key.length + 4;
      if (value is List) {
        size += value.length * 6;
      } else {
        size += '$value'.length;
      }
    }
    return size;
  }

  // ----------------------------------------------------------------- edit

  WhiteboardElement copyWith({
    String? z,
    Map<String, Object?>? data,
    int? rev,
    bool? deleted,
  }) {
    return WhiteboardElement(
      id: id,
      kind: kind,
      z: z ?? this.z,
      data: data ?? this.data,
      rev: rev ?? this.rev,
      deleted: deleted ?? this.deleted,
    );
  }

  /// This element with [changes] put over its data; a null value removes
  /// the key.
  WhiteboardElement withData(Map<String, Object?> changes, {String? z}) {
    final next = Map<String, Object?>.from(data);
    for (final MapEntry(:key, :value) in changes.entries) {
      if (value == null) {
        next.remove(key);
      } else {
        next[key] = value;
      }
    }
    return copyWith(data: next, z: z);
  }

  /// Whether [other] says the same thing (revisions aside).
  bool sameContent(WhiteboardElement other) {
    return z == other.z &&
        kind == other.kind &&
        deleted == other.deleted &&
        deepEquals(data, other.data);
  }

  /// The operation that stores this element. [baseRev] is the revision it
  /// was based on (null for a new one); [revive] asks for a rubbed-out
  /// element back.
  Map<String, Object?> toPutOp(int? baseRev, {bool revive = false}) => {
    'op': 'put',
    'id': id,
    'kind': kind.value,
    'z': z,
    'data': data,
    'base_rev': ?baseRev,
    if (revive) 'revive': true,
  };

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.value,
    'z': z,
    'data': data,
    'rev': rev,
    'deleted': deleted,
  };

  @override
  String toString() => 'WhiteboardElement($id ${kind.value} rev $rev)';
}

/// Elements in drawing order.
int compareElements(WhiteboardElement a, WhiteboardElement b) {
  final byZ = a.z.compareTo(b.z);
  return byZ != 0 ? byZ : a.id.compareTo(b.id);
}

/// A board: its name, its lock and what the person may do with it.
@immutable
class WhiteboardMeta {
  const WhiteboardMeta({
    required this.id,
    required this.conversationId,
    this.title = '',
    this.managersOnly = false,
    this.createdBy,
    this.updatedBy,
    this.updatedAt,
    this.elementCount = 0,
    this.canEdit = false,
    this.canManage = false,
  });

  factory WhiteboardMeta.fromJson(Map<String, dynamic> json) {
    return WhiteboardMeta(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      managersOnly: json['managers_only'] == true,
      createdBy: json['created_by'] as String?,
      updatedBy: json['updated_by'] as String?,
      updatedAt: DateTime.tryParse('${json['updated_at']}'),
      elementCount: (json['element_count'] as num?)?.toInt() ?? 0,
      canEdit: json['can_edit'] == true,
      canManage: json['can_manage'] == true,
    );
  }

  final String id;
  final String conversationId;
  final String title;
  final bool managersOnly;
  final String? createdBy;
  final String? updatedBy;
  final DateTime? updatedAt;
  final int elementCount;
  final bool canEdit;
  final bool canManage;

  WhiteboardMeta copyWith({
    String? title,
    bool? managersOnly,
    bool? canEdit,
    bool? canManage,
  }) {
    return WhiteboardMeta(
      id: id,
      conversationId: conversationId,
      title: title ?? this.title,
      managersOnly: managersOnly ?? this.managersOnly,
      createdBy: createdBy,
      updatedBy: updatedBy,
      updatedAt: updatedAt,
      elementCount: elementCount,
      canEdit: canEdit ?? this.canEdit,
      canManage: canManage ?? this.canManage,
    );
  }
}

/// A board in a conversation's list.
@immutable
class WhiteboardSummary {
  const WhiteboardSummary({
    required this.id,
    required this.conversationId,
    this.title = '',
    this.managersOnly = false,
    this.updatedByName,
    this.updatedAt,
    this.elementCount = 0,
    this.canEdit = false,
  });

  factory WhiteboardSummary.fromJson(
    Map<String, dynamic> json, {
    required String conversationId,
  }) {
    return WhiteboardSummary(
      id: json['id'] as String,
      conversationId: conversationId,
      title: json['title'] as String? ?? '',
      managersOnly: json['managers_only'] == true,
      updatedByName: json['updated_by_name'] as String?,
      updatedAt: DateTime.tryParse('${json['updated_at']}'),
      elementCount: (json['element_count'] as num?)?.toInt() ?? 0,
      canEdit: json['can_edit'] == true,
    );
  }

  final String id;
  final String conversationId;
  final String title;
  final bool managersOnly;
  final String? updatedByName;
  final DateTime? updatedAt;
  final int elementCount;
  final bool canEdit;
}

/// A board with all its live elements, as the server sent it.
@immutable
class WhiteboardSnapshot {
  const WhiteboardSnapshot({required this.board, required this.elements});

  factory WhiteboardSnapshot.fromJson(Map<String, dynamic> json) {
    return WhiteboardSnapshot(
      board: WhiteboardMeta.fromJson(
        Map<String, dynamic>.from(json['board'] as Map),
      ),
      elements: [
        for (final element in (json['elements'] as List<dynamic>? ?? const []))
          if (element is Map)
            WhiteboardElement.fromJson(Map<String, dynamic>.from(element)),
      ]..sort(compareElements),
    );
  }

  final WhiteboardMeta board;
  final List<WhiteboardElement> elements;
}

/// The server's answer to one operation of whiteboard_apply_ops.
@immutable
class WhiteboardOpResult {
  const WhiteboardOpResult({
    required this.id,
    required this.status,
    this.rev,
    this.element,
    this.reason,
  });

  factory WhiteboardOpResult.fromJson(Map<String, dynamic> json) {
    return WhiteboardOpResult(
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? 'rejected',
      rev: (json['rev'] as num?)?.toInt(),
      element: json['element'] is Map
          ? WhiteboardElement.fromJson(
              Map<String, dynamic>.from(json['element'] as Map),
            )
          : null,
      reason: json['reason'] as String?,
    );
  }

  final String id;

  /// `ok`, `conflict` or `rejected`.
  final String status;
  final int? rev;

  /// The element as stored, for conflicts.
  final WhiteboardElement? element;
  final String? reason;

  bool get isOk => status == 'ok';
  bool get isConflict => status == 'conflict';
}

/// A version of a board in the history.
@immutable
class WhiteboardVersionSummary {
  const WhiteboardVersionSummary({
    required this.id,
    required this.createdAt,
    required this.kind,
    this.createdByName,
    this.label,
    this.elementCount = 0,
  });

  factory WhiteboardVersionSummary.fromJson(Map<String, dynamic> json) {
    return WhiteboardVersionSummary(
      id: json['id'] as String,
      createdAt:
          DateTime.tryParse('${json['created_at']}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      kind: json['kind'] as String? ?? 'auto',
      createdByName: json['created_by_name'] as String?,
      label: json['label'] as String?,
      elementCount: (json['element_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final DateTime createdAt;

  /// `auto`, `manual` or `restore` (taken just before a clear or a restore).
  final String kind;
  final String? createdByName;
  final String? label;
  final int elementCount;
}

/// A change to a board's title or lock, from Realtime.
@immutable
class WhiteboardMetaChange {
  const WhiteboardMetaChange({
    required this.title,
    required this.managersOnly,
    required this.deleted,
  });

  final String title;
  final bool managersOnly;
  final bool deleted;
}

/// A random version 4 UUID for a new element or board.
String newWhiteboardId() {
  final random = math.Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int from, int to) => [
    for (var i = from; i < to; i++) bytes[i].toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
