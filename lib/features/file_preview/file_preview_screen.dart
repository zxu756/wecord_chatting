import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/file_preview/file_actions.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/viewers/audio_preview.dart';
import 'package:wecord/features/file_preview/viewers/document_preview.dart';
import 'package:wecord/features/file_preview/viewers/image_preview.dart';
import 'package:wecord/features/file_preview/viewers/pdf_preview.dart';
import 'package:wecord/features/file_preview/viewers/text_preview.dart';
import 'package:wecord/features/file_preview/viewers/video_preview.dart';
import 'package:wecord/features/image_text/image_text_sheet.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Builds the PDF widget for PDFs and converted Office files; tests swap
/// it (PDFium isn't loaded in widget tests).
final pdfViewerBuilderProvider = Provider<PdfViewerBuilder>(
  (ref) => defaultPdfViewerBuilder,
);

/// The images and videos of [gallery] to page through when opening
/// [file], with [file]'s place among them. Other files open alone.
({List<PreviewFile> items, int index}) previewGalleryFor(
  PreviewFile file,
  List<PreviewFile> gallery,
) {
  if (!file.kind.isGalleryMedia) {
    return (items: [file], index: 0);
  }
  final seen = <String>{};
  final items = <PreviewFile>[
    for (final item in gallery)
      if (item.kind.isGalleryMedia && seen.add(item.key)) item,
  ];
  var index = items.indexWhere((item) => item.key == file.key);
  if (index < 0) {
    return (items: [file], index: 0);
  }
  // Keep what the caller knew about the tapped file.
  items[index] = file.withContext(
    messageId: items[index].messageId,
    conversationId: items[index].conversationId,
    senderName: items[index].senderName,
    sentAt: items[index].sentAt,
  );
  return (items: items, index: index);
}

/// Opens the viewer for [file]: full screen on phones, a large overlay
/// over the app on desktop and the web. Images and videos page through
/// [gallery] (the conversation's media, oldest first); with
/// [conversationId] the viewer then loads the rest of the conversation's
/// media too.
Future<void> openFilePreview(
  BuildContext context, {
  required PreviewFile file,
  List<PreviewFile> gallery = const [],
  String? conversationId,
}) {
  final (:items, :index) = previewGalleryFor(file, gallery);
  final desktop = isWideLayout(MediaQuery.sizeOf(context).width);
  return Navigator.of(context, rootNavigator: true).push(
    FilePreviewRoute(
      desktop: desktop,
      builder: (context) => FilePreviewScreen(
        items: items,
        initialIndex: index,
        conversationId: conversationId ?? file.conversationId,
        desktop: desktop,
      ),
    ),
  );
}

/// Phones: an opaque page that fades in. Desktop: a see-through route
/// that scales the viewer in over the dimmed app.
class FilePreviewRoute extends PageRoute<void> {
  FilePreviewRoute({required this.builder, required this.desktop});

  final WidgetBuilder builder;
  final bool desktop;

  @override
  bool get opaque => !desktop;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => WeCordMotion.smooth.duration;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (WeCordMotion.reduceMotion(context)) {
      return child;
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: WeCordMotion.smooth.curve,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween<double>(
          begin: desktop ? 0.96 : 0.98,
          end: 1,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

enum _FileAction { save, share, openIn }

/// The file viewer: a floating glass bar with the file's name, size, who
/// sent it and when, and Download / Share / Open in / Close; below it the
/// file, shown the best way for its type. Images and videos of a
/// conversation page sideways (swipe, ← →); Esc closes, and on phones a
/// swipe down does too.
class FilePreviewScreen extends ConsumerStatefulWidget {
  const FilePreviewScreen({
    required this.items,
    this.initialIndex = 0,
    this.conversationId,
    this.desktop = false,
    super.key,
  });

  final List<PreviewFile> items;
  final int initialIndex;
  final String? conversationId;

  /// Shown as an overlay with rounded corners over the app.
  final bool desktop;

  @override
  ConsumerState<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends ConsumerState<FilePreviewScreen>
    with SingleTickerProviderStateMixin {
  late List<PreviewFile> _items = widget.items;
  late int _index = widget.initialIndex.clamp(0, widget.items.length - 1);
  late final PageController _pages = PageController(initialPage: _index);
  final _focus = FocusNode(debugLabel: 'file-preview');

  var _chrome = true;
  var _zoomed = false;
  var _fullscreen = false;

  _FileAction? _busy;
  double? _busyProgress;

  // Swipe down to close.
  double _drag = 0;
  late final AnimationController _dragReturn = AnimationController(vsync: this)
    ..addListener(
      () => setState(() => _drag = _dragFrom * (1 - _dragReturn.value)),
    );
  double _dragFrom = 0;

  PreviewFile get _current => _items[_index];

  bool get _isMediaGallery => _items.first.kind.isGalleryMedia;

  @override
  void initState() {
    super.initState();
    if (_isMediaGallery && widget.conversationId != null) {
      unawaited(_loadConversationMedia(widget.conversationId!));
    }
  }

  @override
  void dispose() {
    if (_fullscreen && !widget.desktop) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    _pages.dispose();
    _focus.dispose();
    _dragReturn.dispose();
    super.dispose();
  }

  /// Widens the gallery to every image and video in the conversation.
  Future<void> _loadConversationMedia(String conversationId) async {
    try {
      final media = await ref
          .read(chatsRepositoryProvider)
          .listConversationMedia(conversationId);
      final all = [
        for (final item in media.reversed)
          if (PreviewFile.fromMediaItem(item) case final file?
              when file.kind.isGalleryMedia)
            file,
      ];
      if (!mounted || all.length <= _items.length) {
        return;
      }
      final current = _current;
      final index = all.indexWhere((item) => item.key == current.key);
      if (index < 0) {
        return;
      }
      setState(() {
        all[index] = current.withContext(
          senderName: all[index].senderName,
          sentAt: all[index].sentAt,
          messageId: all[index].messageId,
        );
        _items = all;
        _index = index;
      });
      if (_pages.hasClients) {
        _pages.jumpToPage(index);
      }
    } on Object {
      // The thread's own media is enough.
    }
  }

  void _close() {
    unawaited(Navigator.of(context).maybePop());
  }

  void _go(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= _items.length || _zoomed) {
      return;
    }
    final duration = WeCordMotion.smooth.durationOf(context);
    if (duration == Duration.zero || !_pages.hasClients) {
      _pages.jumpToPage(target);
    } else {
      unawaited(
        _pages.animateToPage(
          target,
          duration: duration,
          curve: WeCordMotion.smooth.curve,
        ),
      );
    }
  }

  void _setFullscreen(bool value) {
    setState(() {
      _fullscreen = value;
      _chrome = !value;
    });
    if (!widget.desktop && !kIsWeb) {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        ),
      );
    }
  }

  Future<void> _run(
    _FileAction action,
    Future<void> Function(DownloadProgress onProgress) body,
  ) async {
    if (_busy != null) {
      return;
    }
    setState(() {
      _busy = action;
      _busyProgress = null;
    });
    try {
      await body((received, total) {
        if (mounted && total != null && total > 0) {
          setState(() => _busyProgress = (received / total).clamp(0.0, 1.0));
        }
      });
    } on Object {
      _toast(tr('Could not open the file. Try again.'));
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
          _busyProgress = null;
        });
      }
    }
  }

  void _toast(String text) {
    if (!mounted) {
      return;
    }
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  void _save() {
    final file = _current;
    unawaited(
      _run(_FileAction.save, (onProgress) async {
        final outcome = await ref
            .read(fileActionsProvider)
            .save(file, onProgress: onProgress);
        switch (outcome) {
          case SaveOutcome.savedToPhotos:
            _toast(tr('Saved to Photos'));
          case SaveOutcome.saved:
            _toast(tr('Saved'));
          case SaveOutcome.downloadStarted:
            _toast(tr('Downloading {name}', {'name': file.name}));
          case SaveOutcome.cancelled:
            break;
        }
      }),
    );
  }

  Rect? _originOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _share(BuildContext buttonContext) {
    final file = _current;
    final origin = _originOf(buttonContext);
    unawaited(
      _run(
        _FileAction.share,
        (onProgress) => ref
            .read(fileActionsProvider)
            .share(file, origin: origin, onProgress: onProgress),
      ),
    );
  }

  void _openIn(BuildContext buttonContext) {
    final file = _current;
    final origin = _originOf(buttonContext);
    unawaited(
      _run(_FileAction.openIn, (onProgress) async {
        final opened = await ref
            .read(fileActionsProvider)
            .openIn(file, origin: origin, onProgress: onProgress);
        if (!opened) {
          _toast(tr('No app on this device can open this file.'));
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = _isMediaGallery;
    final themed = media
        ? WeCordTheme.dark().copyWith(platform: Theme.of(context).platform)
        : Theme.of(context);
    return Theme(
      data: themed,
      child: Builder(builder: _buildThemed),
    );
  }

  Widget _buildThemed(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final media = _isMediaGallery;
    final background = media ? c.paper : (tokens.isDark ? c.paper : c.panel);
    final dragProgress = (_drag.abs() / 400).clamp(0.0, 1.0);

    Widget body = _items.length == 1
        ? _page(context, _items.single, 0)
        : PageView.builder(
            key: const ValueKey('file-preview-pages'),
            controller: _pages,
            physics: _zoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: _items.length,
            onPageChanged: (index) => setState(() {
              _index = index;
              _zoomed = false;
            }),
            itemBuilder: (context, index) =>
                _page(context, _items[index], index),
          );

    final canDragDismiss = !widget.desktop && !_zoomed && !_fullscreen;
    if (canDragDismiss &&
        (media ||
            _current.kind == PreviewKind.svg ||
            _current.kind == PreviewKind.office ||
            _current.kind == PreviewKind.other ||
            _current.kind == PreviewKind.audio)) {
      body = GestureDetector(
        key: const ValueKey('file-preview-drag-dismiss'),
        onVerticalDragStart: (_) => _dragReturn.stop(),
        onVerticalDragUpdate: (details) =>
            setState(() => _drag = math.max(0, _drag + details.delta.dy)),
        onVerticalDragEnd: (details) {
          if (_drag > 120 || (details.primaryVelocity ?? 0) > 900) {
            _close();
            return;
          }
          _dragFrom = _drag;
          _dragReturn
            ..duration = WeCordMotion.smooth.durationOf(context)
            ..forward(from: 0);
        },
        child: Transform.translate(
          offset: Offset(0, _drag),
          child: Transform.scale(scale: 1 - dragProgress * 0.12, child: body),
        ),
      );
    }

    final topBar = _TopBar(
      file: _current,
      position: _items.length > 1 ? (_index + 1, _items.length) : null,
      busy: _busy,
      busyProgress: _busyProgress,
      actions: ref.watch(fileActionsProvider),
      onClose: _close,
      onSave: _save,
      onShare: _share,
      onOpenIn: _openIn,
      onCopyText: _current.kind == PreviewKind.image
          ? () => unawaited(showImageTextSheet(context, file: _current))
          : null,
    );

    final Widget content;
    if (media) {
      content = Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              bottom: false,
              minimum: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: _ChromeFade(visible: _chrome && _drag == 0, child: topBar),
            ),
          ),
          if (widget.desktop && _items.length > 1) ...[
            _SideArrow(
              left: true,
              visible: _chrome && _index > 0,
              onPressed: () => _go(-1),
            ),
            _SideArrow(
              left: false,
              visible: _chrome && _index < _items.length - 1,
              onPressed: () => _go(1),
            ),
          ],
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            minimum: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: topBar,
          ),
          Expanded(
            child: SafeArea(top: false, child: ClipRect(child: body)),
          ),
        ],
      );
    }

    Widget screen = ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        backgroundColor: background.withValues(alpha: 1 - dragProgress * 0.9),
        body: content,
      ),
    );

    if (widget.desktop) {
      final size = MediaQuery.sizeOf(context);
      final full = _fullscreen;
      final radius = BorderRadius.circular(full ? 0 : WeCordRadii.xxl);
      screen = Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('file-preview-backdrop'),
              onTap: _close,
              child: ColoredBox(color: c.scrim),
            ),
          ),
          AnimatedPadding(
            duration: WeCordMotion.smooth.durationOf(context),
            curve: WeCordMotion.smooth.curve,
            padding: full
                ? EdgeInsets.zero
                : EdgeInsets.symmetric(
                    horizontal: math.max(24, (size.width - 1480) / 2),
                    vertical: math.max(24, size.height * 0.04),
                  ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: tokens.shadows.dialog,
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  removeBottom: true,
                  removeLeft: true,
                  removeRight: true,
                  child: screen,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: WeCordTheme.overlayStyleFor(tokens.brightness),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _close,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
        },
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          child: Semantics(
            scopesRoute: true,
            explicitChildNodes: true,
            label: _current.name,
            child: screen,
          ),
        ),
      ),
    );
  }

  Widget _page(BuildContext context, PreviewFile file, int index) {
    final active = index == _index;
    final onDownload = _save;
    final key = ValueKey('file-preview-page-${file.key}');
    switch (file.kind) {
      case PreviewKind.image || PreviewKind.svg:
        return ImagePreview(
          key: key,
          file: file,
          onTap: () => setState(() => _chrome = !_chrome),
          onZoomChanged: (zoomed) {
            if (active) {
              setState(() => _zoomed = zoomed);
            }
          },
          onDownload: onDownload,
        );
      case PreviewKind.video:
        return VideoPreview(
          key: key,
          file: file,
          active: active,
          chromeVisible: _chrome,
          onTap: () => setState(() => _chrome = !_chrome),
          fullscreen: _fullscreen,
          onFullscreenChanged: _setFullscreen,
          onDownload: onDownload,
        );
      case PreviewKind.audio:
        return AudioFilePlayer(key: key, file: file, active: active);
      case PreviewKind.pdf:
        return PdfPreview(
          key: key,
          file: file,
          desktop: widget.desktop,
          onDownload: onDownload,
          viewerBuilder: ref.watch(pdfViewerBuilderProvider),
          resolve: (onProgress, cancel) async {
            final fetcher = ref.read(fileFetcherProvider);
            final service = ref.read(filePreviewServiceProvider);
            if (!fetcher.cachesOnDisk) {
              return PdfUriSource(await service.fileUrl(file));
            }
            return PdfFileSource(
              await fetcher.download(
                file,
                url: () => service.fileUrl(file),
                onProgress: onProgress,
                cancel: cancel,
              ),
            );
          },
        );
      case PreviewKind.text ||
          PreviewKind.markdown ||
          PreviewKind.code ||
          PreviewKind.json ||
          PreviewKind.table:
        return TextPreview(key: key, file: file, onDownload: onDownload);
      case PreviewKind.office:
        return OfficePreview(
          key: key,
          file: file,
          desktop: widget.desktop,
          onDownload: onDownload,
          onOpenIn: ref.read(fileActionsProvider).canOpenIn
              ? () => _openIn(context)
              : null,
          pdfViewerBuilder: ref.watch(pdfViewerBuilderProvider),
          onQuickLookClosed: _close,
        );
      case PreviewKind.other:
        return OtherFilePreview(
          key: key,
          file: file,
          onDownload: onDownload,
          onOpenIn: ref.read(fileActionsProvider).canOpenIn
              ? () => _openIn(context)
              : null,
        );
    }
  }
}

class _ChromeFade extends StatelessWidget {
  const _ChromeFade({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: WeCordMotion.durationOf(context, WeCordMotion.base),
      curve: WeCordMotion.standard,
      child: IgnorePointer(ignoring: !visible, child: child),
    );
  }
}

class _SideArrow extends StatelessWidget {
  const _SideArrow({
    required this.left,
    required this.visible,
    required this.onPressed,
  });

  final bool left;
  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left ? 16 : null,
      right: left ? null : 16,
      top: 0,
      bottom: 0,
      child: Center(
        child: _ChromeFade(
          visible: visible,
          child: WeCordGlass(
            borderRadius: BorderRadius.circular(WeCordRadii.pill),
            child: WeCordIconButton(
              key: ValueKey(
                left ? 'file-preview-previous' : 'file-preview-next',
              ),
              icon: left
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded,
              tooltip: left ? tr('Previous') : tr('Next'),
              variant: WeCordButtonVariant.ghost,
              size: 46,
              iconSize: 28,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.file,
    required this.position,
    required this.busy,
    required this.busyProgress,
    required this.actions,
    required this.onClose,
    required this.onSave,
    required this.onShare,
    required this.onOpenIn,
    this.onCopyText,
  });

  final PreviewFile file;
  final (int, int)? position;
  final _FileAction? busy;
  final double? busyProgress;
  final FileActions actions;
  final VoidCallback onClose;
  final VoidCallback onSave;
  final ValueChanged<BuildContext> onShare;
  final ValueChanged<BuildContext> onOpenIn;

  /// Opens "Copy text from picture"; null for what is not a picture.
  final VoidCallback? onCopyText;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final subtitle = [
      if (position case (final at, final of))
        tr('{index} of {count}', {'index': at, 'count': of}),
      previewSubtitle(file),
    ].where((part) => part.isNotEmpty).join(' · ');

    Widget action(
      _FileAction kind,
      IconData icon,
      String tooltip,
      void Function(BuildContext) onPressed,
    ) {
      return Builder(
        builder: (buttonContext) {
          if (busy == kind) {
            return SizedBox.square(
              key: ValueKey('file-preview-busy-${kind.name}'),
              dimension: WeCordSizes.touchTarget,
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    value: busyProgress,
                    color: c.ink,
                    backgroundColor: c.track,
                  ),
                ),
              ),
            );
          }
          return WeCordIconButton(
            key: ValueKey('file-preview-${kind.name}'),
            icon: icon,
            tooltip: tooltip,
            variant: WeCordButtonVariant.ghost,
            size: 40,
            onPressed: busy == null ? () => onPressed(buttonContext) : null,
          );
        },
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: WeCordGlass(
          key: const ValueKey('file-preview-top-bar'),
          borderRadius: BorderRadius.circular(WeCordRadii.xl),
          padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
          child: Row(
            children: [
              WeCordIconButton(
                key: const ValueKey('file-preview-close'),
                icon: Icons.close_rounded,
                tooltip: tr('Close'),
                variant: WeCordButtonVariant.ghost,
                size: 40,
                onPressed: onClose,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      key: const ValueKey('file-preview-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        key: const ValueKey('file-preview-subtitle'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                          color: c.muted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (onCopyText != null)
                WeCordIconButton(
                  key: const ValueKey('file-preview-copy-text'),
                  icon: Icons.document_scanner_outlined,
                  tooltip: tr('Copy text from picture'),
                  variant: WeCordButtonVariant.ghost,
                  size: 40,
                  onPressed: busy == null ? onCopyText : null,
                ),
              action(
                _FileAction.save,
                Icons.download_rounded,
                tr('Download'),
                (_) => onSave(),
              ),
              if (actions.canShare)
                action(
                  _FileAction.share,
                  Icons.ios_share_rounded,
                  tr('Share'),
                  onShare,
                ),
              if (actions.canOpenIn)
                action(
                  _FileAction.openIn,
                  Icons.open_in_new_rounded,
                  tr('Open in…'),
                  onOpenIn,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
