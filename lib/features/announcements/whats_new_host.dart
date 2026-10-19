import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/announcements/whats_new_content.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/feature_flags/feature_flags_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Which version's "What's new" this device has seen. Neither call throws:
/// a device that cannot store it simply never shows the popup twice by luck
/// of the version check, and never blocks anything.
abstract interface class WhatsNewStore {
  /// The version last opened on this device; null the very first time (or
  /// when it cannot be read).
  Future<String?> lastSeenVersion();

  Future<void> markSeen(String version);
}

class SharedPreferencesWhatsNewStore implements WhatsNewStore {
  const SharedPreferencesWhatsNewStore();

  static const _key = 'wecord.whats_new.seen_version';

  @override
  Future<String?> lastSeenVersion() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> markSeen(String version) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_key, version);
    } catch (_) {
      // Seen again next time at worst.
    }
  }
}

class InMemoryWhatsNewStore implements WhatsNewStore {
  InMemoryWhatsNewStore([this.version]);

  String? version;

  @override
  Future<String?> lastSeenVersion() async => version;

  @override
  Future<void> markSeen(String version) async => this.version = version;
}

final whatsNewStoreProvider = Provider<WhatsNewStore>(
  (ref) => const SharedPreferencesWhatsNewStore(),
);

/// The texts of the popups; tests swap their own.
final whatsNewEntriesProvider = Provider<List<WhatsNewEntry>>(
  (ref) => whatsNewEntries,
);

/// Decides whether to show "What's new": the first time WeCord is opened
/// after an update, when that version has an entry. A first-ever launch only
/// notes the version (a new person has nothing to compare with), and so does
/// a version with nothing to say. Sits in the signed-in shell.
class WhatsNewHost extends ConsumerStatefulWidget {
  const WhatsNewHost({required this.child, super.key});

  final Widget child;

  /// Once per run of the app: the shell can be rebuilt (resizing, signing
  /// out and in) without asking again.
  @visibleForTesting
  static var checkedThisRun = false;

  @override
  ConsumerState<WhatsNewHost> createState() => _WhatsNewHostState();
}

class _WhatsNewHostState extends ConsumerState<WhatsNewHost> {
  @override
  void initState() {
    super.initState();
    if (!WhatsNewHost.checkedThisRun) {
      WhatsNewHost.checkedThisRun = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
    }
  }

  Future<void> _check() async {
    try {
      final store = ref.read(whatsNewStoreProvider);
      final version = ref.read(appVersionProvider);
      final entry = whatsNewFor(version, ref.read(whatsNewEntriesProvider));
      final seen = await store.lastSeenVersion();
      if (seen == version) {
        return;
      }
      await store.markSeen(version);
      if (seen == null || entry == null || !mounted) {
        return;
      }
      await showCircleDialog<void>(
        context,
        builder: (context) => WhatsNewDialog(entry: entry),
      );
    } catch (_) {
      // A popup that cannot be decided is not shown; nothing depends on it.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The popup: the changes of one version, in the language of the app.
class WhatsNewDialog extends StatelessWidget {
  const WhatsNewDialog({required this.entry, super.key});

  final WhatsNewEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final chinese = AppStrings.isChinese;
    return CircleDialog(
      title: entry.title.of(chinese: chinese),
      message: tr('WeCord {version}', {'version': entry.version}),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in entry.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox.square(dimension: 6),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.of(chinese: chinese),
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.45,
                        color: c.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        CircleDialogAction.primary(
          key: const ValueKey('whats-new-got-it'),
          label: tr('Got it'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
