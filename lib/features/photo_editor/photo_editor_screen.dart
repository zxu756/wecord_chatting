import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wecord/features/chats/media_send/photo_compression.dart';
import 'package:wecord/features/photo_editor/editor_canvas.dart';
import 'package:wecord/features/photo_editor/editor_model.dart';
import 'package:wecord/features/photo_editor/editor_render.dart';
import 'package:wecord/features/photo_editor/editor_session.dart';
import 'package:wecord/features/photo_editor/editor_toolbars.dart';
import 'package:wecord/features/photo_editor/text_entry.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What the editor hands back.
class PhotoEditResult {
  const PhotoEditResult({required this.document, this.photo});

  /// Everything done to the picture; it opens the editor again where this
  /// left off.
  final EditorDocument document;

  /// The edited picture as a JPEG; null when nothing was changed (send the
  /// original).
  final EditedPhoto? photo;
}

typedef EditorAssetsLoader = Future<EditorAssets?> Function(Uint8List bytes);

typedef EditorRenderer =
    Future<EditedPhoto?> Function({
      required EditorAssets assets,
      required EditorDocument document,
      required String fileName,
      required int maxEdge,
      int quality,
    });

/// The full-screen photo editor: draw, add text, hide parts with a mosaic or
/// blur, and crop and turn. It works on [sourceBytes] and, on Done, pops a
/// [PhotoEditResult] with the finished JPEG (no more than [maxEdge] on the
/// long side). Esc, or the close button, cancels; ⌘Z / ⇧⌘Z undo and redo.
class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({
    required this.sourceBytes,
    required this.fileName,
    this.initial,
    this.maxEdge = maxPhotoEdge,
    this.quality = photoJpegQuality,
    this.loadAssets,
    this.renderer,
    super.key,
  });

  final Uint8List sourceBytes;
  final String fileName;

  /// Edits made before, to carry on from.
  final EditorDocument? initial;
  final int maxEdge;
  final int quality;

  /// For tests: how the picture is decoded.
  final EditorAssetsLoader? loadAssets;

  /// For tests: how the result is rendered.
  final EditorRenderer? renderer;

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  EditorSession? _session;
  var _failed = false;
  var _saving = false;
  var _saveFailed = false;
  final _focus = FocusNode(debugLabel: 'photo-editor');

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final assets = await (widget.loadAssets ?? EditorAssets.decode)(
      widget.sourceBytes,
    );
    if (!mounted) {
      assets?.dispose();
      return;
    }
    if (assets == null) {
      setState(() => _failed = true);
      return;
    }
    setState(() {
      _session = EditorSession(assets: assets, initial: widget.initial);
    });
  }

  @override
  void dispose() {
    _session?.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    final session = _session;
    if (_saving) {
      return;
    }
    if (session != null && session.draftText != null) {
      session.finishTextEntry(keep: false);
      return;
    }
    if (session != null && session.hasChanges) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('Discard your edits?')),
          content: Text(tr('The photo goes back to how it was.')),
          actions: [
            TextButton(
              key: const ValueKey('photo-editor-keep-editing'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Keep editing')),
            ),
            TextButton(
              key: const ValueKey('photo-editor-discard'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr('Discard')),
            ),
          ],
        ),
      );
      if (discard != true) {
        return;
      }
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _done() async {
    final session = _session;
    if (session == null || _saving) {
      return;
    }
    if (session.draftText != null) {
      session.finishTextEntry(keep: true);
    }
    final document = session.document;
    if (document.isUnedited) {
      Navigator.of(context).pop(PhotoEditResult(document: document));
      return;
    }
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    final photo = await (widget.renderer ?? renderEditedPhoto)(
      assets: session.assets,
      document: document,
      fileName: widget.fileName,
      maxEdge: widget.maxEdge,
      quality: widget.quality,
    );
    if (!mounted) {
      return;
    }
    if (photo == null) {
      setState(() {
        _saving = false;
        _saveFailed = true;
      });
      return;
    }
    Navigator.of(
      context,
    ).pop(PhotoEditResult(document: document, photo: photo));
  }

  void _zoomBy(double factor) {
    final session = _session;
    if (session == null) {
      return;
    }
    final size = session.viewSize;
    session.zoomAbout(
      Offset(size.width / 2, size.height / 2),
      session.zoom * factor,
    );
  }

  void _addText(Offset? viewPoint) {
    final session = _session;
    if (session == null) {
      return;
    }
    session.startTextEntry(
      session.newText('', viewPoint: viewPoint),
      isNew: true,
    );
  }

  void _editText(TextOverlay item) {
    _session?.startTextEntry(item, isNew: false);
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final session = _session;
    return {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          unawaited(_cancel()),
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
          session?.undo(),
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
          session?.undo(),
      const SingleActivator(
        LogicalKeyboardKey.keyZ,
        meta: true,
        shift: true,
      ): () =>
          session?.redo(),
      const SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      ): () =>
          session?.redo(),
      const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
          session?.redo(),
      const SingleActivator(LogicalKeyboardKey.equal, meta: true): () =>
          _zoomBy(1.25),
      const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
          _zoomBy(1.25),
      const SingleActivator(LogicalKeyboardKey.minus, meta: true): () =>
          _zoomBy(0.8),
      const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
          _zoomBy(0.8),
      const SingleActivator(LogicalKeyboardKey.digit0, meta: true): () =>
          session?.resetZoom(),
      const SingleActivator(LogicalKeyboardKey.digit0, control: true): () =>
          session?.resetZoom(),
    };
  }

  @override
  Widget build(BuildContext context) {
    // The editor is always dark, like the media viewer.
    final themed = WeCordTheme.dark().copyWith(
      platform: Theme.of(context).platform,
    );
    return Theme(
      data: themed,
      child: Builder(builder: _buildThemed),
    );
  }

  Widget _buildThemed(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final session = _session;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: WeCordTheme.overlayStyleFor(tokens.brightness),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            unawaited(_cancel());
          }
        },
        child: CallbackShortcuts(
          bindings: _shortcuts,
          child: Focus(
            focusNode: _focus,
            autofocus: true,
            child: Semantics(
              scopesRoute: true,
              explicitChildNodes: true,
              namesRoute: true,
              label: tr('Edit photo'),
              child: Scaffold(
                key: const ValueKey('photo-editor'),
                backgroundColor: c.paper,
                body: session == null
                    ? _Loading(failed: _failed, onClose: _cancel)
                    : ListenableBuilder(
                        listenable: session,
                        builder: (context, _) => _editor(context, session),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _editor(BuildContext context, EditorSession session) {
    final c = context.tokens.colors;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return Stack(
      children: [
        Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                child: _TopBar(
                  session: session,
                  busy: _saving,
                  onCancel: () => unawaited(_cancel()),
                  onDone: () => unawaited(_done()),
                  onZoomReset: session.resetZoom,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    wide ? WeCordRadii.xl : 0,
                  ),
                  child: EditorCanvas(
                    session: session,
                    onAddText: _addText,
                    onEditText: _editText,
                  ),
                ),
              ),
            ),
            _Dock(
              session: session,
              onAddText: () => _addText(null),
              onEditText: _editText,
            ),
          ],
        ),
        if (session.draftText != null)
          Positioned.fill(child: EditorTextEntry(session: session)),
        if (_saving || _saveFailed)
          Positioned.fill(
            child: ColoredBox(
              color: c.scrim,
              child: Center(
                child: WeCordGlass(
                  key: const ValueKey('photo-editor-saving'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 18,
                  ),
                  child: Semantics(
                    liveRegion: true,
                    child: _saving
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: c.ink,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                tr('Preparing photo…'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: c.ink,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                tr("Couldn't save your edits. Try again."),
                                key: const ValueKey('photo-editor-save-error'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: c.ink,
                                ),
                              ),
                              const SizedBox(height: 12),
                              WeCordButton(
                                label: tr('OK'),
                                variant: WeCordButtonVariant.secondary,
                                onPressed: () =>
                                    setState(() => _saveFailed = false),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.failed, required this.onClose});

  final bool failed;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SafeArea(
      child: Center(
        child: failed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr("Couldn't open this photo."),
                    key: const ValueKey('photo-editor-open-error'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 16),
                  WeCordButton(
                    label: tr('Close'),
                    variant: WeCordButtonVariant.secondary,
                    onPressed: () => unawaited(onClose()),
                  ),
                ],
              )
            : Semantics(
                label: tr('Loading photo…'),
                liveRegion: true,
                child: CircularProgressIndicator(
                  color: c.ink,
                  strokeWidth: 2.4,
                ),
              ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.session,
    required this.busy,
    required this.onCancel,
    required this.onDone,
    required this.onZoomReset,
  });

  final EditorSession session;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onDone;
  final VoidCallback onZoomReset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Row(
          children: [
            WeCordIconButton(
              key: const ValueKey('photo-editor-cancel'),
              icon: Icons.close_rounded,
              tooltip: tr('Cancel'),
              variant: WeCordButtonVariant.ghost,
              onPressed: busy ? null : onCancel,
            ),
            const Spacer(),
            if (session.zoom > 1) ...[
              EditorOptionButton(
                key: const ValueKey('photo-editor-zoom-reset'),
                icon: Icons.fit_screen_rounded,
                label: tr('Fit to screen'),
                onPressed: onZoomReset,
              ),
              const SizedBox(width: 4),
            ],
            WeCordIconButton(
              key: const ValueKey('photo-editor-undo'),
              icon: Icons.undo_rounded,
              tooltip: tr('Undo'),
              variant: WeCordButtonVariant.ghost,
              onPressed: session.canUndo && !busy ? session.undo : null,
            ),
            WeCordIconButton(
              key: const ValueKey('photo-editor-redo'),
              icon: Icons.redo_rounded,
              tooltip: tr('Redo'),
              variant: WeCordButtonVariant.ghost,
              onPressed: session.canRedo && !busy ? session.redo : null,
            ),
            const SizedBox(width: 8),
            WeCordButton(
              key: const ValueKey('photo-editor-done'),
              label: tr('Done'),
              variant: WeCordButtonVariant.accent,
              onPressed: busy ? null : onDone,
            ),
          ],
        ),
      ),
    );
  }
}

/// The bottom: the options of the chosen tool and the tool selector.
class _Dock extends StatelessWidget {
  const _Dock({
    required this.session,
    required this.onAddText,
    required this.onEditText,
  });

  final EditorSession session;
  final VoidCallback onAddText;
  final ValueChanged<TextOverlay> onEditText;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final tool = session.tool;
    final options = switch (tool) {
      EditorTool.draw => DrawOptions(session: session),
      EditorTool.text => TextOptions(
        session: session,
        onAdd: onAddText,
        onEdit: onEditText,
      ),
      EditorTool.mosaic => MosaicOptions(session: session),
      EditorTool.crop => CropOptions(session: session),
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(WeCordRadii.xxl),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // As tall as the tallest tool's options, so the picture does
                  // not jump when the tool changes.
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 136),
                    child: Center(
                      child: KeyedSubtree(
                        key: ValueKey('photo-editor-options-${tool.name}'),
                        child: options,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  EditorToolSelector(
                    tool: tool,
                    onSelected: session.selectTool,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
