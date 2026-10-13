import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_channel_sidebar.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import 'phone_test_support.dart';

/// Lays out every screen, sheet and dialog with realistic data on phone
/// sizes. Any overflow fails the test.
void main() {
  Future<PhoneWorld> openChat(
    WidgetTester tester, {
    String id = 'dm-1',
    String? title,
    ConversationType type = ConversationType.direct,
    bool withThread = false,
  }) async {
    final world = PhoneWorld();
    world.chats.messages = richMessages(withThread: withThread);
    await world.open(
      tester,
      '${ChatsScreen.path}/$id',
      extra: ChatThreadRouteExtra(title: title ?? bart.displayName, type: type),
    );
    return world;
  }

  Future<PhoneWorld> openCircleChannel(
    WidgetTester tester, {
    String conversationId = 'conv-general',
    String title = '# general',
    ConversationType type = ConversationType.channel,
  }) async {
    final world = PhoneWorld();
    world.chats.messages = richMessages(withThread: true);
    await world.open(
      tester,
      '/circles/circle-1/channels/$conversationId',
      extra: ChatThreadRouteExtra(
        title: title,
        type: type,
        circleId: 'circle-1',
      ),
    );
    return world;
  }

  Future<void> openMoreMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
  }

  Future<void> dismissPopup(WidgetTester tester) async {
    await tester.tapAt(const Offset(4, 400));
    await settle(tester);
  }

  /// Scrolls the message list from the newest message up until [finder] is
  /// built, then brings its first match on screen.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final list = find.byKey(const ValueKey('chat-message-list'));
    await tester.drag(list, const Offset(0, -5000));
    await tester.pump();
    for (var step = 0; step < 40 && finder.evaluate().isEmpty; step++) {
      await tester.drag(list, const Offset(0, 150));
      await tester.pump();
    }
    await tester.ensureVisible(finder.first);
    await settle(tester);
  }

  Future<void> longPressMessage(WidgetTester tester, String text) async {
    final message = find.textContaining(text, findRichText: true);
    await reveal(tester, message);
    await tester.longPress(message.first);
    await settle(tester);
  }

  group('auth', () {
    phoneTestWidgets('sign in and create account', (tester, viewport) async {
      final world = PhoneWorld()..auth.user = null;
      await pumpStandalone(tester, world, const AuthScreen());
      expect(find.text('Sign in'), findsWidgets);

      await tester.tap(find.text('Create account'));
      await settle(tester);
      expect(find.text('Username'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextFormField, 'Username'));
      await showKeyboard(tester, viewport);
      expectFullyVisible(tester, find.byType(EditableText).first);
    });
  });

  group('chats', () {
    phoneTestWidgets('chats list with long names and badges', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      await world.open(tester, ChatsScreen.path);

      expect(find.text(bart.displayName), findsOneWidget);
      expect(find.text('128'), findsOneWidget);
      expect(find.byIcon(Icons.push_pin), findsOneWidget);
      expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);

      // Phones open conversation actions with a long press.
      expect(find.byTooltip('Conversation actions'), findsNothing);
      await tester.longPress(find.text(bart.displayName));
      await settle(tester);
      expect(find.text('Unpin chat'), findsOneWidget);
    });

    phoneTestWidgets('global search', (tester, viewport) async {
      final world = PhoneWorld();
      await world.open(tester, '/search/messages');
      await tester.enterText(find.byType(TextField), 'release');
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      expect(find.text(bart.displayName), findsWidgets);
    });

    phoneTestWidgets('media screen', (tester, viewport) async {
      final world = PhoneWorld();
      await world.open(tester, '/chats/dm-1/media');
      expect(find.text('Media'), findsWidgets);
    });
  });

  group('chat thread', () {
    phoneTestWidgets('direct thread with markdown, reactions and preview', (
      tester,
      viewport,
    ) async {
      await openChat(tester);

      expect(find.byKey(const ValueKey('link-preview-card')), findsWidgets);
      await reveal(tester, find.byKey(const ValueKey('markdown-code-block')));
      expect(find.byKey(const ValueKey('markdown-quote')), findsWidgets);
      expect(find.byTooltip('Search messages'), findsOneWidget);

      // The app bar keeps two actions and a More menu on phones.
      await openMoreMenu(tester);
      expect(find.text('Media'), findsOneWidget);
      await dismissPopup(tester);

      await tester.tap(find.byTooltip('Search messages'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, 'snippet');
      await settle(tester);
      expect(find.text('1 result'), findsOneWidget);
    });

    phoneTestWidgets('app bar title ellipsizes instead of wrapping', (
      tester,
      viewport,
    ) async {
      await openChat(tester);
      final title = tester.widget<Text>(find.text(bart.displayName).first);
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(
        tester.getSize(find.text(bart.displayName).first).width,
        greaterThan(120),
      );
      final toolbarButtons = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(IconButton),
      );
      // Search, one context action and More.
      expect(toolbarButtons, findsNWidgets(3));
    });

    phoneTestWidgets('group thread with announcement and thread chip', (
      tester,
      viewport,
    ) async {
      await openChat(
        tester,
        id: 'group-1',
        title: groupDetail.title,
        type: ConversationType.group,
        withThread: true,
      );
      expect(find.textContaining('Trailhead moved'), findsOneWidget);
      await reveal(tester, find.byKey(const ValueKey('thread-chip-m2')));
      expect(find.byTooltip('Group details'), findsOneWidget);

      await openMoreMenu(tester);
      expect(find.text('Pinned messages'), findsOneWidget);
      expect(find.text('Media'), findsOneWidget);
      await dismissPopup(tester);

      await tester.tap(find.byTooltip('Group details'));
      await settle(tester);
      expect(find.text('Leave group'), findsOneWidget);
    });

    phoneTestWidgets('long-press menu, emoji picker and reactors', (
      tester,
      viewport,
    ) async {
      await openChat(tester);
      await longPressMessage(tester, 'Also this');

      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Remove embed'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      await tester.ensureVisible(find.text('Delete'));

      await tester.tap(find.byTooltip('More reactions'));
      await settle(tester);
      expect(find.text('Add reaction'), findsOneWidget);
      await tester.tap(find.text('😀'));
      await settle(tester);

      final chip = find.byKey(const ValueKey('reaction-chip-😂'));
      await reveal(tester, chip);
      await tester.longPress(chip);
      await settle(tester);
      expect(find.text('Reacted with 😂'), findsOneWidget);
    });

    phoneTestWidgets('reaction chips are touch sized', (
      tester,
      viewport,
    ) async {
      await openChat(tester);
      final chips = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'reaction-chip-',
            ),
      );
      await reveal(tester, chips);
      expectTouchTargets(tester, chips);
    });

    phoneTestWidgets('pinned messages sheet', (tester, viewport) async {
      await openChat(tester);
      await tester.tap(find.byTooltip('Pinned messages'));
      await settle(tester);
      expect(find.text('Pinned messages'), findsWidgets);
      expect(find.text('Pinned by ${me.displayName}'), findsOneWidget);
    });

    phoneTestWidgets('reply, edit and voice composer states', (
      tester,
      viewport,
    ) async {
      await openChat(tester);

      await longPressMessage(tester, 'Agreed');
      await tester.tap(find.text('Reply'));
      await settle(tester);
      expect(find.textContaining('Replying to'), findsOneWidget);
      expectTouchTargets(tester, iconButtonWithTooltip('Cancel reply'));

      await longPressMessage(tester, 'Supercalifragilistic');
      await tester.tap(find.text('Edit'));
      await settle(tester);
      expect(find.text('Editing message'), findsOneWidget);
      expectTouchTargets(tester, iconButtonWithTooltip('Cancel edit'));
      await tester.tap(find.byTooltip('Cancel edit'));
      await settle(tester);

      await tester.tap(find.byTooltip('Record voice message'));
      await settle(tester);
      expect(find.text('Recording...'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel voice message'));
      await settle(tester);
    });

    phoneTestWidgets('composer stays above the keyboard', (
      tester,
      viewport,
    ) async {
      await openChat(tester);
      await tester.tap(find.widgetWithText(TextField, 'Message'));
      await showKeyboard(tester, viewport);
      expectFullyVisible(tester, find.widgetWithText(TextField, 'Message'));
      expectFullyVisible(tester, find.byTooltip('Send'));
    });

    phoneTestWidgets('image preview and forward sheet', (
      tester,
      viewport,
    ) async {
      await openChat(tester);
      final image = find.byIcon(Icons.broken_image_outlined);
      await reveal(tester, image);
      await tester.tap(image.first);
      await settle(tester);
      expect(find.text('Image preview'), findsOneWidget);
      await popTopRoute(tester);

      await longPressMessage(tester, 'Forwarding');
      await tester.tap(find.text('Forward'));
      await settle(tester);
      expect(find.text('Forward to'), findsWidgets);
    });

    phoneTestWidgets('create thread dialog with keyboard', (
      tester,
      viewport,
    ) async {
      await openChat(
        tester,
        id: 'group-1',
        title: groupDetail.title,
        type: ConversationType.group,
      );
      await longPressMessage(tester, 'Agreed');
      await tester.tap(find.text('Create thread'));
      await settle(tester);
      expect(find.text('Create thread'), findsWidgets);
      await showKeyboard(tester, viewport);
      expectFullyVisible(
        tester,
        find.widgetWithText(TextField, 'Thread title'),
      );
      expectFullyVisible(tester, find.widgetWithText(FilledButton, 'Create'));
    });
  });

  group('chat thread typing', () {
    phoneTestWidgets('mention suggestions above the keyboard', (
      tester,
      viewport,
    ) async {
      await openChat(
        tester,
        id: 'group-1',
        title: groupDetail.title,
        type: ConversationType.group,
      );
      final composer = find.widgetWithText(TextField, 'Message');
      await tester.tap(composer);
      await tester.enterText(composer, 'Hey @');
      await showKeyboard(tester, viewport);
      expect(find.text('@ada'), findsOneWidget);
      expectFullyVisible(tester, composer);
      // At least the first suggestion fits; the rest scroll.
      expectFullyVisible(tester, find.text('@ada'));
      // The thread keeps a sliver of messages above the suggestions.
      expect(
        tester.getSize(find.byKey(const ValueKey('chat-message-list'))).height,
        greaterThan(0),
      );
      await tester.enterText(composer, '');
      await tester.pump(const Duration(seconds: 4));
    });

    phoneTestWidgets('message search above the keyboard', (
      tester,
      viewport,
    ) async {
      await openChat(tester);
      await tester.tap(find.byTooltip('Search messages'));
      await settle(tester);
      final search = find.widgetWithText(TextField, 'Search messages');
      await tester.tap(search);
      await showKeyboard(tester, viewport);
      await tester.enterText(search, 'release');
      await settle(tester);
      expectFullyVisible(tester, search);
    });

    phoneTestWidgets('group details sheet above the keyboard', (
      tester,
      viewport,
    ) async {
      await openChat(
        tester,
        id: 'group-1',
        title: groupDetail.title,
        type: ConversationType.group,
      );
      await tester.tap(find.byTooltip('Group details'));
      await settle(tester);
      final search = find.widgetWithText(TextField, 'Search members');
      await scrollIntoView(
        tester,
        search,
        scrollable: find
            .descendant(
              of: find.byType(DraggableScrollableSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(search);
      await showKeyboard(tester, viewport);
      expectCaretVisible(tester, search);
    });
  });

  group('circles', () {
    phoneTestWidgets('circles list and join dialog', (tester, viewport) async {
      final world = PhoneWorld();
      await world.open(tester, '/circles');
      expect(find.text(circleSummaries.first.name), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);

      await tester.tap(find.byTooltip('Join with invite'));
      await settle(tester);
      await showKeyboard(tester, viewport);
      expectFullyVisible(tester, find.widgetWithText(FilledButton, 'Join'));
    });

    phoneTestWidgets('circle mobile home with rail and sidebar', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      await world.open(tester, '/circles/circle-1');

      expect(find.byType(CircleRail), findsOneWidget);
      expect(find.text('general'), findsOneWidget);
      expect(
        find.text(
          'Planning the extremely long weekend trip to Yosemite Valley',
        ),
        findsOneWidget,
      );
      expect(find.text('TEXT CHANNELS'), findsOneWidget);
      expect(find.byKey(const ValueKey('circle-mention-badge')), findsWidgets);
      // The collapsed Archive category hides its quiet channel.
      expect(find.text('old-stuff'), findsNothing);

      expectTouchTargets(tester, find.byType(CircleChannelRow));
      expectTouchTargets(
        tester,
        find.descendant(
          of: find.byType(CircleCategoryHeader),
          matching: find.byType(IconButton),
        ),
      );
      expectTouchTargets(tester, find.byType(CircleRailItem));

      // Rail and sidebar clear the notch.
      expect(
        tester.getTopLeft(find.byType(CircleRail)).dy,
        greaterThanOrEqualTo(viewport.topInset),
      );

      await tester.tap(find.byTooltip('Circle menu'));
      await settle(tester);
      expect(find.text('Notification settings'), findsOneWidget);
    });

    phoneTestWidgets('circle menu sheets and dialogs', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      await world.open(tester, '/circles/circle-1');

      Future<void> fromMenu(String label) async {
        await tester.tap(find.byTooltip('Circle menu'));
        await settle(tester);
        await tester.ensureVisible(find.text(label));
        await settle(tester);
        await tester.tap(find.text(label));
        await settle(tester);
      }

      await fromMenu('Invite friends');
      expect(find.text('Create link'), findsOneWidget);
      expect(find.textContaining('h7Kq2mPz'), findsWidgets);
      await popTopRoute(tester);

      await fromMenu('Notification settings');
      expect(find.text('Unmute'), findsNothing);
      await popTopRoute(tester);

      await fromMenu('Create channel');
      await showKeyboard(tester, viewport);
      expectFullyVisible(tester, find.byType(EditableText).first);
      await popTopRoute(tester);
    });

    phoneTestWidgets('category and nickname dialogs above the keyboard', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      await world.open(tester, '/circles/circle-1');

      await tester.tap(find.byTooltip('Circle menu'));
      await settle(tester);
      await tester.tap(find.text('Create category'));
      await settle(tester);
      await showKeyboard(tester, viewport);
      expectFullyVisible(
        tester,
        find.widgetWithText(TextField, 'Category name'),
      );
      expectFullyVisible(tester, find.widgetWithText(FilledButton, 'Create'));
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      await tester.tap(find.byTooltip('Circle menu'));
      await settle(tester);
      // The menu scrolls on short screens.
      await tester.ensureVisible(find.text('Change my nickname'));
      await settle(tester);
      await tester.tap(find.text('Change my nickname'));
      await settle(tester);
      expectFullyVisible(tester, find.widgetWithText(TextField, 'Nickname'));
      expectFullyVisible(tester, find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      await tester.tap(find.byTooltip('Category options').first);
      await settle(tester);
      expect(find.text('Rename category'), findsOneWidget);
    });

    phoneTestWidgets('transfer ownership dialog above the keyboard', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      await world.open(tester, '/circles/circle-1');

      await tester.tap(find.byTooltip('Circle menu'));
      await settle(tester);
      expect(find.text('Leave circle'), findsNothing);
      await tester.ensureVisible(find.text('Transfer ownership'));
      await settle(tester);
      await tester.tap(find.text('Transfer ownership'));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('transfer-owner-user-2')));
      await settle(tester);
      final confirm = find.byKey(const ValueKey('transfer-confirm-name'));
      await tester.ensureVisible(confirm);
      await settle(tester);
      await tester.showKeyboard(confirm);
      await showKeyboard(tester, viewport);
      await tester.ensureVisible(confirm);
      await settle(tester);
      expectFullyVisible(tester, confirm);
      expectFullyVisible(tester, find.widgetWithText(FilledButton, 'Transfer'));
    });

    phoneTestWidgets('leave circle confirmation', (tester, viewport) async {
      final world = PhoneWorld();
      world.circles.detail = circleDetailWith(
        channelId: 'ch-general',
        permissions: 1 | 2 | 64 | 8192,
        isReadOnly: false,
      );
      await world.open(tester, '/circles/circle-1');

      await tester.tap(find.byTooltip('Circle menu'));
      await settle(tester);
      expect(find.text('Transfer ownership'), findsNothing);
      await tester.ensureVisible(find.text('Leave circle'));
      await settle(tester);
      await tester.tap(find.text('Leave circle'));
      await settle(tester);
      expectFullyVisible(tester, find.widgetWithText(FilledButton, 'Leave'));
    });

    phoneTestWidgets('circle the user is no longer in', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      world.circles.detailError = const CircleMembershipLostException(
        'circle-1',
      );
      await world.open(tester, '/circles/circle-1');

      expect(find.byType(CircleRail), findsOneWidget);
      expectFullyVisible(
        tester,
        find.text("You're no longer a member of this circle"),
      );
      expectFullyVisible(
        tester,
        find.widgetWithText(FilledButton, 'Back to Circles'),
      );
    });

    phoneTestWidgets('roles page and role editor', (tester, viewport) async {
      final world = PhoneWorld();
      await world.open(tester, '/circles/circle-1');

      await tester.tap(find.byTooltip('Circle menu'));
      await settle(tester);
      await tester.ensureVisible(find.text('Roles'));
      await settle(tester);
      await tester.tap(find.text('Roles'));
      await settle(tester);
      expect(find.text('Moderators of the Valley'), findsOneWidget);
      expect(find.text('@everyone'), findsOneWidget);
      expectTouchTargets(tester, iconButtonWithTooltip('Create role'));

      await tester.tap(find.byTooltip('Create role'));
      await settle(tester);
      await showKeyboard(tester, viewport);
      expectFullyVisible(tester, find.widgetWithText(TextField, 'Role name'));
      await popTopRoute(tester);

      await tester.tap(find.text('Trip Leaders'));
      await settle(tester);
      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await settle(tester);
      expectFullyVisible(tester, save);
      expectFullyVisible(tester, find.text('Delete role'));
    });

    phoneTestWidgets('create circle sheet', (tester, viewport) async {
      final world = PhoneWorld();
      await world.open(tester, '/circles/circle-1');
      final create = find.byTooltip('Create Circle');
      await tester.ensureVisible(create);
      await tester.tap(create);
      await settle(tester);
      await showKeyboard(tester, viewport);
      expectFullyVisible(tester, find.byType(EditableText).first);
    });

    phoneTestWidgets('circle feed, composer and post sheets', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      await world.open(tester, '/circles/circle-1');
      await tester.tap(find.text('Feed'));
      await settle(tester);
      expect(find.text('Share with this Circle'), findsOneWidget);
      expect(find.textContaining('Sunrise hike'), findsOneWidget);

      await tester.tap(find.byTooltip('Comment').first);
      await settle(tester);
      await tester.tap(find.byType(EditableText).last);
      await showKeyboard(tester, viewport);
      expectCaretVisible(tester, find.byType(EditableText).last);
    });

    phoneTestWidgets('circle channel thread with members drawer', (
      tester,
      viewport,
    ) async {
      await openCircleChannel(tester);
      expect(find.text('# general'), findsOneWidget);
      expect(find.byTooltip('Show member list'), findsOneWidget);

      await openMoreMenu(tester);
      expect(find.text('Pinned messages'), findsOneWidget);
      await dismissPopup(tester);

      await tester.tap(find.byTooltip('Show member list'));
      await settle(tester);
      expect(find.text('Bart the Bold'), findsOneWidget);
      expect(find.textContaining('ONLINE'), findsOneWidget);
      expect(find.text('🎯 $longStatusText'), findsOneWidget);

      // Long press is the touch stand-in for the desktop context menu.
      await tester.longPress(find.text('Bart the Bold'));
      await settle(tester);
      expect(find.text('View profile'), findsOneWidget);
      expect(find.text('Change nickname'), findsOneWidget);

      await tester.tap(find.text('Manage roles'));
      await settle(tester);
      expect(find.text('Moderators of the Valley'), findsOneWidget);
      expectFullyVisible(tester, find.widgetWithText(FilledButton, 'Save'));
      await popTopRoute(tester);

      await tester.longPress(find.text('Bart the Bold'));
      await settle(tester);
      await tester.tap(find.text('Kick'));
      await settle(tester);
      expect(find.text('Kick Bart the Bold'), findsOneWidget);
      expectFullyVisible(tester, find.widgetWithText(FilledButton, 'Kick'));
    });

    phoneTestWidgets('channel settings and permission overwrites', (
      tester,
      viewport,
    ) async {
      await openCircleChannel(tester);
      await openMoreMenu(tester);
      await tester.tap(find.text('Channel settings'));
      await settle(tester);
      expect(find.text('# general'), findsOneWidget);
      expectFullyVisible(
        tester,
        find.byKey(const ValueKey('channel-slowmode-dropdown')),
      );
      final privateChannel = find.text('Private channel');
      await scrollIntoView(tester, privateChannel);
      expectFullyVisible(tester, privateChannel);
      expectFullyVisible(tester, find.text('Read-only channel'));
      expectTouchTargets(
        tester,
        find.byKey(const ValueKey('channel-private-switch')),
      );

      final grace = find.byKey(const ValueKey('channel-overwrite-ow-grace'));
      await scrollIntoView(tester, grace);
      await tester.tap(grace);
      await settle(tester);
      final connect = find.byKey(const ValueKey('overwrite-row-connect_voice'));
      await tester.ensureVisible(connect);
      await settle(tester);
      expectFullyVisible(tester, connect);
      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await settle(tester);
      expectFullyVisible(tester, save);
      expectFullyVisible(tester, find.text('Remove'));
      await popTopRoute(tester);

      await tester.ensureVisible(find.text('Add role or member'));
      await settle(tester);
      await tester.tap(find.text('Add role or member'));
      await settle(tester);
      expect(find.text('Trip Leaders'), findsOneWidget);
      expect(find.text('Linus'), findsOneWidget);
    });

    phoneTestWidgets('read-only channel replaces the composer', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      world.circles.detail = circleDetailWith(
        channelId: 'ch-general',
        permissions: 1 | 64 | 8192,
      );
      world.chats.messages = richMessages(withThread: true);
      await world.open(
        tester,
        '/circles/circle-1/channels/conv-general',
        extra: const ChatThreadRouteExtra(
          title: '# general',
          type: ConversationType.channel,
          circleId: 'circle-1',
        ),
      );
      expectFullyVisible(
        tester,
        find.text("You don't have permission to send messages in this channel"),
      );
      expect(find.widgetWithText(TextField, 'Message'), findsNothing);
    });

    phoneTestWidgets('slowmode countdown above the keyboard', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      world.circles.detail = circleDetailWith(
        channelId: 'ch-general',
        permissions: 1 | 2 | 64 | 8192,
        isReadOnly: false,
        slowmodeSeconds: 21600,
      );
      world.chats.messages = [
        ...richMessages(withThread: true),
        ChatMessage(
          id: 'my-latest',
          conversationId: 'conv-general',
          senderId: me.id,
          type: MessageType.text,
          body: 'Just posted',
          createdAt: DateTime.now().toUtc(),
        ),
      ];
      await world.open(
        tester,
        '/circles/circle-1/channels/conv-general',
        extra: const ChatThreadRouteExtra(
          title: '# general',
          type: ConversationType.channel,
          circleId: 'circle-1',
        ),
      );
      await tester.tap(find.widgetWithText(TextField, 'Message'));
      await showKeyboard(tester, viewport);
      expectFullyVisible(tester, find.text('Slowmode is enabled'));
      expectFullyVisible(
        tester,
        find.byKey(const ValueKey('composer-slowmode-countdown')),
      );
      expectFullyVisible(tester, find.widgetWithText(TextField, 'Message'));
    });

    phoneTestWidgets('private channels show a lock', (tester, viewport) async {
      final world = PhoneWorld();
      await world.open(tester, '/circles/circle-1');
      final photos = find.text('photo-dump');
      await scrollIntoView(tester, photos);
      expectFullyVisible(
        tester,
        find.descendant(
          of: find.ancestor(
            of: photos,
            matching: find.byType(CircleChannelRow),
          ),
          matching: find.byKey(const ValueKey('channel-lock-icon')),
        ),
      );
    });

    phoneTestWidgets('circle channel composer stays above the keyboard', (
      tester,
      viewport,
    ) async {
      await openCircleChannel(tester);
      await tester.tap(find.widgetWithText(TextField, 'Message'));
      await showKeyboard(tester, viewport);
      expectFullyVisible(tester, find.widgetWithText(TextField, 'Message'));
    });

    phoneTestWidgets('circle thread conversation', (tester, viewport) async {
      await openCircleChannel(
        tester,
        conversationId: 'thread-conv-1',
        title: 'Planning the extremely long weekend trip to Yosemite Valley',
        type: ConversationType.thread,
      );
      expect(find.text('in #general'), findsOneWidget);
      await openMoreMenu(tester);
      expect(find.text('Archive thread'), findsOneWidget);
      await dismissPopup(tester);
    });

    phoneTestWidgets('invite page', (tester, viewport) async {
      final world = PhoneWorld();
      await world.open(tester, '/invite/h7Kq2mPz');
      expect(find.text(circleSummaries[3].name), findsOneWidget);
    });
  });

  group('people', () {
    phoneTestWidgets('contacts with requests and alias sheet', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      await world.open(tester, '/contacts');
      await tester.enterText(
        find.widgetWithText(TextField, 'Search profiles'),
        'member',
      );
      await settle(tester);
      expect(find.text('Accept'), findsOneWidget);

      final alias = find.byTooltip('Edit alias');
      await scrollIntoView(tester, alias);
      await tester.tap(alias.first);
      await settle(tester);
      await tester.tap(find.byType(EditableText).last);
      await showKeyboard(tester, viewport);
      expectFullyVisible(tester, find.byType(EditableText).last);
    });

    phoneTestWidgets('new group sheet', (tester, viewport) async {
      final world = PhoneWorld();
      await world.open(tester, '/contacts');
      final newGroup = find.text('New Group');
      await scrollIntoView(tester, newGroup);
      await tester.tap(newGroup);
      await settle(tester);
      await tester.tap(find.byType(EditableText).last);
      await showKeyboard(tester, viewport);
      expectFullyVisible(tester, find.byType(EditableText).last);
    });

    phoneTestWidgets('user profile with custom status and report sheet', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      await world.open(tester, '/profile/user-2');
      expect(find.textContaining('Deep focus'), findsOneWidget);
      final report = find.text('Report');
      await scrollIntoView(tester, report);
      await tester.tap(report);
      await settle(tester);
      await tester.ensureVisible(find.byType(EditableText).last);
      await settle(tester);
      await tester.tap(find.byType(EditableText).last);
      await showKeyboard(tester, viewport);
      expectCaretVisible(tester, find.byType(EditableText).last);
    });

    phoneTestWidgets('Me screen with status and blocked users sheets', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      world.settings.blockedUsers = [bart, grace];
      await world.open(tester, '/me');
      expect(find.text('Brewing ideas'), findsOneWidget);

      await tester.tap(find.text('Brewing ideas'));
      await settle(tester);
      expect(find.text('Set a status'), findsOneWidget);
      await tester.tap(find.byType(EditableText).last);
      await showKeyboard(tester, viewport);
      expectFullyVisible(tester, find.byType(EditableText).last);
      // The buttons scroll into view with the rest of the sheet.
      await tester.ensureVisible(find.text('Save'));
      await settle(tester);
      expectFullyVisible(tester, find.text('Save'));
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      tester.view.viewInsets = FakeViewPadding.zero;
      await settle(tester);

      final blocked = find.text('Blocked users');
      await scrollIntoView(tester, blocked);
      await tester.tap(blocked);
      await settle(tester);
      expect(find.text('Unblock'), findsWidgets);
    });
  });
}
