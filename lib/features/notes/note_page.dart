import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:wecord/features/ai/note_assist/note_assist_sheet.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart'
    show GlassMenuEntry, globalRectOf, showGlassMenu;
import 'package:wecord/features/chats/message_reactions.dart';
import 'package:wecord/features/chats/offline/outbox.dart' show newClientId;
import 'package:wecord/features/notes/export/note_file_exporter.dart';
import 'package:wecord/features/notes/export/note_pdf.dart';
import 'package:wecord/features/notes/note_comments_controller.dart';
import 'package:wecord/features/notes/note_comments_panel.dart';
import 'package:wecord/features/notes/note_editor.dart';
import 'package:wecord/features/notes/note_editor_controller.dart';
import 'package:wecord/features/notes/note_editor_extras.dart';
import 'package:wecord/features/notes/note_history.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_publish_sheet.dart';
import 'package:wecord/features/notes/note_sync.dart';
import 'package:wecord/features/notes/note_templates.dart';
import 'package:wecord/features/notes/note_text_ops.dart';
import 'package:wecord/features/notes/notes2_repository.dart';
import 'package:wecord/features/notes/notes_repository.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/ui/ui.dart';

/// One note, open for reading and (where allowed) editing together with the
/// people who have it open: title and icon, the blocks, who else is in it,
/// whether everything is stored, its history and settings.
///
/// Used full screen on phones and inside the workspace panel on desktop
/// ([embedded]).
///
/// A page of a circle's knowledge base is a note of the circle: pass
/// [circleId] instead of [conversationId]. It has no chat to be shared in,
/// no comments, no AI and no web page; [knowledgeMenu] adds what a page can
/// do (who may read it, moving it, deleting it) and [trail] shows where it
/// sits in the tree.
class NotePage extends ConsumerStatefulWidget {
  const NotePage({
    required this.noteId,
    this.conversationId,
    this.circleId,
    this.seed,
    this.onBack,
    this.embedded = false,
    this.autofocus = false,
    this.onDeleted,
    this.draftStore,
    this.trail,
    this.knowledgeMenu,
    this.selfName,
    super.key,
  }) : assert(
         (conversationId == null) != (circleId == null),
         'A note belongs to a conversation or to a circle',
       );

  final String noteId;
  final String? conversationId;
  final String? circleId;

  /// Under the header of a knowledge base page: where the page sits.
  final Widget? trail;

  /// The entries a knowledge base page adds to its menu.
  final List<GlassMenuEntry> Function(NoteMeta meta)? knowledgeMenu;

  /// The reader's name in the circle, shown to others in the page.
  final String? selfName;

  /// What the list knows of the note, shown while it loads.
  final NoteMeta? seed;
  final VoidCallback? onBack;

  /// Inside the desktop panel: no page chrome of its own.
  final bool embedded;
  final bool autofocus;
  final VoidCallback? onDeleted;
  final NoteDraftStore? draftStore;

  @override
  ConsumerState<NotePage> createState() => _NotePageState();
}

class _NotePageState extends ConsumerState<NotePage> {
  late final NoteEditorController _controller;
  late final NoteCommentsController _comments;
  final _titleController = TextEditingController();
  final _titleFocus = FocusNode(debugLabel: 'note title');
  final _editorKey = GlobalKey<NoteEditorState>();
  var _titleSynced = '';

  bool get _knowledge => widget.circleId != null;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authRepositoryProvider).currentUser;
    _controller = NoteEditorController(
      repository: ref.read(notesRepositoryProvider),
      noteId: widget.noteId,
      userId: user?.id ?? '',
      userName: _selfName(user?.id),
      newId: newClientId,
      seed: widget.seed,
      drafts: widget.draftStore,
    )..addListener(_onController);
    unawaited(_controller.open());
    _comments = NoteCommentsController(
      repository: ref.read(notes2RepositoryProvider),
      noteId: widget.noteId,
      newId: newClientId,
    )..addListener(_onController);
    if (!_knowledge) {
      unawaited(_comments.open());
    }
  }

  String _selfName(String? userId) {
    if (_knowledge) {
      final name = widget.selfName;
      return name == null || name.isEmpty ? tr('Someone') : name;
    }
    final members = ref
        .read(conversationMembersProvider(widget.conversationId!))
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

  void _onController() {
    final meta = _controller.meta;
    if (meta != null && meta.title != _titleSynced && !_titleFocus.hasFocus) {
      _titleSynced = meta.title;
      _titleController.text = meta.title;
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(NotePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(oldWidget.noteId == widget.noteId, 'NotePage is keyed by its note');
  }

  @override
  void dispose() {
    _comments
      ..removeListener(_onController)
      ..dispose();
    _controller
      ..removeListener(_onController)
      ..dispose();
    _titleController.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ actions --

  Future<void> _share() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final conversationId = widget.conversationId;
    if (conversationId == null) {
      return;
    }
    try {
      await ref
          .read(notesRepositoryProvider)
          .shareNote(widget.noteId, conversationId);
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Shared in the chat.'))),
      );
    } on Object {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not share the note.'))),
      );
    }
  }

  // ----------------------------------------------- comments, AI, export --

  List<GroupMember> get _members {
    final conversationId = widget.conversationId;
    if (conversationId == null) {
      return const [];
    }
    return ref.read(conversationMembersProvider(conversationId)).value ??
        const [];
  }

  void _startComment(NoteCommentTarget target) {
    unawaited(
      showNewNoteComment(
        context,
        members: _members,
        quote: target.quote,
        onSubmit: (body, mentions) async {
          await _comments.add(
            body,
            blockId: target.blockId,
            anchorStart: target.start,
            anchorEnd: target.end,
            anchorText: target.quote,
            mentions: mentions,
          );
        },
      ),
    );
  }

  void _openComments([String? blockId]) {
    unawaited(
      showNoteComments(
        context,
        controller: _comments,
        members: _members,
        canComment: _comments.canComment,
        focusBlockId: blockId,
      ),
    );
  }

  Future<void> _startAssist(NoteAssistTarget target) async {
    final apply = await showNoteAssistSheet(
      context,
      noteId: widget.noteId,
      target: target,
    );
    final editor = _editorKey.currentState;
    if (apply == null || !mounted || editor == null) {
      return;
    }
    // A version to come back to: the answer goes in as ordinary edits.
    try {
      await _controller.flush();
      await ref
          .read(notesRepositoryProvider)
          .createVersion(widget.noteId, label: tr('Before the AI'));
    } on Object {
      // The edit is worth more than the bookmark.
    }
    if (!mounted) {
      return;
    }
    final blockId = target.blockId;
    final start = target.start;
    final end = target.end;
    if (apply.replace && blockId != null && start != null && end != null) {
      editor.replaceRange(
        blockId,
        start,
        end,
        apply.result.blocks.map((block) => block.text).join(' '),
      );
    } else {
      editor.insertBlocksAfter(target.replaceBlockId ?? blockId, [
        for (final block in apply.result.blocks) block.toInsert(),
      ], removeBlockId: target.replaceBlockId);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _exportMarkdown() async {
    final meta = _controller.meta;
    final blocks = _controller.engine.blocks;
    final markdown = noteToMarkdown(meta?.title ?? '', blocks);
    final outcome = await ref
        .read(noteFileExporterProvider)
        .export(
          fileName: noteExportFileName(meta?.title ?? '', 'md'),
          bytes: Uint8List.fromList(utf8.encode('$markdown\n')),
          mimeType: 'text/markdown',
        );
    if (mounted && outcome == NoteExportOutcome.failed) {
      _toast(tr('Could not export the note.'));
    }
  }

  /// A picture of the note for the PDF: its signed link, downloaded.
  Future<ui.Image?> _loadPicture(NoteBlock block) async {
    final path = block.props['path'];
    if (path is! String) {
      return null;
    }
    try {
      final url = await ref.read(notesRepositoryProvider).imageUrl(path);
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        return null;
      }
      final codec = await ui.instantiateImageCodec(
        response.bodyBytes,
        targetWidth: 1200,
      );
      final frame = await codec.getNextFrame();
      return frame.image;
    } on Object {
      return null;
    }
  }

  Future<void> _exportPdf() async {
    final meta = _controller.meta;
    final title = meta?.title ?? '';
    final progress = ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(tr('Making the PDF…')),
        duration: const Duration(seconds: 30),
      ),
    );
    try {
      final bytes = await buildNotePdf(
        title: title,
        icon: meta?.icon ?? NoteMeta.defaultIcon,
        blocks: _controller.engine.blocks,
        loadPicture: _loadPicture,
        untitled: tr('Untitled'),
      );
      progress?.close();
      final outcome = await ref
          .read(noteFileExporterProvider)
          .export(
            fileName: noteExportFileName(title, 'pdf'),
            bytes: bytes,
            mimeType: 'application/pdf',
          );
      if (mounted && outcome == NoteExportOutcome.failed) {
        _toast(tr('Could not export the note.'));
      }
    } on Object {
      progress?.close();
      if (mounted) {
        _toast(tr('Could not export the note.'));
      }
    }
  }

  Future<void> _saveTemplate() async {
    final name = await askTemplateName(
      context,
      initial: _controller.meta?.title ?? '',
    );
    if (name == null || !mounted) {
      return;
    }
    try {
      await ref
          .read(notes2RepositoryProvider)
          .saveTemplate(widget.noteId, name);
      ref.invalidate(noteTemplatesProvider);
      if (mounted) {
        _toast(tr('Saved as a template.'));
      }
    } on Object {
      if (mounted) {
        _toast(tr('Could not save the template.'));
      }
    }
  }

  Future<void> _pickIcon() async {
    if (!_controller.canEdit) {
      return;
    }
    final emoji = await showEmojiReactionPicker(
      context,
      title: tr('Choose an icon'),
    );
    if (emoji != null) {
      await _controller.setIcon(emoji);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete this note?')),
        content: Text(
          tr(
            'It disappears for everyone in this conversation, with its '
            'history and pictures.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref.read(notesRepositoryProvider).deleteNote(widget.noteId);
      final conversationId = widget.conversationId;
      if (conversationId != null) {
        ref.invalidate(notesListProvider(conversationId));
      }
      if (mounted) {
        (widget.onDeleted ?? widget.onBack)?.call();
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('Could not delete the note.'))),
        );
      }
    }
  }

  void _openMenu(BuildContext buttonContext) {
    final meta = _controller.meta;
    if (meta == null) {
      return;
    }
    final exports = <GlassMenuEntry>[
      GlassMenuEntry(
        icon: Icons.description_outlined,
        label: tr('Export as a Markdown file'),
        onSelected: () => unawaited(_exportMarkdown()),
      ),
      GlassMenuEntry(
        icon: Icons.picture_as_pdf_outlined,
        label: tr('Export as a PDF'),
        onSelected: () => unawaited(_exportPdf()),
      ),
      GlassMenuEntry(
        icon: Icons.copy_all_rounded,
        label: tr('Copy as Markdown'),
        onSelected: () {
          unawaited(
            Clipboard.setData(
              ClipboardData(
                text: noteToMarkdown(meta.title, _controller.engine.blocks),
              ),
            ),
          );
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(SnackBar(content: Text(tr('Copied.'))));
        },
      ),
    ];
    if (_knowledge) {
      unawaited(
        showGlassMenu(
          buttonContext,
          anchor: globalRectOf(buttonContext),
          width: 280,
          entries: [...exports, ...?widget.knowledgeMenu?.call(meta)],
        ),
      );
      return;
    }
    unawaited(
      showGlassMenu(
        buttonContext,
        anchor: globalRectOf(buttonContext),
        width: 280,
        entries: [
          if (meta.canManage)
            GlassMenuEntry(
              icon: meta.pinned
                  ? Icons.push_pin_rounded
                  : Icons.push_pin_outlined,
              label: meta.pinned
                  ? tr('Unpin from the chat')
                  : tr('Pin to the top of the chat'),
              onSelected: () =>
                  unawaited(_guard(() => _controller.setPinned(!meta.pinned))),
            ),
          if (meta.canManage)
            GlassMenuEntry(
              icon: meta.managersOnly
                  ? Icons.lock_open_rounded
                  : Icons.lock_outline_rounded,
              label: meta.managersOnly
                  ? tr('Let everyone edit')
                  : tr('Only managers can edit'),
              onSelected: () => unawaited(
                _guard(() => _controller.setManagersOnly(!meta.managersOnly)),
              ),
            ),
          GlassMenuEntry(
            icon: Icons.public_rounded,
            label: tr('Publish to the web…'),
            onSelected: () =>
                unawaited(showNotePublishSheet(context, noteId: widget.noteId)),
          ),
          GlassMenuEntry(
            icon: Icons.bookmark_add_outlined,
            label: tr('Save as a template…'),
            onSelected: () => unawaited(_saveTemplate()),
          ),
          ...exports,
          GlassMenuEntry(
            icon: Icons.delete_outline_rounded,
            label: tr('Delete note'),
            destructive: true,
            onSelected: () => unawaited(_delete()),
          ),
        ],
      ),
    );
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('That did not work. Try again.'))),
        );
      }
    }
  }

  // -------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final meta = _controller.meta ?? widget.seed;
    final conversationId = widget.conversationId;
    final members = conversationId == null
        ? const <GroupMember>[]
        : ref.watch(conversationMembersProvider(conversationId)).value ??
              const [];
    final loading = _controller.loading && _controller.meta == null;

    Widget body;
    if (_controller.unavailable) {
      body = _Notice(
        icon: Icons.lock_outline_rounded,
        title: tr('This note is not available'),
        message: tr('It was deleted, or you no longer have access to it.'),
      );
    } else if (_controller.error != null && meta == null) {
      body = _Notice(
        icon: Icons.cloud_off_rounded,
        title: tr('Could not open the note'),
        message: tr('Check your connection and try again.'),
        action: WeCordButton(
          label: tr('Try again'),
          size: WeCordButtonSize.medium,
          onPressed: () => unawaited(_controller.open()),
        ),
      );
    } else if (loading) {
      body = const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    } else {
      body = NoteEditor(
        key: _editorKey,
        controller: _controller,
        members: members,
        autofocus: widget.autofocus && _controller.canEdit,
        extras: _knowledge
            ? const NoteEditorExtras()
            : NoteEditorExtras(
                comments: _comments,
                canComment: _comments.canComment,
                onComment: _startComment,
                onOpenComments: _openComments,
                onAssist: _controller.canEdit
                    ? (target) => unawaited(_startAssist(target))
                    : null,
              ),
        padding: EdgeInsets.fromLTRB(
          widget.embedded ? 16 : 20,
          8,
          widget.embedded ? 16 : 20,
          96,
        ),
        header: _NoteTitleBlock(
          meta: meta,
          controller: _controller,
          titleController: _titleController,
          titleFocus: _titleFocus,
          onPickIcon: _pickIcon,
          onSubmitted: () {
            final first = _controller.engine.blocks.firstOrNull;
            if (first != null) {
              _editorKey.currentState?.focusBlock(first.id);
            }
          },
        ),
      );
    }

    final header = _NoteHeader(
      controller: _controller,
      knowledge: _knowledge,
      embedded: widget.embedded,
      onBack: widget.onBack,
      onShare: _share,
      commentCount: _comments.openCount,
      onComments: _openComments,
      onHistory: () => unawaited(
        showNoteHistory(
          context,
          noteId: widget.noteId,
          canEdit: _controller.canEdit,
          onRestored: () => unawaited(_controller.reload()),
        ),
      ),
      onMenu: _openMenu,
    );

    return Scaffold(
      backgroundColor: c.panel,
      body: SafeArea(
        top: !widget.embedded,
        bottom: false,
        child: Column(
          children: [
            header,
            ?widget.trail,
            if (_controller.status == NoteSyncStatus.offline)
              _OfflineBanner(pending: _controller.engine.pendingCount),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _NoteHeader extends StatelessWidget {
  const _NoteHeader({
    required this.controller,
    required this.knowledge,
    required this.embedded,
    required this.onShare,
    required this.onHistory,
    required this.onMenu,
    required this.commentCount,
    required this.onComments,
    this.onBack,
  });

  /// Unresolved comment threads, shown on the comments button.
  final int commentCount;
  final VoidCallback onComments;

  final NoteEditorController controller;

  /// A page of a circle's knowledge base: no chat to share in, no comments.
  final bool knowledge;
  final bool embedded;
  final VoidCallback? onBack;
  final VoidCallback onShare;
  final VoidCallback onHistory;
  final void Function(BuildContext buttonContext) onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final meta = controller.meta;
    final status = controller.status;
    final statusLabel = switch (status) {
      NoteSyncStatus.saved => tr('Saved'),
      NoteSyncStatus.saving => tr('Saving…'),
      NoteSyncStatus.offline => tr('Offline'),
    };
    final size = embedded ? 36.0 : 40.0;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: EdgeInsets.fromLTRB(embedded ? 8 : 6, 4, 8, 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.lineSoft)),
      ),
      child: Row(
        children: [
          if (onBack != null)
            WeCordIconButton(
              tooltip: embedded ? tr('Back to notes') : tr('Back'),
              icon: Icons.chevron_left_rounded,
              iconSize: 24,
              size: size,
              variant: WeCordButtonVariant.ghost,
              onPressed: onBack,
            ),
          Expanded(
            child: Semantics(
              liveRegion: true,
              label: statusLabel,
              child: Row(
                children: [
                  Icon(
                    switch (status) {
                      NoteSyncStatus.saved =>
                        Icons.check_circle_outline_rounded,
                      NoteSyncStatus.saving => Icons.sync_rounded,
                      NoteSyncStatus.offline => Icons.cloud_off_rounded,
                    },
                    size: 16,
                    color: status == NoteSyncStatus.offline
                        ? c.warningText
                        : c.subtle,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: status == NoteSyncStatus.offline
                            ? c.warningText
                            : c.subtle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(child: PeerAvatars(peers: controller.peers)),
                ],
              ),
            ),
          ),
          if (meta != null) ...[
            if (!knowledge) ...[
              WeCordIconButton(
                tooltip: tr('Share in the chat'),
                icon: Icons.ios_share_rounded,
                iconSize: 20,
                size: size,
                variant: WeCordButtonVariant.ghost,
                onPressed: onShare,
              ),
              WeCordIconButton(
                key: const ValueKey('note-comments-button'),
                tooltip: tr('Comments'),
                icon: Icons.mode_comment_outlined,
                iconSize: 20,
                size: size,
                variant: WeCordButtonVariant.ghost,
                badgeCount: commentCount > 0 ? commentCount : null,
                onPressed: onComments,
              ),
            ],
            WeCordIconButton(
              tooltip: tr('Version history'),
              icon: Icons.history_rounded,
              iconSize: 21,
              size: size,
              variant: WeCordButtonVariant.ghost,
              onPressed: onHistory,
            ),
            Builder(
              builder: (buttonContext) => WeCordIconButton(
                tooltip: tr('More'),
                icon: Icons.more_horiz_rounded,
                iconSize: 21,
                size: size,
                variant: WeCordButtonVariant.ghost,
                onPressed: () => onMenu(buttonContext),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Overlapped avatars of the people in the note, with "+2".
class PeerAvatars extends StatelessWidget {
  const PeerAvatars({required this.peers, super.key});

  final List<NotePeer> peers;

  @override
  Widget build(BuildContext context) {
    if (peers.isEmpty) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final shown = peers.take(4).toList();
    final names = peers.map((peer) => peer.name).join(', ');
    return Semantics(
      label: tr('Also here: {names}', {'names': names}),
      excludeSemantics: true,
      child: Tooltip(
        message: names,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 26,
              width: 26.0 + (shown.length - 1) * 18,
              child: Stack(
                children: [
                  for (final (index, peer) in shown.indexed)
                    Positioned(
                      left: index * 18.0,
                      child: PersonAvatar(
                        name: peer.name,
                        size: 26,
                        ringColor: c.panel,
                      ),
                    ),
                ],
              ),
            ),
            if (peers.length > shown.length) ...[
              const SizedBox(width: 6),
              Text(
                '+${peers.length - shown.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The icon, title and notices at the top of the note.
class _NoteTitleBlock extends StatelessWidget {
  const _NoteTitleBlock({
    required this.meta,
    required this.controller,
    required this.titleController,
    required this.titleFocus,
    required this.onPickIcon,
    required this.onSubmitted,
  });

  final NoteMeta? meta;
  final NoteEditorController controller;
  final TextEditingController titleController;
  final FocusNode titleFocus;
  final VoidCallback onPickIcon;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final canEdit = controller.canEdit;
    final meta = this.meta;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WeCordPressable(
                key: const ValueKey('note-icon'),
                onPressed: canEdit ? onPickIcon : null,
                tooltip: canEdit ? tr('Change icon') : null,
                semanticLabel: tr('Note icon'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(WeCordRadii.lg),
                ),
                builder: (context, states) => Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: states.contains(WidgetState.hovered)
                        ? c.raisedStrong
                        : c.raised,
                    borderRadius: BorderRadius.circular(WeCordRadii.lg),
                  ),
                  child: Text(
                    meta?.icon ?? NoteMeta.defaultIcon,
                    style: const TextStyle(fontSize: 26),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey('note-title'),
                  controller: titleController,
                  focusNode: titleFocus,
                  readOnly: !canEdit,
                  maxLength: 200,
                  maxLines: null,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(
                    fontSize: 28,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: c.ink,
                  ),
                  cursorColor: c.accent,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    counterText: '',
                    hintText: tr('Untitled'),
                    hintStyle: TextStyle(
                      fontSize: 28,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: c.subtle,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                  onChanged: controller.setTitle,
                  onSubmitted: (_) => onSubmitted(),
                ),
              ),
            ],
          ),
          if (meta != null && (meta.managersOnly || !canEdit)) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (meta.managersOnly)
                  _InfoChip(
                    icon: Icons.lock_outline_rounded,
                    label: tr('Only managers can edit'),
                  ),
                if (!canEdit)
                  _InfoChip(
                    icon: Icons.visibility_outlined,
                    label: tr('You can read this note but not edit it'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: ShapeDecoration(
        color: c.raised,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: c.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.pending});

  final int pending;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('note-offline-banner'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: c.warningSoft,
        child: Text(
          pending > 0
              ? tr(
                  'You are offline. Your changes are kept on this device and '
                  'will be merged when you are back.',
                )
              : tr('You are offline. The note will refresh when you are back.'),
          style: TextStyle(
            fontSize: 13,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: c.warningText,
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: c.faint),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
