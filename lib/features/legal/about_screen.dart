import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wecord/features/legal/legal_document.dart';
import 'package:wecord/features/legal/legal_screen.dart';
import 'package:wecord/features/privacy/device_info.dart' show appVersion;
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Settings: the "About" row, which opens [AboutScreen].
class AboutSettingsEntry extends StatelessWidget {
  const AboutSettingsEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SettingsGroup(
        children: [
          SettingsRow(
            key: const ValueKey('settings-about'),
            icon: Icons.info_outline_rounded,
            title: tr('About WeCord'),
            subtitle: tr('Terms, privacy and licences'),
            onTap: () => unawaited(
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => const AboutScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// About WeCord: the version, the three policy pages and the open-source
/// licences of the packages the app is built from.
class AboutScreen extends StatelessWidget {
  const AboutScreen({this.version = appVersion, super.key});

  /// The app's version; the build's by default.
  final String version;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SettingsPage(
      key: const ValueKey('about-screen'),
      title: tr('About WeCord'),
      children: [
        const SizedBox(height: 12),
        SettingsGroup(
          children: [
            SettingsRow(
              key: const ValueKey('about-version'),
              icon: Icons.chat_bubble_outline_rounded,
              title: tr('WeCord'),
              value: version,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SettingsGroup(
          header: tr('Legal'),
          children: [
            for (final document in LegalDocument.values)
              SettingsRow(
                key: ValueKey('about-${document.slug}'),
                icon: switch (document) {
                  LegalDocument.guidelines => Icons.diversity_3_outlined,
                  LegalDocument.privacy => Icons.privacy_tip_outlined,
                  LegalDocument.terms => Icons.description_outlined,
                },
                title: document.title,
                onTap: () => unawaited(openLegalDocument(context, document)),
              ),
            SettingsRow(
              key: const ValueKey('about-licenses'),
              icon: Icons.code_rounded,
              title: tr('Open-source licences'),
              onTap: () => showLicensePage(
                context: context,
                applicationName: tr('WeCord'),
                applicationVersion: version,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          child: Text(
            tr('The legal texts are drafts and may still change.'),
            style: TextStyle(fontSize: 13, color: c.muted, height: 1.4),
          ),
        ),
      ],
    );
  }
}
