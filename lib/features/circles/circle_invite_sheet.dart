import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_invite_link.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_invite.dart';

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
    final existingMemberIds = {
      for (final member in widget.detail.members) member.profile.id,
    };
    final friendsFuture = ref.watch(contactsRepositoryProvider).listFriends();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder(
          future: friendsFuture,
          builder: (context, snapshot) {
            final friends = (snapshot.data ?? [])
                .where((friend) => !existingMemberIds.contains(friend.id))
                .toList(growable: false);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Invite friends'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (friends.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(tr('No friends to invite')),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final friend in friends)
                          CheckboxListTile(
                            value: _selectedFriendIds.contains(friend.id),
                            title: Text(friend.displayLabel),
                            subtitle: Text('@${friend.username}'),
                            onChanged: _isSaving
                                ? null
                                : (selected) {
                                    setState(() {
                                      if (selected == true) {
                                        _selectedFriendIds.add(friend.id);
                                      } else {
                                        _selectedFriendIds.remove(friend.id);
                                      }
                                    });
                                  },
                          ),
                      ],
                    ),
                  ),
                if (_errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _isSaving || _selectedFriendIds.isEmpty
                        ? null
                        : _invite,
                    child: Text(tr('Invite')),
                  ),
                ),
                const Divider(height: 32),
                CircleInviteLinksSection(circleId: widget.detail.circle.id),
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

String _maxUsesLabel(int? maxUses) {
  return switch (maxUses) {
    null => tr('No limit'),
    1 => tr('1 use'),
    _ => tr('{count} uses', {'count': maxUses}),
  };
}

/// Create, copy, list and revoke shareable invite links for a circle.
class CircleInviteLinksSection extends ConsumerStatefulWidget {
  const CircleInviteLinksSection({required this.circleId, super.key});

  final String circleId;

  @override
  ConsumerState<CircleInviteLinksSection> createState() =>
      _CircleInviteLinksSectionState();
}

class _CircleInviteLinksSectionState
    extends ConsumerState<CircleInviteLinksSection> {
  late Future<List<CircleInvite>> _invites;
  var _expiry = _InviteExpiry.sevenDays;
  int? _maxUses;
  var _isBusy = false;
  String? _copiedCode;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _invites = _loadInvites();
  }

  Future<List<CircleInvite>> _loadInvites() {
    return ref.read(circlesRepositoryProvider).listInvites(widget.circleId);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Invite links'), style: textTheme.titleMedium),
        const SizedBox(height: 12),
        Text(tr('Expire after'), style: textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final expiry in _InviteExpiry.values)
              ChoiceChip(
                label: Text(tr(expiry.label)),
                selected: _expiry == expiry,
                onSelected: _isBusy
                    ? null
                    : (_) => setState(() => _expiry = expiry),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(tr('Max uses'), style: textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final maxUses in _maxUsesOptions)
              ChoiceChip(
                label: Text(_maxUsesLabel(maxUses)),
                selected: _maxUses == maxUses,
                onSelected: _isBusy
                    ? null
                    : (_) => setState(() => _maxUses = maxUses),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: _isBusy ? null : _createInvite,
          icon: const Icon(Icons.add_link),
          label: Text(tr('Create link')),
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorText!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 8),
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
              );
            }
            final invites = snapshot.data ?? const <CircleInvite>[];
            if (invites.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(tr('No active invite links')),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final invite in invites)
                  ListTile(
                    key: ValueKey('circle-invite-${invite.code}'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.link),
                    title: Text(
                      circleInviteLink(invite.code),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(_inviteDetails(invite)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: _copiedCode == invite.code
                              ? tr('Copied')
                              : tr('Copy link'),
                          icon: Icon(
                            _copiedCode == invite.code
                                ? Icons.check
                                : Icons.copy,
                          ),
                          onPressed: () => _copy(invite),
                        ),
                        IconButton(
                          tooltip: tr('Revoke'),
                          icon: const Icon(Icons.link_off),
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
      final code = await ref
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
        _errorText = '$failure $error';
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
