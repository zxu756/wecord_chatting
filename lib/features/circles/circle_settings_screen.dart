import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_settings.dart';
import 'package:wecord/features/chats/edit_history/circle_edit_window.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart';
import 'package:wecord/features/circles/circle_ai_guard_screen.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart';
import 'package:wecord/features/circles/circle_automod_screen.dart';
import 'package:wecord/features/circles/circle_bot_widgets.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_emojis_screen.dart';
import 'package:wecord/features/circles/circle_moderation.dart';
import 'package:wecord/features/circles/circle_onboarding.dart';
import 'package:wecord/features/circles/circle_review_screen.dart';
import 'package:wecord/features/circles/circle_roles_screen.dart';
import 'package:wecord/features/circles/circle_tag_widgets.dart';
import 'package:wecord/features/circles/circle_template_widgets.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/insights/insights_repository.dart';
import 'package:wecord/features/circles/insights/insights_screen.dart';
import 'package:wecord/features/circles/join_requests/join_requests_repository.dart';
import 'package:wecord/features/circles/join_requests/join_settings_screen.dart';
import 'package:wecord/features/circles/mod_tools/member_tools_screen.dart';
import 'package:wecord/features/circles/mod_tools/raid_protection.dart';
import 'package:wecord/features/discovery/circle_discovery_settings_screen.dart';
import 'package:wecord/features/profile/support_links_editor.dart';
import 'package:wecord/features/workflows/workflow_list_page.dart';
import 'package:wecord/features/workflows/workflow_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the circle's settings: its template, tag and bots.
void openCircleSettingsScreen(BuildContext context, String circleId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => CircleSettingsScreen(circleId: circleId),
    ),
  );
}

/// Whether the current user may open circle settings.
bool canOpenCircleSettings(CircleDetail detail) => detail.canManageCircle;

/// Circle settings on paper: the circle's card, the pages that manage it,
/// then its template, tag and bots.
class CircleSettingsScreen extends ConsumerWidget {
  const CircleSettingsScreen({required this.circleId, super.key});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(circleDetailProvider(circleId));
    return CirclePageScaffold(
      title: tr('Circle settings'),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => CircleEmptyState(
          icon: Icons.error_outline,
          title: tr('Could not load the circle.'),
        ),
        data: (detail) => ListView(
          padding: circlePagePadding(context),
          children: [
            _CircleHeaderCard(detail: detail),
            _ManageGroup(detail: detail),
            if (detail.canManageCircle) ...[
              CircleAiSwitch(circleId: circleId),
              CircleEditWindowSection(circleId: circleId),
              // Hidden on iPhone (App Store guideline 3.1.1).
              CircleSupportLinkSection(circleId: circleId),
              CircleTemplateSection(
                key: ValueKey('circle-template-$circleId'),
                circleId: circleId,
              ),
              CircleTagSection(
                key: ValueKey('circle-tag-$circleId'),
                circleId: circleId,
              ),
              CircleBotsSection(
                key: ValueKey('circle-bots-$circleId'),
                detail: detail,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CircleHeaderCard extends StatelessWidget {
  const _CircleHeaderCard({required this.detail});

  final CircleDetail detail;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final circle = detail.circle;
    return CircleCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleNetworkAvatar(
            name: circle.name,
            url: circle.avatarUrl,
            size: 58,
            thing: true,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  circle.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tr('{count} members', {'count': detail.memberCount}),
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rows to the pages that manage the circle, as far as the current user
/// may open them.
class _ManageGroup extends ConsumerWidget {
  const _ManageGroup({required this.detail});

  final CircleDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circleId = detail.circle.id;
    final canReview = detail.canOpenReview;
    final joinMode = detail.canManageCircle
        ? ref.watch(circleJoinSettingsProvider(circleId)).value?.mode
        : null;
    final waiting = canReview
        ? ref.watch(messageReviewCountProvider(circleId)).value ?? 0
        : 0;
    final rows = [
      if (detail.canManageRoles)
        SettingsRow(
          key: const ValueKey('circle-settings-roles'),
          icon: CircleIcons.roles,
          tone: SettingsTone.accent,
          title: tr('Roles'),
          value: '${detail.roles.length}',
          onTap: () => openCircleRolesScreen(context, circleId),
        ),
      if (detail.canModerateMembers)
        SettingsRow(
          key: const ValueKey('circle-settings-members'),
          icon: Icons.manage_accounts_outlined,
          tone: SettingsTone.accent,
          title: tr('Members'),
          subtitle: tr('Find, warn and act on many at once'),
          onTap: () => openMemberToolsScreen(context, circleId),
        ),
      if (detail.canBanMembers)
        SettingsRow(
          key: const ValueKey('circle-settings-bans'),
          icon: Icons.block,
          tone: SettingsTone.danger,
          title: tr('Bans'),
          onTap: () => openCircleBansScreen(context, circleId),
        ),
      if (detail.canRunSafetyActions)
        SettingsRow(
          key: const ValueKey('circle-settings-raid'),
          icon: Icons.shield_outlined,
          tone: SettingsTone.warning,
          title: tr('Raid protection'),
          subtitle: tr('Pause invites and lock down joining'),
          onTap: () => openRaidProtectionScreen(context, circleId),
        ),
      if (detail.canManageCircle) ...[
        SettingsRow(
          key: const ValueKey('circle-settings-automod'),
          icon: CircleIcons.autoMod,
          tone: SettingsTone.warning,
          title: tr('AutoMod'),
          onTap: () => openCircleAutoModScreen(context, detail),
        ),
        SettingsRow(
          key: const ValueKey('circle-settings-ai-guard'),
          icon: CircleIcons.aiGuard,
          tone: SettingsTone.accent,
          title: tr('AI guard'),
          subtitle: tr('Check new members\' first messages'),
          onTap: () => openCircleAiGuardScreen(context, detail),
        ),
        SettingsRow(
          key: const ValueKey('circle-settings-onboarding'),
          icon: Icons.rule,
          tone: SettingsTone.success,
          title: tr('Onboarding'),
          onTap: () => openCircleOnboardingSettings(context, detail),
        ),
        SettingsRow(
          key: const ValueKey('circle-settings-join-mode'),
          icon: Icons.how_to_reg_outlined,
          tone: SettingsTone.warning,
          title: tr('Join mode'),
          subtitle: tr('Open, apply to join, or invite only'),
          value: joinMode?.label,
          onTap: () => openCircleJoinSettings(context, detail),
        ),
        SettingsRow(
          key: const ValueKey('circle-settings-discovery'),
          icon: Icons.explore_outlined,
          tone: SettingsTone.accent,
          title: tr('Discovery'),
          subtitle: tr('Public listing in Explore'),
          onTap: () => openCircleDiscoverySettings(context, detail),
        ),
        SettingsRow(
          key: const ValueKey('circle-settings-workflows'),
          icon: Icons.bolt_rounded,
          tone: SettingsTone.accent,
          title: tr('Workflows'),
          subtitle: tr('Do things when something happens'),
          onTap: () =>
              unawaited(openWorkflows(context, WorkflowScope.circle(circleId))),
        ),
      ],
      if (canReview)
        SettingsRow(
          key: const ValueKey('circle-settings-review'),
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
                  semanticLabel: tr('{count} waiting', {'count': waiting}),
                ),
          showChevron: true,
          onTap: () => openCircleReviewScreen(context, circleId),
        ),
      if (detail.canViewAuditLog)
        SettingsRow(
          key: const ValueKey('circle-settings-audit-log'),
          icon: Icons.history,
          title: tr('Audit log'),
          onTap: () => openCircleAuditLogScreen(context, circleId),
        ),
      if (detail.canViewInsights)
        SettingsRow(
          key: const ValueKey('circle-settings-insights'),
          icon: Icons.insights_outlined,
          tone: SettingsTone.accent,
          title: tr('Insights'),
          subtitle: tr('Members, activity and invites'),
          onTap: () => openCircleInsights(context, detail),
        ),
      if (detail.currentMember != null)
        SettingsRow(
          key: const ValueKey('circle-settings-emojis'),
          icon: Icons.emoji_emotions_outlined,
          title: tr('Emoji & stickers'),
          onTap: () => openCircleEmojisScreen(context, circleId),
        ),
    ];
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return SettingsGroup(header: tr('Manage'), children: rows);
  }
}

/// A section title in circle settings, with an optional note under it.
class CircleSettingsHeader extends StatelessWidget {
  const CircleSettingsHeader(this.title, {this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
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
          if (subtitle case final subtitle?) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
