import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart';
import 'package:wecord/features/circles/circle_review_screen.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/ui/ui.dart';

void openCircleAiGuardScreen(BuildContext context, CircleDetail detail) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => CircleAiGuardScreen(detail: detail),
    ),
  );
}

/// "AI guard for new members": an opt-in check of the first messages a new
/// member sends, before the others see them. Circle managers only.
class CircleAiGuardScreen extends ConsumerWidget {
  const CircleAiGuardScreen({required this.detail, super.key});

  final CircleDetail detail;

  String get circleId => detail.circle.id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guard = ref.watch(circleAiGuardProvider(circleId));
    return CirclePageScaffold(
      title: tr('AI guard'),
      body: guard.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => CircleEmptyState(
          icon: CircleIcons.aiGuard,
          title: tr('Could not load the AI guard.'),
          action: WeCordButton(
            label: tr('Try again'),
            onPressed: () => ref.invalidate(circleAiGuardProvider(circleId)),
          ),
        ),
        data: (guard) => CircleAiGuardForm(
          key: ValueKey('ai-guard-form-$circleId'),
          circleId: circleId,
          canReview: detail.can(CirclePermission.manageMessages),
          initial: guard,
        ),
      ),
    );
  }
}

/// The guard's settings. Every change is saved at once; the form shows the
/// new value straight away and goes back when saving fails.
class CircleAiGuardForm extends ConsumerStatefulWidget {
  const CircleAiGuardForm({
    required this.circleId,
    required this.initial,
    this.canReview = true,
    super.key,
  });

  final String circleId;
  final CircleAiGuard initial;

  /// Whether the user moderates messages, which adds the Review row.
  final bool canReview;

  @override
  ConsumerState<CircleAiGuardForm> createState() => _CircleAiGuardFormState();
}

class _CircleAiGuardFormState extends ConsumerState<CircleAiGuardForm> {
  late CircleAiGuard _guard = widget.initial;
  var _saving = false;

  Future<void> _change(CircleAiGuard next) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final previous = _guard;
    setState(() {
      _guard = next;
      _saving = true;
    });
    try {
      final saved = await ref
          .read(circleAiGuardRepositoryProvider)
          .saveGuard(widget.circleId, next);
      if (mounted) {
        setState(() => _guard = saved);
      }
      ref.invalidate(circleAiGuardProvider(widget.circleId));
    } on Object {
      if (mounted) {
        setState(() => _guard = previous);
      }
      messenger?.showSnackBar(
        SnackBar(content: Text(tr("Couldn't save the AI guard. Try again."))),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final guard = _guard;
    final canReview = widget.canReview;
    final waiting = canReview
        ? ref.watch(messageReviewCountProvider(widget.circleId)).value ?? 0
        : 0;
    return ListView(
      padding: circlePagePadding(context),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 12),
          child: Text(
            tr(
              'Checks the first messages of new members with AI before '
              'everyone else sees them. Messages the AI finds fine appear '
              'within moments.',
            ),
            style: TextStyle(fontSize: 14, color: c.muted, height: 1.4),
          ),
        ),
        if (!guard.circleAiEnabled)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              key: const ValueKey('ai-guard-ai-off'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.warningSoft,
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: c.warningText,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr(
                        'AI features are turned off in this circle, so the '
                        'guard does nothing. Turn on "Allow AI features in '
                        'this circle" in Circle settings to use it.',
                      ),
                      style: TextStyle(
                        fontSize: 13.5,
                        color: c.warningText,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        SettingsGroup(
          key: const ValueKey('ai-guard-main'),
          footer: tr(
            'Only the text of messages from new members is sent to the AI '
            'provider, and only while this is on. Pictures and files are '
            'not sent. If the AI is unavailable, messages are shown as '
            'usual and marked as not checked.',
          ),
          children: [
            SettingsRow.toggle(
              key: const ValueKey('ai-guard-switch'),
              icon: CircleIcons.aiGuard,
              tone: SettingsTone.accent,
              title: tr('AI guard for new members'),
              subtitle: guard.enabled
                  ? (guard.circleAiEnabled
                        ? tr('On')
                        : tr('On, but AI is off in this circle'))
                  : tr('Off'),
              value: guard.enabled,
              onChanged: _saving
                  ? null
                  : (value) =>
                        unawaited(_change(guard.copyWith(enabled: value))),
            ),
          ],
        ),
        if (guard.enabled) ...[
          SettingsSectionHeader(tr('Who counts as new')),
          CircleCard(
            key: const ValueKey('ai-guard-new-rule'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WeCordSegmented<AiGuardNewRule>(
                  expand: true,
                  semanticLabel: tr('Who counts as new'),
                  selected: guard.newRule,
                  onChanged: _saving
                      ? null
                      : (rule) =>
                            unawaited(_change(guard.copyWith(newRule: rule))),
                  segments: [
                    WeCordSegment(
                      key: const ValueKey('ai-guard-rule-joined'),
                      value: AiGuardNewRule.joinedDays,
                      label: tr('Recently joined'),
                    ),
                    WeCordSegment(
                      key: const ValueKey('ai-guard-rule-messages'),
                      value: AiGuardNewRule.messageCount,
                      label: tr('Few messages'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (guard.newRule == AiGuardNewRule.joinedDays)
                  WeCordSegmented<int>(
                    expand: true,
                    semanticLabel: tr('Joined less than'),
                    selected: guard.joinedDays,
                    onChanged: _saving
                        ? null
                        : (days) => unawaited(
                            _change(guard.copyWith(joinedDays: days)),
                          ),
                    segments: [
                      for (final days in aiGuardJoinedDayChoices)
                        WeCordSegment(
                          key: ValueKey('ai-guard-days-$days'),
                          value: days,
                          label: days == 1
                              ? tr('1 day')
                              : tr('{count} days', {'count': days}),
                        ),
                    ],
                  )
                else
                  WeCordSegmented<int>(
                    expand: true,
                    semanticLabel: tr('Fewer than'),
                    selected: guard.messageCount,
                    onChanged: _saving
                        ? null
                        : (count) => unawaited(
                            _change(guard.copyWith(messageCount: count)),
                          ),
                    segments: [
                      for (final count in {
                        ...aiGuardMessageCountChoices,
                        guard.messageCount,
                      }.toList()..sort())
                        WeCordSegment(
                          key: ValueKey('ai-guard-count-$count'),
                          value: count,
                          label: '$count',
                        ),
                    ],
                  ),
                const SizedBox(height: 10),
                Text(
                  key: const ValueKey('ai-guard-new-summary'),
                  guard.newRule == AiGuardNewRule.joinedDays
                      ? (guard.joinedDays == 1
                            ? tr(
                                'Members who joined less than a day ago. '
                                'Moderators and managers are never checked.',
                              )
                            : tr(
                                'Members who joined less than {count} days '
                                'ago. Moderators and managers are never '
                                'checked.',
                                {'count': guard.joinedDays},
                              ))
                      : tr(
                          'Members who have sent fewer than {count} messages '
                          'in this circle. Moderators and managers are never '
                          'checked.',
                          {'count': guard.messageCount},
                        ),
                  style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.4),
                ),
              ],
            ),
          ),
          SettingsSectionHeader(tr('When the AI flags a message')),
          SettingsGroup(
            key: const ValueKey('ai-guard-action'),
            separatorIndent: 14,
            children: [
              _ChoiceRow(
                key: const ValueKey('ai-guard-action-hold'),
                title: tr('Hold for review'),
                subtitle: tr(
                  'Hidden from everyone but the author until a moderator '
                  'approves or removes it.',
                ),
                selected: guard.action == AiGuardAction.hold,
                onTap: _saving
                    ? null
                    : () => unawaited(
                        _change(guard.copyWith(action: AiGuardAction.hold)),
                      ),
              ),
              _ChoiceRow(
                key: const ValueKey('ai-guard-action-flag'),
                title: tr('Flag only'),
                subtitle: tr(
                  'Shown to everyone as usual, and listed for moderators '
                  'to look at.',
                ),
                selected: guard.action == AiGuardAction.flag,
                onTap: _saving
                    ? null
                    : () => unawaited(
                        _change(guard.copyWith(action: AiGuardAction.flag)),
                      ),
              ),
            ],
          ),
        ],
        if (canReview) ...[
          SettingsSectionHeader(tr('Moderation')),
          SettingsGroup(
            children: [
              SettingsRow(
                key: const ValueKey('ai-guard-open-review'),
                icon: Icons.fact_check_outlined,
                tone: SettingsTone.warning,
                title: tr('Review'),
                subtitle: waiting == 0
                    ? tr('Nothing is waiting')
                    : tr('{count} waiting', {'count': waiting}),
                trailing: waiting == 0
                    ? null
                    : CountBadge(
                        count: waiting,
                        tone: BadgeTone.mention,
                        semanticLabel: tr('{count} waiting', {
                          'count': waiting,
                        }),
                      ),
                showChevron: true,
                onTap: () => openCircleReviewScreen(context, widget.circleId),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A row of a single choice: the title, a note and a check when chosen.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: SettingsRow(
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        showChevron: false,
        trailing: selected
            ? Icon(Icons.check_rounded, color: c.accentText, size: 22)
            : const SizedBox(width: 22),
      ),
    );
  }
}
