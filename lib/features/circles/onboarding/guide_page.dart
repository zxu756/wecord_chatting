import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_channel_thread_screen.dart';
import 'package:wecord/features/circles/circle_onboarding.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/onboarding/guide_models.dart';
import 'package:wecord/features/circles/onboarding/guide_prompts_page.dart';
import 'package:wecord/features/circles/onboarding/guide_repository.dart';
import 'package:wecord/features/knowledge_base/kb_screen.dart';
import 'package:wecord/features/settings/profile_editor.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the member guide of a circle.
Future<void> openCircleGuide(
  BuildContext context, {
  required String circleId,
  required String circleName,
  List<CircleChannel> channels = const [],
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (context) => CircleGuidePage(
        circleId: circleId,
        circleName: circleName,
        channels: channels,
      ),
    ),
  );
}

/// Takes the member to [channel] of the circle, the way the sidebar does.
void openGuideChannel(
  BuildContext context,
  String circleId,
  CircleChannel channel,
) {
  final router = GoRouter.of(context);
  if (isWideLayout(MediaQuery.sizeOf(context).width)) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    router.go('${CircleRoutes.path}/$circleId?c=${channel.conversationId}');
    return;
  }
  unawaited(
    router.push<void>(
      CircleChannelThreadScreen.pathFor(circleId, channel.conversationId),
      extra: ChatThreadRouteExtra(
        title: channel.isVoice ? channel.name : '# ${channel.name}',
        type: ConversationType.channel,
        circleId: circleId,
      ),
    ),
  );
}

/// The "New member guide" card at the top of a circle: how far the member
/// is through the newcomer tasks, and the way to the guide. Hidden once
/// everything is done, or when the member puts it away.
class CircleGuideBar extends StatelessWidget {
  const CircleGuideBar({required this.guide, required this.onOpen, super.key});

  final CircleGuide guide;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final needsAnswers = guide.hasPrompts && !guide.answered;
    final subtitle = guide.hasTasks
        ? tr('{done} of {total} done', {
            'done': guide.doneCount,
            'total': guide.taskCount,
          })
        : tr('Choose what you are into');
    final progress = guide.hasTasks ? guide.doneCount / guide.taskCount : null;
    return Material(
      key: const ValueKey('circle-guide-bar'),
      color: c.accentSoft,
      child: SafeArea(
        bottom: false,
        child: WeCordPressable(
          onPressed: onOpen,
          semanticLabel:
              '${tr('New member guide')}. $subtitle'
              '${needsAnswers ? '. ${tr('Questions waiting')}' : ''}',
          excludeSemantics: true,
          pressedScale: 1,
          builder: (context, states) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            child: Row(
              children: [
                Icon(Icons.explore_outlined, size: 20, color: c.accentText),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tr('New member guide'),
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: c.accentText,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        needsAnswers && guide.hasTasks
                            ? '$subtitle · ${tr('Questions waiting')}'
                            : subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: c.accentText,
                        ),
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            key: const ValueKey('circle-guide-progress'),
                            value: progress,
                            minHeight: 4,
                            backgroundColor: c.accentText.withValues(
                              alpha: 0.18,
                            ),
                            valueColor: AlwaysStoppedAnimation(c.accent),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: c.accentText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The guide: the newcomer to-do list with progress, the member's answers
/// to the circle's questions, and whether to keep the card on the circle.
class CircleGuidePage extends ConsumerWidget {
  const CircleGuidePage({
    required this.circleId,
    required this.circleName,
    this.channels = const [],
    super.key,
  });

  final String circleId;
  final String circleName;
  final List<CircleChannel> channels;

  CircleChannel? _channel(String? id) {
    for (final channel in channels) {
      if (channel.id == id) {
        return channel;
      }
    }
    return null;
  }

  Future<void> _doTask(
    BuildContext context,
    WidgetRef ref,
    GuideTask task,
  ) async {
    final repository = ref.read(circleGuideRepositoryProvider);
    switch (task.action) {
      case GuideTaskAction.readRules:
        final onboarding = await ref.read(
          circleOnboardingProvider(circleId).future,
        );
        if (!context.mounted) {
          return;
        }
        await runCircleRulesFlow(
          context,
          ref,
          circleId: circleId,
          circleName: circleName,
          onboarding: onboarding,
        );
      case GuideTaskAction.setAvatar:
        await openProfileEditor(context);
      case GuideTaskAction.readPage:
        final pageId = task.pageId;
        if (pageId == null) {
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) =>
                KnowledgeBaseScreen(circleId: circleId, initialPageId: pageId),
          ),
        );
      case GuideTaskAction.visitChannel:
      case GuideTaskAction.sendMessage:
        final channel = _channel(task.channelId);
        if (channel == null) {
          return;
        }
        if (task.action == GuideTaskAction.visitChannel) {
          try {
            await repository.completeTask(circleId, task.id);
          } on Object {
            // Opening the channel still helps; the tick comes next time.
          }
        }
        if (context.mounted) {
          openGuideChannel(context, circleId, channel);
        }
    }
    ref.invalidate(circleGuideProvider(circleId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final guide = ref.watch(circleGuideProvider(circleId)).value;
    return CirclePageScaffold(
      title: tr('New member guide'),
      subtitle: circleName,
      body: guide == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: circlePagePadding(context),
              children: [
                if (guide.hasTasks) ...[
                  _ProgressCard(guide: guide),
                  const SizedBox(height: 12),
                  SettingsGroup(
                    separatorIndent: 14,
                    children: [
                      for (final task in guide.tasks)
                        _TaskRow(
                          task: task,
                          onTap: () => unawaited(_doTask(context, ref, task)),
                        ),
                    ],
                  ),
                ],
                if (guide.hasPrompts) ...[
                  SettingsSectionHeader(tr('Your interests')),
                  SettingsGroup(
                    children: [
                      SettingsRow(
                        key: const ValueKey('guide-open-prompts'),
                        icon: Icons.interests_outlined,
                        tone: SettingsTone.accent,
                        title: guide.answered
                            ? tr('Change my answers')
                            : tr('Choose what you are into'),
                        subtitle: guide.answered
                            ? _answerSummary(guide)
                            : tr(
                                'Your answers can give you roles and show '
                                'you the channels that fit.',
                              ),
                        onTap: () => unawaited(
                          openGuidePrompts(
                            context,
                            circleId: circleId,
                            circleName: circleName,
                            guide: guide,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                SettingsGroup(
                  separatorIndent: 14,
                  footer: tr(
                    'The guide stays in the circle menu if you hide it here.',
                  ),
                  children: [
                    SettingsRow.toggle(
                      key: const ValueKey('guide-show-card'),
                      title: tr('Show the guide at the top of the circle'),
                      value: !guide.dismissed,
                      onChanged: (show) async {
                        try {
                          await ref
                              .read(circleGuideRepositoryProvider)
                              .dismiss(circleId, dismissed: !show);
                        } on Object {
                          return;
                        }
                        ref.invalidate(circleGuideProvider(circleId));
                      },
                    ),
                  ],
                ),
                if (!guide.hasTasks && !guide.hasPrompts)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr('This circle has no guide yet.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.muted),
                    ),
                  ),
              ],
            ),
    );
  }

  String _answerSummary(CircleGuide guide) {
    final labels = [
      for (final prompt in guide.prompts)
        for (final option in prompt.options)
          if (option.selected) option.label,
    ];
    return labels.isEmpty ? tr('No answers yet') : labels.join(', ');
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.guide});

  final CircleGuide guide;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final complete = guide.tasksComplete;
    return CircleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  complete
                      ? tr('All done. Welcome aboard!')
                      : tr('{done} of {total} done', {
                          'done': guide.doneCount,
                          'total': guide.taskCount,
                        }),
                  key: const ValueKey('guide-progress-label'),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                  ),
                ),
              ),
              if (complete)
                Icon(Icons.celebration_outlined, color: c.accentText),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            label: tr('{done} of {total} done', {
              'done': guide.doneCount,
              'total': guide.taskCount,
            }),
            excludeSemantics: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: guide.doneCount / guide.taskCount,
                minHeight: 8,
                backgroundColor: c.well,
                valueColor: AlwaysStoppedAnimation(c.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.onTap});

  final GuideTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final channel = task.channelName;
    final page = task.pageTitle;
    final subtitle = task.action == GuideTaskAction.readPage
        ? (page == null || page.trim().isEmpty ? tr('Untitled') : page)
        : (channel == null ? null : '#$channel');
    return WeCordPressable(
      key: ValueKey('guide-task-${task.id}'),
      semanticLabel: [
        task.title,
        ?subtitle,
        task.done ? tr('Done') : tr('Not done yet'),
      ].join('. '),
      excludeSemantics: true,
      onPressed: onTap,
      builder: (context, states) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            AnimatedContainer(
              duration: WeCordMotion.quick,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: task.done ? c.accent : Colors.transparent,
                border: Border.all(
                  color: task.done ? c.accent : c.track,
                  width: 2,
                ),
              ),
              child: task.done
                  ? Icon(Icons.check_rounded, size: 16, color: c.onAccent)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: task.done ? c.muted : c.ink,
                      decoration: task.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        style: TextStyle(fontSize: 12.5, color: c.muted),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.subtle),
          ],
        ),
      ),
    );
  }
}
