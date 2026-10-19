import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/admin/admin_console_screen.dart';
import 'package:wecord/features/admin/admin_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Settings: the way into the admin console. Nothing at all for anybody who
/// is not a platform admin (the server checks every call on its own).
class AdminConsoleEntry extends ConsumerWidget {
  const AdminConsoleEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(adminRoleProvider).value;
    if (role == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SettingsGroup(
        children: [
          SettingsRow(
            key: const ValueKey('settings-admin-console'),
            icon: Icons.admin_panel_settings_outlined,
            title: tr('Admin console'),
            subtitle: tr('Reports, flags, notices and feedback'),
            value: role.label,
            onTap: () {
              // The wide settings window floats over the app: go to the
              // page, which takes the window down. Phones push it.
              if (isWideLayout(MediaQuery.sizeOf(context).width)) {
                context.go(AdminConsoleScreen.path);
              } else {
                context.push(AdminConsoleScreen.path);
              }
            },
          ),
        ],
      ),
    );
  }
}
