import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/home/home_avatars.dart';
import 'package:wecord/features/stories/stories_models.dart';
import 'package:wecord/features/stories/stories_providers.dart';
import 'package:wecord/features/stories/stories_repository.dart';
import 'package:wecord/features/stories/story_media.dart';
import 'package:wecord/features/stories/story_report_sheet.dart';
import 'package:wecord/features/stories/story_viewers_sheet.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the full-screen viewer on [start]'s dailies; when they end it goes
/// on to the people after them in [entries] (the row as it was shown).
Future<void> openStoryViewer(
  BuildContext context, {
  required List<StoryTrayEntry> entries,
  required String start,
}) {
  final first = entries.indexWhere((entry) => entry.authorId == start);
  if (first < 0) {
    return Future.value();
  }
  // From the tapped person on, the others with something new; never "my own"
  // in the middle of the row.
  final sequence = [
    entries[first],
    for (final entry in entries.skip(first + 1))
      if (!entry.isMe && entry.hasUnseen) entry,
  ];
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => StoryViewerScreen(entries: sequence),
    ),
  );
}

/// The full-screen viewer: a bar of segments on top, tap the right side for
/// the next daily and the left for the one before, hold to pause, drag down
/// to close, reply and quick emojis underneath (or, for my own, who viewed).
/// With reduced motion nothing advances by itself and a video waits for its
/// play button.
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({required this.entries, super.key});

  final List<StoryTrayEntry> entries;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  var _index = 0;

  void _close() => Navigator.of(context).maybePop();

  void _nextAuthor() {
    if (_index + 1 < widget.entries.length) {
      setState(() => _index++);
    } else {
      _close();
    }
  }

  void _previousAuthor() {
    if (_index > 0) {
      setState(() => _index--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entries[_index];
    return Scaffold(
      key: const ValueKey('story-viewer'),
      // Dailies are always shown on black, like the photo viewers.
      backgroundColor: Colors.black,
      body: _AuthorStories(
        key: ValueKey('story-author-${entry.authorId}'),
        entry: entry,
        onFinished: _nextAuthor,
        onPreviousAuthor: _index > 0 ? _previousAuthor : null,
        onClose: _close,
      ),
    );
  }
}

class _AuthorStories extends ConsumerStatefulWidget {
  const _AuthorStories({
    required this.entry,
    required this.onFinished,
    required this.onClose,
    this.onPreviousAuthor,
    super.key,
  });

  final StoryTrayEntry entry;
  final VoidCallback onFinished;
  final VoidCallback onClose;
  final VoidCallback? onPreviousAuthor;

  @override
  ConsumerState<_AuthorStories> createState() => _AuthorStoriesState();
}

class _AuthorStoriesState extends ConsumerState<_AuthorStories>
    with SingleTickerProviderStateMixin {
  late final AnimationController _timer;
  final _replyController = TextEditingController();
  final _replyFocus = FocusNode(debugLabel: 'story-reply');
  late final ProviderContainer _container;

  List<Story>? _stories;
  var _failed = false;
  var _index = 0;
  var _holding = false;
  var _sheetOpen = false;
  var _manualPlay = false;
  var _sending = false;
  var _dragDy = 0.0;
  var _trayDirty = false;
  double _videoProgress = 0;

  StoryTrayEntry get _author => widget.entry;
  Story? get _story {
    final stories = _stories;
    return stories == null || stories.isEmpty ? null : stories[_index];
  }

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    _timer = AnimationController(vsync: this)
      ..addListener(() {
        if (mounted) {
          setState(() {});
        }
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _next();
        }
      });
    _replyFocus.addListener(_applyPause);
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer.dispose();
    _replyController.dispose();
    _replyFocus
      ..removeListener(_applyPause)
      ..dispose();
    if (_trayDirty) {
      try {
        _container.invalidate(storiesTrayProvider);
      } on Object {
        // The app is closing.
      }
    }
    super.dispose();
  }

  bool get _paused => _holding || _sheetOpen || _replyFocus.hasFocus;

  bool get _reduceMotion => WeCordMotion.reduceMotion(context);

  /// Whether the clock (or the video) runs now.
  bool get _running {
    if (_paused) {
      return false;
    }
    final story = _story;
    if (story == null) {
      return false;
    }
    return !_reduceMotion || (story.isVideo && _manualPlay);
  }

  Future<void> _load() async {
    try {
      final all = await ref.read(
        authorStoriesProvider(_author.authorId).future,
      );
      if (!mounted) {
        return;
      }
      final now = DateTime.now();
      final live = [
        for (final story in all)
          if (!story.hasEndedAt(now)) story,
      ];
      // Start at the first one not seen yet (all seen: the first).
      final firstNew = live.indexWhere((story) => !story.viewed);
      setState(() {
        _stories = live;
        _index = firstNew < 0 ? 0 : firstNew;
      });
      if (live.isEmpty) {
        widget.onFinished();
        return;
      }
      _enter();
    } on Object {
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  /// Starts the daily at [_index]: the clock for a photo, the video's own
  /// progress for a video.
  void _enter() {
    final story = _story;
    if (story == null) {
      return;
    }
    _timer.stop();
    _videoProgress = 0;
    _manualPlay = false;
    if (!story.isVideo) {
      _timer.duration = story.screenTime;
      _timer.value = 0;
      if (_running) {
        unawaited(_timer.forward());
      }
    }
    if (!_author.isMe && !story.viewed) {
      _stories = [
        for (final s in _stories!)
          s.id == story.id ? s.copyWith(viewed: true) : s,
      ];
      _trayDirty = true;
      unawaited(
        ref
            .read(storiesRepositoryProvider)
            .markViewed(story.id)
            .catchError((Object _) {}),
      );
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _applyPause() {
    final story = _story;
    if (story != null && !story.isVideo) {
      if (_running) {
        if (!_timer.isAnimating && _timer.value < 1) {
          unawaited(_timer.forward());
        }
      } else {
        _timer.stop();
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _next() {
    final stories = _stories;
    if (stories == null) {
      return;
    }
    if (_index + 1 < stories.length) {
      setState(() => _index++);
      _enter();
    } else {
      widget.onFinished();
    }
  }

  void _previous() {
    if (_index > 0) {
      setState(() => _index--);
      _enter();
    } else if (widget.onPreviousAuthor != null) {
      widget.onPreviousAuthor!();
    } else {
      _enter();
    }
  }

  double get _progress {
    final story = _story;
    if (story == null) {
      return 0;
    }
    if (story.isVideo) {
      return _videoProgress;
    }
    return _reduceMotion && !_timer.isAnimating ? 1 : _timer.value;
  }

  // ------------------------------------------------------------ actions

  void _snack(String text) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _sendReply() async {
    final story = _story;
    final text = _replyController.text.trim();
    if (story == null || text.isEmpty || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(storiesRepositoryProvider)
          .reply(story.id, text, clientId: newStoryId());
      if (!mounted) {
        return;
      }
      _replyController.clear();
      _replyFocus.unfocus();
      WeCordHaptics.light();
      _snack(tr('Reply sent'));
    } on Object catch (error) {
      if (mounted) {
        _snack(
          error is PostgrestException && error.code == 'P0002'
              ? tr('This daily is no longer available.')
              : tr('Could not send the reply. Try again.'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _react(String emoji) async {
    final story = _story;
    if (story == null) {
      return;
    }
    final same = story.myReaction == emoji;
    final next = same ? null : emoji;
    WeCordHaptics.selection();
    setState(() {
      _stories = [
        for (final s in _stories!)
          s.id == story.id ? s.copyWith(myReaction: next) : s,
      ];
    });
    try {
      await ref.read(storiesRepositoryProvider).react(story.id, next);
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _stories = [
          for (final s in _stories!)
            s.id == story.id ? s.copyWith(myReaction: story.myReaction) : s,
        ];
      });
      _snack(tr('Could not send the reaction. Try again.'));
    }
  }

  Future<T?> _whileOpen<T>(Future<T?> Function() open) async {
    setState(() => _sheetOpen = true);
    _applyPause();
    try {
      return await open();
    } finally {
      if (mounted) {
        setState(() => _sheetOpen = false);
        _applyPause();
      }
    }
  }

  Future<void> _openMenu() async {
    final story = _story;
    if (story == null) {
      return;
    }
    final choice = await _whileOpen<String>(
      () => showWeCordSheet<String>(
        context,
        useRootNavigator: true,
        builder: (sheetContext, _) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: SettingsGroup(
            color: sheetContext.tokens.colors.well,
            children: [
              if (_author.isMe)
                SettingsRow(
                  key: const ValueKey('story-menu-delete'),
                  icon: Icons.delete_outline_rounded,
                  tone: SettingsTone.danger,
                  title: tr('Delete daily'),
                  showChevron: false,
                  onTap: () => Navigator.of(sheetContext).pop('delete'),
                )
              else
                SettingsRow(
                  key: const ValueKey('story-menu-report'),
                  icon: Icons.flag_outlined,
                  tone: SettingsTone.danger,
                  title: tr('Report'),
                  showChevron: false,
                  onTap: () => Navigator.of(sheetContext).pop('report'),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    switch (choice) {
      case 'delete':
        await _confirmDelete(story);
      case 'report':
        final sent = await _whileOpen<bool>(
          () => showReportStorySheet(
            context,
            storyId: story.id,
            authorName: _author.name,
          ),
        );
        if (sent == true && mounted) {
          _snack(tr('Report sent. Thank you for helping keep WeCord safe.'));
        }
    }
  }

  Future<void> _confirmDelete(Story story) async {
    final sure = await _whileOpen<bool>(
      () => showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr('Delete this daily?')),
          content: Text(tr('It disappears for everyone right away.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(tr('Cancel')),
            ),
            TextButton(
              key: const ValueKey('story-delete-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(tr('Delete')),
            ),
          ],
        ),
      ),
    );
    if (sure != true || !mounted) {
      return;
    }
    try {
      await ref.read(storiesRepositoryProvider).delete(story.id);
    } on Object {
      if (mounted) {
        _snack(tr('Could not delete the daily. Try again.'));
      }
      return;
    }
    _trayDirty = true;
    ref.invalidate(authorStoriesProvider(_author.authorId));
    if (!mounted) {
      return;
    }
    final rest = [
      for (final s in _stories!)
        if (s.id != story.id) s,
    ];
    if (rest.isEmpty) {
      widget.onClose();
      return;
    }
    setState(() {
      _stories = rest;
      _index = _index.clamp(0, rest.length - 1);
    });
    _enter();
  }

  Future<void> _openViewers() async {
    final story = _story;
    if (story == null) {
      return;
    }
    await _whileOpen<void>(() => showStoryViewersSheet(context, story));
  }

  // ------------------------------------------------------------ gestures

  void _onTapUp(TapUpDetails details, double width) {
    if (details.localPosition.dx < width * 0.3) {
      _previous();
    } else {
      _next();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final far = _dragDy > 120 || velocity > 700;
    if (far) {
      widget.onClose();
    } else if (_dragDy != 0) {
      setState(() => _dragDy = 0);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_replyFocus.hasFocus) {
        _replyFocus.unfocus();
      } else {
        widget.onClose();
      }
      return KeyEventResult.handled;
    }
    if (_replyFocus.hasFocus) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _next();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _previous();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _Message(
        text: tr('Could not load this daily.'),
        onClose: widget.onClose,
      );
    }
    final story = _story;
    if (story == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final stories = _stories!;
    final scale = _reduceMotion ? 1.0 : (1 - (_dragDy / 1200)).clamp(0.85, 1.0);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Transform.translate(
        offset: _reduceMotion ? Offset.zero : Offset(0, _dragDy),
        child: Transform.scale(
          scale: scale,
          child: Stack(
            fit: StackFit.expand,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => Semantics(
                  container: true,
                  label: tr('{name}\'s daily, {index} of {count}', {
                    'name': _author.name,
                    'index': _index + 1,
                    'count': stories.length,
                  }),
                  customSemanticsActions: {
                    CustomSemanticsAction(label: tr('Next daily')): _next,
                    CustomSemanticsAction(label: tr('Previous daily')):
                        _previous,
                  },
                  child: GestureDetector(
                    key: const ValueKey('story-surface'),
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) =>
                        _onTapUp(details, constraints.maxWidth),
                    onLongPressStart: (_) {
                      setState(() => _holding = true);
                      _applyPause();
                    },
                    onLongPressEnd: (_) {
                      setState(() => _holding = false);
                      _applyPause();
                    },
                    onLongPressCancel: () {
                      if (_holding) {
                        setState(() => _holding = false);
                        _applyPause();
                      }
                    },
                    onVerticalDragUpdate: (details) {
                      setState(
                        () => _dragDy = (_dragDy + details.delta.dy).clamp(
                          0,
                          600,
                        ),
                      );
                    },
                    onVerticalDragEnd: _onDragEnd,
                    child: _media(story),
                  ),
                ),
              ),
              const IgnorePointer(child: _Scrims()),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 4, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ProgressBar(
                          count: stories.length,
                          index: _index,
                          progress: _progress,
                        ),
                        const SizedBox(height: 10),
                        _header(story),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(top: false, child: _bottom(story)),
              ),
              if (story.isVideo && _reduceMotion && !_manualPlay)
                Center(
                  child: IconButton.filled(
                    key: const ValueKey('story-play'),
                    tooltip: tr('Play'),
                    iconSize: 36,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.55),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      setState(() => _manualPlay = true);
                      _applyPause();
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _media(Story story) {
    if (story.isVideo) {
      return StoryVideoSurface(
        key: ValueKey('story-video-${story.id}'),
        path: story.mediaPath,
        posterPath: story.posterPath,
        playing: _running,
        onProgress: (fraction) {
          if (mounted && (fraction - _videoProgress).abs() > 0.004) {
            setState(() => _videoProgress = fraction);
          }
        },
        onEnded: () {
          if (mounted && !_reduceMotion) {
            _next();
          }
        },
        onFailed: () {
          // Nothing to watch: on to the next one.
          if (mounted && !_reduceMotion) {
            _next();
          }
        },
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: StoryImage(
        key: ValueKey('story-image-${story.id}'),
        path: story.mediaPath,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _header(Story story) {
    final now = DateTime.now();
    // The scrim behind the header is dark, so the header is always white.
    return Row(
      children: [
        ResolvedAvatar(
          name: _author.name,
          avatarUrl: _author.avatarUrl,
          size: 36,
          ringColor: Colors.black,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _author.isMe ? tr('Your daily') : _author.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Text(
                _author.isMe
                    ? storyRemainingLabel(story.expiresAt, now)
                    : storyAgeLabel(story.createdAt, now),
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('story-menu'),
          tooltip: tr('More'),
          color: Colors.white,
          onPressed: _openMenu,
          icon: const Icon(Icons.more_horiz_rounded),
        ),
        IconButton(
          key: const ValueKey('story-close'),
          tooltip: tr('Close'),
          color: Colors.white,
          onPressed: widget.onClose,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }

  Widget _bottom(Story story) {
    final caption = story.caption.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                caption,
                key: const ValueKey('story-caption'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.35,
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                ),
              ),
            ),
          if (_author.isMe) _ownBar(story) else _replyBar(story),
        ],
      ),
    );
  }

  Widget _ownBar(Story story) {
    return Row(
      children: [
        TextButton.icon(
          key: const ValueKey('story-views-button'),
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          onPressed: _openViewers,
          icon: const Icon(Icons.visibility_outlined, size: 20),
          label: Text(
            story.viewCount == 1
                ? tr('1 view')
                : tr('{count} views', {'count': story.viewCount}),
          ),
        ),
        if (story.reactionCount > 0)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              '· ${story.reactionCount}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        const Spacer(),
        IconButton(
          key: const ValueKey('story-delete'),
          tooltip: tr('Delete daily'),
          color: Colors.white,
          onPressed: () => unawaited(_confirmDelete(story)),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }

  Widget _replyBar(Story story) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final emoji in storyQuickEmojis)
              Semantics(
                button: true,
                selected: story.myReaction == emoji,
                label: tr('React with {emoji}', {'emoji': emoji}),
                excludeSemantics: true,
                child: InkResponse(
                  key: ValueKey('story-emoji-$emoji'),
                  radius: 26,
                  onTap: () => unawaited(_react(emoji)),
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: story.myReaction == emoji
                        ? BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.22),
                          )
                        : null,
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('story-reply-field'),
                controller: _replyController,
                focusNode: _replyFocus,
                enabled: !_sending,
                minLines: 1,
                maxLines: 3,
                maxLength: 2000,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => unawaited(_sendReply()),
                cursorColor: Colors.white,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: tr('Reply to {name}', {'name': _author.name}),
                  hintStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.16),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(WeCordRadii.pill),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _replyController,
              builder: (context, value, _) => IconButton(
                key: const ValueKey('story-reply-send'),
                tooltip: tr('Send'),
                color: Colors.white,
                onPressed: value.text.trim().isEmpty || _sending
                    ? null
                    : () => unawaited(_sendReply()),
                icon: const Icon(Icons.send_rounded),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A segment per daily: done ones full, the current one filling, the rest
/// empty. Fixed whites on purpose: it sits on the photo, not on a theme
/// surface.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.count,
    required this.index,
    required this.progress,
  });

  final int count;
  final int index;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: tr('Daily {index} of {count}', {
        'index': index + 1,
        'count': count,
      }),
      excludeSemantics: true,
      child: Row(
        key: const ValueKey('story-progress'),
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: Colors.white.withValues(alpha: 0.3)),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: i < index
                            ? 1
                            : i == index
                            ? progress.clamp(0.0, 1.0)
                            : 0,
                        child: const ColoredBox(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A dark fade under the header and over the bottom bar, so white text and
/// icons stay readable on any photo.
class _Scrims extends StatelessWidget {
  const _Scrims();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 140,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.55),
                Colors.transparent,
              ],
            ),
          ),
        ),
        const Spacer(),
        Container(
          height: 200,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
            ),
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onClose});

  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          Center(
            child: Text(
              text,
              key: const ValueKey('story-message'),
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: IconButton(
              tooltip: tr('Close'),
              color: Colors.white,
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
    );
  }
}
