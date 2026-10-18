import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/error_reports/error_reporter.dart';
import 'package:wecord/features/error_reports/error_reporting_hooks.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/settings_group.dart';

/// The reporter the settings switch controls; tests swap in their own.
final errorReporterProvider = Provider<ErrorReporter>((ref) => errorReporter);

/// Whether crash and error reports are sent from this device (on by
/// default). Per device: it is kept on the device, not in the account.
final errorReportsEnabledProvider =
    NotifierProvider<ErrorReportsEnabledController, bool>(
      ErrorReportsEnabledController.new,
    );

class ErrorReportsEnabledController extends Notifier<bool> {
  @override
  bool build() => ref.read(errorReporterProvider).enabled;

  Future<void> set(bool enabled) async {
    state = enabled;
    await ref.read(errorReporterProvider).setEnabled(enabled);
  }
}

/// "Send crash and error reports" with a footer saying what is sent.
class ErrorReportsSettingsGroup extends ConsumerWidget {
  const ErrorReportsSettingsGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsGroup(
      footer: tr(
        'When something goes wrong, WeCord sends the kind of problem, the app '
        'version, your device type, language and the screen you were on. It '
        'never sends your messages, files, contacts, email or passwords. '
        'This applies to this device only.',
      ),
      children: [
        SettingsRow.toggle(
          key: const ValueKey('error-reports-toggle'),
          icon: Icons.bug_report_outlined,
          title: tr('Send crash and error reports'),
          value: ref.watch(errorReportsEnabledProvider),
          onChanged: (enabled) =>
              ref.read(errorReportsEnabledProvider.notifier).set(enabled),
        ),
      ],
    );
  }
}
