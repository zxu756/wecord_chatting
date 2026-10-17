import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/contact_cards/contact_card_models.dart';
import 'package:wecord/features/contact_cards/contact_card_picker.dart';
import 'package:wecord/features/contact_cards/contact_cards_repository.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../../mobile/phone_test_support.dart';
import '../chats/merged_forward/merged_forward_fakes.dart';

void main() {
  group('model', () {
    test('a person\'s card', () {
      final card = ContactCard.maybeFromAttachment({
        'kind': 'contact_card',
        'card': 'user',
        'user_id': 'u9',
        'name': 'Grace Hopper',
        'username': 'grace',
        'avatar_url': 'avatars/g.png',
      })!;
      expect(card.isUser, isTrue);
      expect(card.userId, 'u9');
      expect(card.subtitle, '@grace');
      expect(card.heading, 'Contact card: Grace Hopper');
      expect(card.avatarUrl, 'avatars/g.png');
    });

    test('a circle\'s card carries its invite and member count', () {
      final card = ContactCard.maybeFromAttachment({
        'kind': 'contact_card',
        'card': 'circle',
        'circle_id': 'c1',
        'name': 'Climbing',
        'member_count': 14,
        'invite_code': 'abcdefghij',
      })!;
      expect(card.isUser, isFalse);
      expect(card.subtitle, '14 members');
      expect(card.inviteCode, 'abcdefghij');
      expect(
        ContactCard.maybeFromAttachment({
          'kind': 'contact_card',
          'card': 'circle',
          'circle_id': 'c1',
          'name': 'Solo',
          'member_count': 1,
        })!.subtitle,
        '1 member',
      );
    });

    test('malformed cards are not cards', () {
      expect(ContactCard.maybeFromAttachment(null), isNull);
      expect(ContactCard.maybeFromAttachment({'kind': 'note'}), isNull);
      expect(
        ContactCard.maybeFromAttachment({
          'kind': 'contact_card',
          'card': 'user',
        }),
        isNull,
      );
      expect(
        ContactCard.maybeFromAttachment({
          'kind': 'contact_card',
          'card': 'pet',
        }),
        isNull,
      );
      expect(
        contactCardMessage()
            .copyWith(recalledAt: DateTime.utc(2026))
            .contactCard,
        isNull,
      );
    });

    test('only circles the user may invite to can be shared', () {
      CircleSummary circle({String? role, int? permissions}) => CircleSummary(
        id: 'c',
        name: 'c',
        memberCount: 1,
        channelCount: 1,
        currentUserRole: role,
        currentUserPermissions: permissions,
      );
      expect(canShareCircle(circle(role: 'owner')), isTrue);
      expect(
        canShareCircle(
          circle(
            role: 'member',
            permissions: CirclePermission.maskOf([
              CirclePermission.createInvites,
            ]),
          ),
        ),
        isTrue,
      );
      expect(
        canShareCircle(
          circle(
            role: 'member',
            permissions: CirclePermission.maskOf([
              CirclePermission.sendMessages,
            ]),
          ),
        ),
        isFalse,
      );
      expect(canShareCircle(circle(role: 'admin')), isTrue);
      expect(canShareCircle(circle(role: 'member')), isFalse);
      expect(canShareCircle(circle()), isFalse);
    });
  });

  group('in a chat', () {
    late PhoneWorld world;
    late FakeContactCardsRepository cards;

    setUp(() {
      cards = FakeContactCardsRepository();
      world = PhoneWorld();
      world.extraOverrides = [
        contactCardsRepositoryProvider.overrideWithValue(cards),
      ];
    });

    Future<void> openDirect(WidgetTester tester) async {
      usePhoneViewport(tester, notchedPhone);
      await world.open(
        tester,
        '${ChatsScreen.path}/dm-1',
        extra: ChatThreadRouteExtra(
          title: bart.displayName,
          type: ConversationType.direct,
        ),
      );
    }

    ChatMessage card(Map<String, dynamic> attachment, {String name = 'x'}) =>
        phoneMessage(
          'card-1',
          bart,
          'Contact card: $name',
          minutesAgo: 3,
          attachment: attachment,
        );

    testWidgets('a person\'s card shows name and username', (tester) async {
      world.chats.messages = [
        card({
          'kind': 'contact_card',
          'card': 'user',
          'user_id': bart.id,
          'name': 'Grace Hopper',
          'username': 'grace',
        }, name: 'Grace Hopper'),
      ];
      await openDirect(tester);

      expect(find.text('Grace Hopper'), findsOneWidget);
      expect(find.text('@grace'), findsOneWidget);
      expect(find.text('Contact card'), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('tapping a person\'s card opens the profile', (tester) async {
      world.chats.messages = [
        card({
          'kind': 'contact_card',
          'card': 'user',
          'user_id': bart.id,
          'name': 'Grace Hopper',
          'username': 'grace',
        }, name: 'Grace Hopper'),
      ];
      await openDirect(tester);

      await tester.tap(find.byKey(ValueKey('contact-card-${bart.id}')));
      await settle(tester);

      expect(find.byType(UserProfileView), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('tapping a circle\'s card opens its invite', (tester) async {
      world.chats.messages = [
        card({
          'kind': 'contact_card',
          'card': 'circle',
          'circle_id': 'circle-4',
          'name': 'Climbing',
          'member_count': 14,
          'invite_code': 'abcdefghij',
        }, name: 'Climbing'),
      ];
      await openDirect(tester);

      expect(find.text('14 members'), findsOneWidget);
      expect(find.text('Circle invite'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('contact-card-circle-4')));
      await settle(tester);

      expect(world.router.state.uri.path, '/invite/abcdefghij');
      // The existing invite page: preview and Join.
      expect(find.text('Join circle'), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('the + menu sends a friend as a card', (tester) async {
      await openDirect(tester);

      await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('composer-contact-card-entry')),
      );
      await settle(tester);

      expect(find.text('Friends'), findsWidgets);
      // The friends of the world, searchable.
      expect(
        find.byKey(ValueKey('contact-card-friend-${bart.id}')),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).last, 'grandma');
      await settle(tester);
      expect(
        find.byKey(ValueKey('contact-card-friend-${bart.id}')),
        findsNothing,
      );

      await tester.enterText(find.byType(TextField).last, '');
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('contact-card-friend-${bart.id}')));
      await settle(tester);

      expect(cards.sent, hasLength(1));
      expect(cards.sent.single.kind, ContactCardKind.user);
      expect(cards.sent.single.targetId, bart.id);
      expect(cards.sent.single.conversationId, 'dm-1');
      expect(find.text('Contact card sent'), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('only circles that can be invited to are offered', (
      tester,
    ) async {
      world.circles.circles = [
        const CircleSummary(
          id: 'mine',
          name: 'Mine',
          memberCount: 3,
          channelCount: 1,
          currentUserRole: 'owner',
        ),
        CircleSummary(
          id: 'invites-ok',
          name: 'Open door',
          memberCount: 30,
          channelCount: 1,
          currentUserRole: 'member',
          currentUserPermissions: CirclePermission.maskOf([
            CirclePermission.viewChannel,
            CirclePermission.createInvites,
          ]),
        ),
        CircleSummary(
          id: 'closed',
          name: 'Closed door',
          memberCount: 30,
          channelCount: 1,
          currentUserRole: 'member',
          currentUserPermissions: CirclePermission.maskOf([
            CirclePermission.viewChannel,
          ]),
        ),
      ];
      await openDirect(tester);

      await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('composer-contact-card-entry')),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('contact-card-tab-circles')));
      await settle(tester);

      expect(
        find.byKey(const ValueKey('contact-card-circle-mine')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('contact-card-circle-invites-ok')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('contact-card-circle-closed')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('contact-card-circle-invites-ok')),
      );
      await settle(tester);
      expect(cards.sent.single.kind, ContactCardKind.circle);
      expect(cards.sent.single.targetId, 'invites-ok');
      await world.close(tester);
    });

    testWidgets('a refused card says why and stays', (tester) async {
      cards.failWith = const ContactCardRefusedException();
      await openDirect(tester);

      await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('composer-contact-card-entry')),
      );
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('contact-card-friend-${bart.id}')));
      await settle(tester);

      expect(find.text('This contact cannot be shared.'), findsOneWidget);
      expect(
        find.byKey(ValueKey('contact-card-friend-${bart.id}')),
        findsOneWidget,
      );
      await world.close(tester);
    });
  });
}
