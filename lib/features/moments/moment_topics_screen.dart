import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/hashtags/hashtag_routes.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The topics (#话题) friends use in their Moments lately. A topic is a way
/// to filter the Moments the person can already see; the counts only cover
/// Moments they may see.
class MomentTopicsScreen extends ConsumerWidget {
  const MomentTopicsScreen({super.key});

  static const path = momentTopicsPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final topics = ref.watch(momentsTopicsProvider);
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaperPageHeader(title: tr('Topics')),
                Expanded(
                  child: topics.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stackTrace) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tr('Could not load topics.'),
                            style: TextStyle(color: c.dangerText),
                          ),
                          const SizedBox(height: 12),
                          WeCordButton(
                            label: tr('Try again'),
                            onPressed: () =>
                                ref.invalidate(momentsTopicsProvider),
                          ),
                        ],
                      ),
                    ),
                    data: (topics) => topics.isEmpty
                        ? const _NoTopics()
                        : _TopicList(topics: topics),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicList extends StatelessWidget {
  const _TopicList({required this.topics});

  final List<MomentTopic> topics;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text(
            tr('Topics your friends and you used lately.'),
            style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
          ),
        ),
        SettingsGroup(
          color: c.panel,
          children: [
            for (final topic in topics)
              SettingsRow(
                key: ValueKey('moment-topic-${topic.tag}'),
                icon: Icons.tag_rounded,
                tone: SettingsTone.accent,
                title: topic.tag,
                value: tr('{count} Moments', {'count': topic.postCount}),
                onTap: () => context.push(momentTagPath(topic.tag)),
              ),
          ],
        ),
      ],
    );
  }
}

class _NoTopics extends StatelessWidget {
  const _NoTopics();

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SettingsIconTile(
              icon: Icons.tag_rounded,
              tone: SettingsTone.accent,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              tr('No topics yet'),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.displaySmall?.copyWith(fontSize: 22, color: c.ink),
            ),
            const SizedBox(height: 6),
            Text(
              tr('Write #something in a Moment to start one.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}
