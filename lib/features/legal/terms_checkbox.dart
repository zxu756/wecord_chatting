import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:wecord/features/legal/legal_document.dart';
import 'package:wecord/features/legal/legal_screen.dart';
import 'package:wecord/features/legal/minimum_age.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "I am at least 13 and agree to the Terms of Service and Community
/// Guidelines." with a box to tick and the two documents as links. Used at
/// sign-up and in the prompt for existing accounts.
///
/// The sentence is one translation with the two links in square brackets
/// (`[Terms of Service]`), so each language keeps its own word order.
class TermsAgreementCheckbox extends StatefulWidget {
  const TermsAgreementCheckbox({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;

  /// Null while the form is busy.
  final ValueChanged<bool>? onChanged;

  @override
  State<TermsAgreementCheckbox> createState() => _TermsAgreementCheckboxState();
}

class _TermsAgreementCheckboxState extends State<TermsAgreementCheckbox> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  List<InlineSpan> _sentence(BuildContext context, TextStyle base) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    final c = context.tokens.colors;
    final text = tr(
      'I am at least {age} and agree to the [Terms of Service] and the '
      '[Community Guidelines].',
      {'age': minimumAge},
    );
    const documents = [LegalDocument.terms, LegalDocument.guidelines];
    final spans = <InlineSpan>[];
    var linkIndex = 0;
    var cursor = 0;
    for (final match in RegExp(r'\[([^\]]+)\]').allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final document = documents[linkIndex.clamp(0, documents.length - 1)];
      final recognizer = TapGestureRecognizer()
        ..onTap = () => openLegalDocument(context, document);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: match.group(1),
          recognizer: recognizer,
          style: base.copyWith(
            color: c.accentText,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
            decorationColor: c.accentText,
          ),
        ),
      );
      linkIndex += 1;
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final base = TextStyle(fontSize: 14, height: 1.4, color: c.ink);
    final enabled = widget.onChanged != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WeCordPressable(
          key: const ValueKey('terms-checkbox'),
          toggled: widget.value,
          semanticLabel: tr('Agree to the terms'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          pressedScale: 1,
          onPressed: enabled
              ? () {
                  WeCordHaptics.selection();
                  widget.onChanged!(!widget.value);
                }
              : null,
          builder: (context, states) {
            return Padding(
              padding: const EdgeInsets.all(2),
              child: AnimatedContainer(
                duration: WeCordMotion.quick,
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: widget.value ? c.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: widget.value ? c.accent : c.muted,
                    width: 1.6,
                  ),
                ),
                child: widget.value
                    ? const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: Colors.white,
                      )
                    : null,
              ),
            );
          },
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text.rich(
              TextSpan(style: base, children: _sentence(context, base)),
            ),
          ),
        ),
      ],
    );
  }
}
