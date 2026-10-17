import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wecord/features/photo_editor/editor_session.dart';
import 'package:wecord/features/photo_editor/editor_toolbars.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The box where the text of a text overlay is typed, over the dimmed
/// editor: a field, the colors, the pill switch and Done. The text shows on
/// the picture as it is typed.
class EditorTextEntry extends StatefulWidget {
  const EditorTextEntry({required this.session, super.key});

  final EditorSession session;

  @override
  State<EditorTextEntry> createState() => _EditorTextEntryState();
}

class _EditorTextEntryState extends State<EditorTextEntry> {
  late final TextEditingController _text = TextEditingController(
    text: widget.session.draftText?.text ?? '',
  );
  final _focus = FocusNode(debugLabel: 'photo-editor-text-entry');

  EditorSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed({String? text, int? color, bool? pill}) {
    final draft = _s.draftText;
    if (draft != null) {
      _s.updateDraft(draft.copyWith(text: text, color: color, pill: pill));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final draft = _s.draftText;
    if (draft == null) {
      return const SizedBox.shrink();
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _s.finishTextEntry(keep: false),
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
            _s.finishTextEntry(keep: true),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            _s.finishTextEntry(keep: true),
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('photo-editor-text-scrim'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _s.finishTextEntry(keep: true),
              child: ColoredBox(color: c.scrim),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 8,
            child: SafeArea(
              bottom: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: WeCordGlass(
                    key: const ValueKey('photo-editor-text-entry'),
                    borderRadius: BorderRadius.circular(WeCordRadii.xl),
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 44,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                alignment: Alignment.centerLeft,
                                decoration: BoxDecoration(
                                  color: c.raised,
                                  borderRadius: BorderRadius.circular(
                                    WeCordRadii.lg,
                                  ),
                                ),
                                child: TextField(
                                  key: const ValueKey(
                                    'photo-editor-text-field',
                                  ),
                                  controller: _text,
                                  focusNode: _focus,
                                  autofocus: true,
                                  minLines: 1,
                                  maxLines: 4,
                                  textInputAction: TextInputAction.newline,
                                  onChanged: (value) => _changed(text: value),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: c.ink,
                                  ),
                                  decoration: InputDecoration(
                                    isCollapsed: true,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    filled: false,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    hintText: tr('Type something…'),
                                    hintStyle: TextStyle(color: c.subtle),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            WeCordButton(
                              key: const ValueKey('photo-editor-text-done'),
                              label: tr('Done'),
                              variant: WeCordButtonVariant.accent,
                              onPressed: () => _s.finishTextEntry(keep: true),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: EditorColorRow(
                                compact: true,
                                keyPrefix: 'photo-editor-entry-color',
                                selected: draft.color,
                                onSelected: (color) => _changed(color: color),
                              ),
                            ),
                            EditorOptionButton(
                              key: const ValueKey('photo-editor-entry-pill'),
                              icon: Icons.rounded_corner_rounded,
                              label: tr('Background'),
                              selected: draft.pill,
                              onPressed: () => _changed(pill: !draft.pill),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
