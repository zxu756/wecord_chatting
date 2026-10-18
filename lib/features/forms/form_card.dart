import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/forms/form_fill_page.dart';
import 'package:wecord/features/forms/form_models.dart';
import 'package:wecord/features/forms/form_repository.dart';
import 'package:wecord/features/forms/form_results_page.dart';
import 'package:wecord/features/forms/form_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A form in a chat, in the "well" style of chains and polls: the title, how
/// many people answered, the deadline and a "Fill in" button. It follows the
/// form live (no message per answer); tapping it opens the fill-in page, or
/// the results when there is nothing left to fill in.
class FormCardView extends ConsumerWidget {
  const FormCardView({required this.card, super.key});

  final FormCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final async = ref.watch(formProvider(card.formId));
    final form = async.value;
    final title = form?.title.isNotEmpty == true ? form!.title : card.title;
    final now = DateTime.now();

    void open() {
      if (form == null) {
        return;
      }
      if (!form.canFill(now) && form.canViewResults && !form.hasAnswered) {
        unawaited(openFormResults(context, formId: card.formId));
      } else {
        unawaited(openFormFill(context, formId: card.formId));
      }
    }

    Widget body() {
      if (form == null) {
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: async.hasError
              ? WeCordPressable(
                  onPressed: () => ref.invalidate(formProvider(card.formId)),
                  semanticLabel: tr('Try again'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(WeCordRadii.sm),
                  ),
                  builder: (context, states) => Text(
                    tr("Couldn't load this form. Tap to try again."),
                    style: TextStyle(fontSize: 13.5, color: c.muted),
                  ),
                )
              : Text(
                  tr('Loading…'),
                  style: TextStyle(fontSize: 13.5, color: c.muted),
                ),
        );
      }
      final closed = form.isClosed(now);
      final max = form.settings.maxResponses;
      final canFill = form.canFill(now);
      Widget action;
      if (closed) {
        action = const SizedBox.shrink();
      } else if (form.hasAnswered && !canFill) {
        action = Text(
          tr('Submitted'),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: c.successText,
          ),
        );
      } else if (!canFill) {
        action = Text(
          tr('Full'),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: c.muted,
          ),
        );
      } else if (form.hasAnswered) {
        action = WeCordButton(
          key: ValueKey('form-edit-${card.formId}'),
          label: tr('Edit my answers'),
          variant: WeCordButtonVariant.secondary,
          size: WeCordButtonSize.small,
          onPressed: () =>
              unawaited(openFormFill(context, formId: card.formId)),
        );
      } else {
        action = WeCordButton(
          key: ValueKey('form-fill-${card.formId}'),
          label: tr('Fill in'),
          variant: WeCordButtonVariant.accent,
          size: WeCordButtonSize.small,
          onPressed: () =>
              unawaited(openFormFill(context, formId: card.formId)),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (form.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                form.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, height: 1.35, color: c.muted),
              ),
            ),
          const SizedBox(height: 10),
          if (max != null) ...[
            FormBar(fraction: max == 0 ? 0 : form.responseCount / max),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  '${formCountText(form)} · ${tr('{count} questions', {'count': form.fields.length})}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: c.muted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (form.canViewResults) ...[
                WeCordButton(
                  key: ValueKey('form-results-${card.formId}'),
                  label: tr('Results'),
                  variant: WeCordButtonVariant.ghost,
                  size: WeCordButtonSize.small,
                  onPressed: () =>
                      unawaited(openFormResults(context, formId: card.formId)),
                ),
                const SizedBox(width: 4),
              ],
              action,
            ],
          ),
        ],
      );
    }

    final status = form == null ? null : formStatusText(context, form, now);
    final closed = form?.isClosed(now) ?? false;
    final summary = form == null
        ? title
        : '$title, ${formCountText(form)}, $status';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380, minWidth: 240),
      child: WeCordPressable(
        key: ValueKey('form-card-${card.formId}'),
        onPressed: form == null ? null : open,
        semanticLabel: tr('Form: {summary}', {'summary': summary}),
        hint: tr('Opens the form'),
        mergeSemantics: false,
        pressedScale: 0.99,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        builder: (context, states) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.well,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
            border: Border.all(
              color: states.contains(WidgetState.hovered) ? c.line : c.lineSoft,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FormIconTile(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Form'),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: c.subtle,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.25,
                            fontWeight: FontWeight.w800,
                            color: c.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      FormPill(text: status, closed: closed),
                      if (form!.settings.anonymous)
                        FormPill(
                          text: tr('Anonymous'),
                          icon: Icons.visibility_off_outlined,
                        ),
                    ],
                  ),
                ),
              body(),
            ],
          ),
        ),
      ),
    );
  }
}
