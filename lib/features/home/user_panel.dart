import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/message_author.dart';
import 'package:wecord/features/presence/presence_indicator.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/presence/presence_status_sheet.dart';
import 'package:wecord/features/settings/custom_status_sheet.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/custom_status.dart';

/// The signed-in user at the bottom of the sidebar on wide layouts: avatar
/// with presence, name, custom status (tap to change either) and settings.
class UserPanel extends ConsumerWidget {
  const UserPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    // Invisible (or online status hidden) shows as such here, though
    // others see the user offline.
    final presence = ref.watch(ownPresenceProvider);
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
                    : () => showPresenceStatusSheet(
                        context,
                        onEditCustomStatus: () async {
                          final saved = await showCustomStatusSheet(
                            context,
                            current: status,
                          );
                          if (saved == true) {
                            ref.invalidate(currentProfileProvider);
                          }
                        },
                      ),
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
                            child: PresenceIndicator(
                              key: ValueKey(
                                'user-panel-presence-${presence.value}',
                              ),
                              status: presence,
                              borderColor: colorScheme.surfaceContainerHigh,
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
                              status?.label ?? presence.label,
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
