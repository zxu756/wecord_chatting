import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/inbox/digest/digest_models.dart';
import 'package:wecord/features/inbox/digest/digest_repository.dart';
import 'package:wecord/features/privacy/option_picker.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens Settings -> AI -> Daily digest.
void openDigestSettings(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const DigestSettingsScreen()),
  );
}

String get _appLanguage => AppStrings.isChinese ? 'zh' : 'en';

/// "8:00 AM" or "08:00", as the device writes times.
String digestTimeLabel(BuildContext context, DigestSettings settings) {
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay(hour: settings.hour, minute: settings.minute),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
}

/// The "Daily digest" row of Settings -> AI.
class DigestSettingsRow extends ConsumerWidget {
  const DigestSettingsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(digestSettingsProvider).value;
    final following = settings?.subscriptions.length ?? 0;
    return SettingsRow(
      key: const ValueKey('digest-settings-tile'),
      icon: Icons.wb_twilight_rounded,
      tone: SettingsTone.accent,
      title: tr('Daily digest'),
      subtitle: tr(
        'A short summary of the chats you follow, once a day, only when there is news.',
      ),
      value: settings == null || !settings.enabled || following == 0
          ? tr('Off')
          : digestTimeLabel(context, settings),
      onTap: () => openDigestSettings(context),
    );
  }
}

/// A chat that can be followed.
class _Option {
  const _Option({
    required this.id,
    required this.title,
    required this.followed,
    this.subtitle,
  });

  final String id;
  final String title;

  /// The circle of a channel.
  final String? subtitle;
  final bool followed;
}

/// Settings -> AI -> Daily digest: the switch, the time of day, and which
/// groups and circle channels to follow (at most 10).
class DigestSettingsScreen extends ConsumerStatefulWidget {
  const DigestSettingsScreen({super.key});

  @override
  ConsumerState<DigestSettingsScreen> createState() =>
      _DigestSettingsScreenState();
}

class _DigestSettingsScreenState extends ConsumerState<DigestSettingsScreen> {
  /// What the person just chose and the server has not confirmed yet.
  final _followOverrides = <String, bool>{};
  bool? _enabledOverride;
  var _languageChecked = false;

  Future<void> _refresh() async {
    ref.invalidate(digestSettingsProvider);
    await ref.read(digestSettingsProvider.future);
  }

  void _tell(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _enabledOverride = value);
    try {
      await ref
          .read(digestRepositoryProvider)
          .saveSettings(enabled: value, language: _appLanguage);
      await _refresh();
    } on Object {
      if (mounted) {
        _tell(couldNotSaveText());
      }
    } finally {
      if (mounted) {
        setState(() => _enabledOverride = null);
      }
    }
  }

  Future<void> _pickTime(DigestSettings settings) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: settings.hour, minute: settings.minute),
      helpText: tr('Deliver the digest at'),
    );
    if (picked == null || !mounted) {
      return;
    }
    try {
      await ref
          .read(digestRepositoryProvider)
          .saveSettings(
            hour: picked.hour,
            minute: picked.minute,
            language: _appLanguage,
          );
      await _refresh();
    } on Object {
      if (mounted) {
        _tell(couldNotSaveText());
      }
    }
  }

  Future<void> _follow(String conversationId, bool follow) async {
    setState(() => _followOverrides[conversationId] = follow);
    try {
      await ref
          .read(digestRepositoryProvider)
          .setSubscription(
            conversationId,
            subscribed: follow,
            language: _appLanguage,
          );
      await _refresh();
    } on DigestLimitReached {
      if (mounted) {
        _tell(
          tr('You can follow at most {max} chats. Unfollow one first.', {
            'max':
                ref.read(digestSettingsProvider).value?.maxSubscriptions ?? 10,
          }),
        );
      }
    } on Object {
      if (mounted) {
        _tell(couldNotSaveText());
      }
    } finally {
      if (mounted) {
        setState(() => _followOverrides.remove(conversationId));
      }
    }
  }

  /// The summaries follow the app's language: bring a stale one up to date.
  void _syncLanguage(DigestSettings settings) {
    if (_languageChecked) {
      return;
    }
    _languageChecked = true;
    if (settings.language != _appLanguage &&
        settings.subscriptions.isNotEmpty) {
      unawaited(
        ref
            .read(digestRepositoryProvider)
            .saveSettings(language: _appLanguage)
            .then((_) => ref.invalidate(digestSettingsProvider))
            .catchError((Object _) {}),
      );
    }
  }

  List<_Option> _options(DigestSettings settings) {
    final conversations =
        ref.watch(conversationsProvider).value ?? const <ConversationSummary>[];
    final circles = {
      for (final circle
          in ref.watch(circleSummariesProvider).value ??
              const <CircleSummary>[])
        circle.id: circle,
    };
    bool followed(String id) => _followOverrides[id] ?? settings.follows(id);

    _Option fromConversation(ConversationSummary conversation) {
      final title = conversation.title?.trim() ?? '';
      final isChannel = conversation.type == ConversationType.channel;
      return _Option(
        id: conversation.id,
        title: isChannel ? '#$title' : title,
        subtitle: isChannel ? circles[conversation.circleId]?.name : null,
        followed: followed(conversation.id),
      );
    }

    final options = <_Option>[];
    final seen = <String>{};
    // The chats already followed come first, by the name the server has when
    // the chat list does not know them.
    for (final subscription in settings.subscriptions) {
      final conversation = conversations
          .where((c) => c.id == subscription.conversationId)
          .firstOrNull;
      seen.add(subscription.conversationId);
      if (conversation != null &&
          (conversation.title ?? '').trim().isNotEmpty) {
        options.add(fromConversation(conversation));
      } else {
        final circle = subscription.circleName;
        options.add(
          _Option(
            id: subscription.conversationId,
            title: circle == null || circle.isEmpty
                ? subscription.title
                : '#${subscription.title}',
            subtitle: circle == null || circle.isEmpty ? null : circle,
            followed: followed(subscription.conversationId),
          ),
        );
      }
    }
    for (final conversation in conversations) {
      if (seen.contains(conversation.id) ||
          (conversation.type != ConversationType.group &&
              conversation.type != ConversationType.channel) ||
          (conversation.title ?? '').trim().isEmpty) {
        continue;
      }
      options.add(fromConversation(conversation));
    }
    return options;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final loaded = ref.watch(digestSettingsProvider);
    final aiOn = ref.watch(aiEnabledProvider);
    final settings = loaded.value;
    if (settings != null) {
      _syncLanguage(settings);
    }
    final enabled = _enabledOverride ?? settings?.enabled ?? true;
    final options = settings == null ? const <_Option>[] : _options(settings);
    final followingCount = options.where((option) => option.followed).length;
    final full =
        settings != null && followingCount >= settings.maxSubscriptions;
    return SettingsPage(
      key: const ValueKey('digest-settings-screen'),
      title: tr('Daily digest'),
      children: [
        const SizedBox(height: 12),
        if (loaded.hasError && settings == null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              tr('Could not load. Try again.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.dangerText),
            ),
          )
        else if (settings == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          SettingsGroup(
            footer: aiOn
                ? tr(
                    'WeCord AI reads only the messages you can see in the chats you follow, and only when something new was said. Recalled, disappearing and view-once messages and messages from people you blocked are never sent. Each digest counts as one AI request.',
                  )
                : tr(
                    'AI features are off in Settings, so no digest is made until you turn them on.',
                  ),
            children: [
              SettingsRow.toggle(
                key: const ValueKey('digest-enabled-switch'),
                icon: Icons.wb_twilight_rounded,
                tone: enabled ? SettingsTone.accent : SettingsTone.neutral,
                title: tr('Send me a daily digest'),
                subtitle: tr(
                  'It appears in Notifications and you get a push when it is ready.',
                ),
                value: enabled,
                onChanged: _enabledOverride == null
                    ? (value) => unawaited(_setEnabled(value))
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsGroup(
            header: tr('Delivery'),
            footer: tr(
              'The digest uses the time zone your devices report, so it follows you when you travel.',
            ),
            children: [
              SettingsRow(
                key: const ValueKey('digest-time-row'),
                icon: Icons.schedule_rounded,
                title: tr('Time'),
                value: digestTimeLabel(context, settings),
                onTap: enabled ? () => unawaited(_pickTime(settings)) : null,
              ),
              SettingsRow(
                key: const ValueKey('digest-zone-row'),
                icon: Icons.public_rounded,
                title: tr('Time zone'),
                value: settings.timeZone,
                showChevron: false,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsGroup(
            key: const ValueKey('digest-chats'),
            header: tr('Chats you follow ({count} of {max})', {
              'count': followingCount,
              'max': settings.maxSubscriptions,
            }),
            footer: full
                ? tr(
                    'You follow {max} chats, the most you can. Unfollow one to follow another.',
                    {'max': settings.maxSubscriptions},
                  )
                : tr(
                    'Groups and circle channels you are in. Private chats are not included.',
                  ),
            children: [
              if (options.isEmpty)
                SettingsRow(
                  key: const ValueKey('digest-no-chats'),
                  icon: Icons.forum_outlined,
                  title: tr('No groups or channels yet'),
                  showChevron: false,
                ),
              for (final option in options)
                SettingsRow.toggle(
                  key: ValueKey('digest-follow-${option.id}'),
                  icon: Icons.forum_outlined,
                  title: option.title,
                  subtitle: option.subtitle,
                  value: option.followed,
                  // A full list still lets a followed chat be unfollowed.
                  onChanged:
                      _followOverrides.containsKey(option.id) ||
                          (full && !option.followed)
                      ? null
                      : (value) => unawaited(_follow(option.id, value)),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}
