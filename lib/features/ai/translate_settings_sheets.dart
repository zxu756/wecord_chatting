import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/translate_settings.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Settings → AI → "Translate to": the language messages are translated
/// into, by auto-translate, the message menu and "Text from picture". The
/// language of the app unless the person picks one of the six.
class TranslateToRow extends ConsumerWidget {
  const TranslateToRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(aiTranslateSettingsProvider);
    return SettingsRow(
      key: const ValueKey('translate-to-row'),
      icon: Icons.translate_rounded,
      title: tr('Translate to'),
      subtitle: tr(
        'Used by auto-translate, Translate and Copy text from picture.',
      ),
      value: settings.target == null
          ? tr('App language')
          : settings.target!.label,
      onTap: () => unawaited(showTranslateToSheet(context)),
    );
  }
}

Future<void> showTranslateToSheet(BuildContext context) {
  return showWeCordSheet<void>(
    context,
    title: tr('Translate to'),
    builder: (context, _) => const SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: _TranslateToOptions(),
      ),
    ),
  );
}

class _TranslateToOptions extends ConsumerWidget {
  const _TranslateToOptions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final current = ref.watch(aiTranslateSettingsProvider).target;
    final controller = ref.read(aiTranslateSettingsProvider.notifier);

    Widget check(bool on) => on
        ? Icon(Icons.check_rounded, size: 20, color: c.accent)
        : const SizedBox(width: 20);

    return SettingsGroup(
      key: const ValueKey('translate-to-options'),
      color: c.well,
      separatorIndent: 14,
      children: [
        SettingsRow(
          key: const ValueKey('translate-to-app'),
          title: tr('App language'),
          subtitle: tr('Follow the language of the app ({language})', {
            'language': AiLanguage.appLanguage.label,
          }),
          trailing: check(current == null),
          onTap: () {
            WeCordHaptics.selection();
            unawaited(controller.setTarget(null));
            Navigator.of(context).pop();
          },
        ),
        for (final language in AiLanguage.values)
          SettingsRow(
            key: ValueKey('translate-to-${language.code}'),
            title: language.label,
            trailing: check(current == language),
            onTap: () {
              WeCordHaptics.selection();
              unawaited(controller.setTarget(language));
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }
}

/// Settings → AI → "Don't translate": languages that stay as they are, so
/// someone who reads English never has English translated.
class DontTranslateRow extends ConsumerWidget {
  const DontTranslateRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skipped = ref.watch(aiTranslateSettingsProvider).noTranslate;
    return SettingsRow(
      key: const ValueKey('dont-translate-row'),
      icon: Icons.translate_outlined,
      title: tr("Don't translate"),
      subtitle: tr('Auto-translate leaves these languages as they are.'),
      value: skipped.isEmpty
          ? tr('None')
          : [
              for (final language in AiLanguage.values)
                if (skipped.contains(language)) language.label,
            ].join(', '),
      onTap: () => unawaited(showDontTranslateSheet(context)),
    );
  }
}

Future<void> showDontTranslateSheet(BuildContext context) {
  return showWeCordSheet<void>(
    context,
    title: tr("Don't translate"),
    builder: (context, _) => const SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: _DontTranslateOptions(),
      ),
    ),
  );
}

class _DontTranslateOptions extends ConsumerWidget {
  const _DontTranslateOptions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final skipped = ref.watch(aiTranslateSettingsProvider).noTranslate;
    final controller = ref.read(aiTranslateSettingsProvider.notifier);
    return SettingsGroup(
      key: const ValueKey('dont-translate-options'),
      color: c.well,
      separatorIndent: 14,
      children: [
        for (final language in AiLanguage.values)
          SettingsRow.toggle(
            key: ValueKey('dont-translate-${language.code}'),
            title: language.label,
            value: skipped.contains(language),
            onChanged: (on) {
              WeCordHaptics.selection();
              unawaited(controller.setNoTranslate(language, on: on));
            },
          ),
      ],
    );
  }
}
