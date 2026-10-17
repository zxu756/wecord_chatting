import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart'
    show GlassMenuEntry, globalRectOf, showGlassMenu;
import 'package:wecord/features/notes/note_block_views.dart';
import 'package:wecord/features/notes/note_editor_controller.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_text_controller.dart';
import 'package:wecord/features/notes/note_text_ops.dart';
import 'package:wecord/features/notes/notes_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A person who can be @mentioned in a note.
typedef NoteMentionCandidate = ({String userId, String label});

/// The state of one block's text field.
class _BlockField {
  _BlockField(this.id, NoteBlock block)
    : text = NoteTextController(text: block.text, marks: block.marks),
      focus = FocusNode(debugLabel: 'note block $id');

  final String id;
  final NoteTextController text;
  final FocusNode focus;
  final key = GlobalKey();

  void dispose() {
    text.dispose();
    focus.dispose();
  }
}

/// The body of a note: a column of blocks, each its own text field, with
/// the shortcuts of a writing app (⌘B/⌘I/⌘K, `- `, `1. `, `[] `, `# `, `>
/// `), a formatting bar, @mentions, pictures, and the carets of the other
/// people in the note. Everything typed goes through the
/// [NoteEditorController]'s engine, which merges it with their edits.
class NoteEditor extends ConsumerStatefulWidget {
  const NoteEditor({
    required this.controller,
    this.members = const [],
    this.header,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 96),
    this.maxContentWidth = 760,
    this.autofocus = false,
    super.key,
  });

  final NoteEditorController controller;

  /// People who can be mentioned.
  final List<GroupMember> members;

  /// Scrolls with the blocks, above them (icon and title).
  final Widget? header;
  final EdgeInsets padding;
  final double maxContentWidth;

  /// Puts the caret in the first block when it opens.
  final bool autofocus;

  @override
  ConsumerState<NoteEditor> createState() => NoteEditorState();
}

class NoteEditorState extends ConsumerState<NoteEditor> {
  final _fields = <String, _BlockField>{};
  final _scroll = ScrollController();
  String? _focusedId;
  final _stale = <_BlockField>[];
  ({String blockId, int start, int end, String query})? _mention;

  NoteEditorController get _controller => widget.controller;
  bool get _readOnly => !_controller.canEdit;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onEngine);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final first = _controller.engine.blocks.firstOrNull;
        if (first != null && mounted && !_readOnly) {
          _focus(first.id);
        }
      });
    }
  }

  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onEngine);
      widget.controller.addListener(_onEngine);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onEngine);
    for (final field in [..._fields.values, ..._stale]) {
      field.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _onEngine() {
    if (!mounted) {
      return;
    }
    // Remote changes and merges flow into the text fields; what the
    // person is typing already matches.
    for (final block in _controller.engine.blocks) {
      final field = _fields[block.id];
      if (field != null) {
        field.text.applyRemote(block.text, block.marks);
      }
    }
    setState(() {});
  }

  _BlockField _fieldFor(NoteBlock block) {
    final existing = _fields[block.id];
    if (existing != null) {
      return existing;
    }
    final field = _BlockField(block.id, block);
    field.text.onUserChange = (text, marks) =>
        _onUserChange(block.id, text, marks);
    field.focus.addListener(() {
      if (field.focus.hasFocus) {
        _focusedId = field.id;
        _reportCursor(field);
        if (mounted) {
          setState(() {});
        }
      }
    });
    field.text.addListener(() => _reportCursor(field));
    _fields[block.id] = field;
    return field;
  }

  void _reportCursor(_BlockField field) {
    if (!field.focus.hasFocus) {
      return;
    }
    final selection = field.text.selection;
    _controller.setCursor(
      blockId: field.id,
      offset: selection.isValid ? selection.extentOffset : null,
    );
  }

  // ----------------------------------------------------------------- focus --

  /// Puts the caret in a block (at the end, or at [offset]).
  void focusBlock(String id, {int? offset}) => _focus(id, offset: offset);

  void _focus(String id, {int? offset}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final block = _controller.engine.blockById(id);
      if (block == null) {
        return;
      }
      final field = _fieldFor(block);
      if (block.kind.hasText) {
        field.focus.requestFocus();
        final at = (offset ?? block.text.length).clamp(0, block.text.length);
        field.text.selection = TextSelection.collapsed(offset: at);
      } else {
        field.focus.requestFocus();
      }
      final context = field.key.currentContext;
      if (context != null) {
        unawaited(
          Scrollable.ensureVisible(
            context,
            duration: WeCordMotion.durationOf(context, WeCordMotion.base),
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          ),
        );
      }
    });
    setState(() => _focusedId = id);
  }

  List<NoteBlock> get _blocks => _controller.engine.blocks;

  NoteBlock? get _focusedBlock {
    final id = _focusedId;
    return id == null ? null : _controller.engine.blockById(id);
  }

  _BlockField? get _focusedField =>
      _focusedId == null ? null : _fields[_focusedId];

  // --------------------------------------------------------------- changes --

  void _onUserChange(String id, String text, List<NoteMark> marks) {
    final engine = _controller.engine;
    final block = engine.blockById(id);
    if (block == null) {
      return;
    }
    if (block.kind != NoteBlockKind.code && text.contains('\n')) {
      _splitOnNewline(block, text, marks);
      return;
    }
    // A markdown shortcut typed into a paragraph.
    if (block.kind == NoteBlockKind.paragraph) {
      final shortcut = shortcutFor(text);
      if (shortcut != null) {
        _convert(
          block,
          shortcut.kind,
          text: shortcut.text,
          props: shortcut.props,
        );
        return;
      }
      if (text == '/') {
        engine.updateBlock(id, text: text, marks: marks);
        _openBlockMenu(block, slash: true);
        return;
      }
    }
    engine.updateBlock(id, text: text, marks: marks);
    _updateMention(id, text);
  }

  /// Turns [block] into [kind], with new text; the field follows.
  void _convert(
    NoteBlock block,
    NoteBlockKind kind, {
    String? text,
    Map<String, Object?>? props,
  }) {
    final field = _fields[block.id];
    var nextProps = props ?? block.props;
    if (kind != NoteBlockKind.todo) {
      nextProps = {
        for (final entry in nextProps.entries)
          if (entry.key != 'checked') entry.key: entry.value,
      };
    }
    _controller.engine.updateBlock(
      block.id,
      kind: kind,
      text: text,
      marks: text == null ? null : const [],
      props: nextProps,
    );
    if (text != null && field != null) {
      field.text.applyRemote(text, const []);
    }
    if (kind.hasText) {
      _focus(block.id, offset: text?.length);
    }
  }

  void _splitOnNewline(NoteBlock block, String text, List<NoteMark> marks) {
    final engine = _controller.engine;
    final field = _fields[block.id];
    final newline = text.indexOf('\n');
    final first = splitText(text, marks, newline);

    // Pasted lines become blocks of their own.
    if ('\n'.allMatches(text).length > 1) {
      engine.updateBlock(block.id, text: first.left, marks: first.leftMarks);
      field?.text.applyRemote(first.left, first.leftMarks);
      final parsed = parsePastedText(first.right.substring(1));
      if (parsed.isEmpty) {
        _focus(
          engine.insertBlock(afterId: block.id, kind: _nextKind(block.kind)).id,
        );
        return;
      }
      final created = engine.insertBlocks(block.id, parsed);
      _focus(created.last.id, offset: created.last.text.length);
      return;
    }

    // One Enter: split the block at the caret.
    final rest = splitText(first.right, first.rightMarks, 1);
    final left = first.left;
    final right = rest.right;

    // Enter on an empty list item or quote ends the list.
    if (left.isEmpty &&
        right.isEmpty &&
        (block.kind.isListItem || block.kind == NoteBlockKind.quote)) {
      _convert(block, NoteBlockKind.paragraph, text: '');
      return;
    }
    // "---" and Enter makes a divider.
    if (block.kind == NoteBlockKind.paragraph &&
        left == '---' &&
        right.isEmpty) {
      engine.updateBlock(
        block.id,
        kind: NoteBlockKind.divider,
        text: '',
        marks: const [],
      );
      field?.text.applyRemote('', const []);
      _focus(engine.insertBlock(afterId: block.id).id);
      return;
    }
    engine.updateBlock(block.id, text: left, marks: first.leftMarks);
    field?.text.applyRemote(left, first.leftMarks);
    final created = engine.insertBlock(
      afterId: block.id,
      kind: _nextKind(block.kind),
      text: right,
      marks: rest.rightMarks,
    );
    _focus(created.id, offset: 0);
  }

  NoteBlockKind _nextKind(NoteBlockKind kind) {
    return switch (kind) {
      NoteBlockKind.bullet ||
      NoteBlockKind.numbered ||
      NoteBlockKind.todo ||
      NoteBlockKind.quote => kind,
      _ => NoteBlockKind.paragraph,
    };
  }

  KeyEventResult _onKey(NoteBlock block, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final field = _fields[block.id];
    if (field == null) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (!block.kind.hasText) {
      // A picture or divider is deleted with Backspace/Delete.
      if (!_readOnly &&
          (key == LogicalKeyboardKey.backspace ||
              key == LogicalKeyboardKey.delete)) {
        final blocks = _blocks;
        final at = blocks.indexWhere((other) => other.id == block.id);
        _controller.engine.deleteBlock(block.id);
        final remaining = _blocks;
        if (remaining.isNotEmpty) {
          _focus(remaining[(at - 1).clamp(0, remaining.length - 1)].id);
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final selection = field.text.selection;
    final collapsed = selection.isValid && selection.isCollapsed;
    final blocks = _blocks;
    final index = blocks.indexWhere((other) => other.id == block.id);
    if (key == LogicalKeyboardKey.backspace &&
        collapsed &&
        selection.baseOffset == 0) {
      if (block.kind != NoteBlockKind.paragraph) {
        _convert(block, NoteBlockKind.paragraph);
        return KeyEventResult.handled;
      }
      if (index > 0) {
        _mergeIntoPrevious(blocks, index);
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowUp &&
        collapsed &&
        selection.baseOffset == 0 &&
        index > 0) {
      _focus(blocks[index - 1].id);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown &&
        collapsed &&
        selection.baseOffset == field.text.text.length &&
        index + 1 < blocks.length) {
      _focus(blocks[index + 1].id, offset: 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      field.focus.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _mergeIntoPrevious(List<NoteBlock> blocks, int index) {
    final engine = _controller.engine;
    final current = blocks[index];
    final previous = blocks[index - 1];
    if (!previous.kind.hasText) {
      // A divider or picture before: remove it.
      engine.deleteBlock(previous.id);
      _focus(current.id, offset: 0);
      return;
    }
    final joined = joinText(
      previous.text,
      previous.marks,
      current.text,
      current.marks,
    );
    engine.updateBlock(previous.id, text: joined.text, marks: joined.marks);
    _fields[previous.id]?.text.applyRemote(joined.text, joined.marks);
    engine.deleteBlock(current.id);
    _focus(previous.id, offset: previous.text.length);
  }

  // -------------------------------------------------------------- toolbar --

  void _toggleMark(String type) {
    final field = _focusedField;
    if (field == null || _readOnly) {
      return;
    }
    field.text.toggle(type);
    field.focus.requestFocus();
    setState(() {});
  }

  Future<void> _editLink() async {
    final field = _focusedField;
    if (field == null || _readOnly) {
      return;
    }
    final existing = field.text.linkAtSelection;
    final selection = field.text.selection;
    if (existing == null && (!selection.isValid || selection.isCollapsed)) {
      // Nothing selected to link.
      return;
    }
    final url = await showNoteLinkDialog(
      context,
      initial: existing?.linkUrl ?? '',
    );
    if (url == null || !mounted) {
      return;
    }
    field.text.setLink(url.trim());
    field.focus.requestFocus();
    setState(() {});
  }

  void _setKind(NoteBlockKind kind) {
    final block = _focusedBlock ?? _blocks.firstOrNull;
    if (block == null || _readOnly) {
      return;
    }
    if (kind == NoteBlockKind.divider) {
      _convertToDivider(block);
      return;
    }
    // Choosing the kind it already is turns it back into a paragraph.
    final target = block.kind == kind ? NoteBlockKind.paragraph : kind;
    _convert(block, target);
  }

  void _convertToDivider(NoteBlock block) {
    final engine = _controller.engine;
    if (block.kind == NoteBlockKind.paragraph && block.text.isEmpty) {
      engine.updateBlock(
        block.id,
        kind: NoteBlockKind.divider,
        text: '',
        marks: const [],
      );
      final next = engine.insertBlock(afterId: block.id);
      _focus(next.id);
      return;
    }
    final divider = engine.insertBlock(
      afterId: block.id,
      kind: NoteBlockKind.divider,
    );
    final next = engine.insertBlock(afterId: divider.id);
    _focus(next.id);
  }

  Future<void> _insertImage() async {
    if (_readOnly) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final picked = await ref.read(imagePickerServiceProvider).pickImage();
      if (picked == null || !mounted) {
        return;
      }
      final path = await ref
          .read(notesRepositoryProvider)
          .uploadImage(
            _controller.noteId,
            bytes: picked.bytes,
            fileName: picked.fileName,
            mimeType: picked.mimeType,
          );
      if (!mounted) {
        return;
      }
      final after = _focusedBlock ?? _blocks.lastOrNull;
      final engine = _controller.engine;
      final image = engine.insertBlock(
        afterId: after?.id,
        kind: NoteBlockKind.image,
        props: {'path': path, 'name': picked.fileName},
      );
      // Typing continues under the picture.
      final next = engine.insertBlock(afterId: image.id);
      _focus(next.id);
    } on Object {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not add the picture.'))),
      );
    }
  }

  // ---------------------------------------------------------- block menu --

  void _openBlockMenu(NoteBlock block, {bool slash = false, Rect? anchor}) {
    if (_readOnly) {
      return;
    }
    final field = _fields[block.id];
    final rect = anchor ?? (field == null ? null : _rectOf(field));
    if (rect == null) {
      return;
    }
    final blocks = _blocks;
    final index = blocks.indexWhere((other) => other.id == block.id);
    void turnInto(NoteBlockKind kind) {
      if (slash) {
        _convert(block, kind, text: '');
      } else {
        _convert(block, kind);
      }
    }

    final turn = <(NoteBlockKind, IconData, String)>[
      (NoteBlockKind.paragraph, Icons.notes_rounded, tr('Text')),
      (NoteBlockKind.heading1, Icons.title_rounded, tr('Heading 1')),
      (NoteBlockKind.heading2, Icons.text_fields_rounded, tr('Heading 2')),
      (NoteBlockKind.heading3, Icons.format_size_rounded, tr('Heading 3')),
      (
        NoteBlockKind.bullet,
        Icons.format_list_bulleted_rounded,
        tr('Bulleted list'),
      ),
      (
        NoteBlockKind.numbered,
        Icons.format_list_numbered_rounded,
        tr('Numbered list'),
      ),
      (NoteBlockKind.todo, Icons.check_box_outlined, tr('To-do list')),
      (NoteBlockKind.quote, Icons.format_quote_rounded, tr('Quote')),
      (NoteBlockKind.code, Icons.code_rounded, tr('Code block')),
    ];
    unawaited(
      showGlassMenu(
        context,
        anchor: rect,
        entries: [
          for (final (kind, icon, label) in turn)
            GlassMenuEntry(
              icon: icon,
              label: label,
              onSelected: () => turnInto(kind),
            ),
          GlassMenuEntry(
            icon: Icons.horizontal_rule_rounded,
            label: tr('Divider'),
            onSelected: () {
              if (slash) {
                _controller.engine.updateBlock(
                  block.id,
                  text: '',
                  marks: const [],
                );
                _fields[block.id]?.text.applyRemote('', const []);
              }
              _convertToDivider(block);
            },
          ),
          GlassMenuEntry(
            icon: Icons.image_outlined,
            label: tr('Picture'),
            onSelected: () {
              if (slash) {
                _controller.engine.updateBlock(
                  block.id,
                  text: '',
                  marks: const [],
                );
                _fields[block.id]?.text.applyRemote('', const []);
              }
              unawaited(_insertImage());
            },
          ),
          if (!slash) ...[
            GlassMenuEntry(
              icon: Icons.arrow_upward_rounded,
              label: tr('Move up'),
              onSelected: index > 0
                  ? () => _controller.engine.moveBlock(
                      block.id,
                      index > 1 ? blocks[index - 2].id : null,
                    )
                  : null,
            ),
            GlassMenuEntry(
              icon: Icons.arrow_downward_rounded,
              label: tr('Move down'),
              onSelected: index >= 0 && index + 1 < blocks.length
                  ? () => _controller.engine.moveBlock(
                      block.id,
                      blocks[index + 1].id,
                    )
                  : null,
            ),
            GlassMenuEntry(
              icon: Icons.copy_rounded,
              label: tr('Duplicate'),
              onSelected: () {
                _controller.engine.insertBlock(
                  afterId: block.id,
                  kind: block.kind,
                  text: block.text,
                  marks: block.marks,
                  props: block.props,
                );
              },
            ),
            GlassMenuEntry(
              icon: Icons.delete_outline_rounded,
              label: tr('Delete block'),
              destructive: true,
              onSelected: () {
                _controller.engine.deleteBlock(block.id);
                final remaining = _blocks;
                if (remaining.isNotEmpty) {
                  _focus(
                    remaining[(index - 1).clamp(0, remaining.length - 1)].id,
                  );
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Rect? _rectOf(_BlockField field) {
    final context = field.key.currentContext;
    if (context == null || !context.mounted) {
      return null;
    }
    return globalRectOf(context);
  }

  // -------------------------------------------------------------- mentions --

  void _updateMention(String id, String text) {
    final field = _fields[id];
    if (field == null || widget.members.isEmpty) {
      return;
    }
    final selection = field.text.selection;
    final caret = selection.isValid
        ? selection.extentOffset.clamp(0, text.length)
        : text.length;
    final match = RegExp(
      r'(?:^|\s)@([^\s@]{0,24})$',
    ).firstMatch(text.substring(0, caret));
    if (match == null) {
      if (_mention != null) {
        setState(() => _mention = null);
      }
      return;
    }
    final query = match.group(1)!;
    setState(() {
      _mention = (
        blockId: id,
        start: caret - query.length - 1,
        end: caret,
        query: query.toLowerCase(),
      );
    });
  }

  List<NoteMentionCandidate> _mentionCandidates() {
    final mention = _mention;
    if (mention == null) {
      return const [];
    }
    final result = <NoteMentionCandidate>[];
    for (final member in widget.members) {
      final nickname = member.nickname?.trim();
      final label = nickname == null || nickname.isEmpty
          ? member.profile.displayName
          : nickname;
      if (mention.query.isEmpty ||
          label.toLowerCase().contains(mention.query) ||
          member.profile.username.toLowerCase().contains(mention.query)) {
        result.add((userId: member.profile.id, label: '@$label'));
      }
      if (result.length >= 5) {
        break;
      }
    }
    return result;
  }

  void _pickMention(NoteMentionCandidate candidate) {
    final mention = _mention;
    final field = mention == null ? null : _fields[mention.blockId];
    if (mention == null || field == null) {
      return;
    }
    field.text.insertMention(
      start: mention.start,
      end: mention.end,
      userId: candidate.userId,
      label: candidate.label,
    );
    setState(() => _mention = null);
    field.focus.requestFocus();
  }

  // ---------------------------------------------------------------- build --

  /// Called by the format bar: the kind and marks at the caret.
  bool _markActive(String type) => _focusedField?.text.isActive(type) ?? false;

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null &&
        (uri.scheme == 'http' ||
            uri.scheme == 'https' ||
            uri.scheme == 'mailto')) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = _controller.engine;
    final blocks = engine.blocks;
    final numbers = listNumbers(blocks);
    // Fields of blocks that are gone are disposed after this frame.
    final liveIds = {for (final block in blocks) block.id};
    final gone = [
      for (final id in _fields.keys)
        if (!liveIds.contains(id)) id,
    ];
    if (gone.isNotEmpty) {
      for (final id in gone) {
        _stale.add(_fields.remove(id)!);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final field in _stale) {
          field.dispose();
        }
        _stale.clear();
      });
    }
    final peersByBlock = <String, List<NotePeer>>{};
    for (final peer in _controller.peers) {
      final blockId = peer.blockId;
      if (blockId != null) {
        peersByBlock.putIfAbsent(blockId, () => []).add(peer);
      }
    }
    final readOnly = _readOnly;
    final candidates = _mentionCandidates();
    final focused = _focusedBlock;

    final list = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxContentWidth),
        child: ListView.builder(
          controller: _scroll,
          padding: widget.padding,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: blocks.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return widget.header ?? const SizedBox.shrink();
            }
            final block = blocks[index - 1];
            final field = _fieldFor(block);
            return NoteBlockRow(
              key: ValueKey('note-block-${block.id}'),
              block: block,
              rowKey: field.key,
              text: field.text,
              focusNode: field.focus,
              number: numbers[index - 1],
              readOnly: readOnly,
              peers: peersByBlock[block.id] ?? const [],
              onKeyEvent: (event) => _onKey(block, event),
              onToggleChecked: readOnly
                  ? null
                  : () => engine.updateBlock(
                      block.id,
                      props: {...block.props, 'checked': !block.checked},
                    ),
              onMenu: readOnly
                  ? null
                  : (rect) => _openBlockMenu(block, anchor: rect),
              onOpenLink: _openLink,
              onTapBlock: block.kind.hasText ? null : () => _focus(block.id),
              onLastBlockTap: index == blocks.length
                  ? () {
                      // Tapping under the last block puts the caret in it,
                      // or adds a paragraph after a picture or divider.
                      if (block.kind.hasText) {
                        _focus(block.id);
                      } else if (!readOnly) {
                        final created = engine.insertBlock(afterId: block.id);
                        _focus(created.id);
                      }
                    }
                  : null,
            );
          },
        ),
      ),
    );

    final bar = readOnly
        ? null
        : NoteFormatBar(
            kind: focused?.kind,
            isActive: _markActive,
            onToggleMark: _toggleMark,
            onLink: _editLink,
            onKind: _setKind,
            onImage: _insertImage,
            onMention: () {
              final field = _focusedField;
              if (field == null) {
                return;
              }
              final selection = field.text.selection;
              final at = selection.isValid
                  ? selection.extentOffset
                  : field.text.text.length;
              final text = field.text.text;
              final needsSpace =
                  at > 0 && !RegExp(r'\s').hasMatch(text[at - 1]);
              field.text.value = field.text.value.copyWith(
                text: text.replaceRange(at, at, needsSpace ? ' @' : '@'),
                selection: TextSelection.collapsed(
                  offset: at + (needsSpace ? 2 : 1),
                ),
              );
              field.focus.requestFocus();
            },
            onMore: () {
              final block = focused ?? _blocks.firstOrNull;
              if (block != null) {
                _openBlockMenu(block);
              }
            },
          );

    final apple =
        Theme.of(context).platform == TargetPlatform.macOS ||
        Theme.of(context).platform == TargetPlatform.iOS;
    SingleActivator command(LogicalKeyboardKey key, {bool shift = false}) =>
        SingleActivator(key, meta: apple, control: !apple, shift: shift);

    return CallbackShortcuts(
      bindings: readOnly
          ? const {}
          : {
              command(LogicalKeyboardKey.keyB): () =>
                  _toggleMark(NoteMark.bold),
              command(LogicalKeyboardKey.keyI): () =>
                  _toggleMark(NoteMark.italic),
              command(LogicalKeyboardKey.keyE): () =>
                  _toggleMark(NoteMark.code),
              command(LogicalKeyboardKey.keyX, shift: true): () =>
                  _toggleMark(NoteMark.strike),
              command(LogicalKeyboardKey.keyK): () => unawaited(_editLink()),
            },
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(child: list),
              ?bar,
            ],
          ),
          if (candidates.isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              bottom: bar == null ? 12 : 64,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: NoteMentionTray(
                  candidates: candidates,
                  onPick: _pickMention,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
