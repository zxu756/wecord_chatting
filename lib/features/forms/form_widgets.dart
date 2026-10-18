import 'package:flutter/material.dart';
import 'package:wecord/features/forms/form_models.dart';
import 'package:wecord/features/later/later_time.dart' show describeWhen;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The deadline in words: "Closes Today 8:00 PM", or "Closed".
String formStatusText(BuildContext context, FormSnapshot form, DateTime now) {
  if (form.isClosed(now)) {
    return tr('Closed');
  }
  final deadline = form.settings.deadline;
  if (deadline == null) {
    return trIn('Form', 'Open');
  }
  return tr('Closes {when}', {
    'when': describeWhen(
      MaterialLocalizations.of(context),
      deadline.toLocal(),
      now,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    ),
  });
}

/// "12 submitted", "12/30 submitted".
String formCountText(FormSnapshot form) {
  final max = form.settings.maxResponses;
  if (max == null) {
    return tr('{count} submitted', {'count': form.responseCount});
  }
  return tr('{count}/{max} submitted', {
    'count': form.responseCount,
    'max': max,
  });
}

/// The small squircle with the form icon at the start of a form card.
class FormIconTile extends StatelessWidget {
  const FormIconTile({this.size = 32, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SettingsIconTile(
        icon: Icons.assignment_outlined,
        tone: SettingsTone.accent,
        size: size,
      ),
    );
  }
}

/// "Open", "Closes tomorrow 9 am", "Closed" or "Anonymous" as a small pill.
class FormPill extends StatelessWidget {
  const FormPill({
    required this.text,
    this.closed = false,
    this.icon,
    super.key,
  });

  final String text;
  final bool closed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final foreground = closed ? c.muted : c.accentText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: closed ? c.raised : c.accentSoft,
        borderRadius: BorderRadius.circular(WeCordRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (closed || icon != null) ...[
            Icon(
              icon ?? Icons.lock_outline_rounded,
              size: 12,
              color: foreground,
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A thin bar with [fraction] of it filled, in the accent color on the
/// track color. Used for the progress on a card and the bars of a chart.
class FormBar extends StatelessWidget {
  const FormBar({required this.fraction, this.height = 8, super.key});

  final double fraction;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Container(
          height: height,
          color: c.track,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fraction.clamp(0.0, 1.0),
            child: Container(color: c.accent),
          ),
        ),
      ),
    );
  }
}

/// A full page for the form screens: a header with a back button, the
/// title and some actions, over [child]. On wide screens the page is a
/// centred panel.
class FormPageFrame extends StatelessWidget {
  const FormPageFrame({
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.pageKey,
    this.maxWidth = 720,
    this.bottom,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  final Key? pageKey;
  final double maxWidth;

  /// A bar under the content (the submit button).
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final wide = isWideLayout(MediaQuery.sizeOf(context).width);
    final page = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.lineSoft)),
          ),
          child: Row(
            children: [
              WeCordIconButton(
                key: const ValueKey('form-back'),
                tooltip: tr('Back'),
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 19,
                variant: WeCordButtonVariant.ghost,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: c.ink,
                        ),
                      ),
                      if (subtitle case final subtitle?)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: c.muted),
                        ),
                    ],
                  ),
                ),
              ),
              ...actions,
            ],
          ),
        ),
        Expanded(child: child),
        if (bottom case final bottom?)
          Container(
            decoration: BoxDecoration(
              color: c.panel,
              border: Border(top: BorderSide(color: c.lineSoft)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  10 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: bottom,
              ),
            ),
          ),
      ],
    );
    return Scaffold(
      key: pageKey,
      backgroundColor: wide ? c.paper : c.panel,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: false,
        child: wide
            ? Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Container(
                    margin: const EdgeInsets.only(top: 24),
                    decoration: BoxDecoration(
                      color: c.panel,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(WeCordRadii.xxl),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: page,
                  ),
                ),
              )
            : page,
      ),
    );
  }
}

/// A short message in the middle of a page, with an optional button.
class FormNote extends StatelessWidget {
  const FormNote({
    required this.icon,
    required this.text,
    this.action,
    super.key,
  });

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: c.faint),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: c.muted),
            ),
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}

/// The icon for each kind of question.
IconData formFieldIcon(FormFieldType type) => switch (type) {
  FormFieldType.shortText => Icons.short_text_rounded,
  FormFieldType.longText => Icons.notes_rounded,
  FormFieldType.number => Icons.pin_outlined,
  FormFieldType.singleChoice => Icons.radio_button_checked_rounded,
  FormFieldType.multipleChoice => Icons.check_box_outlined,
  FormFieldType.date => Icons.event_outlined,
  FormFieldType.image => Icons.image_outlined,
  FormFieldType.member => Icons.person_outline_rounded,
};

/// The name of each kind of question.
String formFieldTypeName(FormFieldType type) => switch (type) {
  FormFieldType.shortText => tr('Short text'),
  FormFieldType.longText => tr('Long text'),
  FormFieldType.number => tr('Number'),
  FormFieldType.singleChoice => tr('Single choice'),
  FormFieldType.multipleChoice => tr('Multiple choice'),
  FormFieldType.date => tr('Date'),
  FormFieldType.image => tr('Picture'),
  FormFieldType.member => tr('Member'),
};
