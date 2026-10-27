import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chat_privacy/chat_privacy_repository.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/notes/export/note_file_exporter.dart';
import 'package:wecord/features/whiteboard/whiteboard_canvas.dart';
import 'package:wecord/features/whiteboard/whiteboard_controller.dart';
import 'package:wecord/features/whiteboard/whiteboard_elements_view.dart';
import 'package:wecord/features/whiteboard/whiteboard_export.dart';
import 'package:wecord/features/whiteboard/whiteboard_painter.dart';
import 'package:wecord/features/whiteboard/whiteboard_picture.dart';
import 'package:wecord/features/whiteboard/whiteboard_repository.dart';
import 'package:wecord/features/whiteboard/whiteboard_routes.dart';
import 'package:wecord/features/whiteboard/whiteboard_sync.dart';
import 'package:wecord/features/whiteboard/whiteboard_toolbar.dart';
import 'package:wecord/features/whiteboard/whiteboard_versions_sheet.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The boards stay light in every theme, so a color means the same thing to
/// everyone looking at the board and in the exported picture.
const whiteboardPalette = WhiteboardPalette(
  background: Color(0xFFFAFAFB),
  grid: Color(0xFFD7D8DE),
  selection: Color(0xFF3B6EF5),
  handleFill: Color(0xFFFFFFFF),
  label: Color(0xFF1B1B1F),
);

enum _MenuAction {
  rename,
  fit,
  export,
  versions,
  lock,
  clear,
  delete,
}

/// One whiteboard: the drawing, the tools, who else is here, and the
/// board's menu. `/chats/<id>/whiteboards/<board id>`.
class WhiteboardPage extends ConsumerStatefulWidget {
  const WhiteboardPage({
    required this.conversationId,
    required this.boardId,
    this.title,
    this.controller,
    super.key,
  });

  final String conversationId;
  final String boardId;

  /// A controller made and loaded by a test; the page then does not load it
  /// again (it still disposes it with the page).
  @visibleForTesting
  final WhiteboardController? controller;

  /// Shown until the board has loaded.
  final String? title;

  static const listToggleKey = ValueKey('whiteboard-list-toggle');
  static const menuKey = ValueKey('whiteboard-menu');
  static const undoKey = ValueKey('whiteboard-undo');
  static const redoKey = ValueKey('whiteboard-redo');
  static const fitKey = ValueKey('whiteboard-fit');
  static const titleKey = ValueKey('whiteboard-title');
  static const syncKey = ValueKey('whiteboard-sync');

  @override
  ConsumerState<WhiteboardPage> createState() => _WhiteboardPageState();
}

class _WhiteboardPageState extends ConsumerState<WhiteboardPage>
    with WidgetsBindingObserver {
  late final WhiteboardController _controller;
  var _listMode = false;
  var _noticeSeen = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final given = widget.controller;
    if (given != null) {
      _controller = given..measureWords = measureWhiteboardText;
      _needsLoad = false;
    } else {
      final user = ref.read(authRepositoryProvider).currentUser;
      _controller = WhiteboardController(
        boardId: widget.boardId,
        repository: ref.read(whiteboardRepositoryProvider),
        drafts: ref.read(whiteboardDraftStoreProvider),
        userId: user?.id ?? '',
        userName: _selfName(user?.id),
      )..measureWords = measureWhiteboardText;
    }
    _controller.addListener(_onController);
    if (_needsLoad) {
      unawaited(_controller.load());
    }
  }

  var _needsLoad = true;

  String _selfName(String? userId) {
    final members = ref
        .read(conversationMembersProvider(widget.conversationId))
        .value;
    if (userId != null && members != null) {
      for (final member in members) {
        if (member.profile.id == userId) {
          return member.profile.displayName;
        }
      }
    }
    return tr('Someone');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_controller.flushNow());
    }
  }

  void _onController() {
    if (_controller.noticeSerial != _noticeSeen) {
      _noticeSeen = _controller.noticeSerial;
      final message = switch (_controller.notice) {
        WhiteboardNotice.boardFull => tr(
          'This whiteboard is full ({max} items). Delete something to add more.',
          {'max': 3000},
        ),
        WhiteboardNotice.boardTooBig => tr(
          'This whiteboard holds as much as it can. Delete something to add more.',
        ),
        WhiteboardNotice.tooManyPictures => tr(
          'A whiteboard can hold {max} pictures.',
          {'max': 60},
        ),
        WhiteboardNotice.readOnly => tr(
          'You can look at this whiteboard but not change it.',
        ),
        WhiteboardNotice.pictureFailed => tr(
          'The picture could not be added. Try again.',
        ),
        WhiteboardNotice.rejected => tr(
          'The whiteboard did not accept that change.',
        ),
        null => null,
      };
      if (message != null && mounted) {
        _toast(message);
      }
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller
      ..removeListener(_onController)
      ..dispose();
    super.dispose();
  }

  // -------------------------------------------------------------- actions --

  Future<void> _pickPicture() async {
    if (!_controller.canEdit) {
      _toast(tr('You can look at this whiteboard but not change it.'));
      return;
    }
    final picked = await ref.read(imagePickerServiceProvider).pickImage();
    if (picked == null || !mounted) {
      return;
    }
    final prepared = await prepareWhiteboardPicture(
      picked.bytes,
      fileName: picked.fileName,
      mimeType: picked.mimeType,
    );
    if (!mounted) {
      return;
    }
    if (prepared == null) {
      _toast(tr('That picture could not be used.'));
      return;
    }
    await _controller.addImage(
      prepared.bytes,
      fileName: prepared.fileName,
      mimeType: prepared.mimeType,
      pixels: prepared.size,
    );
  }

  Future<void> _rename() async {
    final text = TextEditingController(text: _controller.title);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Name this whiteboard')),
        content: TextField(
          key: const ValueKey('whiteboard-rename-field'),
          controller: text,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(hintText: tr('Whiteboard name')),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            key: const ValueKey('whiteboard-rename-done'),
            onPressed: () => Navigator.of(context).pop(text.text),
            child: Text(tr('Save')),
          ),
        ],
      ),
    );
    text.dispose();
    if (result == null) {
      return;
    }
    if (!await _controller.rename(result) && mounted) {
      _toast(tr('Could not rename the whiteboard.'));
    }
  }

  Future<void> _export() async {
    final elements = _controller.engine.elements;
    final png = await renderWhiteboardPng(elements, _controller.images);
    if (!mounted) {
      return;
    }
    if (png == null) {
      _toast(tr('There is nothing to export yet.'));
      return;
    }
    final name = _controller.title.trim().isEmpty
        ? tr('Whiteboard')
        : _controller.title;
    final outcome = await ref
        .read(noteFileExporterProvider)
        .export(
          fileName: noteExportFileName(name, 'png'),
          bytes: png,
          mimeType: 'image/png',
        );
    if (!mounted) {
      return;
    }
    if (outcome == NoteExportOutcome.failed) {
      _toast(tr('Could not export the whiteboard.'));
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            key: const ValueKey('whiteboard-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _clear() async {
    final ok = await _confirm(
      title: tr('Clear this whiteboard?'),
      body: tr(
        'Everything on it is removed for everyone. The board is saved as an earlier version first, so you can go back to it.',
      ),
      action: tr('Clear'),
    );
    if (!ok || !mounted) {
      return;
    }
    if (!await _controller.clear() && mounted) {
      _toast(tr('Could not clear the whiteboard.'));
    }
  }

  Future<void> _delete() async {
    final ok = await _confirm(
      title: tr('Delete this whiteboard?'),
      body: tr(
        'It and its earlier versions are deleted for everyone. This cannot be undone.',
      ),
      action: tr('Delete'),
    );
    if (!ok || !mounted) {
      return;
    }
    try {
      await _controller.flushNow();
      await _controller.repository.deleteBoard(widget.boardId);
      await _controller.drafts.clear(widget.boardId);
      ref.invalidate(whiteboardListProvider(widget.conversationId));
      if (mounted) {
        _leave();
      }
    } on Object {
      if (mounted) {
        _toast(tr('Could not delete the whiteboard.'));
      }
    }
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(whiteboardListPath(widget.conversationId));
    }
  }

  // ---------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final restricted = ref.watch(
      restrictSharingProvider(widget.conversationId),
    );
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, restricted: restricted),
                ..._banners(context),
                Expanded(child: _body(context)),
                if (_controller.loadState == WhiteboardLoadState.ready &&
                    !_listMode)
                  WhiteboardToolbar(
                    controller: _controller,
                    onPickPicture: () => unawaited(_pickPicture()),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context, {required bool restricted}) {
    final c = context.tokens.colors;
    final title = _controller.title.isNotEmpty
        ? _controller.title
        : (widget.title?.isNotEmpty == true ? widget.title! : tr('Whiteboard'));
    final ready = _controller.loadState == WhiteboardLoadState.ready;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 4),
      child: Row(
        children: [
          WeCordIconButton(
            key: const ValueKey('whiteboard-back'),
            icon: Icons.chevron_left_rounded,
            iconSize: 24,
            size: 44,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            variant: WeCordButtonVariant.onPaper,
            onPressed: _leave,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Semantics(
              header: true,
              child: InkWell(
                key: WhiteboardPage.titleKey,
                onTap: ready && _controller.canEdit
                    ? () => unawaited(_rename())
                    : null,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: c.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (ready) ...[
            _Peers(controller: _controller),
            _SyncBadge(controller: _controller),
            WeCordIconButton(
              key: WhiteboardPage.listToggleKey,
              icon: _listMode ? Icons.draw_outlined : Icons.list_alt_rounded,
              size: 44,
              tooltip: _listMode
                  ? tr('Show the drawing')
                  : tr('Show as a list'),
              variant: WeCordButtonVariant.onPaper,
              onPressed: () => setState(() => _listMode = !_listMode),
            ),
            PopupMenuButton<_MenuAction>(
              key: WhiteboardPage.menuKey,
              tooltip: tr('More'),
              icon: Icon(Icons.more_horiz_rounded, color: c.ink),
              onSelected: _onMenu,
              itemBuilder: (context) => [
                if (_controller.canEdit)
                  PopupMenuItem(
                    value: _MenuAction.rename,
                    child: Text(tr('Rename')),
                  ),
                PopupMenuItem(
                  value: _MenuAction.fit,
                  child: Text(tr('Show everything')),
                ),
                if (!restricted)
                  PopupMenuItem(
                    value: _MenuAction.export,
                    child: Text(tr('Export as picture')),
                  ),
                PopupMenuItem(
                  value: _MenuAction.versions,
                  child: Text(tr('Earlier versions')),
                ),
                if (_controller.canManage)
                  PopupMenuItem(
                    value: _MenuAction.lock,
                    child: Text(
                      _controller.meta?.managersOnly == true
                          ? tr('Let everyone draw')
                          : tr('Only managers can draw'),
                    ),
                  ),
                if (_controller.canManage)
                  PopupMenuItem(
                    value: _MenuAction.clear,
                    child: Text(tr('Clear whiteboard')),
                  ),
                if (_controller.canManage)
                  PopupMenuItem(
                    value: _MenuAction.delete,
                    child: Text(tr('Delete whiteboard')),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _onMenu(_MenuAction action) {
    switch (action) {
      case _MenuAction.rename:
        unawaited(_rename());
      case _MenuAction.fit:
        _controller.fitToContent();
      case _MenuAction.export:
        unawaited(_export());
      case _MenuAction.versions:
        unawaited(showWhiteboardVersions(context, _controller));
      case _MenuAction.lock:
        unawaited(
          _controller.setManagersOnly(_controller.meta?.managersOnly != true),
        );
      case _MenuAction.clear:
        unawaited(_clear());
      case _MenuAction.delete:
        unawaited(_delete());
    }
  }

  List<Widget> _banners(BuildContext context) {
    if (_controller.loadState != WhiteboardLoadState.ready) {
      return const [];
    }
    return [
      if (!_controller.canEdit)
        _Banner(
          key: const ValueKey('whiteboard-readonly'),
          icon: Icons.visibility_outlined,
          text: _controller.meta?.managersOnly == true
              ? tr('Only managers can draw on this whiteboard.')
              : tr('You can look at this whiteboard but not change it.'),
        ),
      if (_controller.engine.status == WhiteboardSyncStatus.offline)
        _Banner(
          key: const ValueKey('whiteboard-offline'),
          icon: Icons.cloud_off_outlined,
          text: tr(
            'Offline. What you draw is kept on this device and sent when you are back.',
          ),
        ),
    ];
  }

  Widget _body(BuildContext context) {
    final c = context.tokens.colors;
    switch (_controller.loadState) {
      case WhiteboardLoadState.loading:
        return Center(child: CircularProgressIndicator(color: c.muted));
      case WhiteboardLoadState.failed:
        return _Message(
          icon: Icons.cloud_off_outlined,
          text: tr("That couldn't load. Try again."),
          actionLabel: tr('Try again'),
          onAction: () => unawaited(_controller.load()),
        );
      case WhiteboardLoadState.gone:
        return _Message(
          icon: Icons.layers_clear_outlined,
          text: tr('This whiteboard was deleted.'),
          actionLabel: tr('Back'),
          onAction: _leave,
        );
      case WhiteboardLoadState.ready:
        if (_listMode) {
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: WhiteboardElementsView(controller: _controller),
            ),
          );
        }
        return Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                container: true,
                label: tr(
                  'Whiteboard drawing, {count} items. Use the list view to read or change it without drawing.',
                  {'count': _controller.engine.liveCount},
                ),
                child: WhiteboardCanvas(
                  controller: _controller,
                  palette: whiteboardPalette,
                  onPicture: () => unawaited(_pickPicture()),
                ),
              ),
            ),
            PositionedDirectional(
              top: 8,
              end: 8,
              child: _CanvasControls(controller: _controller),
            ),
          ],
        );
    }
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.warningSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.warningText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, height: 1.3, color: c.warningText),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: c.faint),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.4, color: c.muted),
            ),
            const SizedBox(height: 16),
            WeCordButton(
              label: actionLabel,
              variant: WeCordButtonVariant.secondary,
              onPressed: onAction,
            ),
          ],
        ),
      ),
    );
  }
}

/// Undo, redo and "show everything" over the corner of the drawing.
class _CanvasControls extends StatelessWidget {
  const _CanvasControls({required this.controller});

  final WhiteboardController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: c.lineSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (controller.canEdit) ...[
                WeCordIconButton(
                  key: WhiteboardPage.undoKey,
                  icon: Icons.undo_rounded,
                  size: 44,
                  tooltip: tr('Undo'),
                  variant: WeCordButtonVariant.ghost,
                  onPressed: controller.canUndo ? controller.undo : null,
                ),
                WeCordIconButton(
                  key: WhiteboardPage.redoKey,
                  icon: Icons.redo_rounded,
                  size: 44,
                  tooltip: tr('Redo'),
                  variant: WeCordButtonVariant.ghost,
                  onPressed: controller.canRedo ? controller.redo : null,
                ),
              ],
              WeCordIconButton(
                key: WhiteboardPage.fitKey,
                icon: Icons.fit_screen_outlined,
                size: 44,
                tooltip: tr('Show everything'),
                variant: WeCordButtonVariant.ghost,
                onPressed: controller.fitToContent,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The others on the board: up to three faces and a count.
class _Peers extends StatelessWidget {
  const _Peers({required this.controller});

  final WhiteboardController controller;

  @override
  Widget build(BuildContext context) {
    final peers = controller.peers;
    if (peers.isEmpty) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final shown = peers.take(3).toList();
    return Semantics(
      label: tr(
        '{count} others here: {names}',
        {'count': peers.length, 'names': peers.map((p) => p.name).join(', ')},
      ),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final peer in shown)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 2),
                child: PersonAvatar(
                  name: peer.name,
                  size: 28,
                  ringColor: Color(peer.color),
                  color: Color(peer.color),
                ),
              ),
            if (peers.length > shown.length)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 2, end: 4),
                child: Text(
                  '+${peers.length - shown.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.muted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A small icon that says whether the drawing is stored.
class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.controller});

  final WhiteboardController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final status = controller.engine.status;
    final (icon, label, color) = switch (status) {
      WhiteboardSyncStatus.saved => (
        Icons.cloud_done_outlined,
        tr('Saved'),
        c.muted,
      ),
      WhiteboardSyncStatus.saving => (
        Icons.cloud_upload_outlined,
        tr('Saving…'),
        c.muted,
      ),
      WhiteboardSyncStatus.offline => (
        Icons.cloud_off_outlined,
        tr('Offline, kept on this device'),
        c.warningText,
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Tooltip(
        message: label,
        child: Semantics(
          key: WhiteboardPage.syncKey,
          label: label,
          child: ExcludeSemantics(child: Icon(icon, size: 20, color: color)),
        ),
      ),
    );
  }
}
