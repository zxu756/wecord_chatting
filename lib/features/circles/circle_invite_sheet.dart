import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_invite_link.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/join_requests/join_requests_repository.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_invite.dart';
import 'package:wecord/shared/ui/ui.dart';

class CircleInviteSheet extends ConsumerStatefulWidget {
  const CircleInviteSheet({required this.detail, super.key});

  final CircleDetail detail;

  @override
  ConsumerState<CircleInviteSheet> createState() => _CircleInviteSheetState();
}

class _CircleInviteSheetState extends ConsumerState<CircleInviteSheet> {
  final _selectedFriendIds = <String>{};
  var _isSaving = false;
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final existingMemberIds = {
      for (final member in widget.detail.members) member.profile.id,
    };
    final friendsFuture = ref.watch(contactsRepositoryProvider).listFriends();
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: FutureBuilder(
          future: friendsFuture,
          builder: (context, snapshot) {
            final friends = (snapshot.data ?? [])
                .where((friend) => !existingMemberIds.contains(friend.id))
                .toList(growable: false);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    tr('Invite friends'),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: c.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.detail.circle.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: c.muted),
                ),
                const SizedBox(height: 14),
                if (friends.isEmpty)
                  CircleCard(
                    color: c.well,
                    child: Text(
                      tr('No friends to invite'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: c.muted),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: SettingsGroup(
                      color: c.well,
                      children: [
                        Flexible(
                          child: ListView(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            children: [
                              for (final friend in friends)
                                CircleFriendPickRow(
                                  friend: friend,
                                  selected: _selectedFriendIds.contains(
                                    friend.id,
                                  ),
                                  onChanged: _isSaving
                                      ? null
                                      : (selected) => setState(() {
                                          if (selected) {
                                            _selectedFriendIds.add(friend.id);
                                          } else {
                                            _selectedFriendIds.remove(
                                              friend.id,
                                            );
                                          }
                                        }),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _errorText!,
                    style: TextStyle(fontSize: 13, color: c.dangerText),
                  ),
                ],
                if (friends.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  WeCordButton(
                    label: tr('Invite'),
                    expand: true,
                    loading: _isSaving,
                    onPressed: _isSaving || _selectedFriendIds.isEmpty
                        ? null
                        : _invite,
                  ),
                ],
                const SizedBox(height: 8),
                CircleInviteLinksSection(
                  circleId: widget.detail.circle.id,
                  canSkipReview: widget.detail.canSkipJoinReview,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _invite() async {
    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    try {
      await ref
          .read(circlesRepositoryProvider)
          .inviteMembers(
            circleId: widget.detail.circle.id,
            memberIds: _selectedFriendIds.toList(growable: false),
          );
      ref.invalidate(circleDetailProvider(widget.detail.circle.id));
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = tr('Could not invite friends. Try again. {error}', {
          'error': error,
        });
      });
    }
  }
}

enum _InviteExpiry {
  oneDay('1 day', Duration(days: 1)),
  sevenDays('7 days', Duration(days: 7)),
  never('Never', null);

  const _InviteExpiry(this.label, this.duration);

  final String label;
  final Duration? duration;
}

const _maxUsesOptions = <int?>[null, 1, 10, 100];

/// Create, copy, list and revoke shareable invite links for a circle.
class CircleInviteLinksSection extends ConsumerStatefulWidget {
  const CircleInviteLinksSection({
    required this.circleId,
    this.canSkipReview = false,
    super.key,
  });

  final String circleId;

  /// The member may make links that skip review (create_invites and
  /// kick_members).
  final bool canSkipReview;

  @override
  ConsumerState<CircleInviteLinksSection> createState() =>
      _CircleInviteLinksSectionState();
}

class _CircleInviteLinksSectionState
    extends ConsumerState<CircleInviteLinksSection> {
  late Future<List<CircleInvite>> _invites;
  var _expiry = _InviteExpiry.sevenDays;
  int? _maxUses;
  var _skipReview = false;

  /// The codes of the links that skip review (only read for members who
  /// may make such links).
  var _skipping = <String>{};
  var _isBusy = false;
  String? _copiedCode;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _invites = _loadInvites();
  }

  Future<List<CircleInvite>> _loadInvites() async {
    final invites = await ref
        .read(circlesRepositoryProvider)
        .listInvites(widget.circleId);
    if (widget.canSkipReview) {
      try {
        _skipping = await ref
            .read(joinRequestsRepositoryProvider)
            .invitesSkippingReview(widget.circleId);
      } on Object {
        // The links still show; only their "skips review" mark is missing.
      }
    }
    return invites;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    TextStyle label() =>
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.muted);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(tr('Invite links')),
        CircleCard(
          color: c.well,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Expire after'), style: label()),
              const SizedBox(height: 6),
              WeCordSegmented<_InviteExpiry>(
                expand: true,
                height: 36,
                selected: _expiry,
                onChanged: _isBusy
                    ? null
                    : (expiry) => setState(() => _expiry = expiry),
                segments: [
                  for (final expiry in _InviteExpiry.values)
                    WeCordSegment(value: expiry, label: tr(expiry.label)),
                ],
              ),
              const SizedBox(height: 12),
              Text(tr('Max uses'), style: label()),
              const SizedBox(height: 6),
              WeCordSegmented<int?>(
                expand: true,
                height: 36,
                selected: _maxUses,
                onChanged: _isBusy
                    ? null
                    : (maxUses) => setState(() => _maxUses = maxUses),
                segments: [
                  for (final maxUses in _maxUsesOptions)
                    WeCordSegment(
                      value: maxUses,
                      label: maxUses == null ? tr('No limit') : '$maxUses',
                    ),
                ],
              ),
              if (widget.canSkipReview) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('Skip review'),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tr(
                              'People who use this link join at once, even '
                              'when the circle reviews who joins.',
                            ),
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: c.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    WeCordSwitch(
                      key: const ValueKey('invite-skip-review'),
                      semanticLabel: tr('Skip review'),
                      value: _skipReview,
                      onChanged: _isBusy
                          ? null
                          : (value) => setState(() => _skipReview = value),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              WeCordButton(
                variant: WeCordButtonVariant.secondary,
                icon: Icons.add_link_rounded,
                label: tr('Create link'),
                onPressed: _isBusy ? null : _createInvite,
              ),
            ],
          ),
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorText!,
            style: TextStyle(fontSize: 13, color: c.dangerText),
          ),
        ],
        const SizedBox(height: 12),
        FutureBuilder<List<CircleInvite>>(
          future: _invites,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Text(
                tr('Could not load invite links. {error}', {
                  'error': snapshot.error,
                }),
                style: TextStyle(fontSize: 13, color: c.dangerText),
              );
            }
            final invites = snapshot.data ?? const <CircleInvite>[];
            if (invites.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  tr('No active invite links'),
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              );
            }
            return SettingsGroup(
              color: c.well,
              children: [
                for (final invite in invites)
                  SettingsRow(
                    key: ValueKey('circle-invite-${invite.code}'),
                    icon: Icons.link_rounded,
                    tone: SettingsTone.accent,
                    title: circleInviteLink(invite.code),
                    subtitle: _skipping.contains(invite.code)
                        ? '${_inviteDetails(invite)} · ${tr('skips review')}'
                        : _inviteDetails(invite),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        WeCordIconButton(
                          tooltip: _copiedCode == invite.code
                              ? tr('Copied')
                              : tr('Copy link'),
                          icon: _copiedCode == invite.code
                              ? Icons.check_rounded
                              : Icons.copy_rounded,
                          size: 34,
                          variant: WeCordButtonVariant.ghost,
                          onPressed: () => _copy(invite),
                        ),
                        WeCordIconButton(
                          tooltip: tr('Revoke'),
                          icon: Icons.link_off_rounded,
                          size: 34,
                          variant: WeCordButtonVariant.ghost,
                          onPressed: _isBusy ? null : () => _revoke(invite),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _createInvite() async {
    await _run(() async {
      final code = widget.canSkipReview && _skipReview
          ? await ref
                .read(joinRequestsRepositoryProvider)
                .createInvite(
                  circleId: widget.circleId,
                  skipReview: true,
                  expiresIn: _expiry.duration,
                  maxUses: _maxUses,
                )
          : await ref
                .read(circlesRepositoryProvider)
                .createInvite(
                  circleId: widget.circleId,
                  expiresIn: _expiry.duration,
                  maxUses: _maxUses,
                );
      await Clipboard.setData(ClipboardData(text: circleInviteLink(code)));
      _copiedCode = code;
    }, failure: tr('Could not create invite link.'));
  }

  Future<void> _revoke(CircleInvite invite) async {
    await _run(
      () => ref.read(circlesRepositoryProvider).revokeInvite(invite.code),
      failure: tr('Could not revoke invite link.'),
    );
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String failure,
  }) async {
    setState(() {
      _isBusy = true;
      _errorText = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _invites = _loadInvites();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _errorText = '$failure ${errorText(error)}';
      });
    }
  }

  Future<void> _copy(CircleInvite invite) async {
    await Clipboard.setData(ClipboardData(text: circleInviteLink(invite.code)));
    if (mounted) setState(() => _copiedCode = invite.code);
  }
}

String _inviteDetails(CircleInvite invite) {
  final uses = invite.maxUses == null
      ? tr('{count} uses', {'count': invite.useCount})
      : tr('{count} / {max} uses', {
          'count': invite.useCount,
          'max': invite.maxUses,
        });
  final expiresAt = invite.expiresAt;
  final String expiry;
  if (expiresAt == null) {
    expiry = tr('never expires');
  } else {
    final remaining = expiresAt.difference(DateTime.now().toUtc());
    expiry = remaining.inDays >= 1
        ? tr('expires in {days} d', {'days': remaining.inDays})
        : remaining.inHours >= 1
        ? tr('expires in {hours} h', {'hours': remaining.inHours})
        : tr('expires in < 1 h');
  }
  return tr('Code {code} · {uses} · {expiry}', {
    'code': invite.code,
    'uses': uses,
    'expiry': expiry,
  });
}
