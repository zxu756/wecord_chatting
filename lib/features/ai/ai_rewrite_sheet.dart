import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The longest draft AI will rewrite, as the server limits it.
const aiMaxDraftLength = 8000;

/// Opens the rewrite sheet for [draft]: pick what to do, preview the
/// result, then replace the draft, add the result below it, or cancel.
/// Nothing is sent from here.
Future<void> showAiRewriteSheet(
  BuildContext context, {
  required String draft,
  required ValueChanged<String> onReplace,
  required ValueChanged<String> onInsertBelow,
  String? conversationId,
  VoidCallback? onHelpReply,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Rewrite with AI'),
    builder: (context, _) => AiRewriteSheet(
      draft: draft,
      conversationId: conversationId,
      onReplace: onReplace,
      onInsertBelow: onInsertBelow,
      onHelpReply: onHelpReply,
    ),
  );
}

enum _Stage { pick, pickLanguage, working, result, error }

class AiRewriteSheet extends ConsumerStatefulWidget {
  const AiRewriteSheet({
    required this.draft,
    required this.onReplace,
    required this.onInsertBelow,
    this.conversationId,
    this.onHelpReply,
    super.key,
  });

  final String draft;
  final String? conversationId;
  final ValueChanged<String> onReplace;
  final ValueChanged<String> onInsertBelow;

  /// Opens "Help me reply" (F6) in place of this sheet; null where there is
  /// nothing to reply to (the note to self).
  final VoidCallback? onHelpReply;

  @override
  ConsumerState<AiRewriteSheet> createState() => _AiRewriteSheetState();
}

class _AiRewriteSheetState extends ConsumerState<AiRewriteSheet> {
  var _stage = _Stage.pick;
  String _result = '';
  Object? _error;
  AiRewriteMode? _mode;
  AiLanguage? _target;
  var _generation = 0;

  String get _text => widget.draft.trim();

  Future<void> _run(AiRewriteMode mode, {AiLanguage? target}) async {
    final generation = ++_generation;
    setState(() {
      _mode = mode;
      _target = target;
      _stage = _Stage.working;
      _error = null;
    });
    try {
      final result = await ref
          .read(aiRepositoryProvider)
          .rewrite(
            mode: mode,
            text: _text,
            target: target,
            conversationId: widget.conversationId,
          );
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _result = result;
        _stage = _Stage.result;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      if (error is AiNotConfiguredException) {
        ref.invalidate(aiStatusProvider);
      }
      setState(() {
        _error = error;
        _stage = _Stage.error;
      });
    }
  }

  void _finish(ValueChanged<String> apply) {
    final result = _result;
    Navigator.of(context).pop();
    apply(result);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;
    final text = _text;

    Widget draftBox(String label, String body, {bool selectable = false}) {
      final style = TextStyle(fontSize: 14.5, height: 1.4, color: c.ink);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.subtle,
              ),
            ),
          ),
          Container(
            constraints: BoxConstraints(maxHeight: maxHeight * 0.3),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: c.well,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: selectable
                    ? SelectableText(body, style: style)
                    : Text(body, style: style),
              ),
            ),
          ),
        ],
      );
    }

    // "Help me reply" (F6): replies to the chat instead of polishing a draft.
    final helpReply = widget.onHelpReply == null
        ? null
        : SettingsGroup(
            children: [
              SettingsRow(
                key: const ValueKey('ai-rewrite-help-reply'),
                icon: Icons.reply_all_rounded,
                title: tr('Help me reply'),
                onTap: () {
                  final open = widget.onHelpReply!;
                  Navigator.of(context).pop();
                  open();
                },
              ),
            ],
          );

    final Widget content;
    if (text.isEmpty) {
      final note = _Note(
        key: const ValueKey('ai-rewrite-empty'),
        text: tr('Write a message first, then use AI to polish it.'),
      );
      content = helpReply == null
          ? note
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [helpReply, const SizedBox(height: 14), note],
            );
    } else if (text.length > aiMaxDraftLength) {
      content = _Note(
        key: const ValueKey('ai-rewrite-too-long'),
        text: tr('This message is too long for AI to rewrite.'),
      );
    } else {
      switch (_stage) {
        case _Stage.pick:
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              draftBox(tr('Your message'), text),
              const SizedBox(height: 14),
              if (helpReply != null) ...[helpReply, const SizedBox(height: 14)],
              SettingsGroup(
                children: [
                  for (final (mode, icon) in const [
                    (AiRewriteMode.fix, Icons.spellcheck_rounded),
                    (AiRewriteMode.shorter, Icons.short_text_rounded),
                    (AiRewriteMode.polite, Icons.sentiment_satisfied_rounded),
                    (AiRewriteMode.formal, Icons.business_center_outlined),
                  ])
                    SettingsRow(
                      key: ValueKey('ai-rewrite-${mode.code}'),
                      icon: icon,
                      title: mode.label,
                      onTap: () => unawaited(_run(mode)),
                    ),
                  SettingsRow(
                    key: const ValueKey('ai-rewrite-translate'),
                    icon: Icons.translate_rounded,
                    title: AiRewriteMode.translate.label,
                    onTap: () => setState(() => _stage = _Stage.pickLanguage),
                  ),
                ],
              ),
            ],
          );
        case _Stage.pickLanguage:
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsGroup(
                header: tr('Translate to…'),
                children: [
                  for (final language in AiLanguage.values)
                    SettingsRow(
                      key: ValueKey('ai-rewrite-language-${language.code}'),
                      title: language.label,
                      onTap: () => unawaited(
                        _run(AiRewriteMode.translate, target: language),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: WeCordButton(
                  label: tr('Back'),
                  variant: WeCordButtonVariant.ghost,
                  onPressed: () => setState(() => _stage = _Stage.pick),
                ),
              ),
            ],
          );
        case _Stage.working:
          content = Semantics(
            liveRegion: true,
            label: tr('Working on it…'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: c.muted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    tr('Working on it…'),
                    style: TextStyle(fontSize: 14, color: c.muted),
                  ),
                ],
              ),
            ),
          );
        case _Stage.result:
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              draftBox(tr('Your message'), text),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: KeyedSubtree(
                  key: const ValueKey('ai-rewrite-result'),
                  child: draftBox(tr('Suggestion'), _result, selectable: true),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  tr('Written by AI. Nothing is sent until you send it.'),
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  WeCordButton(
                    key: const ValueKey('ai-rewrite-replace'),
                    label: tr('Replace'),
                    variant: WeCordButtonVariant.accent,
                    onPressed: () => _finish(widget.onReplace),
                  ),
                  WeCordButton(
                    key: const ValueKey('ai-rewrite-insert'),
                    label: tr('Insert below'),
                    variant: WeCordButtonVariant.secondary,
                    onPressed: () => _finish(widget.onInsertBelow),
                  ),
                  WeCordButton(
                    key: const ValueKey('ai-rewrite-cancel'),
                    label: tr('Cancel'),
                    variant: WeCordButtonVariant.ghost,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          );
        case _Stage.error:
          final error = _error ?? const AiFailedException();
          final canRetry =
              error is! AiNotConfiguredException &&
              error is! AiLimitReachedException &&
              error is! AiDisabledInCircleException;
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Note(
                key: const ValueKey('ai-rewrite-error'),
                text: aiErrorMessage(error),
                isError: true,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canRetry && _mode != null)
                    WeCordButton(
                      key: const ValueKey('ai-rewrite-retry'),
                      label: tr('Try again'),
                      variant: WeCordButtonVariant.accent,
                      onPressed: () => unawaited(_run(_mode!, target: _target)),
                    ),
                  WeCordButton(
                    label: tr('Cancel'),
                    variant: WeCordButtonVariant.ghost,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          );
      }
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: content,
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.isError = false, super.key});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isError ? c.dangerSoft : c.well,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: isError ? c.dangerText : c.muted,
          ),
        ),
      ),
    );
  }
}
