import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart'
    show SendRefusedException;
import 'package:wecord/features/chats/sheet_rows.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/contact_cards/contact_card_models.dart';
import 'package:wecord/features/contact_cards/contact_cards_repository.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/home/home_avatars.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Whether the current user may invite people to [circle], and so share it
/// as a card (the server checks Create invites, owners always may).
bool canShareCircle(CircleSummary circle) {
  if (circle.currentUserRole == 'owner') {
    return true;
  }
  final permissions = circle.currentUserPermissions;
  if (permissions != null) {
    return CirclePermission.createInvites.isGrantedBy(permissions);
  }
  return circle.currentUserRole == 'admin';
}

/// Opens the contact card picker over a chat: a friend or a circle the
/// user can invite to. Sends the card on a tap; true when it was sent.
Future<bool?> showContactCardPicker(
  BuildContext context, {
  required String conversationId,
}) {
  return showWeCordSheet<bool>(
    context,
    title: tr('Contact card'),
    builder: (context, _) => ContactCardPicker(conversationId: conversationId),
  );
}

enum _PickerTab { friends, circles }

class ContactCardPicker extends ConsumerStatefulWidget {
  const ContactCardPicker({required this.conversationId, super.key});

  final String conversationId;

  @override
  ConsumerState<ContactCardPicker> createState() => _ContactCardPickerState();
}

class _ContactCardPickerState extends ConsumerState<ContactCardPicker> {
  var _tab = _PickerTab.friends;
  var _query = '';
  var _sending = false;
  String? _errorText;

  Future<void> _send(ContactCardKind kind, String targetId) async {
    if (_sending) {
      return;
    }
    setState(() {
      _sending = true;
      _errorText = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(contactCardsRepositoryProvider)
          .send(
            conversationId: widget.conversationId,
            kind: kind,
            targetId: targetId,
          );
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger?.showSnackBar(SnackBar(content: Text(tr('Contact card sent'))));
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sending = false;
        _errorText =
            error is ContactCardRefusedException ||
                error is SendRefusedException
            ? error.toString()
            : tr('Could not send the contact card. Try again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final friends = ref.watch(friendsProvider);
    final circles = ref.watch(circleSummariesProvider);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.min(
              600,
              (MediaQuery.sizeOf(context).height - keyboard) * 0.85,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: WeCordSegmented<_PickerTab>(
                  expand: true,
                  semanticLabel: tr('Contact card'),
                  selected: _tab,
                  onChanged: (tab) => setState(() {
                    _tab = tab;
                    _query = '';
                  }),
                  segments: [
                    WeCordSegment(
                      key: const ValueKey('contact-card-tab-friends'),
                      value: _PickerTab.friends,
                      label: tr('Friends'),
                    ),
                    WeCordSegment(
                      key: const ValueKey('contact-card-tab-circles'),
                      value: _PickerTab.circles,
                      label: tr('Circles'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Semantics(
                  label: _tab == _PickerTab.friends
                      ? tr('Search friends')
                      : tr('Search circles'),
                  textField: true,
                  child: WeCordTextField(
                    key: ValueKey('contact-card-search-${_tab.name}'),
                    fieldKey: const ValueKey('contact-card-search'),
                    hint: _tab == _PickerTab.friends
                        ? tr('Search friends')
                        : tr('Search circles'),
                    prefixIcon: Icons.search_rounded,
                    textInputAction: TextInputAction.search,
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
              ),
              if (_errorText != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(
                    _errorText!,
                    style: TextStyle(fontSize: 13.5, color: c.dangerText),
                  ),
                ),
              Flexible(
                child: _tab == _PickerTab.friends
                    ? friends.when(
                        loading: () => const SheetSpinner(),
                        error: (error, stackTrace) => SheetNote(
                          text: tr('Could not load friends.'),
                          error: true,
                        ),
                        data: _friendList,
                      )
                    : circles.when(
                        loading: () => const SheetSpinner(),
                        error: (error, stackTrace) => SheetNote(
                          text: tr('Could not load circles.'),
                          error: true,
                        ),
                        data: _circleList,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _friendList(List<Profile> friends) {
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final friend in friends)
        if (query.isEmpty ||
            friend.displayLabel.toLowerCase().contains(query) ||
            friend.displayName.toLowerCase().contains(query) ||
            friend.username.toLowerCase().contains(query))
          friend,
    ];
    if (shown.isEmpty) {
      return SheetNote(
        text: friends.isEmpty
            ? tr('No friends yet')
            : tr('No matching friends'),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      itemCount: shown.length,
      itemBuilder: (context, index) {
        final friend = shown[index];
        return SheetListRow(
          key: ValueKey('contact-card-friend-${friend.id}'),
          enabled: !_sending,
          leading: ResolvedAvatar(
            name: friend.displayLabel,
            avatarUrl: friend.avatarUrl,
            size: 40,
          ),
          title: friend.displayLabel,
          subtitle: '@${friend.username}',
          trailing: Icon(
            Icons.send_rounded,
            size: 18,
            color: context.tokens.colors.faint,
          ),
          onTap: () => unawaited(_send(ContactCardKind.user, friend.id)),
        );
      },
    );
  }

  Widget _circleList(List<CircleSummary> circles) {
    final query = _query.trim().toLowerCase();
    final invitable = [
      for (final circle in circles)
        if (canShareCircle(circle)) circle,
    ];
    final shown = [
      for (final circle in invitable)
        if (query.isEmpty || circle.name.toLowerCase().contains(query)) circle,
    ];
    if (shown.isEmpty) {
      return SheetNote(
        text: invitable.isEmpty
            ? tr('You are not in a circle you can invite people to.')
            : tr('No matching circles'),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      itemCount: shown.length,
      itemBuilder: (context, index) {
        final circle = shown[index];
        return SheetListRow(
          key: ValueKey('contact-card-circle-${circle.id}'),
          enabled: !_sending,
          leading: ResolvedAvatar(
            name: circle.name,
            avatarUrl: circle.avatarUrl,
            size: 40,
            squircle: true,
          ),
          title: circle.name,
          subtitle: circle.memberCount == 1
              ? tr('1 member')
              : tr('{count} members', {'count': circle.memberCount}),
          trailing: Icon(
            Icons.send_rounded,
            size: 18,
            color: context.tokens.colors.faint,
          ),
          onTap: () => unawaited(_send(ContactCardKind.circle, circle.id)),
        );
      },
    );
  }
}
