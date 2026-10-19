import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/features/profile/profile_social_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';

import '../../mobile/phone_test_support.dart';

Future<PhoneWorld> _open(
  WidgetTester tester, {
  List<BirthdayFriend> birthdays = const [],
  int mutualFriends = 0,
}) async {
  usePhoneViewport(tester, notchedPhone);
  final world = PhoneWorld()
    ..extraOverrides = [
      birthdaysTodayProvider.overrideWith((ref) async => birthdays),
      mutualFriendCountProvider.overrideWith(
        (ref, userId) async => mutualFriends,
      ),
    ];
  await world.open(tester, '/notifications');
  await settle(tester);
  return world;
}

Future<void> _filter(WidgetTester tester, String name) async {
  final chip = find.byKey(ValueKey('inbox-filter-$name'));
  await tester.ensureVisible(chip);
  await settle(tester);
  await tester.tap(chip);
  await settle(tester);
}

void main() {
  testWidgets('a friend\'s birthday is a card, under All and Friends', (
    tester,
  ) async {
    await _open(
      tester,
      birthdays: const [
        BirthdayFriend(userId: 'user-2', username: 'bart', displayName: 'Bart'),
      ],
    );

    expect(find.byKey(const ValueKey('birthday-card-user-2')), findsOneWidget);
    expect(
      find.textContaining('Bart has a birthday today', findRichText: true),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('birthday-wish-user-2')), findsOneWidget);

    await _filter(tester, 'friends');
    expect(find.byKey(const ValueKey('birthday-card-user-2')), findsOneWidget);
    await _filter(tester, 'mentions');
    expect(find.byKey(const ValueKey('birthday-card-user-2')), findsNothing);
  });

  testWidgets('no birthdays, no cards', (tester) async {
    await _open(tester);
    expect(find.textContaining('has a birthday today'), findsNothing);
  });

  testWidgets('a friend request says how many friends you share', (
    tester,
  ) async {
    await _open(tester, mutualFriends: 3);
    await _filter(tester, 'friends');
    expect(find.text('3 mutual friends'), findsOneWidget);
  });

  testWidgets('a request with no friends in common says nothing', (
    tester,
  ) async {
    await _open(tester);
    await _filter(tester, 'friends');
    expect(find.textContaining('mutual friend'), findsNothing);
  });

  testWidgets('the card reads in Chinese', (tester) async {
    addTearDown(() => AppStrings.isChinese = false);
    await _open(
      tester,
      birthdays: const [
        BirthdayFriend(userId: 'user-2', username: 'bart', displayName: 'Bart'),
      ],
    );
    // The app follows its language setting (English here); switch the
    // strings and rebuild the page.
    AppStrings.isChinese = true;
    await _filter(tester, 'all');
    expect(
      find.textContaining('Bart 今天生日', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('送上祝福'), findsOneWidget);
  });
}
