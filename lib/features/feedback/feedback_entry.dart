import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wecord/features/feedback/feedback_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Settings: the "Feedback and help" row, which opens [FeedbackScreen].
class FeedbackSettingsEntry extends StatelessWidget {
  const FeedbackSettingsEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SettingsGroup(
        children: [
          SettingsRow(
            key: const ValueKey('settings-feedback'),
            icon: Icons.support_agent_rounded,
            title: tr('Feedback and help'),
            subtitle: tr('Tell us what went wrong or what you would like'),
            onTap: () => unawaited(
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => const FeedbackScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
