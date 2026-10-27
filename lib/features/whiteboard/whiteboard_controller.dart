import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:wecord/features/whiteboard/whiteboard_geometry.dart';
import 'package:wecord/features/whiteboard/whiteboard_history.dart';
import 'package:wecord/features/whiteboard/whiteboard_images.dart';
import 'package:wecord/features/whiteboard/whiteboard_models.dart';
import 'package:wecord/features/whiteboard/whiteboard_repository.dart';
import 'package:wecord/features/whiteboard/whiteboard_sync.dart';
import 'package:wecord/shared/models/fractional_key.dart';

/// What the person draws with.
enum WhiteboardTool {
  select,
  pen,
  highlighter,
  eraser,
  shape,
  sticky,
  text,
  image,
  hand,
}

/// Why something the person tried did not happen; the page says it plainly.
enum WhiteboardNotice {
  boardFull,
  boardTooBig,
  tooManyPictures,
  readOnly,
  pictureFailed,
  rejected,
}

enum WhiteboardLoadState { loading, ready, failed, gone }

/// The colors on offer for lines, shapes and text.
const whiteboardInkColors = <int>[
  0xFF1B1B1F,
  0xFFE5484D,
  0xFFF76B15,
  0xFFE6A700,
  0xFF30A46C,
  0xFF3B6EF5,
  0xFF8E4EC6,
  0xFF8B8D98,
];

/// The colors of sticky notes.
const whiteboardNoteColors = <int>[
  0xFFFFE08A,
  0xFFFFC9C9,
  0xFFC7F0D2,
  0xFFCDE3FF,
  0xFFE6D5FF,
  0xFFFFD8A8,
];

/// The line widths on offer.
const whiteboardWidths = <double>[2, 4, 8, 14];

/// A line being drawn right now.
class WhiteboardInkInProgress {
  WhiteboardInkInProgress({
    required this.id,
    required this.color,
    required this.width,
    required this.highlighter,
    required this.usesPressure,
  });

  final String id;
  final int color;
  final double width;
  final bool highlighter;
  final bool usesPressure;
  final points = <Offset>[];
  final pressures = <double>[];

  List<double> get flat => [
    for (final p in points) ...[p.dx, p.dy],
  ];
}

/// Everything a person does on one board, apart from painting it: loading,
/// the tools, selecting and moving, undo, the live view of other people, and
/// keeping the local copy in step with the server.
class WhiteboardController extends ChangeNotifier {
  WhiteboardController({
    required this.boardId,
    required this.repository,
    required this.userId,
    required this.userName,
    this.avatarUrl,
    WhiteboardDraftStore? drafts,
    this.flushDelay = const Duration(milliseconds: 350),
    String Function()? newId,
  }) : drafts = drafts ?? const SharedPreferencesWhiteboardDraftStore(),
       _newId = newId ?? newWhiteboardId {
    engine = WhiteboardSyncEngine(boardId: boardId, remote: repository)
      ..addListener(_onEngine);
    images = WhiteboardImageStore(download: repository.downloadImage);
    myColor = _peerColorFor(userId);
  }

  final String boardId;
  final WhiteboardRepository repository;
  final String userId;
  final String userName;
  final String? avatarUrl;
  final WhiteboardDraftStore drafts;
  final Duration flushDelay;
  final String Function() _newId;

  late final WhiteboardSyncEngine engine;
  late final WhiteboardImageStore images;
  final history = WhiteboardHistory();
  late final int myColor;

  WhiteboardLoadState loadState = WhiteboardLoadState.loading;
  WhiteboardMeta? meta;
  WhiteboardNotice? notice;
  var noticeSerial = 0;
  var _disposed = false;

  /// Bumps for every repaint-worthy change.
  int get paintVersion => _paintVersion;
  var _paintVersion = 0;

  bool get canEdit => meta?.canEdit ?? false;
  bool get canManage => meta?.canManage ?? false;
  String get title => meta?.title ?? '';

  // ---------------------------------------------------------------- tools --

  WhiteboardTool tool = WhiteboardTool.pen;
  int inkColor = whiteboardInkColors.first;
  double inkWidth = whiteboardWidths[1];
  WhiteboardShape shapeKind = WhiteboardShape.rect;
  bool shapeFilled = false;
  int noteColor = whiteboardNoteColors.first;

  /// An Apple Pencil (or another stylus) was used: fingers then only move
  /// the view, so a resting palm does not draw.
  bool stylusSeen = false;

  void setTool(WhiteboardTool next) {
    if (tool == next) {
      return;
    }
    _finishEdit();
    tool = next;
    if (next != WhiteboardTool.select) {
      selection = const {};
    }
    _changed();
  }

  /// Back to Select after a note or text was placed; keeps the selection
  /// and the typing that just started.
  void returnToSelect() {
    tool = WhiteboardTool.select;
    _changed();
  }

  void setInkColor(int color) {
    inkColor = color;
    if (selection.isNotEmpty) {
      _changeSelection((e) {
        switch (e.kind) {
          case WhiteboardKind.sticky:
            return e.withData({'c': color});
          case WhiteboardKind.shape:
            return e.withData({
              'c': color,
              if (e.fill != null) 'f': color,
            });
          case WhiteboardKind.stroke:
          case WhiteboardKind.text:
            return e.withData({'c': color});
          case WhiteboardKind.image:
            return e;
        }
      });
    }
    _changed();
  }

  void setNoteColor(int color) {
    noteColor = color;
    if (selection.isNotEmpty) {
      _changeSelection(
        (e) => e.kind == WhiteboardKind.sticky ? e.withData({'c': color}) : e,
      );
    }
    _changed();
  }

  void setInkWidth(double width) {
    inkWidth = width;
    if (selection.isNotEmpty) {
      _changeSelection(
        (e) => e.kind == WhiteboardKind.stroke || e.kind == WhiteboardKind.shape
            ? e.withData({'sw': width})
            : e,
      );
    }
    _changed();
  }

  void setShapeKind(WhiteboardShape shape) {
    shapeKind = shape;
    tool = WhiteboardTool.shape;
    selection = const {};
    _changed();
  }

  void setShapeFilled(bool filled) {
    shapeFilled = filled;
    if (selection.isNotEmpty) {
      _changeSelection(
        (e) => e.kind == WhiteboardKind.shape && !e.shape.isSegment
            ? e.withData({'f': filled ? e.color : null})
            : e,
      );
    }
    _changed();
  }

  void setFontSize(double size) {
    _changeSelection(
      (e) => e.kind == WhiteboardKind.text
          ? e.withData({'fs': size, 'w': null, 'h': null})
          : e,
    );
    _changed();
  }

  // ----------------------------------------------------------------- view --

  WhiteboardView view = const WhiteboardView();
  Size viewport = Size.zero;

  void setView(WhiteboardView next) {
    view = next;
    _changed();
  }

  void fitToContent() {
    final bounds = unionBounds(engine.elements);
    if (viewport.isEmpty) {
      return;
    }
    view = bounds == null
        ? WhiteboardView(
            offset: Offset(viewport.width / 2, viewport.height / 2),
          )
        : WhiteboardView.fit(bounds, viewport);
    _changed();
  }

  /// Board units for [screen].
  Offset toBoard(Offset screen) => view.toBoard(screen);

  // -------------------------------------------------------------- loading --

  StreamSubscription<WhiteboardElement>? _elementsSub;
  StreamSubscription<WhiteboardMetaChange>? _metaSub;
  StreamSubscription<List<WhiteboardPeer>>? _peersSub;
  StreamSubscription<WhiteboardPointer>? _pointersSub;
  StreamSubscription<WhiteboardLiveStroke>? _liveStrokesSub;
  WhiteboardLive? _live;
  Timer? _flushTimer;
  Timer? _cursorSweep;

  List<WhiteboardPeer> peers = const [];
  final pointers = <String, ({Offset at, DateTime seen})>{};
  final liveStrokes = <String, WhiteboardLiveStroke>{};

  Future<void> load() async {
    loadState = WhiteboardLoadState.loading;
    _changed();
    final WhiteboardSnapshot snapshot;
    try {
      snapshot = await repository.getBoard(boardId);
    } on Object {
      if (_disposed) {
        return;
      }
      loadState = WhiteboardLoadState.failed;
      _changed();
      return;
    }
    if (_disposed) {
      return;
    }
    WhiteboardDraft? draft;
    try {
      draft = await drafts.load(boardId);
    } on Object {
      draft = null;
    }
    if (_disposed) {
      return;
    }
    meta = snapshot.board;
    engine.load(snapshot, draft: draft);
    loadState = WhiteboardLoadState.ready;
    _subscribe();
    if (engine.hasPendingChanges) {
      _scheduleFlush();
    }
    _changed();
  }

  void _subscribe() {
    _elementsSub = repository.elementChanges(boardId).listen((element) {
      engine.receiveRemote(element);
      if (element.deleted && selection.contains(element.id)) {
        selection = {...selection}..remove(element.id);
      }
    });
    _metaSub = repository.metaChanges(boardId).listen(_onMetaChange);
    final live = repository.openLive(
      boardId,
      userId: userId,
      name: userName,
      avatarUrl: avatarUrl,
      color: myColor,
    );
    _live = live;
    _peersSub = live.peers.listen((list) {
      peers = list;
      final ids = {for (final p in list) p.userId};
      pointers.removeWhere((id, _) => !ids.contains(id));
      liveStrokes.removeWhere((_, s) => !ids.contains(s.userId));
      _changed();
    });
    _pointersSub = live.pointers.listen((pointer) {
      pointers[pointer.userId] = (
        at: Offset(pointer.x, pointer.y),
        seen: DateTime.now(),
      );
      _paintOnly();
    });
    _liveStrokesSub = live.strokes.listen((stroke) {
      if (stroke.done) {
        liveStrokes.remove(stroke.userId);
      } else {
        liveStrokes[stroke.userId] = stroke;
      }
      _paintOnly();
    });
    _cursorSweep = Timer.periodic(const Duration(seconds: 4), (_) {
      final limit = DateTime.now().subtract(const Duration(seconds: 8));
      final before = pointers.length;
      pointers.removeWhere((_, value) => value.seen.isBefore(limit));
      if (pointers.length != before) {
        _paintOnly();
      }
    });
  }

  Future<void> _onMetaChange(WhiteboardMetaChange change) async {
    final current = meta;
    if (current == null) {
      return;
    }
    if (change.deleted) {
      loadState = WhiteboardLoadState.gone;
      _changed();
      return;
    }
    final lockChanged = change.managersOnly != current.managersOnly;
    meta = current.copyWith(
      title: change.title,
      managersOnly: change.managersOnly,
    );
    _changed();
    if (lockChanged) {
      // What this person may do depends on the lock and on their role.
      try {
        final fresh = await repository.getBoard(boardId);
        if (!_disposed) {
          meta = fresh.board;
          _changed();
        }
      } on Object {
        // Keep what is known.
      }
    }
  }

  /// Reads the board again (after a restore or a clear).
  Future<void> reload() async {
    try {
      final snapshot = await repository.getBoard(boardId);
      if (_disposed) {
        return;
      }
      meta = snapshot.board;
      selection = const {};
      history.clear();
      engine.load(snapshot);
      _changed();
    } on Object {
      // The realtime changes bring the same state.
    }
  }

  // ----------------------------------------------------------- engine sync --

  void _onEngine() {
    if (_disposed) {
      return;
    }
    if (engine.lastRejection != null) {
      final reason = engine.lastRejection;
      engine.lastRejection = null;
      _notice(
        reason == 'too many elements'
            ? WhiteboardNotice.boardFull
            : reason == 'too much data'
            ? WhiteboardNotice.boardTooBig
            : WhiteboardNotice.rejected,
      );
    }
    _paintVersion++;
    notifyListeners();
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(flushDelay, () {
      _flushTimer = null;
      unawaited(flushNow());
    });
  }

  /// Sends what is waiting and keeps the draft in step.
  Future<void> flushNow() async {
    if (_disposed) {
      return;
    }
    final ok = await engine.flush();
    if (_disposed) {
      return;
    }
    await _saveDraft();
    if (!ok) {
      // Try again in a while; the draft already keeps the work.
      _flushTimer?.cancel();
      _flushTimer = Timer(const Duration(seconds: 6), () {
        _flushTimer = null;
        unawaited(flushNow());
      });
    }
  }

  Future<void> _saveDraft() async {
    try {
      if (engine.hasPendingChanges) {
        await drafts.save(engine.toDraft());
      } else {
        await drafts.clear(boardId);
      }
    } on Object {
      // The draft is a courtesy; the server copy is what counts.
    }
  }

  /// Called after every local change.
  void _local() {
    if (!canEdit) {
      return;
    }
    _scheduleFlush();
    unawaited(_saveDraft());
  }

  void _notice(WhiteboardNotice value) {
    notice = value;
    noticeSerial++;
    _paintVersion++;
    notifyListeners();
  }

  void _changed() {
    if (_disposed) {
      return;
    }
    _paintVersion++;
    notifyListeners();
  }

  void _paintOnly() {
    if (_disposed) {
      return;
    }
    _paintVersion++;
    notifyListeners();
  }

  // ----------------------------------------------------------- selection --

  Set<String> selection = const {};

  List<WhiteboardElement> get selectedElements => [
    for (final id in selection)
      if (engine.elementById(id) != null) engine.elementById(id)!,
  ]..sort(compareElements);

  void select(Iterable<String> ids) {
    selection = {...ids};
    _changed();
  }

  void clearSelection() {
    if (selection.isEmpty) {
      return;
    }
    _finishEdit();
    selection = const {};
    _changed();
  }

  /// The topmost element under [point] (board units), or null.
  WhiteboardElement? hitAt(Offset point, {double slop = 8}) {
    final tolerance = slop / view.scale;
    final list = engine.elements;
    for (var i = list.length - 1; i >= 0; i--) {
      if (hitTestElement(list[i], point, tolerance: tolerance)) {
        return list[i];
      }
    }
    return null;
  }

  void tapSelect(Offset point, {bool additive = false}) {
    final hit = hitAt(point);
    if (hit == null) {
      if (!additive) {
        clearSelection();
      }
      return;
    }
    if (additive) {
      selection = selection.contains(hit.id)
          ? ({...selection}..remove(hit.id))
          : {...selection, hit.id};
    } else {
      selection = {hit.id};
    }
    _changed();
  }

  void selectAll() {
    selection = {for (final e in engine.elements) e.id};
    _changed();
  }

  // ------------------------------------------------------ adding elements --

  bool _allowEdit() {
    if (canEdit) {
      return true;
    }
    _notice(WhiteboardNotice.readOnly);
    return false;
  }

  bool _hasRoomFor(int count, {int bytes = 0}) {
    if (engine.liveCount + count > WhiteboardLimits.maxElements) {
      _notice(WhiteboardNotice.boardFull);
      return false;
    }
    if (engine.approximateSize + bytes > WhiteboardLimits.maxDataSize) {
      _notice(WhiteboardNotice.boardTooBig);
      return false;
    }
    return true;
  }

  String _topKey() {
    final list = engine.elements;
    return keyBetween(list.isEmpty ? null : list.last.z, null);
  }

  List<String> _topKeys(int count) {
    final list = engine.elements;
    return keysBetween(list.isEmpty ? null : list.last.z, null, count);
  }

  void _add(List<WhiteboardElement> created) {
    engine.upsertAll(created);
    history.record([
      for (final e in created) ElementChange(id: e.id, after: e),
    ]);
    _local();
  }

  // Pen and highlighter ----------------------------------------------------

  WhiteboardInkInProgress? ink;

  void beginStroke(
    Offset point, {
    double? pressure,
    PointerDeviceKind kind = PointerDeviceKind.mouse,
  }) {
    if (!_allowEdit() || !_hasRoomFor(1)) {
      return;
    }
    final stylus =
        kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus;
    if (stylus) {
      stylusSeen = true;
    }
    final highlighter = tool == WhiteboardTool.highlighter;
    ink = WhiteboardInkInProgress(
      id: _newId(),
      color: inkColor,
      width: highlighter ? math.max(inkWidth * 3, 14) : inkWidth,
      highlighter: highlighter,
      usesPressure: stylus && !highlighter,
    );
    _addInkPoint(point, pressure);
    _changed();
  }

  void extendStroke(Offset point, {double? pressure}) {
    final current = ink;
    if (current == null) {
      return;
    }
    final last = current.points.last;
    if ((point - last).distance * view.scale < 1.2) {
      return;
    }
    _addInkPoint(point, pressure);
    _live?.sendStroke(
      WhiteboardLiveStroke(
        userId: userId,
        strokeId: current.id,
        points: current.flat,
        color: current.color,
        width: current.width,
        highlighter: current.highlighter,
      ),
    );
    _paintOnly();
  }

  void _addInkPoint(Offset point, double? pressure) {
    final current = ink!;
    current.points.add(
      Offset(
        clampCoordinate(point.dx),
        clampCoordinate(point.dy),
      ),
    );
    current.pressures.add((pressure ?? 0.5).clamp(0.0, 1.0));
  }

  void endStroke() {
    final current = ink;
    ink = null;
    if (current == null) {
      return;
    }
    _live?.sendStroke(
      WhiteboardLiveStroke(
        userId: userId,
        strokeId: current.id,
        points: const [],
        color: current.color,
        width: current.width,
        done: true,
      ),
    );
    final simplified = simplifyStroke(
      current.points,
      current.usesPressure ? current.pressures : null,
    );
    final pieces = splitStroke(simplified.points, simplified.pressures);
    if (!_hasRoomFor(pieces.length)) {
      _changed();
      return;
    }
    final keys = _topKeys(pieces.length);
    final created = <WhiteboardElement>[
      for (var i = 0; i < pieces.length; i++)
        WhiteboardElement(
          id: i == 0 ? current.id : _newId(),
          kind: WhiteboardKind.stroke,
          z: keys[i],
          data: {
            'p': pieces[i].points,
            'pr': ?pieces[i].pressures,
            'c': current.color,
            'sw': current.width,
            if (current.highlighter) 'hl': true,
          },
        ),
    ];
    _add(created);
    _changed();
  }

  void cancelStroke() {
    if (ink != null) {
      ink = null;
      _changed();
    }
  }

  // Shapes -----------------------------------------------------------------

  WhiteboardElement? shapeDraft;
  Offset? _shapeStart;

  void beginShape(Offset start) {
    if (!_allowEdit() || !_hasRoomFor(1)) {
      return;
    }
    _shapeStart = start;
    shapeDraft = _shapeFrom(start, start);
    _changed();
  }

  void updateShape(Offset end) {
    final start = _shapeStart;
    if (start == null) {
      return;
    }
    shapeDraft = _shapeFrom(start, end);
    _live?.sendPointer(end.dx, end.dy);
    _paintOnly();
  }

  WhiteboardElement _shapeFrom(Offset a, Offset b) {
    final id = shapeDraft?.id ?? _newId();
    final data = <String, Object?>{'s': shapeKind.value, 'c': inkColor, 'sw': inkWidth};
    if (shapeKind.isSegment) {
      data
        ..['x'] = round1(clampCoordinate(a.dx))
        ..['y'] = round1(clampCoordinate(a.dy))
        ..['w'] = round1(b.dx - a.dx)
        ..['h'] = round1(b.dy - a.dy);
    } else {
      final rect = Rect.fromPoints(a, b);
      data
        ..['x'] = round1(clampCoordinate(rect.left))
        ..['y'] = round1(clampCoordinate(rect.top))
        ..['w'] = round1(rect.width)
        ..['h'] = round1(rect.height);
      if (shapeFilled) {
        data['f'] = inkColor;
      }
    }
    return WhiteboardElement(
      id: id,
      kind: WhiteboardKind.shape,
      z: _topKey(),
      data: data,
    );
  }

  void endShape() {
    var draft = shapeDraft;
    final start = _shapeStart;
    shapeDraft = null;
    _shapeStart = null;
    if (draft == null || start == null) {
      return;
    }
    final tiny = shapeKind.isSegment
        ? math.sqrt(draft.w * draft.w + draft.h * draft.h) * view.scale < 8
        : draft.w * view.scale < 8 && draft.h * view.scale < 8;
    if (tiny) {
      // A tap makes a shape of a pleasant size around the tap.
      final end = shapeKind.isSegment
          ? start + const Offset(140, 0)
          : start + const Offset(120, 80);
      draft = _shapeFrom(start, end);
    }
    _add([draft]);
    selection = {draft.id};
    _changed();
  }

  // Sticky notes, text and pictures ---------------------------------------

  /// The sticky note or text being typed in.
  String? editingId;
  WhiteboardElement? _editStart;

  WhiteboardElement? addSticky(Offset at) {
    if (!_allowEdit() || !_hasRoomFor(1)) {
      return null;
    }
    final element = WhiteboardElement(
      id: _newId(),
      kind: WhiteboardKind.sticky,
      z: _topKey(),
      data: {
        'x': round1(clampCoordinate(at.dx - 80)),
        'y': round1(clampCoordinate(at.dy - 60)),
        'w': 160.0,
        'h': 120.0,
        't': '',
        'c': noteColor,
        'fs': 18.0,
      },
    );
    _add([element]);
    selection = {element.id};
    _beginEdit(element);
    return element;
  }

  WhiteboardElement? addText(Offset at) {
    if (!_allowEdit() || !_hasRoomFor(1)) {
      return null;
    }
    final element = WhiteboardElement(
      id: _newId(),
      kind: WhiteboardKind.text,
      z: _topKey(),
      data: {
        'x': round1(clampCoordinate(at.dx)),
        'y': round1(clampCoordinate(at.dy)),
        't': '',
        'c': inkColor,
        'fs': 24.0,
      },
    );
    // A text with nothing in it is not stored until it has words.
    engine.upsert(element);
    selection = {element.id};
    _beginEdit(element, isNew: true);
    return element;
  }

  bool _editingNew = false;

  void _beginEdit(WhiteboardElement element, {bool isNew = false}) {
    editingId = element.id;
    _editStart = isNew ? null : element;
    _editingNew = isNew;
    _changed();
  }

  /// Starts typing in an existing sticky note or text.
  void beginEditing(String id) {
    final element = engine.elementById(id);
    if (element == null ||
        !_allowEdit() ||
        (element.kind != WhiteboardKind.sticky &&
            element.kind != WhiteboardKind.text)) {
      return;
    }
    selection = {id};
    _beginEdit(element);
  }

  /// The words of the element being typed in; [measured] is the size the
  /// words take (a text keeps it so everyone sees the same box).
  void setEditingText(String text, {Size? measured}) {
    final id = editingId;
    final element = id == null ? null : engine.elementById(id);
    if (element == null) {
      return;
    }
    final limit = element.kind == WhiteboardKind.sticky
        ? WhiteboardLimits.maxStickyText
        : WhiteboardLimits.maxTextLength;
    final clipped = text.length > limit ? text.substring(0, limit) : text;
    final changes = <String, Object?>{'t': clipped};
    if (element.kind == WhiteboardKind.text && measured != null) {
      changes['w'] = round1(math.max(24, measured.width));
      changes['h'] = round1(math.max(element.fontSize, measured.height));
    }
    engine.upsert(element.withData(changes));
    _local();
  }

  /// Done typing: an empty new text goes away, the rest is one undo step.
  void finishEditing() => _finishEdit();

  void _finishEdit() {
    final id = editingId;
    if (id == null) {
      return;
    }
    editingId = null;
    final element = engine.elementById(id);
    final start = _editStart;
    final isNew = _editingNew;
    _editStart = null;
    _editingNew = false;
    if (element == null) {
      _changed();
      return;
    }
    if (isNew && element.kind == WhiteboardKind.text) {
      if (element.text.trim().isEmpty) {
        engine.remove(id);
        selection = const {};
      } else {
        history.record([ElementChange(id: id, after: element)]);
        _local();
      }
    } else if (start != null) {
      history.record([ElementChange(id: id, before: start, after: element)]);
    }
    _changed();
  }

  /// Adds a sticky note or a text with its words already written (the list
  /// view uses this; no typing on the canvas needed). Placed at [at] or in
  /// the middle of what is on screen.
  WhiteboardElement? addWords({required bool sticky, required String text, Offset? at}) {
    if (!_allowEdit() || !_hasRoomFor(1)) {
      return null;
    }
    final limit = sticky ? WhiteboardLimits.maxStickyText : WhiteboardLimits.maxTextLength;
    final words = text.length > limit ? text.substring(0, limit) : text;
    final center = at ?? view.toBoard(viewport.center(Offset.zero));
    final measured = sticky ? null : measureWords(words, 24);
    final element = WhiteboardElement(
      id: _newId(),
      kind: sticky ? WhiteboardKind.sticky : WhiteboardKind.text,
      z: _topKey(),
      data: sticky
          ? {
              'x': round1(clampCoordinate(center.dx - 80)),
              'y': round1(clampCoordinate(center.dy - 60)),
              'w': 160.0,
              'h': 120.0,
              't': words,
              'c': noteColor,
              'fs': 18.0,
            }
          : {
              'x': round1(clampCoordinate(center.dx)),
              'y': round1(clampCoordinate(center.dy)),
              't': words,
              'c': inkColor,
              'fs': 24.0,
              if (measured != null) 'w': round1(math.max(24, measured.width)),
              if (measured != null) 'h': round1(measured.height),
            },
    );
    _add([element]);
    selection = {element.id};
    _changed();
    return element;
  }

  /// Replaces the words of a sticky note or a text as one undo step.
  void replaceWords(String id, String text) {
    final element = engine.elementById(id);
    if (element == null ||
        !_allowEdit() ||
        (element.kind != WhiteboardKind.sticky && element.kind != WhiteboardKind.text)) {
      return;
    }
    final limit = element.kind == WhiteboardKind.sticky
        ? WhiteboardLimits.maxStickyText
        : WhiteboardLimits.maxTextLength;
    final words = text.length > limit ? text.substring(0, limit) : text;
    final changes = <String, Object?>{'t': words};
    if (element.kind == WhiteboardKind.text) {
      final size = measureWords(words, element.fontSize);
      changes['w'] = round1(math.max(24, size.width));
      changes['h'] = round1(size.height);
    }
    final next = element.withData(changes);
    engine.upsert(next);
    history.record([ElementChange(id: id, before: element, after: next)]);
    _local();
    _changed();
  }

  /// How the words are measured; the page sets this to real text layout.
  Size Function(String text, double fontSize) measureWords = _guessWords;

  static Size _guessWords(String text, double fontSize) {
    var longest = 1;
    var lines = 0;
    for (final line in (text.isEmpty ? ' ' : text).split('\n')) {
      longest = math.max(longest, line.length);
      lines++;
    }
    return Size(longest * fontSize * 0.6, lines * fontSize * 1.3);
  }

  /// Puts a picture on the board. [bytes] are already scaled down.
  Future<bool> addImage(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    required Size pixels,
    Offset? at,
  }) async {
    if (!_allowEdit() || !_hasRoomFor(1)) {
      return false;
    }
    final pictures = engine.elements
        .where((e) => e.kind == WhiteboardKind.image)
        .length;
    if (pictures >= WhiteboardLimits.maxPictures) {
      _notice(WhiteboardNotice.tooManyPictures);
      return false;
    }
    final String path;
    try {
      path = await repository.uploadImage(
        boardId,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
      );
    } on Object {
      _notice(WhiteboardNotice.pictureFailed);
      return false;
    }
    if (_disposed) {
      return false;
    }
    await images.put(path, bytes);
    final ratio = pixels.width <= 0 || pixels.height <= 0
        ? 1.0
        : pixels.width / pixels.height;
    final width = math.min(360.0, pixels.width <= 0 ? 360.0 : pixels.width);
    final height = width / ratio;
    final center = at ?? view.toBoard(viewport.center(Offset.zero));
    final element = WhiteboardElement(
      id: _newId(),
      kind: WhiteboardKind.image,
      z: _topKey(),
      data: {
        'x': round1(clampCoordinate(center.dx - width / 2)),
        'y': round1(clampCoordinate(center.dy - height / 2)),
        'w': round1(width),
        'h': round1(height),
        'path': path,
      },
    );
    _add([element]);
    selection = {element.id};
    _changed();
    return true;
  }

  // ------------------------------------------------------------- erasing --

  final _erased = <ElementChange>[];

  void beginErase(Offset point) {
    if (!_allowEdit()) {
      return;
    }
    _erased.clear();
    eraseAt(point);
  }

  void eraseAt(Offset point) {
    if (!canEdit) {
      return;
    }
    final hit = hitAt(point, slop: 10);
    if (hit == null) {
      return;
    }
    _erased.add(ElementChange(id: hit.id, before: hit));
    engine.remove(hit.id);
    selection = {...selection}..remove(hit.id);
  }

  void endErase() {
    if (_erased.isNotEmpty) {
      history.record(List.of(_erased));
      _erased.clear();
      _local();
    }
    _changed();
  }

  // ------------------------------------------------- moving and resizing --

  final _dragOrigin = <String, WhiteboardElement>{};

  /// Whether a drag starting at [point] would move the selection.
  bool pointOnSelection(Offset point) {
    final tolerance = 8 / view.scale;
    for (final e in selectedElements) {
      if (hitTestElement(e, point, tolerance: tolerance)) {
        return true;
      }
    }
    return false;
  }

  void beginMove() {
    if (!_allowEdit()) {
      return;
    }
    _finishEdit();
    _dragOrigin
      ..clear()
      ..addEntries([for (final e in selectedElements) MapEntry(e.id, e)]);
  }

  void moveBy(Offset delta) {
    if (_dragOrigin.isEmpty) {
      return;
    }
    engine.upsertAll([
      for (final origin in _dragOrigin.values) movedBy(origin, delta),
    ]);
  }

  void endMove() => _commitDrag();

  WhiteboardHandle? _handle;

  /// The handle under [point], for the single selected element.
  WhiteboardHandle? handleAt(Offset point) {
    if (!canEdit || selection.length != 1) {
      return null;
    }
    final element = engine.elementById(selection.first);
    if (element == null) {
      return null;
    }
    final reach = 16 / view.scale;
    for (final entry in handlesOf(element).entries) {
      if ((entry.value - point).distance <= reach) {
        return entry.key;
      }
    }
    return null;
  }

  void beginResize(WhiteboardHandle handle) {
    if (!_allowEdit()) {
      return;
    }
    _finishEdit();
    _handle = handle;
    _dragOrigin
      ..clear()
      ..addEntries([for (final e in selectedElements) MapEntry(e.id, e)]);
  }

  void resizeTo(Offset point) {
    final handle = _handle;
    if (handle == null || _dragOrigin.length != 1) {
      return;
    }
    engine.upsert(resizedBy(_dragOrigin.values.first, handle, point));
  }

  void endResize() {
    _handle = null;
    _commitDrag();
  }

  void _commitDrag() {
    final changes = <ElementChange>[];
    for (final origin in _dragOrigin.values) {
      final now = engine.elementById(origin.id);
      if (now != null && !now.sameContent(origin)) {
        changes.add(ElementChange(id: origin.id, before: origin, after: now));
      }
    }
    _dragOrigin.clear();
    if (changes.isNotEmpty) {
      history.record(changes);
      _local();
    }
    _changed();
  }

  // Marquee -----------------------------------------------------------------

  Rect? marquee;
  Offset? _marqueeStart;

  void beginMarquee(Offset start) {
    _marqueeStart = start;
    marquee = Rect.fromPoints(start, start);
    _changed();
  }

  void updateMarquee(Offset end) {
    final start = _marqueeStart;
    if (start == null) {
      return;
    }
    marquee = Rect.fromPoints(start, end);
    _paintOnly();
  }

  void endMarquee({bool additive = false}) {
    final area = marquee;
    marquee = null;
    _marqueeStart = null;
    if (area == null) {
      return;
    }
    final inside = {
      for (final e in elementsInView(engine.elements, area))
        if (elementInMarquee(e, area)) e.id,
    };
    selection = additive ? {...selection, ...inside} : inside;
    _changed();
  }

  // ------------------------------------------------------- selection edits --

  void _changeSelection(WhiteboardElement Function(WhiteboardElement) change) {
    if (!canEdit) {
      return;
    }
    final changes = <ElementChange>[];
    final puts = <WhiteboardElement>[];
    for (final element in selectedElements) {
      final next = change(element);
      if (!next.sameContent(element)) {
        puts.add(next);
        changes.add(ElementChange(id: element.id, before: element, after: next));
      }
    }
    if (puts.isEmpty) {
      return;
    }
    engine.upsertAll(puts);
    history.record(changes);
    _local();
  }

  void deleteSelection() {
    if (!_allowEdit()) {
      return;
    }
    _finishEdit();
    final victims = selectedElements;
    if (victims.isEmpty) {
      return;
    }
    engine.removeAll([for (final e in victims) e.id]);
    history.record([for (final e in victims) ElementChange(id: e.id, before: e)]);
    selection = const {};
    _local();
    _changed();
  }

  void duplicateSelection() {
    if (!_allowEdit()) {
      return;
    }
    final originals = selectedElements;
    if (originals.isEmpty || !_hasRoomFor(originals.length)) {
      return;
    }
    final keys = _topKeys(originals.length);
    final copies = [
      for (var i = 0; i < originals.length; i++)
        movedBy(
          WhiteboardElement(
            id: _newId(),
            kind: originals[i].kind,
            z: keys[i],
            data: originals[i].data,
          ),
          const Offset(24, 24),
        ),
    ];
    _add(copies);
    selection = {for (final c in copies) c.id};
    _changed();
  }

  void bringToFront() => _reorder(toFront: true);

  void sendToBack() => _reorder(toFront: false);

  void _reorder({required bool toFront}) {
    if (!_allowEdit()) {
      return;
    }
    final chosen = selectedElements;
    if (chosen.isEmpty) {
      return;
    }
    final list = engine.elements;
    final others = [
      for (final e in list)
        if (!selection.contains(e.id)) e,
    ];
    final keys = toFront
        ? keysBetween(others.isEmpty ? null : others.last.z, null, chosen.length)
        : keysBetween(null, others.isEmpty ? null : others.first.z, chosen.length);
    final changes = <ElementChange>[];
    final puts = <WhiteboardElement>[];
    for (var i = 0; i < chosen.length; i++) {
      final next = chosen[i].copyWith(z: keys[i]);
      puts.add(next);
      changes.add(ElementChange(id: chosen[i].id, before: chosen[i], after: next));
    }
    engine.upsertAll(puts);
    history.record(changes);
    _local();
    _changed();
  }

  // ----------------------------------------------------------------- undo --

  bool get canUndo => canEdit && history.canUndo;
  bool get canRedo => canEdit && history.canRedo;

  void undo() {
    if (!canUndo) {
      return;
    }
    _finishEdit();
    final touched = history.undo(engine);
    selection = {
      for (final id in touched)
        if (engine.elementById(id) != null) id,
    };
    _local();
    _changed();
  }

  void redo() {
    if (!canRedo) {
      return;
    }
    _finishEdit();
    final touched = history.redo(engine);
    selection = {
      for (final id in touched)
        if (engine.elementById(id) != null) id,
    };
    _local();
    _changed();
  }

  // -------------------------------------------------------------- pointer --

  /// Shows this person's pointer to the others (throttled by the channel).
  void pointerMoved(Offset board) => _live?.sendPointer(board.dx, board.dy);

  // ------------------------------------------------------------ board meta --

  Future<bool> rename(String next) async {
    try {
      meta = await repository.updateMeta(boardId, {'title': next.trim()});
      _changed();
      return true;
    } on Object {
      return false;
    }
  }

  Future<bool> setManagersOnly(bool value) async {
    try {
      meta = await repository.updateMeta(boardId, {'managers_only': value});
      _changed();
      return true;
    } on Object {
      return false;
    }
  }

  Future<bool> clear() async {
    try {
      await flushNow();
      await repository.clearBoard(boardId);
      await reload();
      return true;
    } on Object {
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _cursorSweep?.cancel();
    unawaited(_elementsSub?.cancel());
    unawaited(_metaSub?.cancel());
    unawaited(_peersSub?.cancel());
    unawaited(_pointersSub?.cancel());
    unawaited(_liveStrokesSub?.cancel());
    unawaited(_live?.close());
    // One last try to send what is left; the draft keeps it if that fails.
    if (engine.hasPendingChanges && canEdit) {
      unawaited(
        engine.flush().then<void>((_) async {
          try {
            if (engine.hasPendingChanges) {
              await drafts.save(engine.toDraft());
            } else {
              await drafts.clear(boardId);
            }
          } on Object {
            // Nothing more to do.
          }
          engine.dispose();
        }),
      );
    } else {
      engine.dispose();
    }
    images.dispose();
    super.dispose();
  }
}

/// A color for a person's pointer, from their id, so the same person has the
/// same color for everyone.
int _peerColorFor(String userId) {
  const palette = <int>[
    0xFFE5484D,
    0xFFF76B15,
    0xFF30A46C,
    0xFF3B6EF5,
    0xFF8E4EC6,
    0xFFD6409F,
    0xFF12A594,
  ];
  var hash = 0;
  for (final unit in userId.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}
