import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_template_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';

/// Opens the circle's settings: its template (and more sections as the
/// circle allows).
void openCircleSettingsScreen(BuildContext context, String circleId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => CircleSettingsScreen(circleId: circleId),
    ),
  );
}

/// Whether the current user may open circle settings.
bool canOpenCircleSettings(CircleDetail detail) => detail.canManageCircle;

class CircleSettingsScreen extends ConsumerWidget {
  const CircleSettingsScreen({required this.circleId, super.key});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(circleDetailProvider(circleId));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Circle settings'))),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(tr('Could not load the circle.')),
          ),
        ),
        data: (detail) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (detail.canManageCircle)
              CircleTemplateSection(
                key: ValueKey('circle-template-$circleId'),
                circleId: circleId,
              ),
          ],
        ),
      ),
    );
  }
}

/// A section title in circle settings.
class CircleSettingsHeader extends StatelessWidget {
  const CircleSettingsHeader(this.title, {this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle case final subtitle?) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
