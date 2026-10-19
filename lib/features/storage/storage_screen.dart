import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/features/storage/local_storage_service.dart';
import 'package:wecord/features/storage/storage_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart' show formatFileSize;
import 'package:wecord/shared/ui/ui.dart';

/// What this device holds, measured when the page opens and again after
/// anything is cleared.
final storageReportProvider = FutureProvider.autoDispose<StorageReport>((ref) {
  return ref.watch(localStorageServiceProvider).measure();
});

/// Opens Settings → Storage.
Future<void> openStorageSettings(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (context) => const StorageScreen()),
  );
}

/// The row in Settings that opens [StorageScreen].
class StorageSettingsRow extends StatelessWidget {
  const StorageSettingsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      key: const ValueKey('storage-tile'),
      icon: Icons.pie_chart_outline_rounded,
      title: tr('Storage'),
      subtitle: tr('See what WeCord keeps on this device and clear it'),
      onTap: () => unawaited(openStorageSettings(context)),
    );
  }
}

/// Settings → Storage (L2): how much of this device WeCord uses, by kind of
/// data and by chat, clearing it, and clearing old media by itself. Only
/// copies are touched; nothing changes on the server or for anyone else.
class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});

  static const clearAllKey = ValueKey('storage-clear-all');
  static const confirmKey = ValueKey('storage-confirm-clear');
  static const autoCleanKey = ValueKey('storage-auto-clean');

  @override
  ConsumerState<StorageScreen> createState() => _StorageScreenState();
}

/// How many chats the page lists.
const storageChatLimit = 20;

class _StorageScreenState extends ConsumerState<StorageScreen> {
  var _busy = false;

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            key: StorageScreen.confirmKey,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true && mounted;
  }

  Future<void> _run(Future<int> Function() clear) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    var freed = 0;
    try {
      freed = await clear();
    } finally {
      ref.invalidate(storageReportProvider);
      if (mounted) {
        setState(() => _busy = false);
      }
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            freed > 0
                ? tr('Freed {size}.', {'size': formatFileSize(freed)})
                : tr('Nothing to clear.'),
          ),
        ),
      );
  }

  Future<void> _clearCategory(StorageCategory category) async {
    final confirmed = await _confirm(
      title: _categoryClearTitle(category),
      body: _categoryClearBody(category),
      action: tr('Clear'),
    );
    if (!confirmed) {
      return;
    }
    await _run(
      () => ref.read(localStorageServiceProvider).clearCategory(category),
    );
  }

  Future<void> _clearAll() async {
    final confirmed = await _confirm(
      title: tr('Clear all cached data?'),
      body: tr(
        'This removes the copies of chats, files and previews that WeCord keeps on this device. Nothing changes on the server or for anyone else. Anything you open again is downloaded again and uses data.',
      ),
      action: tr('Clear all'),
    );
    if (!confirmed) {
      return;
    }
    await _run(() => ref.read(localStorageServiceProvider).clearAll());
  }

  Future<void> _clearConversation(
    ConversationStorage usage,
    String name,
  ) async {
    final confirmed = await _confirm(
      title: tr('Clear what is kept for {name}?', {'name': name}),
      body: tr(
        'This removes the cached messages, downloaded files and previews of this chat from this device. Nothing changes on the server or for anyone else. Files you open again are downloaded again and use data.',
      ),
      action: tr('Clear'),
    );
    if (!confirmed) {
      return;
    }
    await _run(
      () => ref
          .read(localStorageServiceProvider)
          .clearConversation(usage.conversationId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(storageReportProvider);
    final disk = ref.watch(diskCacheProvider);
    return SettingsPage(
      key: const ValueKey('storage-screen'),
      title: tr('Storage'),
      children: switch (report) {
        AsyncData(:final value) => _content(context, value, disk.available),
        AsyncError() => _content(
          context,
          const StorageReport(bytes: {}, conversations: []),
          disk.available,
        ),
        _ => const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      },
    );
  }

  List<Widget> _content(
    BuildContext context,
    StorageReport report,
    bool hasDisk,
  ) {
    final c = context.tokens.colors;
    final categories = [
      for (final category in StorageCategory.values)
        if (_shown(category, report, hasDisk)) category,
    ];
    final titles = <String, ConversationSummary>{
      for (final conversation
          in ref.watch(conversationsProvider).value ??
              const <ConversationSummary>[])
        conversation.id: conversation,
    };
    return [
      const SizedBox(height: 12),
      _Summary(report: report, categories: categories),
      SettingsGroup(
        header: tr('What takes space'),
        footer: tr(
          'Clearing only removes copies on this device. Nothing changes on the server or for anyone else. Anything you open again is downloaded again and uses data.',
        ),
        children: [
          for (final category in categories)
            SettingsRow(
              key: ValueKey('storage-${category.name}'),
              icon: _categoryIcon(category),
              tone: _categoryTone(category),
              title: _categoryTitle(category),
              subtitle: _categorySubtitle(category),
              value: formatFileSize(report.of(category)),
              onTap: category.clearable && report.of(category) > 0 && !_busy
                  ? () => unawaited(_clearCategory(category))
                  : null,
              showChevron: category.clearable && report.of(category) > 0,
            ),
        ],
      ),
      const SizedBox(height: 16),
      WeCordButton(
        key: StorageScreen.clearAllKey,
        label: tr('Clear all cached data'),
        variant: WeCordButtonVariant.secondary,
        expand: true,
        loading: _busy,
        onPressed: report.hasClearable && !_busy ? _clearAll : null,
      ),
      if (hasDisk) ...[
        SettingsSectionHeader(tr('Automatic clean-up')),
        const _AutoCleanCard(),
      ],
      if (report.conversations.isNotEmpty) ...[
        SettingsGroup(
          header: tr('By chat'),
          children: [
            for (final usage in report.conversations.take(storageChatLimit))
              _chatRow(usage, titles[usage.conversationId]),
            if (report.unassignedFileBytes > 0)
              SettingsRow(
                key: const ValueKey('storage-unassigned'),
                icon: Icons.insert_drive_file_outlined,
                title: tr('Files not tied to a chat'),
                subtitle: tr(
                  'Kept before WeCord took note of where they came from',
                ),
                value: formatFileSize(report.unassignedFileBytes),
              ),
          ],
        ),
      ],
      SizedBox(height: 12, child: ColoredBox(color: c.paper)),
    ];
  }

  Widget _chatRow(ConversationStorage usage, ConversationSummary? chat) {
    final title = chat?.title?.trim();
    final name = title == null || title.isEmpty ? tr('A chat') : title;
    final direct = chat?.type == ConversationType.direct;
    final parts = [
      if (usage.messageBytes > 0)
        tr('Messages {size}', {'size': formatFileSize(usage.messageBytes)}),
      if (usage.fileBytes > 0)
        tr('Files {size}', {'size': formatFileSize(usage.fileBytes)}),
    ];
    return SettingsRow(
      key: ValueKey('storage-chat-${usage.conversationId}'),
      icon: direct ? Icons.person_outline_rounded : Icons.forum_outlined,
      title: name,
      subtitle: parts.join(' · '),
      value: formatFileSize(usage.total),
      onTap: _busy ? null : () => unawaited(_clearConversation(usage, name)),
    );
  }

  bool _shown(StorageCategory category, StorageReport report, bool hasDisk) {
    return switch (category) {
      StorageCategory.messages ||
      StorageCategory.texts ||
      StorageCategory.wallpapers => true,
      // Browsers keep no files of their own for the app.
      StorageCategory.downloads || StorageCategory.thumbnails => hasDisk,
      StorageCategory.unsent => report.of(category) > 0,
    };
  }
}

IconData _categoryIcon(StorageCategory category) => switch (category) {
  StorageCategory.messages => Icons.forum_outlined,
  StorageCategory.downloads => Icons.download_done_rounded,
  StorageCategory.thumbnails => Icons.photo_size_select_actual_outlined,
  StorageCategory.texts => Icons.text_snippet_outlined,
  StorageCategory.wallpapers => Icons.wallpaper_rounded,
  StorageCategory.unsent => Icons.schedule_send_outlined,
};

SettingsTone _categoryTone(StorageCategory category) => switch (category) {
  StorageCategory.messages => SettingsTone.accent,
  StorageCategory.downloads => SettingsTone.success,
  StorageCategory.thumbnails => SettingsTone.warning,
  _ => SettingsTone.neutral,
};

String _categoryTitle(StorageCategory category) => switch (category) {
  StorageCategory.messages => tr('Cached messages'),
  StorageCategory.downloads => tr('Downloaded files'),
  StorageCategory.thumbnails => tr('Previews'),
  StorageCategory.texts => tr('Recognized text and transcripts'),
  StorageCategory.wallpapers => tr('Wallpaper photos'),
  StorageCategory.unsent => tr('Waiting to send'),
};

String _categorySubtitle(StorageCategory category) => switch (category) {
  StorageCategory.messages => tr(
    'The chat list and the newest messages, to read offline',
  ),
  StorageCategory.downloads => tr(
    'Pictures, videos, voice messages and files you opened',
  ),
  StorageCategory.thumbnails => tr('Small pictures of PDFs and videos'),
  StorageCategory.texts => tr(
    'Text read from pictures and voice messages, kept only here',
  ),
  StorageCategory.wallpapers => tr('Photos you chose as chat wallpaper'),
  StorageCategory.unsent => tr(
    'Attachments that are still being sent. They are not cleared.',
  ),
};

String _categoryClearTitle(StorageCategory category) => switch (category) {
  StorageCategory.messages => tr('Clear cached messages?'),
  StorageCategory.downloads => tr('Clear downloaded files?'),
  StorageCategory.thumbnails => tr('Clear previews?'),
  StorageCategory.texts => tr('Clear recognized text and transcripts?'),
  StorageCategory.wallpapers => tr('Clear wallpaper photos?'),
  StorageCategory.unsent => tr('Clear all cached data?'),
};

String _categoryClearBody(StorageCategory category) => switch (category) {
  StorageCategory.messages => tr(
    'Chats are loaded from the server again the next time you open them. Until then you cannot read them offline. Messages waiting to be sent are kept.',
  ),
  StorageCategory.downloads => tr(
    'Pictures, videos and files you open again are downloaded again, which uses data.',
  ),
  StorageCategory.thumbnails => tr(
    'Previews are drawn again the next time you see the file, which uses data.',
  ),
  StorageCategory.texts => tr(
    'Text read from pictures and voice messages is made again the next time you ask for it.',
  ),
  StorageCategory.wallpapers => tr(
    'Wallpaper photos are downloaded again the next time a chat shows them, which uses data.',
  ),
  StorageCategory.unsent => '',
};

/// The total, and a bar of what it is made of.
class _Summary extends StatelessWidget {
  const _Summary({required this.report, required this.categories});

  final StorageReport report;
  final List<StorageCategory> categories;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final browser = report.browser;
    final total = report.total;
    Color colorOf(StorageCategory category) => switch (category) {
      StorageCategory.messages => c.accent,
      StorageCategory.downloads => c.live,
      StorageCategory.thumbnails => c.warning,
      StorageCategory.texts => c.muted,
      StorageCategory.wallpapers => c.subtle,
      StorageCategory.unsent => c.faint,
    };
    final parts = [
      for (final category in categories)
        if (report.of(category) > 0) category,
    ];
    final summary = tr('WeCord keeps {size} on this device', {
      'size': formatFileSize(total),
    });
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: BorderRadius.circular(WeCordRadii.xl),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                key: const ValueKey('storage-total'),
                container: true,
                child: Text(
                  formatFileSize(total),
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    color: c.ink,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(summary, style: TextStyle(fontSize: 13.5, color: c.muted)),
              if (parts.isNotEmpty) ...[
                const SizedBox(height: 14),
                // Decorative: every row below says the same in words.
                ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 10,
                      child: Row(
                        children: [
                          for (final category in parts)
                            Expanded(
                              flex: report.of(category).clamp(1, 1 << 30),
                              child: ColoredBox(color: colorOf(category)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (browser != null) ...[
                const SizedBox(height: 12),
                Text(
                  tr(
                    'This browser lets WeCord use up to {quota}; it uses {usage} now, including the app itself.',
                    {
                      'quota': formatFileSize(browser.quota),
                      'usage': formatFileSize(browser.usage),
                    },
                  ),
                  key: const ValueKey('storage-browser'),
                  style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The auto-clean choice.
class _AutoCleanCard extends ConsumerWidget {
  const _AutoCleanCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final period = ref.watch(autoCleanPeriodProvider);
    return SettingsGroup(
      footer: period == AutoCleanPeriod.off
          ? tr(
              'Downloaded files, previews and recognized text you have not opened for this long are removed by themselves. Messages stay. Files you open again are downloaded again.',
            )
          : tr(
              'Files, previews and recognized text not opened for {days} days are removed by themselves, at most once a day. Messages stay. Files you open again are downloaded again.',
              {'days': period.days},
            ),
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Remove media not opened for'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 10),
              WeCordSegmented<AutoCleanPeriod>(
                key: StorageScreen.autoCleanKey,
                expand: true,
                semanticLabel: tr('Remove media not opened for'),
                selected: period,
                onChanged: (value) => unawaited(
                  ref.read(autoCleanPeriodProvider.notifier).set(value),
                ),
                segments: [
                  WeCordSegment(
                    key: const ValueKey('auto-clean-off'),
                    value: AutoCleanPeriod.off,
                    label: tr('Never'),
                  ),
                  for (final option in AutoCleanPeriod.values)
                    if (option.days != null)
                      WeCordSegment(
                        key: ValueKey('auto-clean-${option.name}'),
                        value: option,
                        label: tr('{days} days', {'days': option.days}),
                      ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
