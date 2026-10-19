import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart'
    show formatAuditTime;
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_moderation.dart'
    show circleTimeoutDurations;
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/mod_tools/ban_duration_picker.dart';
import 'package:wecord/features/circles/mod_tools/mod_notes_screen.dart';
import 'package:wecord/features/circles/mod_tools/mod_tools_models.dart';
import 'package:wecord/features/circles/mod_tools/mod_tools_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The most members one batch can hold (the database refuses more).
const modBatchLimit = 50;

/// Whether the current user has any of the member-moderation permissions
/// the member list needs.
extension ModMemberToolsPermissions on CircleDetail {
  bool get canModerateMembers =>
      can(CirclePermission.moderateMembers) ||
      can(CirclePermission.kickMembers) ||
      can(CirclePermission.banMembers);

  /// Notes and warnings are for members who can time people out.
  bool get canWriteModNotes => can(CirclePermission.moderateMembers);

  /// Whether the current user may read and write notes about [member]: the
  /// same rank rule as timing them out (never themselves, never the owner,
  /// only members ranked below).
  bool canNoteAbout(CircleMember member) {
    return canWriteModNotes &&
        !member.isCurrentUser &&
        member.role != 'owner' &&
        rankOf(member) < currentUserRank;
  }

  /// Raid protection and safety actions: the moderators who review who
  /// joins, and those who run the circle.
  bool get canRunSafetyActions =>
      can(CirclePermission.kickMembers) || can(CirclePermission.manageCircle);
}

void openMemberToolsScreen(BuildContext context, String circleId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => MemberToolsScreen(circleId: circleId),
    ),
  );
}

/// Circle settings → Members: find members by when they joined, how old their
/// account is, how much they have said, a role or a flag, then act on many
/// at once.
class MemberToolsScreen extends ConsumerStatefulWidget {
  const MemberToolsScreen({required this.circleId, this.now, super.key});

  final String circleId;
  final DateTime Function()? now;

  @override
  ConsumerState<MemberToolsScreen> createState() => _MemberToolsScreenState();
}

class _MemberToolsScreenState extends ConsumerState<MemberToolsScreen> {
  static const _pageSize = 50;

  final _search = TextEditingController();
  Timer? _debounce;
  var _filter = const ModMemberFilter();
  var _members = <ModMember>[];
  var _total = 0;
  var _loading = true;
  var _loadingMore = false;
  Object? _error;
  var _selecting = false;
  final _selected = <String>{};
  var _acting = false;
  var _requestId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final requestId = ++_requestId;
    setState(() {
      _error = null;
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
    });
    try {
      final page = await ref
          .read(modToolsRepositoryProvider)
          .listMembers(
            widget.circleId,
            _filter,
            limit: _pageSize,
            offset: more ? _members.length : 0,
          );
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() {
        _members = more ? [..._members, ...page.members] : page.members;
        _total = page.total;
        _loading = false;
        _loadingMore = false;
        _selected.removeWhere(
          (id) => !_members.any((member) => member.userId == id),
        );
      });
    } on Object catch (error) {
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _setFilter(ModMemberFilter filter) {
    _filter = filter;
    _selected.clear();
    unawaited(_load());
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted && text.trim() != _filter.query) {
        _setFilter(_filter.copyWith(query: text.trim()));
      }
    });
  }

  Future<void> _openFilters(CircleDetail? detail) async {
    final next = await showWeCordSheet<ModMemberFilter>(
      context,
      title: tr('Filter members'),
      detents: const [0.6, 0.92],
      builder: (context, controller) => _FilterSheet(
        initial: _filter,
        roles: [
          for (final role in detail?.roles ?? const <CircleRole>[])
            if (!role.isDefault) role,
        ],
        controller: controller,
      ),
    );
    if (next != null && mounted) {
      _setFilter(next);
    }
  }

  void _toggle(ModMember member) {
    setState(() {
      if (_selected.contains(member.userId)) {
        _selected.remove(member.userId);
      } else if (_selected.length < modBatchLimit) {
        _selected.add(member.userId);
      } else {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              tr('You can choose up to {count} members at a time.', {
                'count': modBatchLimit,
              }),
            ),
          ),
        );
      }
    });
  }

  void _selectAll() {
    setState(() {
      final all = [
        for (final member in _members)
          if (member.actionable) member.userId,
      ].take(modBatchLimit);
      if (_selected.length == all.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(all);
      }
    });
  }

  List<ModMember> get _chosen => [
    for (final member in _members)
      if (_selected.contains(member.userId)) member,
  ];

  Future<void> _run(
    BatchAction action, {
    int? seconds,
    String? reason,
    required String doneMessage,
  }) async {
    final ids = _selected.toList();
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _acting = true);
    try {
      final outcome = await ref
          .read(modToolsRepositoryProvider)
          .batch(
            widget.circleId,
            ids,
            action,
            seconds: seconds,
            reason: reason,
          );
      ref.invalidate(circleDetailProvider(widget.circleId));
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            outcome.allDone
                ? doneMessage
                : tr(
                    'Done for {done} of {total}. The others could not be changed.',
                    {'done': outcome.done, 'total': outcome.requested},
                  ),
          ),
        ),
      );
      if (mounted) {
        setState(() {
          _selected.clear();
          _selecting = false;
        });
      }
      await _load();
    } on Object {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not do that. Try again.'))),
      );
    } finally {
      if (mounted) {
        setState(() => _acting = false);
      }
    }
  }

  Future<void> _timeout() async {
    final duration = await showCircleDialog<Duration>(
      context,
      builder: (context) => CircleDialog(
        title: tr('Time out {count} members', {'count': _selected.length}),
        message: tr(
          "They can still read, but can't send messages, react, start "
          'threads or join voice until it ends.',
        ),
        content: SettingsGroup(
          color: context.tokens.colors.well,
          separatorIndent: 14,
          children: [
            for (final (label, duration) in circleTimeoutDurations)
              SettingsRow(
                key: ValueKey('batch-timeout-${duration.inSeconds}'),
                title: tr(label),
                onTap: () => Navigator.of(context).pop(duration),
              ),
          ],
        ),
        actions: [
          CircleDialogAction(
            label: tr('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
    if (duration == null || !mounted) {
      return;
    }
    await _run(
      BatchAction.timeout,
      seconds: duration.inSeconds,
      doneMessage: tr('Timed out {count} members.', {
        'count': _selected.length,
      }),
    );
  }

  Future<void> _kick() async {
    final confirmed = await confirmCircleAction(
      context,
      title: tr('Remove {count} members?', {'count': _selected.length}),
      message: tr('They can join again with an invite.'),
      confirmLabel: tr('Remove'),
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(
      BatchAction.kick,
      doneMessage: tr('Removed {count} members.', {'count': _selected.length}),
    );
  }

  Future<void> _ban() async {
    final choice = await showCircleDialog<({String reason, Duration? length})>(
      context,
      builder: (context) => _BatchBanDialog(count: _selected.length),
    );
    if (choice == null || !mounted) {
      return;
    }
    await _run(
      BatchAction.ban,
      seconds: choice.length?.inSeconds,
      reason: choice.reason,
      doneMessage: tr('Banned {count} members.', {'count': _selected.length}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final detail = ref.watch(circleDetailProvider(widget.circleId)).value;
    final now = (widget.now ?? DateTime.now)();
    final chosen = _chosen;
    final bar = chosen.isNotEmpty;
    return CirclePageScaffold(
      title: tr('Members'),
      actions: [
        WeCordButton(
          key: const ValueKey('member-tools-select'),
          label: _selecting ? tr('Done') : tr('Select'),
          variant: WeCordButtonVariant.ghost,
          size: WeCordButtonSize.medium,
          onPressed: _members.isEmpty && !_selecting
              ? null
              : () => setState(() {
                  _selecting = !_selecting;
                  if (!_selecting) {
                    _selected.clear();
                  }
                }),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: circlePagePadding(context).copyWith(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: WeCordTextField(
                    fieldKey: const ValueKey('member-tools-search'),
                    controller: _search,
                    onPaper: true,
                    hint: tr('Search members'),
                    prefixIcon: Icons.search_rounded,
                    textInputAction: TextInputAction.search,
                    onChanged: _onSearch,
                  ),
                ),
                const SizedBox(width: 10),
                _FilterButton(
                  count: _filter.activeCount,
                  onPressed: () => unawaited(_openFilters(detail)),
                ),
              ],
            ),
          ),
          if (_filter.activeCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  _filterSummary(_filter, detail),
                  key: const ValueKey('member-tools-summary'),
                  style: TextStyle(fontSize: 13, color: c.muted, height: 1.4),
                ),
              ),
            ),
          Expanded(
            child: _loading && _members.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _members.isEmpty
                ? CircleEmptyState(
                    icon: Icons.error_outline,
                    title: tr('Could not load the members.'),
                    action: WeCordButton(
                      label: tr('Try again'),
                      onPressed: () => unawaited(_load()),
                    ),
                  )
                : _members.isEmpty
                ? CircleEmptyState(
                    key: const ValueKey('member-tools-empty'),
                    icon: Icons.people_outline,
                    title: tr('No members match.'),
                    message: _filter.activeCount > 0 || _filter.query.isNotEmpty
                        ? tr('Try fewer filters.')
                        : null,
                  )
                : ListView(
                    padding: circlePagePadding(context).copyWith(top: 8),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                        child: Text(
                          _total == 1
                              ? tr('1 member')
                              : tr('{count} members', {'count': _total}),
                          key: const ValueKey('member-tools-total'),
                          style: TextStyle(fontSize: 13, color: c.muted),
                        ),
                      ),
                      SettingsGroup(
                        separatorIndent: 66,
                        children: [
                          for (final member in _members)
                            _MemberToolsRow(
                              key: ValueKey('member-tools-${member.userId}'),
                              member: member,
                              now: now,
                              selecting: _selecting,
                              selected: _selected.contains(member.userId),
                              onTap: () {
                                if (_selecting) {
                                  if (member.actionable) {
                                    _toggle(member);
                                  }
                                } else if (detail?.canWriteModNotes ?? false) {
                                  openModNotes(
                                    context,
                                    circleId: widget.circleId,
                                    userId: member.userId,
                                    name: member.name,
                                    now: widget.now,
                                  );
                                }
                              },
                            ),
                        ],
                      ),
                      if (_members.length < _total) ...[
                        const SizedBox(height: 12),
                        Align(
                          child: WeCordButton(
                            key: const ValueKey('member-tools-more'),
                            label: tr('Show more'),
                            variant: WeCordButtonVariant.secondary,
                            loading: _loadingMore,
                            onPressed: () => unawaited(_load(more: true)),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
          ),
          if (_selecting)
            _BatchBar(
              key: const ValueKey('member-tools-bar'),
              count: chosen.length,
              busy: _acting,
              onSelectAll: _selectAll,
              onTimeout: bar && chosen.every((member) => member.canTimeout)
                  ? () => unawaited(_timeout())
                  : null,
              onKick: bar && chosen.every((member) => member.canKick)
                  ? () => unawaited(_kick())
                  : null,
              onBan: bar && chosen.every((member) => member.canBan)
                  ? () => unawaited(_ban())
                  : null,
            ),
        ],
      ),
    );
  }
}

/// "Joined in the last 7 days · Flagged" for the active filters.
String _filterSummary(ModMemberFilter filter, CircleDetail? detail) {
  final parts = <String>[
    if (filter.joinedWithinDays case final days?)
      tr('Joined in the last {days} days', {'days': days}),
    if (filter.joinedBeforeDays case final days?)
      tr('Joined over {days} days ago', {'days': days}),
    if (filter.accountWithinDays case final days?)
      tr('Account under {days} days old', {'days': days}),
    if (filter.maxMessages == 0)
      tr('No messages')
    else if (filter.maxMessages case final max?)
      tr('Fewer than {count} messages', {'count': max + 1}),
    if (filter.minMessages case final min?)
      tr('{count} or more messages', {'count': min}),
    if (filter.roleId case final id?)
      detail?.roles
              .where((role) => role.id == id)
              .map((role) => role.name)
              .firstOrNull ??
          tr('A role'),
    if (filter.onlyFlagged) tr('Flagged'),
  ];
  return parts.join(' · ');
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          key: const ValueKey('member-tools-filter'),
          tooltip: count == 0
              ? tr('Filters')
              : tr('Filters, {count} on', {'count': count}),
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: c.panel,
            foregroundColor: c.ink,
            fixedSize: const Size.square(48),
            minimumSize: const Size.square(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
              side: BorderSide(color: c.line),
            ),
          ),
          icon: const Icon(Icons.tune_rounded),
        ),
        if (count > 0)
          PositionedDirectional(
            end: -4,
            top: -4,
            child: CountBadge(count: count, tone: BadgeTone.quiet, size: 18),
          ),
      ],
    );
  }
}

/// One member: avatar, name, and what a moderator weighs.
class _MemberToolsRow extends StatelessWidget {
  const _MemberToolsRow({
    required this.member,
    required this.now,
    required this.selecting,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final ModMember member;
  final DateTime now;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final account = member.accountCreatedAt;
    final newAccount = account != null && now.difference(account).inDays < 7;
    final details = [
      '@${member.username}',
      tr('Joined {time}', {'time': formatAuditTime(member.joinedAt, now: now)}),
      member.messageCount == 1
          ? tr('1 message')
          : tr('{count} messages', {'count': member.messageCount}),
    ].join(' · ');
    final tags = <Widget>[
      if (member.flagged)
        CircleTag(
          label: tr('Flagged'),
          background: c.dangerSoft,
          foreground: c.dangerText,
        ),
      if (member.warningCount > 0)
        CircleTag(
          label: member.warningCount == 1
              ? tr('1 warning')
              : tr('{count} warnings', {'count': member.warningCount}),
          background: c.warningSoft,
          foreground: c.warningText,
        ),
      if (newAccount)
        CircleTag(
          label: tr('New account'),
          background: c.well,
          foreground: c.muted,
        ),
      if (member.timedOutUntil != null)
        CircleTag(
          label: tr('Timed out'),
          background: c.well,
          foreground: c.muted,
        ),
    ];
    final disabled = selecting && !member.actionable;
    return Semantics(
      container: true,
      selected: selected,
      label: [
        member.name,
        details,
        if (member.flagged) tr('Flagged'),
        if (member.warningCount > 0)
          tr('{count} warnings', {'count': member.warningCount}),
        if (selecting && !member.actionable)
          tr('You cannot act on this member'),
      ].join(', '),
      child: InkWell(
        onTap: disabled ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Opacity(
            opacity: disabled ? 0.5 : 1,
            child: Row(
              children: [
                if (selecting) ...[
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 24,
                    color: selected ? c.accent : c.track,
                  ),
                  const SizedBox(width: 10),
                ],
                CircleNetworkAvatar(
                  name: member.name,
                  url: member.avatarUrl,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        member.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        details,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: c.muted),
                      ),
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Wrap(spacing: 6, runSpacing: 4, children: tags),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar at the bottom while choosing members.
class _BatchBar extends StatelessWidget {
  const _BatchBar({
    required this.count,
    required this.busy,
    required this.onSelectAll,
    required this.onTimeout,
    required this.onKick,
    required this.onBan,
    super.key,
  });

  final int count;
  final bool busy;
  final VoidCallback onSelectAll;
  final VoidCallback? onTimeout;
  final VoidCallback? onKick;
  final VoidCallback? onBan;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Material(
      color: c.panel,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.line)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      count == 0
                          ? tr('Choose members')
                          : count == 1
                          ? tr('1 chosen')
                          : tr('{count} chosen', {'count': count}),
                      key: const ValueKey('member-tools-chosen'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                  ),
                  WeCordButton(
                    key: const ValueKey('member-tools-select-all'),
                    label: tr('Select all'),
                    variant: WeCordButtonVariant.ghost,
                    size: WeCordButtonSize.small,
                    onPressed: onSelectAll,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  WeCordButton(
                    key: const ValueKey('member-tools-timeout'),
                    label: tr('Time out'),
                    variant: WeCordButtonVariant.secondary,
                    loading: busy,
                    onPressed: busy ? null : onTimeout,
                  ),
                  WeCordButton(
                    key: const ValueKey('member-tools-kick'),
                    label: tr('Remove'),
                    variant: WeCordButtonVariant.secondary,
                    onPressed: busy ? null : onKick,
                  ),
                  WeCordButton(
                    key: const ValueKey('member-tools-ban'),
                    label: tr('Ban'),
                    variant: WeCordButtonVariant.danger,
                    onPressed: busy ? null : onBan,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reason and length for banning a selection.
class _BatchBanDialog extends StatefulWidget {
  const _BatchBanDialog({required this.count});

  final int count;

  @override
  State<_BatchBanDialog> createState() => _BatchBanDialogState();
}

class _BatchBanDialogState extends State<_BatchBanDialog> {
  final _reason = TextEditingController();
  Duration? _length;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CircleDialog(
      title: tr('Ban {count} members', {'count': widget.count}),
      message: tr(
        'Remove them from this circle and keep them from rejoining, even '
        'with an invite.',
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          BanDurationPicker(
            selected: _length,
            onChanged: (length) => setState(() => _length = length),
          ),
          const SizedBox(height: 16),
          WeCordTextField(
            fieldKey: const ValueKey('batch-ban-reason'),
            controller: _reason,
            maxLength: 512,
            maxLines: 3,
            minLines: 1,
            label: tr('Reason (optional)'),
            helperText: tr('Only moderators see it.'),
          ),
        ],
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.danger(
          key: const ValueKey('batch-ban-confirm'),
          label: tr('Ban'),
          onPressed: () => Navigator.of(
            context,
          ).pop((reason: _reason.text.trim(), length: _length)),
        ),
      ],
    );
  }
}

/// The filter choices as a sheet; pops the new filter.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initial,
    required this.roles,
    required this.controller,
  });

  final ModMemberFilter initial;
  final List<CircleRole> roles;
  final ScrollController? controller;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ModMemberFilter _filter = widget.initial;

  Widget _group(String header, List<Widget> rows) {
    return SettingsGroup(header: header, separatorIndent: 14, children: rows);
  }

  Widget _option({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final c = context.tokens.colors;
    return SettingsRow(
      key: key,
      title: label,
      showChevron: false,
      trailing: selected
          ? Icon(Icons.check_rounded, size: 20, color: c.accentText)
          : null,
      onTap: () => setState(onTap),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = _filter;
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: widget.controller,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              _group(tr('Joined'), [
                _option(
                  key: const ValueKey('filter-joined-any'),
                  label: tr('Any time'),
                  selected:
                      f.joinedWithinDays == null && f.joinedBeforeDays == null,
                  onTap: () => _filter = _filter.copyWith(
                    joinedWithinDays: null,
                    joinedBeforeDays: null,
                  ),
                ),
                _option(
                  key: const ValueKey('filter-joined-7'),
                  label: tr('In the last 7 days'),
                  selected: f.joinedWithinDays == 7,
                  onTap: () => _filter = _filter.copyWith(
                    joinedWithinDays: 7,
                    joinedBeforeDays: null,
                  ),
                ),
                _option(
                  key: const ValueKey('filter-joined-30'),
                  label: tr('In the last 30 days'),
                  selected: f.joinedWithinDays == 30,
                  onTap: () => _filter = _filter.copyWith(
                    joinedWithinDays: 30,
                    joinedBeforeDays: null,
                  ),
                ),
                _option(
                  key: const ValueKey('filter-joined-old'),
                  label: tr('More than 30 days ago'),
                  selected: f.joinedBeforeDays == 30,
                  onTap: () => _filter = _filter.copyWith(
                    joinedWithinDays: null,
                    joinedBeforeDays: 30,
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              _group(tr('Account age'), [
                _option(
                  key: const ValueKey('filter-account-any'),
                  label: tr('Any age'),
                  selected: f.accountWithinDays == null,
                  onTap: () =>
                      _filter = _filter.copyWith(accountWithinDays: null),
                ),
                _option(
                  key: const ValueKey('filter-account-7'),
                  label: tr('Under 7 days old'),
                  selected: f.accountWithinDays == 7,
                  onTap: () => _filter = _filter.copyWith(accountWithinDays: 7),
                ),
                _option(
                  key: const ValueKey('filter-account-30'),
                  label: tr('Under 30 days old'),
                  selected: f.accountWithinDays == 30,
                  onTap: () =>
                      _filter = _filter.copyWith(accountWithinDays: 30),
                ),
              ]),
              const SizedBox(height: 12),
              _group(tr('Messages in the circle'), [
                _option(
                  key: const ValueKey('filter-messages-any'),
                  label: tr('Any number'),
                  selected: f.minMessages == null && f.maxMessages == null,
                  onTap: () => _filter = _filter.copyWith(
                    minMessages: null,
                    maxMessages: null,
                  ),
                ),
                _option(
                  key: const ValueKey('filter-messages-none'),
                  label: tr('None'),
                  selected: f.maxMessages == 0,
                  onTap: () => _filter = _filter.copyWith(
                    minMessages: null,
                    maxMessages: 0,
                  ),
                ),
                _option(
                  key: const ValueKey('filter-messages-few'),
                  label: tr('Fewer than 5'),
                  selected: f.maxMessages == 4,
                  onTap: () => _filter = _filter.copyWith(
                    minMessages: null,
                    maxMessages: 4,
                  ),
                ),
                _option(
                  key: const ValueKey('filter-messages-many'),
                  label: tr('5 or more'),
                  selected: f.minMessages == 5,
                  onTap: () => _filter = _filter.copyWith(
                    minMessages: 5,
                    maxMessages: null,
                  ),
                ),
              ]),
              if (widget.roles.isNotEmpty) ...[
                const SizedBox(height: 12),
                _group(tr('Role'), [
                  _option(
                    key: const ValueKey('filter-role-any'),
                    label: tr('Any role'),
                    selected: f.roleId == null,
                    onTap: () => _filter = _filter.copyWith(roleId: null),
                  ),
                  for (final role in widget.roles)
                    _option(
                      key: ValueKey('filter-role-${role.id}'),
                      label: role.name,
                      selected: f.roleId == role.id,
                      onTap: () => _filter = _filter.copyWith(roleId: role.id),
                    ),
                ]),
              ],
              const SizedBox(height: 12),
              SettingsGroup(
                separatorIndent: 14,
                children: [
                  SettingsRow.toggle(
                    key: const ValueKey('filter-flagged'),
                    title: tr('Flagged only'),
                    subtitle: tr(
                      'A warning, an open report, or a message the AI guard '
                      'held or flagged.',
                    ),
                    value: f.onlyFlagged,
                    onChanged: (on) => setState(
                      () => _filter = _filter.copyWith(onlyFlagged: on),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: WeCordButton(
                  key: const ValueKey('filter-reset'),
                  label: tr('Reset'),
                  variant: WeCordButtonVariant.secondary,
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(ModMemberFilter(query: widget.initial.query)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WeCordButton(
                  key: const ValueKey('filter-apply'),
                  label: tr('Apply'),
                  onPressed: () => Navigator.of(context).pop(_filter),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
