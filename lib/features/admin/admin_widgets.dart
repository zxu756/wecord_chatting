import 'package:flutter/material.dart';
import 'package:wecord/features/admin/admin_models.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The icon of a kind of report.
IconData adminKindIcon(ReportKind kind) => switch (kind) {
  ReportKind.user => Icons.person_outline_rounded,
  ReportKind.circle => Icons.blur_circular_rounded,
  ReportKind.post => Icons.article_outlined,
  ReportKind.message => Icons.chat_bubble_outline_rounded,
};

SettingsTone adminKindTone(ReportKind kind) => switch (kind) {
  ReportKind.user => SettingsTone.accent,
  ReportKind.circle => SettingsTone.success,
  ReportKind.post => SettingsTone.warning,
  ReportKind.message => SettingsTone.neutral,
};

/// A small rounded state label ("Open", "Suspended until 3 Nov").
class AdminStateTag extends StatelessWidget {
  const AdminStateTag({
    required this.label,
    this.tone = SettingsTone.neutral,
    super.key,
  });

  final String label;
  final SettingsTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final (fill, foreground) = switch (tone) {
      SettingsTone.neutral => (c.raised, c.muted),
      SettingsTone.accent => (c.accentSoft, c.accentText),
      SettingsTone.success => (c.successSoft, c.successText),
      SettingsTone.warning => (c.warningSoft, c.warningText),
      SettingsTone.danger => (c.dangerSoft, c.dangerText),
    };
    return CircleTag(label: label, background: fill, foreground: foreground);
  }
}

/// The date an admin reads on a card: "2026-10-21 14:30" in local time.
String adminDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String adminDate(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

/// A titled white card of the report page.
class AdminSection extends StatelessWidget {
  const AdminSection({
    required this.title,
    required this.child,
    this.trailing,
    this.caption,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  /// A muted line under the title.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final caption = this.caption;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CircleCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: c.subtle,
                      ),
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            if (caption != null) ...[
              const SizedBox(height: 2),
              Text(caption, style: TextStyle(fontSize: 12.5, color: c.muted)),
            ],
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// A label and its value on one line ("Members  12").
class AdminFact extends StatelessWidget {
  const AdminFact({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.muted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 14, color: c.ink, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quoted text from a snapshot, in a quiet block.
class AdminQuote extends StatelessWidget {
  const AdminQuote({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      child: SelectableText(
        text,
        style: TextStyle(fontSize: 14.5, color: c.ink, height: 1.4),
      ),
    );
  }
}
