import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/note_assist/note_assist_models.dart';
import 'package:wecord/features/ai/note_assist/note_assist_repository.dart';
import 'package:wecord/features/notes/note_editor_extras.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What the person chose to do with an AI answer.
class NoteAssistApply {
  const NoteAssistApply({required this.result, required this.replace});

  final NoteAssistResult result;

  /// True: put the answer in place of the selected words. False: add it as
  /// blocks under the text.
  final bool replace;
}

/// Opens the AI for a note: pick what to do, read the answer, then put it in
/// the note (under the text, or in place of the selected words). Resolves to
/// what the person chose, or null when they closed it. The answer is a
/// suggestion; nothing changes in the note until it is chosen.
Future<NoteAssistApply?> showNoteAssistSheet(
  BuildContext context, {
  required String noteId,
  required NoteAssistTarget target,
}) {
  return showWeCordSheet<NoteAssistApply>(
    context,
    title: tr('Ask the AI'),
    detents: const [0.6, 0.92],
    initialDetent: 0.75,
    builder: (context, scrollController) => NoteAssistSheet(
      noteId: noteId,
      target: target,
      scrollController: scrollController,
    ),
  );
}

enum _Stage { choose, tone, language, working, answer, failed }

class NoteAssistSheet extends ConsumerStatefulWidget {
  const NoteAssistSheet({
    required this.noteId,
    required this.target,
    this.scrollController,
    super.key,
  });

  final String noteId;
  final NoteAssistTarget target;
  final ScrollController? scrollController;

  @override
  ConsumerState<NoteAssistSheet> createState() => _NoteAssistSheetState();
}

class _NoteAssistSheetState extends ConsumerState<NoteAssistSheet> {
  var _stage = _Stage.choose;
  NoteAssistMode? _mode;
  NoteAssistTone? _tone;
  AiLanguage? _target;
  NoteAssistResult? _result;
  Object? _error;

  Future<void> _run() async {
    final mode = _mode;
    if (mode == null) {
      return;
    }
    setState(() {
      _stage = _Stage.working;
      _error = null;
    });
    try {
      final result = await ref
          .read(noteAssistRepositoryProvider)
          .assist(
            noteId: widget.noteId,
            mode: mode,
            text: widget.target.hasSelection
                ? widget.target.selectedText
                : null,
            tone: _tone,
            target: _target,
          );
      if (mounted) {
        setState(() {
          _result = result;
          _stage = _Stage.answer;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _stage = _Stage.failed;
        });
      }
    }
  }

  void _pick(NoteAssistMode mode) {
    _mode = mode;
    switch (mode) {
      case NoteAssistMode.tone:
        setState(() => _stage = _Stage.tone);
      case NoteAssistMode.translate:
        setState(() => _stage = _Stage.language);
      default:
        unawaited(_run());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final body = switch (_stage) {
      _Stage.choose => _chooser(context),
      _Stage.tone => _options<NoteAssistTone>(
        context,
        title: tr('Change the tone'),
        values: NoteAssistTone.values,
        label: (tone) => tone.label,
        keyFor: (tone) => 'assist-tone-${tone.code}',
        onPick: (tone) {
          _tone = tone;
          unawaited(_run());
        },
      ),
      _Stage.language => _options<AiLanguage>(
        context,
        title: tr('Translate into'),
        values: AiLanguage.values,
        label: (language) => language.label,
        keyFor: (language) => 'assist-language-${language.code}',
        onPick: (language) {
          _target = language;
          unawaited(_run());
        },
      ),
      _Stage.working => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          key: const ValueKey('assist-working'),
          children: [
            const SizedBox.square(
              dimension: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 14),
            Semantics(
              liveRegion: true,
              child: Text(
                tr('Thinking…'),
                style: TextStyle(fontSize: 14.5, color: c.muted),
              ),
            ),
          ],
        ),
      ),
      _Stage.failed => _failed(context),
      _Stage.answer => _answer(context),
    };
    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: [body],
    );
  }

  Widget _scopeLine(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        widget.target.hasSelection
            ? tr('On the words you selected')
            : tr('On the whole note'),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: c.subtle,
        ),
      ),
    );
  }

  Widget _chooser(BuildContext context) {
    final c = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _scopeLine(context),
        for (final mode in NoteAssistMode.values)
          WeCordPressable(
            key: ValueKey('assist-mode-${mode.code}'),
            onPressed: () => _pick(mode),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            pressedScale: 0.99,
            builder: (context, states) => Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: states.contains(WidgetState.hovered)
                    ? c.raised
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.accentSoft,
                      borderRadius: BorderRadius.circular(WeCordRadii.md),
                    ),
                    child: Icon(mode.icon, size: 21, color: c.accentText),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mode.label,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                        Text(
                          mode.hint,
                          style: TextStyle(fontSize: 13, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          tr(
            'The AI reads only this note. What it writes is a suggestion: '
            'nothing changes until you add it.',
          ),
          style: TextStyle(fontSize: 12.5, height: 1.4, color: c.subtle),
        ),
      ],
    );
  }

  Widget _options<T>(
    BuildContext context, {
    required String title,
    required List<T> values,
    required String Function(T value) label,
    required String Function(T value) keyFor,
    required void Function(T value) onPick,
  }) {
    final c = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            WeCordIconButton(
              icon: Icons.chevron_left_rounded,
              iconSize: 24,
              tooltip: tr('Back'),
              variant: WeCordButtonVariant.ghost,
              onPressed: () => setState(() => _stage = _Stage.choose),
            ),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
            ),
          ],
        ),
        for (final value in values)
          WeCordPressable(
            key: ValueKey(keyFor(value)),
            onPressed: () => onPick(value),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            pressedScale: 0.99,
            builder: (context, states) => Container(
              constraints: const BoxConstraints(minHeight: 52),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: states.contains(WidgetState.hovered)
                    ? c.raised
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
              ),
              child: Text(
                label(value),
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _failed(BuildContext context) {
    final c = context.tokens.colors;
    final error = _error!;
    final noRetry =
        error is AiNotConfiguredException ||
        error is AiDisabledInCircleException ||
        error is AiTurnedOffException ||
        error is AiLimitReachedException;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        key: const ValueKey('assist-error'),
        children: [
          Icon(Icons.error_outline_rounded, size: 30, color: c.subtle),
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              aiErrorMessage(error),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, height: 1.4, color: c.muted),
            ),
          ),
          const SizedBox(height: 16),
          if (!noRetry)
            WeCordButton(
              label: tr('Try again'),
              variant: WeCordButtonVariant.secondary,
              onPressed: () => unawaited(_run()),
            ),
          const SizedBox(height: 8),
          WeCordButton(
            label: tr('Back'),
            variant: WeCordButtonVariant.ghost,
            onPressed: () => setState(() => _stage = _Stage.choose),
          ),
        ],
      ),
    );
  }

  Widget _answer(BuildContext context) {
    final c = context.tokens.colors;
    final result = _result!;
    final mode = _mode!;
    if (result.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          key: const ValueKey('assist-empty'),
          children: [
            Icon(Icons.auto_awesome_rounded, size: 30, color: c.subtle),
            const SizedBox(height: 12),
            Text(
              mode == NoteAssistMode.extractTasks
                  ? tr('No to-dos found.')
                  : tr('There is nothing in the note to work on yet.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, color: c.muted),
            ),
            const SizedBox(height: 16),
            WeCordButton(
              label: tr('Back'),
              variant: WeCordButtonVariant.secondary,
              onPressed: () => setState(() => _stage = _Stage.choose),
            ),
          ],
        ),
      );
    }
    final canReplace =
        widget.target.hasSelection &&
        widget.target.blockId != null &&
        mode.canReplaceSelection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('assist-result'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.raised,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final block in result.blocks)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: _AnswerLine(block: block),
                ),
            ],
          ),
        ),
        if (result.truncated)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              tr('The note is long, so the AI read only part of it.'),
              style: TextStyle(fontSize: 12.5, color: c.subtle),
            ),
          ),
        const SizedBox(height: 14),
        if (canReplace) ...[
          WeCordButton(
            key: const ValueKey('assist-replace'),
            label: tr('Replace the selection'),
            expand: true,
            onPressed: () => Navigator.of(
              context,
            ).pop(NoteAssistApply(result: result, replace: true)),
          ),
          const SizedBox(height: 8),
        ],
        WeCordButton(
          key: const ValueKey('assist-insert'),
          label: tr('Add below'),
          expand: true,
          variant: canReplace
              ? WeCordButtonVariant.secondary
              : WeCordButtonVariant.primary,
          onPressed: () => Navigator.of(
            context,
          ).pop(NoteAssistApply(result: result, replace: false)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: WeCordButton(
                label: tr('Try again'),
                variant: WeCordButtonVariant.ghost,
                size: WeCordButtonSize.small,
                onPressed: () => unawaited(_run()),
              ),
            ),
            Expanded(
              child: WeCordButton(
                label: tr('Back'),
                variant: WeCordButtonVariant.ghost,
                size: WeCordButtonSize.small,
                onPressed: () => setState(() => _stage = _Stage.choose),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AnswerLine extends StatelessWidget {
  const _AnswerLine({required this.block});

  final NoteAssistBlock block;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final heading = block.kind.isHeading;
    final marker = switch (block.kind.value) {
      'bullet' || 'numbered' => '• ',
      'todo' => block.checked ? '☑ ' : '☐ ',
      'quote' => '❝ ',
      _ => '',
    };
    return Text(
      '$marker${block.text}',
      style: TextStyle(
        fontSize: heading ? 16 : 14.5,
        height: 1.45,
        fontWeight: heading ? FontWeight.w800 : FontWeight.w500,
        color: c.ink,
      ),
    );
  }
}
