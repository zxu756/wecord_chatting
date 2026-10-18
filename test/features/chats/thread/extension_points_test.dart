import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart'
    show GlassMenuEntry;
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/message_action_menu.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer_builtin.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer_registrations.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu_builtin.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu_registrations.dart';
import 'package:wecord/features/chats/thread/registry/header_actions.dart';
import 'package:wecord/features/chats/thread/registry/header_actions_builtin.dart';
import 'package:wecord/features/chats/thread/registry/header_actions_registrations.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/features/chats/thread/registry/message_actions_builtin.dart';
import 'package:wecord/features/chats/thread/registry/message_actions_registrations.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../../mobile/phone_test_support.dart';

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

/// A feature plugs into the chat page from its own file: here all four
/// registries get one extra entry and the page shows each of them, in place.
void main() {
  testWidgets('features extend the page through the four registries', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      usePhoneViewport(tester, _desktop);
      final world = PhoneWorld();
      world.chats.messages = [
        phoneMessage('m1', bart, 'Morning everyone', minutesAgo: 5),
      ];
      world.extraOverrides = [
        messageActionRegistryProvider.overrideWithValue(
          MessageActionRegistry([
            ...builtInMessageActions,
            ...messageActionExtensions,
            MessageActionContribution(
              id: 'demo',
              order: 650,
              build: (ctx) => [
                MessageAction(
                  icon: Icons.star,
                  label: 'Demo action',
                  onSelected: () {},
                ),
              ],
            ),
          ]),
        ),
        bubbleFooterRegistryProvider.overrideWithValue(
          BubbleFooterRegistry([
            ...builtInBubbleFooterEntries,
            ...bubbleFooterExtensions,
            BubbleFooterEntry.below(
              id: 'demo',
              order: 700,
              build: (ctx) => Text('Demo footer for ${ctx.message.id}'),
            ),
          ]),
        ),
        composerMenuRegistryProvider.overrideWithValue(
          ComposerMenuRegistry([
            ...builtInComposerMenu,
            ...composerMenuExtensions,
            ComposerMenuContribution(
              id: 'demo',
              order: 350,
              build: (ctx) => GlassMenuEntry(
                icon: Icons.star,
                label: 'Demo entry',
                onSelected: () {},
              ),
            ),
          ]),
        ),
        headerActionRegistryProvider.overrideWithValue(
          HeaderActionRegistry([
            ...builtInHeaderActions,
            ...headerActionExtensions,
            HeaderActionContribution(
              id: 'demo',
              order: 950,
              build: (ctx) => ChatThreadAction(
                id: 'demo',
                tooltip: 'Demo header action',
                icon: Icons.star,
                onPressed: () {},
              ),
            ),
          ]),
        ),
      ];
      await world.open(
        tester,
        '${ChatsScreen.path}/dm-1',
        extra: ChatThreadRouteExtra(
          title: bart.displayName,
          type: ConversationType.direct,
        ),
      );

      // The footer slot.
      expect(find.text('Demo footer for m1'), findsOneWidget);

      // The header: not primary, so it is in More.
      expect(find.byTooltip('Demo header action'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('chat-header-more')));
      await tester.pumpAndSettle();
      expect(find.text('Demo header action'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // The "+" menu, between Create poll (300) and Contact card (500).
      await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
      await tester.pumpAndSettle();
      final poll = tester.getCenter(find.text('Create poll')).dy;
      final demo = tester.getCenter(find.text('Demo entry')).dy;
      final contact = tester.getCenter(find.text('Contact card')).dy;
      expect(poll, lessThan(demo));
      expect(demo, lessThan(contact));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // The message menu, between Edit (600) and Create task (700): the
      // message is someone else's, so after Forward (300) and before Create
      // task.
      await tester.tap(
        find.text('Morning everyone'),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      final forward = tester.getCenter(find.text('Forward')).dy;
      final action = tester.getCenter(find.text('Demo action')).dy;
      final task = tester.getCenter(find.text('Create task')).dy;
      expect(forward, lessThan(action));
      expect(action, lessThan(task));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
