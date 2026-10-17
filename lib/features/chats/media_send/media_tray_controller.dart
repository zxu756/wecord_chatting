import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/media_send/media_draft.dart';
import 'package:wecord/features/chats/media_send/media_picker.dart';

/// What the tray above the composer holds: the files chosen for the next
/// message, its caption, and the quality switch.
@immutable
class MediaTrayState {
  const MediaTrayState({
    this.items = const [],
    this.caption = '',
    this.original = false,
    this.viewOnce = false,
    this.loading = 0,
    this.leftOut = 0,
    this.preparing,
  });

  final List<DraftAttachment> items;
  final String caption;

  /// "Original quality": photos are sent without scaling or re-compression.
  final bool original;

  /// Send each photo or video to be opened once by whoever receives it.
  final bool viewOnce;

  /// Files being looked at (the tray shows placeholders for them).
  final int loading;

  /// Files that did not fit the limit of 10 at the last add; the tray tells
  /// the reader once.
  final int leftOut;

  /// While the photos are being scaled for sending: (done, total).
  final (int, int)? preparing;

  bool get isEmpty => items.isEmpty && loading == 0;

  /// Anything in the tray is open: it shows while there are files or some
  /// are loading.
  bool get isOpen => !isEmpty;

  bool get hasImages => items.any((item) => item.kind == DraftKind.image);

  /// Only photos and videos can be view-once, not files.
  bool get canViewOnce =>
      items.isNotEmpty && items.every((item) => item.kind != DraftKind.file);

  /// Whether the next send is view-once (the switch is on and applies).
  bool get sendsViewOnce => viewOnce && canViewOnce;

  /// Items over the 50 MB limit; sending waits until they are removed.
  List<DraftAttachment> get tooBig => [
    for (final item in items)
      if (item.overLimit) item,
  ];

  bool get isPreparing => preparing != null;

  bool get canSend =>
      items.isNotEmpty && tooBig.isEmpty && loading == 0 && !isPreparing;

  /// How many more files fit.
  int get room => maxTrayItems - items.length - loading;

  MediaTrayState copyWith({
    List<DraftAttachment>? items,
    String? caption,
    bool? original,
    bool? viewOnce,
    int? loading,
    int? leftOut,
    Object? preparing = _keep,
  }) {
    return MediaTrayState(
      items: items ?? this.items,
      caption: caption ?? this.caption,
      original: original ?? this.original,
      viewOnce: viewOnce ?? this.viewOnce,
      loading: loading ?? this.loading,
      leftOut: leftOut ?? this.leftOut,
      preparing: identical(preparing, _keep)
          ? this.preparing
          : preparing as (int, int)?,
    );
  }
}

const _keep = Object();

/// The tray of one conversation. Kept while the chat is open.
final mediaTrayProvider = NotifierProvider.autoDispose
    .family<MediaTrayController, MediaTrayState, String>(
      MediaTrayController.new,
    );

class MediaTrayController extends Notifier<MediaTrayState> {
  MediaTrayController(this.conversationId);

  /// The conversation this tray belongs to.
  final String conversationId;

  var _disposed = false;

  @override
  MediaTrayState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    return const MediaTrayState();
  }

  /// Adds files (picked, dropped or pasted), looking at each one first.
  /// Files beyond the 10 an album holds are counted in
  /// [MediaTrayState.leftOut].
  Future<void> add(List<XFile> files, {Map<XFile, Uint8List>? posters}) async {
    if (files.isEmpty) {
      return;
    }
    final room = state.room;
    final accepted = files.length < room ? files.length : (room < 0 ? 0 : room);
    state = state.copyWith(
      loading: state.loading + accepted,
      leftOut: files.length - accepted,
    );
    if (accepted == 0) {
      return;
    }
    final reader = ref.read(videoPosterReaderProvider);
    // Files put back by "Edit and resend" bring the poster they had.
    final VideoPosterReader poster = posters == null || posters.isEmpty
        ? reader
        : (file) async => posters[file] ?? await reader(file);
    final batch = await buildDrafts(files, room: accepted, videoPoster: poster);
    if (_disposed) {
      return;
    }
    state = state.copyWith(
      items: [...state.items, ...batch.drafts],
      loading: state.loading - accepted < 0 ? 0 : state.loading - accepted,
    );
  }

  /// Puts files back after a send failed ("Edit and resend"): with their
  /// caption unless the reader has already typed one, the poster frames of
  /// videos, and the "Original quality" choice they were sent with.
  Future<void> restore(
    List<XFile> files, {
    String caption = '',
    Map<XFile, Uint8List>? posters,
    bool original = false,
  }) async {
    var next = state;
    if (caption.isNotEmpty && state.caption.isEmpty) {
      next = next.copyWith(caption: caption);
    }
    // The choice they were sent with, unless other files already wait in
    // the tray with theirs.
    next = next.copyWith(
      original: state.isEmpty ? original : original || state.original,
    );
    state = next;
    await add(files, posters: posters);
  }

  void remove(String id) {
    state = state.copyWith(
      items: [
        for (final item in state.items)
          if (item.id != id) item,
      ],
      leftOut: 0,
    );
  }

  void setCaption(String caption) {
    state = state.copyWith(caption: caption);
  }

  void setOriginal(bool value) {
    state = state.copyWith(original: value);
  }

  void setViewOnce(bool value) {
    state = state.copyWith(viewOnce: value);
  }

  void setPreparing((int, int)? progress) {
    state = state.copyWith(preparing: progress);
  }

  void dismissNotice() {
    if (state.leftOut != 0) {
      state = state.copyWith(leftOut: 0);
    }
  }

  /// Empties the tray (after sending, or when the reader closes it). The
  /// quality switch stays as it was; view-once never carries over.
  void clear() {
    state = MediaTrayState(original: state.original);
  }
}
