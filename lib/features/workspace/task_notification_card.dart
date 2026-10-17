import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/lists/lists_repository.dart';
import 'package:wecord/features/lists/task_widgets.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/workspace/workspace_navigation.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// An assignment or a due reminder in the notifications, like the cards
/// for mentions: who, what, the task and a way to open it.
class TaskNotificationCard extends ConsumerWidget {
  const TaskNotificationCard({
    required this.notification,
    this.conversationName,
    super.key,
  });

  final TaskNotification notification;

  /// "#channel · Circle" or a group's name; null for direct messages.
  final String? conversationName;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(listsRepositoryProvider);
    if (notification.isUnread) {
      try {
        await repository.markNotificationsRead([notification.id]);
        ref.invalidate(taskNotificationsProvider);
      } on Object {
        // Opening still works.
      }
    }
    if (!context.mounted) {
      return;
    }
    openWorkspace(
      context,
      conversationId: notification.conversationId,
      tab: WorkspaceTab.lists,
      listId: notification.listId,
      itemId: notification.itemId,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final actor = notification.actorName;
    final kind = notification.kind;
    final headline = switch (kind) {
      TaskNotificationKind.assigned => tr('assigned you a task'),
      TaskNotificationKind.dueSoon => tr('Task due soon'),
      TaskNotificationKind.overdue => tr('Task overdue'),
    };
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(WeCordRadii.xl),
    );
    final badgeColor = switch (kind) {
      TaskNotificationKind.assigned => c.accent,
      TaskNotificationKind.dueSoon => c.warning,
      TaskNotificationKind.overdue => c.danger,
    };
    final badgeIcon = switch (kind) {
      TaskNotificationKind.assigned => Icons.assignment_ind_outlined,
      TaskNotificationKind.dueSoon => Icons.schedule_rounded,
      TaskNotificationKind.overdue => Icons.error_outline_rounded,
    };
    final time = Text(
      formatDue(
        context,
        notification.createdAt.toLocal(),
        hasTime: true,
        now: DateTime.now(),
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: c.muted,
      ),
    );
    return WeCordPressable(
      key: ValueKey('inbox-task-${notification.id}'),
      onPressed: () => unawaited(_open(context, ref)),
      shape: shape,
      pressedScale: 0.98,
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: const EdgeInsets.all(14),
          decoration: ShapeDecoration(
            color: hovered
                ? Color.alphaBlend(c.ink.withValues(alpha: 0.025), c.panel)
                : c.panel,
            shape: shape.copyWith(
              side: notification.isUnread
                  ? BorderSide(color: c.accent, width: 2)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileAvatar(
                name: actor ?? notification.title,
                avatarUrl: notification.actorAvatarUrl,
                badge: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.panel, width: 2.5),
                  ),
                  child: Icon(badgeIcon, size: 11, color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                if (kind == TaskNotificationKind.assigned &&
                                    actor != null) ...[
                                  TextSpan(
                                    text: actor,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const TextSpan(text: ' '),
                                ],
                                TextSpan(
                                  text: headline,
                                  style: TextStyle(
                                    fontWeight:
                                        kind == TaskNotificationKind.assigned
                                        ? FontWeight.w400
                                        : FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            style: TextStyle(
                              fontSize: 14.5,
                              height: 1.4,
                              color: c.ink,
                            ),
                          ),
                        ),
                        if (notification.isUnread)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: c.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (conversationName != null &&
                        conversationName!.isNotEmpty)
                      Text(
                        conversationName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.muted),
                      ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: c.well,
                        borderRadius: BorderRadius.circular(WeCordRadii.md),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notification.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: notification.isDone ? c.muted : c.ink,
                              decoration: notification.isDone
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          if (notification.dueAt != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: TaskChip(
                                icon: Icons.event_outlined,
                                label: formatDue(
                                  context,
                                  notification.dueAt!,
                                  hasTime: true,
                                ),
                                color: kind == TaskNotificationKind.overdue
                                    ? c.dangerText
                                    : c.muted,
                                background: kind == TaskNotificationKind.overdue
                                    ? c.dangerSoft
                                    : c.raised,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        WeCordButton(
                          key: ValueKey('inbox-task-open-${notification.id}'),
                          label: tr('Open task'),
                          size: WeCordButtonSize.small,
                          variant: WeCordButtonVariant.secondary,
                          onPressed: () => unawaited(_open(context, ref)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: time,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
