import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/time_tokens/time_token.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// How long a group must have been quiet to be offered for clean-up.
enum InactivityPeriod {
  days30(30),
  days90(90),
  days180(180);

  const InactivityPeriod(this.days);

  final int days;
}

/// A group chat nobody has written in for a while, as
/// `list_inactive_groups` returns it.
class InactiveGroup {
  const InactiveGroup({
    required this.id,
    required this.memberCount,
    required this.lastActivityAt,
    this.title,
    this.avatarUrl,
    this.myRole = 'member',
    this.canLeave = true,
    this.isPinned = false,
    this.isMuted = false,
  });

  factory InactiveGroup.fromJson(Map<String, dynamic> json) {
    return InactiveGroup(
      id: json['conversation_id'] as String,
      title: json['title'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      lastActivityAt: DateTime.parse(json['last_activity_at'] as String),
      myRole: json['my_role'] as String? ?? 'member',
      canLeave: json['can_leave'] != false,
      isPinned: json['is_pinned'] == true,
      isMuted: json['is_muted'] == true,
    );
  }

  final String id;
  final String? title;
  final String? avatarUrl;
  final int memberCount;

  /// The last message, or when the group was made if nobody ever wrote.
  final DateTime lastActivityAt;
  final String myRole;

  /// False for the only owner of a group with other members.
  final bool canLeave;
  final bool isPinned;
  final bool isMuted;

  String get name {
    final value = title?.trim();
    return value == null || value.isEmpty ? tr('Untitled group') : value;
  }
}

abstract interface class GroupCleanupRepository {
  /// The caller's groups quiet for at least [days], oldest first.
  Future<List<InactiveGroup>> listInactiveGroups(int days);
}

final groupCleanupRepositoryProvider = Provider<GroupCleanupRepository>((ref) {
  try {
    return SupabaseGroupCleanupRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _NoGroupCleanupRepository();
  }
});

class SupabaseGroupCleanupRepository implements GroupCleanupRepository {
  const SupabaseGroupCleanupRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<InactiveGroup>> listInactiveGroups(int days) async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_inactive_groups',
      params: {'inactive_days': days},
    );
    return [
      for (final row in rows)
        InactiveGroup.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }
}

class _NoGroupCleanupRepository implements GroupCleanupRepository {
  const _NoGroupCleanupRepository();

  @override
  Future<List<InactiveGroup>> listInactiveGroups(int days) async => const [];
}

/// The groups quiet for [InactivityPeriod.days] days.
final inactiveGroupsProvider = FutureProvider.autoDispose
    .family<List<InactiveGroup>, int>((ref, days) {
      return ref.watch(groupCleanupRepositoryProvider).listInactiveGroups(days);
    });

/// How a batch of leaving ended.
class GroupCleanupResult {
  const GroupCleanupResult({required this.left, required this.failed});

  final List<InactiveGroup> left;
  final List<InactiveGroup> failed;
}

/// Leaves groups after a short window in which it can be undone. Lives as
/// long as the app, so a batch goes through even when the page is closed.
class GroupCleanupController extends Notifier<List<InactiveGroup>> {
  /// How long "Undo" works.
  static const undoWindow = Duration(seconds: 6);

  Timer? _timer;

  /// The groups waiting out the undo window; empty when nothing is pending.
  @override
  List<InactiveGroup> build() {
    ref.onDispose(() => _timer?.cancel());
    return const [];
  }

  /// Leaves [groups] once [undoWindow] has passed, unless [undo] is called.
  /// [onFinished] hears how it went.
  void schedule(
    List<InactiveGroup> groups, {
    required void Function(GroupCleanupResult result) onFinished,
    Duration? delay,
  }) {
    if (groups.isEmpty || state.isNotEmpty) {
      return;
    }
    state = List.unmodifiable(groups);
    _timer = Timer(delay ?? undoWindow, () => _run(groups, onFinished));
  }

  /// Cancels the pending batch; true when there was one.
  bool undo() {
    if (state.isEmpty) {
      return false;
    }
    _timer?.cancel();
    _timer = null;
    state = const [];
    return true;
  }

  Future<void> _run(
    List<InactiveGroup> groups,
    void Function(GroupCleanupResult result) onFinished,
  ) async {
    _timer = null;
    final repository = ref.read(chatsRepositoryProvider);
    final left = <InactiveGroup>[];
    final failed = <InactiveGroup>[];
    for (final group in groups) {
      try {
        await repository.leaveGroupConversation(group.id);
        left.add(group);
      } catch (_) {
        failed.add(group);
      }
    }
    state = const [];
    ref.invalidate(conversationsProvider);
    ref.invalidate(inactiveGroupsProvider);
    onFinished(GroupCleanupResult(left: left, failed: failed));
  }
}

final groupCleanupControllerProvider =
    NotifierProvider<GroupCleanupController, List<InactiveGroup>>(
      GroupCleanupController.new,
    );

void openGroupCleanup(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const GroupCleanupScreen()),
  );
}

/// Settings -> Chats -> Clean up groups: pick how long a group has been
/// quiet, tick the ones to leave, and leave them together.
class GroupCleanupScreen extends ConsumerStatefulWidget {
  const GroupCleanupScreen({super.key});

  @override
  ConsumerState<GroupCleanupScreen> createState() => _GroupCleanupScreenState();
}

class _GroupCleanupScreenState extends ConsumerState<GroupCleanupScreen> {
  var _period = InactivityPeriod.days90;
  final _selected = <String>{};

  void _setPeriod(InactivityPeriod period) {
    setState(() {
      _period = period;
      _selected.clear();
    });
  }

  void _toggle(InactiveGroup group) {
    if (!group.canLeave) {
      return;
    }
    setState(() {
      if (!_selected.remove(group.id)) {
        _selected.add(group.id);
      }
    });
  }

  void _toggleAll(List<InactiveGroup> leavable) {
    setState(() {
      if (_selected.length == leavable.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(leavable.map((group) => group.id));
      }
    });
  }

  Future<void> _leave(List<InactiveGroup> groups) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(
          groups.length == 1
              ? tr('Leave 1 group?')
              : tr('Leave {count} groups?', {'count': groups.length}),
        ),
        content: Text(
          tr(
            'You will stop getting their messages and they will leave your chat list. A member can add you back later.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('group-cleanup-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Leave')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(groupCleanupControllerProvider.notifier);
    controller.schedule(
      groups,
      onFinished: (result) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(_resultText(result)),
            duration: const Duration(seconds: 5),
          ),
        );
      },
    );
    setState(_selected.clear);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('group-cleanup-undo-bar'),
          duration: GroupCleanupController.undoWindow,
          persist: false,
          content: Text(
            groups.length == 1
                ? tr('Leaving 1 group…')
                : tr('Leaving {count} groups…', {'count': groups.length}),
          ),
          action: SnackBarAction(
            label: tr('Undo'),
            onPressed: () {
              if (controller.undo()) {
                messenger.hideCurrentSnackBar();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      tr('Nothing changed. You are still in them.'),
                    ),
                  ),
                );
              }
            },
          ),
        ),
      );
  }

  String _resultText(GroupCleanupResult result) {
    if (result.failed.isEmpty) {
      return result.left.length == 1
          ? tr('Left 1 group.')
          : tr('Left {count} groups.', {'count': result.left.length});
    }
    return tr('Left {left}, but {failed} could not be left. Try again.', {
      'left': result.left.length,
      'failed': result.failed.length,
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final groups = ref.watch(inactiveGroupsProvider(_period.days));
    final pending = ref.watch(groupCleanupControllerProvider);
    final pendingIds = {for (final group in pending) group.id};
    final all = [
      for (final group in groups.value ?? const <InactiveGroup>[])
        if (!pendingIds.contains(group.id)) group,
    ];
    final leavable = [
      for (final group in all)
        if (group.canLeave) group,
    ];
    final chosen = [
      for (final group in leavable)
        if (_selected.contains(group.id)) group,
    ];
    final now = DateTime.now();

    return SettingsPage(
      key: const ValueKey('group-cleanup-screen'),
      title: tr('Clean up groups'),
      children: [
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
          child: Text(
            tr(
              'Leave group chats nobody has written in for a while. You choose which ones, and you can undo before anything happens.',
            ),
            style: TextStyle(fontSize: 14.5, height: 1.45, color: c.muted),
          ),
        ),
        WeCordSegmented<InactivityPeriod>(
          expand: true,
          semanticLabel: tr('Quiet for'),
          selected: _period,
          onChanged: _setPeriod,
          segments: [
            for (final period in InactivityPeriod.values)
              WeCordSegment(
                key: ValueKey('group-cleanup-${period.days}'),
                value: period,
                label: tr('{count} days', {'count': period.days}),
              ),
          ],
        ),
        const SizedBox(height: 16),
        switch (groups) {
          AsyncError() => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              tr('Could not load your groups. Try again.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.dangerText),
            ),
          ),
          AsyncData() when all.isEmpty => _EmptyState(period: _period),
          AsyncData() => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SelectionBar(
                total: leavable.length,
                selected: chosen.length,
                onSelectAll: leavable.isEmpty
                    ? null
                    : () => _toggleAll(leavable),
                onLeave: chosen.isEmpty ? null : () => _leave(chosen),
              ),
              const SizedBox(height: 12),
              SettingsGroup(
                separatorIndent: 70,
                children: [
                  for (final group in all)
                    _GroupRow(
                      group: group,
                      now: now,
                      selected: _selected.contains(group.id),
                      onTap: () => _toggle(group),
                    ),
                ],
              ),
            ],
          ),
          _ => const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.period});

  final InactivityPeriod period;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      key: const ValueKey('group-cleanup-empty'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Column(
        children: [
          SettingsIconTile(
            icon: Icons.check_rounded,
            tone: SettingsTone.success,
            size: 48,
          ),
          const SizedBox(height: 14),
          Text(
            tr('Nothing to clean up'),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr(
              'Every group of yours has had a message in the last {count} days.',
              {'count': period.days},
            ),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
          ),
        ],
      ),
    );
  }
}

/// "3 of 12 selected", Select all and the Leave button.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.total,
    required this.selected,
    required this.onSelectAll,
    required this.onLeave,
  });

  final int total;
  final int selected;
  final VoidCallback? onSelectAll;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final allSelected = total > 0 && selected == total;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selected == 0
                      ? tr('{count} quiet groups', {'count': total})
                      : tr('{selected} of {total} selected', {
                          'selected': selected,
                          'total': total,
                        }),
                  key: const ValueKey('group-cleanup-count'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                WeCordPressable(
                  key: const ValueKey('group-cleanup-select-all'),
                  onPressed: onSelectAll,
                  semanticLabel: allSelected
                      ? tr('Select none')
                      : tr('Select all'),
                  builder: (context, states) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      allSelected ? tr('Select none') : tr('Select all'),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: onSelectAll == null ? c.faint : c.accentText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          WeCordButton(
            key: const ValueKey('group-cleanup-leave'),
            label: selected == 0
                ? tr('Leave')
                : tr('Leave {count}', {'count': selected}),
            variant: WeCordButtonVariant.danger,
            icon: Icons.logout_rounded,
            onPressed: onLeave,
          ),
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.now,
    required this.selected,
    required this.onTap,
  });

  final InactiveGroup group;
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final enabled = group.canLeave;
    final last = tr('Last activity {when}', {
      'when': relativeTimeText(group.lastActivityAt, now),
    });
    final detail = [
      last,
      tr('{count} members', {'count': group.memberCount}),
      if (group.isPinned) tr('Pinned'),
    ].join(' · ');
    return WeCordPressable(
      key: ValueKey('group-cleanup-row-${group.id}'),
      selected: selected,
      toggled: enabled ? selected : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      semanticLabel: [
        group.name,
        detail,
        if (!enabled) tr('You are the only owner. Hand it over first.'),
      ].join(', '),
      excludeSemantics: true,
      onPressed: enabled ? onTap : null,
      builder: (context, states) => Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        color: selected
            ? c.accentSoft
            : states.contains(WidgetState.hovered)
            ? c.raised
            : null,
        child: Row(
          children: [
            Opacity(
              opacity: enabled ? 1 : 0.5,
              child: ChatAvatar(
                name: group.name,
                avatarUrl: group.avatarUrl,
                thing: true,
                size: 42,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: enabled ? c.ink : c.muted,
                    ),
                  ),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.muted, height: 1.3),
                  ),
                  if (!enabled)
                    Text(
                      tr('You are the only owner. Hand it over first.'),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: c.warningText,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ExcludeSemantics(
              child: Icon(
                !enabled
                    ? Icons.lock_outline_rounded
                    : selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 24,
                color: !enabled
                    ? c.faint
                    : selected
                    ? c.accent
                    : c.faint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
