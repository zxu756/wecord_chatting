import 'package:flutter/material.dart';
import 'package:wecord/features/groups/group_cleanup.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Settings -> Chats: housekeeping for your conversations.
class ChatSettingsGroup extends StatelessWidget {
  const ChatSettingsGroup({this.header, super.key});

  final String? header;

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      header: header,
      children: [
        SettingsRow(
          key: const ValueKey('group-cleanup-tile'),
          icon: Icons.cleaning_services_outlined,
          title: tr('Clean up groups'),
          subtitle: tr('Leave group chats nobody writes in any more'),
          onTap: () => openGroupCleanup(context),
        ),
      ],
    );
  }
}
