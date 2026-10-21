import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/auth/auth_screen.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_channel_sidebar.dart';
import 'package:wecord/features/circles/circle_channel_thread_screen.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/later/saved_messages_screen.dart';
import 'package:wecord/features/groups/group_creation_sheet.dart';
import 'package:wecord/features/inbox/inbox_screen.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_ui.dart';
import 'package:wecord/shared/models/circle_audit_entry.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../features/circles/circle_detail_screen_test.dart' as circle_fakes;
import '../features/circles/circle_emojis_test.dart' as emoji_fakes;
import '../features/voice/voice_fakes.dart';
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
    // Centered, so the floating header and composer don't cover it.
    await Scrollable.ensureVisible(
      tester.element(finder.first),
      alignment: 0.5,
    );
    await settle(tester);
  }

  /// The open sheet is a WeCord sheet (grabber, 28 corners on the panel)
  /// without Material list tiles, chips or ripples.
  void expectWeCordSheet(WidgetTester tester) {
    final sheet = find.byType(WeCordSheet);
    expect(sheet, findsOneWidget);
    for (final type in [ListTile, ChoiceChip, InkWell]) {
      expect(
        find.descendant(of: sheet, matching: find.byType(type)),
        findsNothing,
        reason: '$type in a WeCord sheet',
      );
    }
    final bottomSheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(bottomSheet.showDragHandle, isNot(isTrue));
    // showWeCordSheet draws the panel itself over a clear Material sheet.
    expect(bottomSheet.backgroundColor, Colors.transparent);
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

      final toggle = find.byKey(const ValueKey('auth-toggle-mode'));
      await tester.ensureVisible(toggle);
      await settle(tester);
      await tester.tap(toggle);
      await settle(tester);
      expect(find.text('Username'), findsOneWidget);
      await tester.ensureVisible(find.text('Username'));
      await settle(tester);

      await tester.tap(find.widgetWithText(WeCordTextField, 'Username'));
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

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-dm-dm-1')),
          matching: find.text(bart.displayName),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-dm-dm-1')),
          matching: find.text('99+'),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.push_pin), findsOneWidget);
      expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);

      // Phones open conversation actions with a long press.
      expect(find.byTooltip('Conversation actions'), findsNothing);
      await tester.longPress(find.byKey(const ValueKey('home-dm-dm-1')));
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
        of: find.byKey(const ValueKey('chat-thread-header')),
        matching: find.byType(WeCordIconButton),
      );
      // Back, search, one context action and More.
      expect(toolbarButtons, findsNWidgets(4));
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
      // The owner's "Ask members to confirm" switch sits above the list of
      // actions; scroll down to the last of them.
      await scrollIntoView(tester, find.text('Leave group'));
      expect(find.text('Leave group'), findsOneWidget);
      expectWeCordSheet(tester);
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
      expectWeCordSheet(tester);
      await tester.tap(find.text('😀'));
      await settle(tester);

      final chip = find.byKey(const ValueKey('reaction-chip-😂'));
      await reveal(tester, chip);
      await tester.longPress(chip);
      await settle(tester);
      expect(find.text('Reacted with 😂'), findsOneWidget);
      expectWeCordSheet(tester);
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
      // Direct chats keep the call button next to search.
      expect(find.byTooltip('Start voice call'), findsOneWidget);
      await openMoreMenu(tester);
      await tester.tap(find.text('Pinned messages'));
      await settle(tester);
      expect(find.text('Pinned messages'), findsWidgets);
      expect(find.text('Pinned by ${me.displayName}'), findsOneWidget);
      expectWeCordSheet(tester);
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
      expectTouchTargets(tester, _weCordButtonWithTooltip('Cancel reply'));

      await longPressMessage(tester, 'Supercalifragilistic');
      await tester.tap(find.text('Edit'));
      await settle(tester);
      expect(find.text('Editing message'), findsOneWidget);
      expectTouchTargets(tester, _weCordButtonWithTooltip('Cancel edit'));
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
      await tester.tap(find.byKey(const ValueKey('chat-composer-field')));
      await showKeyboard(tester, viewport);
      expectFullyVisible(
        tester,
        find.byKey(const ValueKey('chat-composer-field')),
      );
      // Phones show the microphone until there is something to send.
      expectFullyVisible(tester, find.byTooltip('Record voice message'));
      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'Hi',
      );
      await settle(tester);
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
      expect(find.byType(FilePreviewScreen), findsOneWidget);
      await popTopRoute(tester);

      await longPressMessage(tester, 'Forwarding');
      await tester.tap(find.text('Forward'));
      await settle(tester);
      expect(find.text('Forward to'), findsWidgets);
      expectWeCordSheet(tester);
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
      final composer = find.byKey(const ValueKey('chat-composer-field'));
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

    Future<PhoneWorld> openPolls(WidgetTester tester) async {
      final world = PhoneWorld();
      world.chats.messages = pollMessages();
      await world.open(
        tester,
        '/circles/circle-1/channels/conv-general',
        extra: const ChatThreadRouteExtra(
          title: '# general',
          type: ConversationType.channel,
          circleId: 'circle-1',
        ),
      );
      return world;
    }

    phoneTestWidgets('poll bubbles with long answers', (
      tester,
      viewport,
    ) async {
      await openPolls(tester);
      expect(find.text('4 votes · Closed'), findsOneWidget);
      final longAnswer = find.text(
        'Thursday evening, after the long planning meeting wraps up',
      );
      await tester.ensureVisible(longAnswer);
      await settle(tester);
      expectFullyVisible(tester, longAnswer);
      expect(find.text('6 votes · Ends in 19h'), findsOneWidget);
      final rows = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'poll-option-poll-open-',
            ),
      );
      expect(rows, findsNWidgets(4));
      for (final element in rows.evaluate()) {
        expect(
          (element.renderObject! as RenderBox).size.height,
          greaterThanOrEqualTo(44),
        );
      }
      final viewVotes = find.byKey(const ValueKey('poll-view-votes-poll-open'));
      await tester.ensureVisible(viewVotes);
      await settle(tester);
      expectFullyVisible(tester, viewVotes);
    });

    phoneTestWidgets('poll votes sheet', (tester, viewport) async {
      final world = await openPolls(tester);
      world.chats.pollVoters = {
        'o1': [bart, grace],
        'o2': [me, bart, grace, linus],
      };
      final viewVotes = find.byKey(const ValueKey('poll-view-votes-poll-open'));
      // Centered, clear of the floating composer.
      await Scrollable.ensureVisible(tester.element(viewVotes), alignment: 0.5);
      await settle(tester);
      await tester.tap(viewVotes);
      await settle(tester);
      expect(find.text('Votes'), findsOneWidget);
      expectWeCordSheet(tester);
      expectFullyVisible(tester, find.text(grace.displayName));
      await tester.tap(find.byKey(const ValueKey('poll-voters-option-o2')));
      await settle(tester);
      final lastVoter = find.text('@${linus.username}');
      await tester.scrollUntilVisible(
        lastVoter,
        80,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await settle(tester);
      expectFullyVisible(tester, lastVoter);
    });

    phoneTestWidgets('poll form above the keyboard', (tester, viewport) async {
      await openPolls(tester);
      await tester.tap(find.byTooltip('Attach'));
      await settle(tester);
      await tester.tap(find.text('Create poll'));
      await settle(tester);

      final question = find.byKey(const ValueKey('poll-question-field'));
      await tester.tap(question);
      await tester.enterText(
        question,
        'Which day works best for the release retrospective?',
      );
      await showKeyboard(tester, viewport);
      expectCaretVisible(tester, question);

      for (var index = 0; index < 4; index++) {
        final add = find.byKey(const ValueKey('poll-add-option'));
        await tester.ensureVisible(add);
        await settle(tester);
        await tester.tap(add);
        await settle(tester);
      }
      final last = find.byKey(const ValueKey('poll-option-field-5'));
      await tester.ensureVisible(last);
      await tester.tap(last);
      await tester.enterText(last, 'Thursday evening after planning');
      await settle(tester);
      expectCaretVisible(tester, last);

      final post = find.byKey(const ValueKey('poll-post-button'));
      await tester.ensureVisible(post);
      await settle(tester);
      expectFullyVisible(tester, post);
      expectTouchTargets(tester, post);
    });

    phoneTestWidgets('slash commands above the keyboard', (
      tester,
      viewport,
    ) async {
      await openCircleChannel(tester);
      final composer = find.byKey(const ValueKey('chat-composer-field'));
      await tester.tap(composer);
      await tester.enterText(composer, '/');
      await showKeyboard(tester, viewport);
      expect(find.byKey(const ValueKey('slash-command-list')), findsOneWidget);
      expectFullyVisible(tester, composer);
      expectFullyVisible(
        tester,
        find.byKey(const ValueKey('slash-command-shrug')),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('chat-message-list'))).height,
        greaterThan(0),
      );
      await tester.enterText(composer, '/ni');
      await tester.pump();
      expectFullyVisible(
        tester,
        find.byKey(const ValueKey('slash-command-nick')),
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

  group('navigation', () {
    final phoneHome = find.byKey(const ValueKey('phone-home'));
    final userPanel = find.byKey(const ValueKey('phone-user-panel'));

    phoneTestWidgets('home with rail, messages and the user panel', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      await world.open(tester, '/home');

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(CircleRail), findsOneWidget);
      expectFullyVisible(tester, find.text('Messages'));
      for (final key in [
        'phone-home-search',
        'phone-home-add-friends',
        'phone-home-saved',
        'phone-home-new',
      ]) {
        expectFullyVisible(tester, find.byKey(ValueKey(key)));
        expectTouchTargets(tester, find.byKey(ValueKey(key)));
      }
      // Friends, online first.
      final bartTile = find.byKey(ValueKey('phone-friend-${bart.id}'));
      final graceTile = find.byKey(ValueKey('phone-friend-${grace.id}'));
      // Add friend, Saved, Agenda and Moments come first, then the friends
      // (on the narrowest phones the later ones are a swipe away).
      final momentsTile = find.byKey(const ValueKey('phone-home-moments'));
      if (bartTile.evaluate().isNotEmpty) {
        expect(
          tester.getTopLeft(momentsTile).dx,
          lessThan(tester.getTopLeft(bartTile).dx),
        );
      }
      if (bartTile.evaluate().isNotEmpty && graceTile.evaluate().isNotEmpty) {
        expect(
          tester.getTopLeft(bartTile).dx,
          lessThan(tester.getTopLeft(graceTile).dx),
        );
      }
      expect(find.byKey(const ValueKey('home-dm-dm-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-dm-group-1')), findsOneWidget);
      expect(
        find.text('Trailhead moved to the north lot this Saturday.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('home-dm-age-dm-1')), findsOneWidget);
      // Channels stay in their circle.
      expect(find.byKey(const ValueKey('home-dm-conv-general')), findsNothing);
      expectTouchTargets(tester, find.byType(CircleRailItem));
      expectFullyVisible(tester, userPanel);
      expectTouchTargets(
        tester,
        find.byKey(const ValueKey('phone-notifications-button')),
      );
      // The bell counts the unread mention and the pending request.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('phone-notifications-button')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );

      // Add Friends opens the Friends page full screen; back returns.
      await tester.tap(find.byKey(const ValueKey('phone-home-add-friends')));
      await settle(tester);
      expect(find.byType(ContactsScreen), findsOneWidget);
      expect(find.text('Friends'), findsWidgets);
      expect(userPanel, findsNothing);
      await tester.tap(find.byKey(const ValueKey('paper-page-back')));
      await settle(tester);
      expect(userPanel, findsOneWidget);

      // Saved sits next to Add friend, as it does beside Friends on desktop.
      await tester.tap(find.byKey(const ValueKey('phone-home-saved')));
      await settle(tester);
      expect(find.byType(SavedMessagesScreen), findsOneWidget);
      expect(userPanel, findsNothing);
      await tester.tap(find.byKey(const ValueKey('paper-page-back')));
      await settle(tester);
      expect(userPanel, findsOneWidget);

      // So do direct messages, with a back button.
      await tester.tap(find.byKey(const ValueKey('home-dm-dm-1')));
      await settle(tester);
      expect(userPanel, findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await settle(tester);
      expect(userPanel, findsOneWidget);

      // The avatar opens You, the bell the notifications.
      await tester.tap(find.byKey(const ValueKey('phone-user-panel-avatar')));
      await settle(tester);
      expect(find.byKey(const ValueKey('settings-screen')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-back')));
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('phone-notifications-button')),
      );
      await settle(tester);
      expect(find.byType(InboxScreen), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('paper-page-back')));
      await settle(tester);
      expect(phoneHome, findsOneWidget);

      // The name and status open the status picker, with the custom status
      // behind it.
      await tester.tap(find.byKey(const ValueKey('phone-user-panel-status')));
      await settle(tester);
      for (final value in ['online', 'idle', 'dnd', 'invisible']) {
        expect(find.byKey(ValueKey('presence-option-$value')), findsOneWidget);
      }
      final custom = find.byKey(const ValueKey('presence-custom-status'));
      await tester.ensureVisible(custom);
      await settle(tester);
      await tester.tap(custom);
      await settle(tester);
      expect(find.text('Set a status'), findsOneWidget);
    });

    phoneTestWidgets('home runs edge to edge', (tester, viewport) async {
      final world = PhoneWorld();
      await world.open(tester, '/home');

      // The rail starts under the status bar; the panel and the rail's
      // first item below it.
      expect(tester.getTopLeft(find.byType(CircleRail)).dy, 0);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('phone-home-panel'))).dy,
        greaterThanOrEqualTo(viewport.topInset),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('circle-rail-home'))).dy,
        greaterThanOrEqualTo(viewport.topInset),
      );
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('phone-home'))).dy,
        viewport.size.height,
      );
      // The user panel floats above the home indicator.
      expect(
        tester.getBottomLeft(userPanel).dy,
        lessThanOrEqualTo(viewport.size.height - viewport.bottomInset),
      );

      // Scrolled to the end, the last conversation clears the user panel.
      await tester.drag(
        find.byKey(const ValueKey('phone-messages-list')),
        const Offset(0, -2000),
      );
      await settle(tester);
      final last = find.byKey(const ValueKey('home-dm-dm-3'));
      expect(
        tester.getBottomLeft(last).dy,
        lessThanOrEqualTo(tester.getTopLeft(userPanel).dy),
      );

      // Status bar icons contrast with the page.
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find
            .ancestor(
              of: phoneHome,
              matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
            )
            .first,
      );
      final dark =
          Theme.of(tester.element(phoneHome)).brightness == Brightness.dark;
      expect(
        region.value.statusBarIconBrightness,
        dark ? Brightness.light : Brightness.dark,
      );
      expect(region.value.statusBarColor, Colors.transparent);
    });

    phoneTestWidgets('new message and new group from the plus button', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      await world.open(tester, '/home');

      await tester.tap(find.byKey(const ValueKey('phone-home-new')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('phone-new-message')));
      await settle(tester);
      final pick = find.byKey(ValueKey('phone-pick-friend-${bart.id}'));
      expectFullyVisible(tester, pick);
      await tester.tap(pick);
      await settle(tester);
      expect(
        tester
            .widget<ChatThreadScreen>(find.byType(ChatThreadScreen))
            .conversationId,
        'dm-1',
      );
      await tester.tap(find.byTooltip('Back'));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('phone-home-new')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('phone-new-group')));
      await settle(tester);
      expect(find.byType(GroupCreationSheet), findsOneWidget);
      expectWeCordSheet(tester);
    });

    phoneTestWidgets('the old Messages link opens home', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      await world.open(tester, ChatsScreen.path);
      expect(phoneHome, findsOneWidget);
      expect(find.byKey(const ValueKey('home-dm-dm-1')), findsOneWidget);
    });

    phoneTestWidgets('pages pushed over a circle cover the user panel', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      await world.open(tester, '/circles/circle-1');
      expect(userPanel, findsOneWidget);
      expect(find.byType(CircleChannelSidebar), findsOneWidget);
      await tester.tap(find.text('Feed'));
      await settle(tester);
      expect(userPanel, findsNothing);
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expect(userPanel, findsOneWidget);
    });

    phoneTestWidgets('notifications with mentions, replies and requests', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      await world.open(tester, '/notifications');

      expect(
        find.byKey(const ValueKey('inbox-friend-requests')),
        findsOneWidget,
      );
      expect(find.text('Mentioned you'), findsOneWidget);
      expect(find.text('Replied to you'), findsOneWidget);
      expect(find.text('@Ada can you bring the tripod?'), findsOneWidget);
      expect(find.byKey(const ValueKey('inbox-unread-dot')), findsOneWidget);

      // A channel mention opens the channel in its circle.
      await tester.tap(find.byKey(const ValueKey('inbox-item-inbox-mention')));
      await settle(tester);
      final channel = tester.widget<CircleChannelThreadScreen>(
        find.byType(CircleChannelThreadScreen),
      );
      expect(channel.circleId, 'circle-1');
      expect(channel.conversationId, 'conv-general');
      await popTopRoute(tester);

      // Opened from a link, back goes home.
      await tester.tap(find.byKey(const ValueKey('paper-page-back')));
      await settle(tester);
      expect(phoneHome, findsOneWidget);
    });

    phoneTestWidgets('you page opened from a link goes back home', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      await world.open(tester, '/me');
      expect(find.byKey(const ValueKey('settings-screen')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-back')));
      await settle(tester);
      expect(phoneHome, findsOneWidget);
    });
  });

  group('circles', () {
    phoneTestWidgets('rail adds circles with an invite', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      await world.open(tester, '/home');
      expect(
        find.byKey(ValueKey('circle-rail-${circleSummaries.first.id}')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(CircleRail),
          matching: find.text('99+'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('circle-rail-add')));
      await settle(tester);
      await tester.tap(find.text('Join with invite'));
      await settle(tester);
      await showKeyboard(tester, viewport);
      expectFullyVisible(tester, find.widgetWithText(WeCordButton, 'Join'));
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
      expect(find.text('Text Channels'), findsOneWidget);
      expect(find.byKey(const ValueKey('circle-mention-badge')), findsWidgets);
      // The collapsed Archive category hides its quiet channel.
      expect(find.text('old-stuff'), findsNothing);

      expectTouchTargets(tester, find.byType(CircleChannelRow));
      expectTouchTargets(
        tester,
        find.descendant(
          of: find.byType(CircleCategoryHeader),
          matching: find.byType(WeCordIconButton),
        ),
      );
      expectTouchTargets(tester, find.byType(CircleRailItem));

      // The rail runs under the status bar; its items and the channel
      // panel clear the notch, and the user panel floats at the bottom.
      expect(tester.getTopLeft(find.byType(CircleRail)).dy, 0);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('circle-rail-home'))).dy,
        greaterThanOrEqualTo(viewport.topInset),
      );
      expect(
        tester.getTopLeft(find.byType(CircleChannelSidebar)).dy,
        greaterThanOrEqualTo(viewport.topInset),
      );
      expectFullyVisible(
        tester,
        find.byKey(const ValueKey('phone-user-panel')),
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
      // The menu scrolls on short screens.
      await tester.ensureVisible(find.text('Create category'));
      await settle(tester);
      await tester.tap(find.text('Create category'));
      await settle(tester);
      await showKeyboard(tester, viewport);
      expectFullyVisible(
        tester,
        find.widgetWithText(WeCordTextField, 'Category name'),
      );
      expectFullyVisible(tester, find.widgetWithText(WeCordButton, 'Create'));
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      await tester.tap(find.byTooltip('Circle menu'));
      await settle(tester);
      // The menu scrolls on short screens.
      await tester.ensureVisible(find.text('Change my nickname'));
      await settle(tester);
      await tester.tap(find.text('Change my nickname'));
      await settle(tester);
      expectFullyVisible(
        tester,
        find.widgetWithText(WeCordTextField, 'Nickname'),
      );
      expectFullyVisible(tester, find.widgetWithText(WeCordButton, 'Save'));
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      await hideKeyboard(tester, viewport);

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
      expectFullyVisible(tester, find.widgetWithText(WeCordButton, 'Transfer'));
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
      expectFullyVisible(tester, find.widgetWithText(WeCordButton, 'Leave'));
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
        find.widgetWithText(WeCordButton, 'Back to home'),
      );
    });

    phoneTestWidgets('audit log with filters and details', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      final now = DateTime.now();
      world.circles.auditEntries = [
        CircleAuditEntry(
          id: 'audit-long',
          circleId: 'circle-1',
          action: 'channel_permissions_update',
          targetType: 'channel',
          targetLabel: 'yosemite-2026-planning-and-logistics',
          changes: const {
            'target_name': 'Moderators of the Valley',
            'allow': {'old': 0, 'new': 1 | 2 | 4 | 64 | 256 | 8192},
            'deny': {'old': 2, 'new': 0},
          },
          createdAt: now.subtract(const Duration(minutes: 1)),
          actor: const CircleAuditActor(
            id: 'user-9',
            username: 'bartholomew_the_bold',
            displayName: 'Bartholomew the Extremely Bold and Verbose',
          ),
        ),
        ...circle_fakes.sampleAuditEntries(now: now, count: 30),
      ];
      await world.open(tester, '/circles/circle-1');

      await tester.tap(find.byTooltip('Circle menu'));
      await settle(tester);
      await tester.ensureVisible(find.text('Audit log'));
      await settle(tester);
      await tester.tap(find.text('Audit log'));
      await settle(tester);

      expect(find.text('Audit log'), findsOneWidget);
      expectTouchTargets(
        tester,
        find.ancestor(
          of: find.byTooltip('Filter by action'),
          matching: find.byType(WeCordIconButton),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('circle-audit-audit-long')));
      await settle(tester);
      expect(
        find.textContaining('Mention everyone', findRichText: true),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Filter by action'));
      await settle(tester);
      await tester.tap(find.text('Roles').last);
      await settle(tester);
      expectFullyVisible(
        tester,
        find.byKey(const ValueKey('circle-audit-filter-chip')),
      );
      expect(
        find.byKey(const ValueKey('circle-audit-audit-1')),
        findsOneWidget,
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
      expectTouchTargets(
        tester,
        find.ancestor(
          of: find.byTooltip('Create role'),
          matching: find.byType(WeCordIconButton),
        ),
      );

      await tester.tap(find.byTooltip('Create role'));
      await settle(tester);
      await showKeyboard(tester, viewport);
      expectFullyVisible(
        tester,
        find.widgetWithText(WeCordTextField, 'Role name'),
      );
      await popTopRoute(tester);

      await tester.tap(find.text('Trip Leaders'));
      await settle(tester);
      final save = find.widgetWithText(WeCordButton, 'Save');
      await tester.ensureVisible(save);
      await settle(tester);
      expectFullyVisible(tester, save);
      expectFullyVisible(tester, find.text('Delete role'));
    });

    phoneTestWidgets('create circle sheet', (tester, viewport) async {
      final world = PhoneWorld();
      await world.open(tester, '/circles/circle-1');
      final add = find.byKey(const ValueKey('circle-rail-add'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await settle(tester);
      await tester.tap(find.text('Create a circle'));
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
      expect(find.textContaining('Online — '), findsOneWidget);
      expect(find.text('🎯 $longStatusText'), findsOneWidget);

      // Long press is the touch stand-in for the desktop context menu.
      await tester.longPress(find.text('Bart the Bold'));
      await settle(tester);
      expect(find.text('View profile'), findsOneWidget);
      expect(find.text('Change nickname'), findsOneWidget);

      await tester.tap(find.text('Manage roles'));
      await settle(tester);
      expect(find.text('Moderators of the Valley'), findsOneWidget);
      expectFullyVisible(tester, find.widgetWithText(WeCordButton, 'Save'));
      await popTopRoute(tester);

      await tester.longPress(find.text('Bart the Bold'));
      await settle(tester);
      await tester.tap(find.text('Kick'));
      await settle(tester);
      expect(find.text('Kick Bart the Bold'), findsOneWidget);
      expectFullyVisible(tester, find.widgetWithText(WeCordButton, 'Kick'));
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
      // The editor's Save comes after the overview form's.
      final save = find.widgetWithText(WeCordButton, 'Save').last;
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

    phoneTestWidgets('webhook messages with a BOT tag', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      world.chats.messages = webhookMessages();
      await world.open(
        tester,
        '/circles/circle-1/channels/conv-general',
        extra: const ChatThreadRouteExtra(
          title: '# general',
          type: ConversationType.channel,
          circleId: 'circle-1',
        ),
      );
      final tag = find.byKey(const ValueKey('message-bot-tag'));
      expect(tag, findsOneWidget);
      expectFullyVisible(tester, tag);
      expectFullyVisible(
        tester,
        find.textContaining('production finished', findRichText: true),
      );
    });

    Future<PhoneWorld> openEmojiChannel(WidgetTester tester) async {
      final world = PhoneWorld();
      world.chats.messages = emojiMessages();
      await world.open(
        tester,
        '/circles/circle-1/channels/conv-general',
        extra: const ChatThreadRouteExtra(
          title: '# general',
          type: ConversationType.channel,
          circleId: 'circle-1',
        ),
      );
      return world;
    }

    phoneTestWidgets('custom emoji, reactions and stickers', (
      tester,
      viewport,
    ) async {
      await openEmojiChannel(tester);

      final ownSticker = find.byKey(
        ValueKey('sticker-image-${emoji_fakes.shipItStickerId}'),
      );
      expectFullyVisible(tester, ownSticker);
      // Channels read as cards: own stickers sit under the sender's name,
      // without a bubble, beside the avatar.
      expect(tester.getTopLeft(ownSticker).dx, lessThan(80));
      final placeholder = find.byKey(const ValueKey('sticker-placeholder'));
      await _centerOn(tester, placeholder);
      expectFullyVisible(tester, placeholder);
      expectFullyVisible(tester, find.text('[Sticker] secret_handshake'));

      final jumbo = find.byKey(
        ValueKey('custom-emoji-${emoji_fakes.catThumbsId}'),
      );
      await _centerOn(tester, jumbo);
      expect(tester.getSize(jumbo), const Size.square(48));

      final chip = find.byKey(
        ValueKey('reaction-chip-custom:${emoji_fakes.partyParrotId}'),
      );
      await _centerOn(tester, chip);
      expectFullyVisible(tester, chip);
      expectTouchTargets(tester, chip);
      final far = find.text(':far_away_mountain_goat:');
      expectFullyVisible(tester, far);
      expect(tester.getSize(far).width, lessThanOrEqualTo(120));
    });

    phoneTestWidgets('sticker picker and emoji suggestions', (
      tester,
      viewport,
    ) async {
      await openEmojiChannel(tester);

      await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
      await settle(tester);
      await tester.tap(find.text('Send sticker'));
      await settle(tester);
      final option = find.byKey(
        ValueKey('sticker-option-${emoji_fakes.shipItStickerId}'),
      );
      await tester.ensureVisible(option);
      await settle(tester);
      expectFullyVisible(tester, option);
      expectTouchTargets(tester, option);
      await popTopRoute(tester);

      final field = find.byKey(const ValueKey('chat-composer-field'));
      await tester.enterText(field, 'Trip :b');
      await tester.enterText(field, 'Trip :bl');
      await showKeyboard(tester, viewport);
      final candidate = find.byKey(
        ValueKey('custom-emoji-candidate-${emoji_fakes.blobWaveId}'),
      );
      expectFullyVisible(tester, candidate);
      expectTouchTargets(tester, candidate);
      expectCaretVisible(tester, field);
    });

    phoneTestWidgets('emoji and stickers page', (tester, viewport) async {
      final world = PhoneWorld();
      await world.open(tester, '/circles/circle-1');
      await tester.tap(find.byTooltip('Circle menu'));
      await settle(tester);
      await tester.ensureVisible(find.text('Emoji & stickers'));
      await settle(tester);
      await tester.tap(find.text('Emoji & stickers'));
      await settle(tester);

      final upload = find.byKey(const ValueKey('circle-emojis-upload-emoji'));
      expectFullyVisible(tester, upload);
      expectTouchTargets(tester, upload);
      expectFullyVisible(tester, find.text('2 of 50 emoji'));
      final menu = find.byKey(
        ValueKey('circle-emoji-menu-${emoji_fakes.partyParrotId}'),
      );
      expectTouchTargets(tester, menu);

      await tester.tap(menu);
      await settle(tester);
      await tester.tap(find.text('Rename'));
      await settle(tester);
      await showKeyboard(tester, viewport);
      final name = find.byKey(const ValueKey('circle-emoji-name-field'));
      expectCaretVisible(tester, name);
      expectFullyVisible(
        tester,
        find.byKey(const ValueKey('circle-emoji-name-submit')),
      );
      await popTopRoute(tester);
      tester.view.viewInsets = FakeViewPadding.zero;
      await settle(tester);

      await tester.tap(find.text('Stickers'));
      await settle(tester);
      expectFullyVisible(
        tester,
        find.byKey(const ValueKey('circle-emojis-upload-sticker')),
      );
      expectFullyVisible(tester, find.text('1 of 20 stickers'));
    });

    phoneTestWidgets('channel integrations and webhook URL', (
      tester,
      viewport,
    ) async {
      final world = await openCircleChannel(tester);
      world.circles.webhooks = channelWebhooks();
      await openMoreMenu(tester);
      await tester.tap(find.text('Channel settings'));
      await settle(tester);

      final create = find.byKey(const ValueKey('webhook-create-button'));
      await scrollIntoView(tester, create);
      expectFullyVisible(tester, create);
      expectTouchTargets(tester, create);
      final first = find.byKey(const ValueKey('webhook-webhook-1'));
      await tester.ensureVisible(first);
      await settle(tester);
      expectFullyVisible(tester, first);
      expectTouchTargets(
        tester,
        find.byKey(const ValueKey('webhook-menu-webhook-1')),
      );

      await scrollIntoView(tester, create);
      await tester.tap(create);
      await settle(tester);
      final name = find.byKey(const ValueKey('webhook-name-field'));
      await tester.enterText(name, 'Release notes');
      await showKeyboard(tester, viewport);
      expectCaretVisible(tester, name);
      await tester.tap(find.byKey(const ValueKey('webhook-name-submit')));
      await settle(tester);
      tester.view.viewInsets = FakeViewPadding.zero;
      await settle(tester);

      expect(find.text('Webhook created'), findsOneWidget);
      final url = find.byKey(const ValueKey('webhook-url'));
      await tester.ensureVisible(url);
      await settle(tester);
      expectFullyVisible(tester, url);
      expectFullyVisible(
        tester,
        find.byKey(const ValueKey('webhook-copy-url')),
      );
      expectFullyVisible(tester, find.text('Done'));
    });

    phoneTestWidgets('channel overview and delete confirmation', (
      tester,
      viewport,
    ) async {
      await openCircleChannel(tester);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('chat-thread-subtitle')))
            .data,
        startsWith('Weekend plans'),
      );
      await tester.tap(find.byKey(const ValueKey('chat-thread-topic')));
      await settle(tester);
      expectFullyVisible(tester, find.text('Close'));
      await tester.tap(find.text('Close'));
      await settle(tester);

      await openMoreMenu(tester);
      await tester.tap(find.text('Channel settings'));
      await settle(tester);
      final topic = find.byKey(const ValueKey('channel-topic-field'));
      await tester.tap(topic);
      await showKeyboard(tester, viewport);
      await tester.enterText(topic, 'Carpools only');
      await settle(tester);
      expectCaretVisible(tester, topic);
      final save = find.byKey(const ValueKey('channel-overview-save'));
      await tester.ensureVisible(save);
      await settle(tester);
      expectFullyVisible(tester, save);
      expectTouchTargets(tester, save);

      final delete = find.byKey(const ValueKey('channel-delete-button'));
      await scrollIntoView(tester, delete);
      expectFullyVisible(tester, delete);
      await tester.tap(delete);
      await settle(tester);
      final confirm = find.byKey(
        const ValueKey('channel-delete-confirm-field'),
      );
      await tester.enterText(confirm, 'general');
      await settle(tester);
      expectCaretVisible(tester, confirm);
      expectFullyVisible(tester, find.widgetWithText(WeCordButton, 'Delete'));
    });

    phoneTestWidgets('forum post list', (tester, viewport) async {
      await openCircleChannel(
        tester,
        conversationId: 'conv-help',
        title: 'help-and-questions',
      );
      expect(find.byKey(const ValueKey('forum-post-list')), findsOneWidget);
      expectFullyVisible(tester, find.byKey(const ValueKey('forum-new-post')));
      expectTouchTargets(tester, find.byKey(const ValueKey('forum-new-post')));
      expectFullyVisible(
        tester,
        find.byKey(const ValueKey('forum-sort-button')),
      );
      expectTouchTargets(
        tester,
        find.byKey(const ValueKey('forum-sort-button')),
      );
      expectFullyVisible(
        tester,
        find.text('Read me first: how this forum works'),
      );
      await scrollIntoView(
        tester,
        find.text('Bear canister rental'),
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('forum-post-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expectFullyVisible(tester, find.text('Bear canister rental'));

      await tester.tap(find.byKey(const ValueKey('forum-sort-button')));
      await settle(tester);
      expectFullyVisible(tester, find.text('Newest'));
    });

    phoneTestWidgets('forum new post sheet above the keyboard', (
      tester,
      viewport,
    ) async {
      await openCircleChannel(
        tester,
        conversationId: 'conv-help',
        title: 'help-and-questions',
      );
      await tester.tap(find.byKey(const ValueKey('forum-new-post')));
      await settle(tester);
      final title = find.byKey(const ValueKey('forum-post-title-field'));
      await showKeyboard(tester, viewport);
      expectCaretVisible(tester, title);

      final body = find.byKey(const ValueKey('forum-post-body-field'));
      await tester.ensureVisible(body);
      await tester.tap(body);
      await tester.enterText(body, 'Line one\nLine two\nLine three');
      await settle(tester);
      expectCaretVisible(tester, body);

      final tag = find.byKey(const ValueKey('forum-tag-choice-tag-trip'));
      await tester.ensureVisible(tag);
      await settle(tester);
      expectFullyVisible(tester, tag);
      expectTouchTargets(tester, tag);

      final submit = find.byKey(const ValueKey('forum-post-submit'));
      await tester.ensureVisible(submit);
      await settle(tester);
      expectFullyVisible(tester, submit);
      expectTouchTargets(tester, submit);
    });

    phoneTestWidgets('forum post with its opening post', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      world.chats.messages = forumPostMessages();
      await world.open(
        tester,
        '/circles/circle-1/channels/post-conv-1',
        extra: const ChatThreadRouteExtra(
          title: forumPostTitle,
          type: ConversationType.thread,
          circleId: 'circle-1',
        ),
      );
      expect(find.byKey(const ValueKey('forum-opening-post')), findsOneWidget);
      expectFullyVisible(tester, find.byTooltip('Back'));
      expectFullyVisible(
        tester,
        find.byKey(const ValueKey('chat-composer-field')),
      );

      final opening = find.byKey(const ValueKey('forum-opening-post'));
      await tester.drag(
        find.byKey(const ValueKey('chat-message-list')),
        const Offset(0, 2000),
      );
      await settle(tester);
      expect(
        tester.getRect(opening).width,
        greaterThan(viewport.size.width - 40),
      );
      expectFullyVisible(
        tester,
        find.descendant(of: opening, matching: find.text(forumPostTitle)),
      );
    });

    Future<PhoneWorld> openCircleEvents(WidgetTester tester) async {
      final world = PhoneWorld();
      await world.open(tester, '/circles/circle-1');
      await tester.tap(find.byKey(const ValueKey('circle-events-entry')));
      await settle(tester);
      return world;
    }

    phoneTestWidgets('events entry in the circle sidebar', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      await world.open(tester, '/circles/circle-1');
      final entry = find.byKey(const ValueKey('circle-events-entry'));
      expectFullyVisible(tester, entry);
      expectTouchTargets(tester, entry);
      expectFullyVisible(
        tester,
        find.byKey(const ValueKey('circle-events-live')),
      );
      expect(
        find.descendant(of: entry, matching: find.textContaining('Events (3)')),
        findsOneWidget,
      );
    });

    phoneTestWidgets('events list cards', (tester, viewport) async {
      await openCircleEvents(tester);
      expect(find.byKey(const ValueKey('circle-events-list')), findsOneWidget);
      final live = find.byKey(const ValueKey('circle-event-event-live'));
      expect(tester.getRect(live).width, greaterThan(viewport.size.width - 40));
      final interest = find.byKey(
        const ValueKey('circle-event-interest-event-live'),
      );
      expectFullyVisible(tester, interest);
      expectTouchTargets(tester, interest);
      expectFullyVisible(tester, find.byTooltip('Create event'));
      expectTouchTargets(tester, find.byTooltip('Create event'));
      await scrollIntoView(
        tester,
        find.byKey(const ValueKey('circle-events-show-past')),
      );
      expectFullyVisible(
        tester,
        find.byKey(const ValueKey('circle-events-show-past')),
      );
    });

    phoneTestWidgets('event detail', (tester, viewport) async {
      await openCircleEvents(tester);
      await tester.tap(
        find.text('Golden hour photo walk along the Embarcadero'),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('circle-event-detail')), findsOneWidget);
      for (final key in [
        'circle-event-detail-interest',
        'circle-event-add-to-calendar',
      ]) {
        final button = find.byKey(ValueKey(key));
        await tester.ensureVisible(button);
        await settle(tester);
        expectFullyVisible(tester, button);
        expectTouchTargets(tester, button);
      }
      expectTouchTargets(tester, find.byTooltip('Event options'));
      await scrollIntoView(
        tester,
        find.byKey(const ValueKey('circle-event-interested-list')),
      );
    });

    phoneTestWidgets('create event sheet above the keyboard', (
      tester,
      viewport,
    ) async {
      await openCircleEvents(tester);
      await tester.tap(find.byKey(const ValueKey('circle-events-create')));
      await settle(tester);
      final title = find.byKey(const ValueKey('event-title-field'));
      await showKeyboard(tester, viewport);
      expectCaretVisible(tester, title);

      final start = find.byKey(const ValueKey('event-start-button'));
      await tester.ensureVisible(start);
      await settle(tester);
      expectFullyVisible(tester, start);
      expectTouchTargets(tester, start);

      final location = find.byKey(const ValueKey('event-location-type'));
      await tester.ensureVisible(location);
      await settle(tester);
      expectFullyVisible(tester, location);
      await tester.tap(find.text('Elsewhere'));
      await settle(tester);

      final place = find.byKey(const ValueKey('event-location-field'));
      await tester.ensureVisible(place);
      await tester.tap(place);
      await tester.enterText(place, 'Dolores Park, by the tennis courts');
      await settle(tester);
      expectCaretVisible(tester, place);

      final description = find.byKey(const ValueKey('event-description-field'));
      await tester.ensureVisible(description);
      await tester.tap(description);
      await tester.enterText(description, 'Line one\nLine two\nLine three');
      await settle(tester);
      expectCaretVisible(tester, description);

      final save = find.byKey(const ValueKey('event-save'));
      await tester.ensureVisible(save);
      await settle(tester);
      expectFullyVisible(tester, save);
      expectTouchTargets(tester, save);
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
      expect(find.byKey(const ValueKey('chat-composer-field')), findsNothing);
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
      await tester.tap(find.byKey(const ValueKey('chat-composer-field')));
      await showKeyboard(tester, viewport);
      expectFullyVisible(tester, find.text('Slowmode is enabled'));
      expectFullyVisible(
        tester,
        find.byKey(const ValueKey('composer-slowmode-countdown')),
      );
      expectFullyVisible(
        tester,
        find.byKey(const ValueKey('chat-composer-field')),
      );
    });

    phoneTestWidgets('private channels show a lock', (tester, viewport) async {
      final world = PhoneWorld();
      await world.open(tester, '/circles/circle-1');
      final photos = find.text('photo-dump');
      await scrollIntoView(
        tester,
        photos,
        scrollable: find
            .descendant(
              of: find.byType(CircleChannelSidebar),
              matching: find.byType(Scrollable),
            )
            .first,
      );
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
      await tester.tap(find.byKey(const ValueKey('chat-composer-field')));
      await showKeyboard(tester, viewport);
      expectFullyVisible(
        tester,
        find.byKey(const ValueKey('chat-composer-field')),
      );
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

    phoneTestWidgets('voice channel members, call view and panel', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      world.circles.detail = circleDetailWithVoice();
      world.voice.states['circle-1'] = [
        voiceMember(
          userId: bart.id,
          name: bart.displayName,
          nickname: 'Bart the Bold',
          selfMute: true,
          video: true,
          screen: true,
        ),
        voiceMember(userId: grace.id, name: grace.displayName, selfDeaf: true),
      ];
      world.voiceCalls.prepare = (call) {
        call.remotes = [
          VoiceCallParticipant(
            userId: bart.id,
            name: 'Bart the Bold',
            isSpeaking: true,
          ),
          VoiceCallParticipant(
            userId: grace.id,
            name: grace.displayName,
            microphoneEnabled: true,
          ),
        ];
      };
      await world.open(tester, '/circles/circle-1');

      final lounge = find.byKey(const ValueKey('circle-channel-row-ch-lounge'));
      await tester.scrollUntilVisible(
        lounge,
        200,
        scrollable: find
            .descendant(
              of: find.byType(CircleChannelSidebar),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await settle(tester);
      expect(
        find.byKey(const ValueKey('voice-channel-members-ch-lounge')),
        findsOneWidget,
      );
      // Phones show a live card: who is in the channel, and a way to join.
      expect(find.textContaining('Bart the Bold'), findsOneWidget);
      expect(find.text('2 · Join'), findsOneWidget);

      await tester.tap(lounge);
      await settle(tester);
      expect(world.voice.joined, ['ch-lounge']);
      expect(find.byKey(const ValueKey('voice-call-grid')), findsOneWidget);
      expectFullyVisible(
        tester,
        find.byKey(const ValueKey('voice-control-leave')),
      );
      expectTouchTargets(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('voice-call-controls')),
          matching: find.byType(VoiceControlButton),
        ),
      );
      // The call view has its own controls; the panel waits for home.
      final panel = find.byKey(const ValueKey('voice-connected-panel'));
      expect(panel, findsNothing);
      expect(find.byKey(const ValueKey('phone-user-panel')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('voice-control-camera')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('voice-control-screen')));
      await settle(tester);
      expect(
        find.byKey(ValueKey('voice-screen-tile-${me.id}')),
        findsOneWidget,
      );

      // Back home, the panel floats above the user panel.
      world.router.go(ChatsScreen.path);
      await settle(tester);
      expect(panel, findsOneWidget);
      expectFullyVisible(tester, panel);
      expect(
        tester.getBottomLeft(panel).dy,
        lessThanOrEqualTo(
          tester.getTopLeft(find.byKey(const ValueKey('phone-user-panel'))).dy,
        ),
      );
      expectTouchTargets(
        tester,
        find.descendant(of: panel, matching: find.byType(VoiceRoundButton)),
      );
      await world.close(tester);
    });

    phoneTestWidgets('voice channel before joining', (tester, viewport) async {
      final world = PhoneWorld();
      world.circles.detail = circleDetailWithVoice();
      world.voice.states['circle-1'] = [
        for (final profile in [bart, grace, linus, ...extraMembers.take(5)])
          voiceMember(
            userId: profile.id,
            name: profile.displayName,
            channelId: 'ch-stage',
          ),
      ];
      await world.open(
        tester,
        '/circles/circle-1/channels/conv-stage',
        extra: const ChatThreadRouteExtra(
          title: 'Stage and very long voice channel name for testing',
          type: ConversationType.channel,
          circleId: 'circle-1',
        ),
      );

      expect(find.byKey(const ValueKey('voice-not-connected')), findsOneWidget);
      expect(find.text('8 people are here'), findsOneWidget);
      final join = find.byKey(const ValueKey('voice-join-button'));
      await tester.ensureVisible(join);
      await settle(tester);
      expectFullyVisible(tester, join);
      expectTouchTargets(tester, join);
      await world.close(tester);
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
      // Report waits behind More.
      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      final report = find.text('Report');
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

/// The whole tappable area of the WeCord icon button with [tooltip].
Finder _weCordButtonWithTooltip(String tooltip) {
  return find.ancestor(
    of: find.byTooltip(tooltip),
    matching: find.byType(WeCordIconButton),
  );
}

/// Scrolls [finder] to the middle of its list, clear of the floating chat
/// header and composer.
Future<void> _centerOn(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder.first), alignment: 0.5);
  await settle(tester);
}
