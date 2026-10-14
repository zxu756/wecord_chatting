import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/message_author.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/custom_status_sheet.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/custom_status.dart';

/// The signed-in user at the bottom of the sidebar on wide layouts: avatar
/// with presence, name, custom status (tap to change it) and settings.
class UserPanel extends ConsumerWidget {
  const UserPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    // Hidden from others (show_online_status off) means hidden here too;
    // until presence has loaded, assume online.
    final onlineIds = ref.watch(onlineUserIdsProvider).valueOrNull;
    final online =
        profile != null &&
        (onlineIds == null || onlineIds.contains(profile.id));
    final status = activeCustomStatus(profile?.customStatus);
    final name = profile == null
        ? ''
        : profile.displayName.trim().isNotEmpty
        ? profile.displayName
        : profile.username;

    return Material(
      key: const ValueKey('user-panel'),
      color: colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: profile == null
                    ? null
                    : () async {
                        final saved = await showCustomStatusSheet(
                          context,
                          current: status,
                        );
                        if (saved == true) {
                          ref.invalidate(currentProfileProvider);
                        }
                      },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          FallbackAvatar(
                            title: name,
                            avatarUrl: profile?.avatarUrl,
                            radius: 16,
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              key: ValueKey(
                                online
                                    ? 'user-panel-online'
                                    : 'user-panel-offline',
                              ),
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: online
                                    ? Colors.green
                                    : colorScheme.outline,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colorScheme.surfaceContainerHigh,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              status?.label ??
                                  (online ? tr('Online') : tr('Invisible')),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: tr('User settings'),
              visualDensity: VisualDensity.compact,
              onPressed: () => context.go(SettingsScreen.path),
              icon: const Icon(Icons.settings_outlined, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
