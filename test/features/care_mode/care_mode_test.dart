import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/care_mode/care_home_shortcuts.dart';
import 'package:wecord/features/care_mode/care_mode_host.dart';
import 'package:wecord/features/care_mode/care_mode_screen.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/care_mode/care_registry_filters.dart';
import 'package:wecord/features/care_mode/read_aloud.dart';
import 'package:wecord/features/care_mode/speech_reader.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu_registrations.dart';
import 'package:wecord/features/chats/thread/registry/header_actions_registrations.dart';
import 'package:wecord/features/chats/thread/registry/message_actions_registrations.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/moments/moments_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../../mobile/phone_test_support.dart';
import 'care_fakes.dart';

/// The widget tests here run on one phone; the sizes at other phones are
/// covered by the accessibility screens.
void phoneTest(
  String description,
  Future<void> Function(WidgetTester tester, PhoneViewport viewport) body,
) => phoneTestWidgets(description, body, viewports: const [notchedPhone]);

void main() {
  group('text size', () {
    test('grows the system size by 1.3 and stops at 2.0', () {
      double at(double system) =>
          CareTextScaler(TextScaler.linear(system)).scale(10) / 10;
      expect(at(1), closeTo(1.3, 1e-9));
      expect(at(0.8), closeTo(1.04, 1e-9));
      // 1.6 x 1.3 would be 2.08: capped at what the layouts are checked at.
      expect(at(1.6), closeTo(2.0, 1e-9));
      // Already past the ceiling: the system size alone, never smaller.
      expect(at(2.0), closeTo(2.0, 1e-9));
      expect(at(2.5), closeTo(2.5, 1e-9));
    });

    test('scalers with the same numbers are equal', () {
      expect(
        const CareTextScaler(TextScaler.linear(1)),
        const CareTextScaler(TextScaler.linear(1)),
      );
      expect(
        const CareTextScaler(TextScaler.linear(1)),
        isNot(const CareTextScaler(TextScaler.linear(1.2))),
      );
    });
  });

  group('choices', () {
    test('start off, with the options on', () {
      const settings = CareModeSettings();
      expect(settings.enabled, isFalse);
      expect(settings.simplifies, isFalse);
      expect(settings.readsAloud, isFalse);
      expect(settings.forcesHighContrast, isFalse);
      expect(settings.simpleHome, isTrue);
      expect(settings.readAloud, isTrue);
      expect(settings.highContrast, isFalse);
    });

    test('options only count while the switch is on', () {
      const on = CareModeSettings(enabled: true, highContrast: true);
      expect(on.simplifies, isTrue);
      expect(on.readsAloud, isTrue);
      expect(on.forcesHighContrast, isTrue);
      final off = on.copyWith(enabled: false);
      expect(off.simplifies, isFalse);
      expect(off.readsAloud, isFalse);
      expect(off.forcesHighContrast, isFalse);
    });

    test('are read from the store at once and saved when changed', () async {
      final store = InMemoryCareModeStore(
        const CareModeSettings(enabled: true, readAloud: false),
      );
      final container = ProviderContainer(
        overrides: [careModeStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      // No waiting: the first frame already has them.
      expect(container.read(careModeProvider).enabled, isTrue);
      expect(container.read(careModeProvider).readAloud, isFalse);

      await container.read(careModeProvider.notifier).setHighContrast(true);
      expect(container.read(careModeProvider).highContrast, isTrue);
      expect(store.saved?.highContrast, isTrue);
      expect(store.saved?.enabled, isTrue);

      // Turning the mode off keeps the options for next time.
      await container.read(careModeProvider.notifier).setEnabled(false);
      expect(store.saved?.enabled, isFalse);
      expect(store.saved?.highContrast, isTrue);
      expect(store.saved?.readAloud, isFalse);
    });
  });

  group('reading aloud', () {
    test('picks the language from the words', () {
      expect(speechLanguageFor('晚上七点见', appIsChinese: false), 'zh-CN');
      expect(speechLanguageFor('See you at 7', appIsChinese: true), 'en-US');
      expect(speechLanguageFor('7:30', appIsChinese: true), 'zh-CN');
      expect(speechLanguageFor('7:30', appIsChinese: false), 'en-US');
      expect(speechLanguageFor('Hello 你好', appIsChinese: false), 'zh-CN');
    });

    test('speaks the words without markdown marks, line by line', () {
      ChatMessage message(String body, {MessageType? type}) => phoneMessage(
        'm',
        bart,
        body,
        minutesAgo: 1,
        type: type ?? MessageType.text,
      );
      expect(readAloudTextFor(message('**Dinner** at _seven_')), isNotEmpty);
      expect(
        readAloudTextFor(message('**Dinner** at seven')),
        'Dinner at seven',
      );
      expect(readAloudTextFor(message('One\nTwo')), 'One. Two');
      expect(readAloudTextFor(message('', type: MessageType.image)), '');
    });
  });

  group('menus', () {
    ProviderContainer containerWith(CareModeSettings settings) {
      final container = ProviderContainer(
        overrides: [
          careModeStoreProvider.overrideWithValue(
            InMemoryCareModeStore(settings),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('keep every entry while Care mode is off', () {
      final container = containerWith(const CareModeSettings());
      final messages = container.read(messageActionRegistryProvider).ids;
      expect(
        messages,
        containsAll(
          careHiddenMessageActionIds.intersection({
            'create-task',
            'pin',
            'thread',
            'remind',
            'select',
            'publish',
            'remove-embed',
          }),
        ),
      );
      expect(messages, contains('read-aloud'));
      expect(
        container.read(headerActionRegistryProvider).ids,
        containsAll(['notes', 'wallpaper', 'summarize']),
      );
      expect(
        container.read(composerMenuRegistryProvider).ids,
        containsAll(['poll', 'chain', 'schedule']),
      );
    });

    test('drop the rarely used entries with the simple home', () {
      final container = containerWith(const CareModeSettings(enabled: true));
      final messages = container.read(messageActionRegistryProvider).ids;
      expect(messages, containsAll(['reply', 'copy', 'read-aloud', 'delete']));
      expect(messages, isNot(contains('create-task')));
      expect(messages, isNot(contains('remind')));
      expect(messages, isNot(contains('thread')));
      final header = container.read(headerActionRegistryProvider).ids;
      expect(header, containsAll(['search', 'call', 'video-call', 'media']));
      expect(header, isNot(contains('notes')));
      expect(header, isNot(contains('wallpaper')));
      final composer = container.read(composerMenuRegistryProvider).ids;
      expect(composer, containsAll(['photos-and-videos', 'files', 'sticker']));
      expect(composer, isNot(contains('poll')));
      expect(composer, isNot(contains('schedule')));
    });

    test('come back with everything when the simple home is off', () {
      final container = containerWith(
        const CareModeSettings(enabled: true, simpleHome: false),
      );
      expect(
        container.read(messageActionRegistryProvider).ids,
        contains('create-task'),
      );
      expect(
        container.read(headerActionRegistryProvider).ids,
        contains('notes'),
      );
    });

    test('keep a menu already read untouched when the mode changes', () async {
      final container = containerWith(const CareModeSettings());
      final before = container.read(messageActionRegistryProvider);
      await container.read(careModeProvider.notifier).setEnabled(true);
      final after = container.read(messageActionRegistryProvider);
      expect(identical(before, after), isFalse);
      expect(after.ids, isNot(contains('create-task')));
    });
  });

  group('on the phone', () {
    phoneTest('the switch in Settings turns it on and off', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      await world.open(tester, '/me');
      final switchRow = find.byKey(CareModeSettingsGroup.switchKey);
      await scrollIntoView(tester, switchRow);
      expect(find.byKey(CareModeSettingsGroup.optionsKey), findsNothing);
      final normal = tester.getSize(find.text('Care mode').first).height;

      await tester.tap(switchRow);
      await settle(tester);
      expect(world.careStore.saved?.enabled, isTrue);
      // The options row appears, and the text is bigger.
      expect(find.byKey(CareModeSettingsGroup.optionsKey), findsOneWidget);
      final care = tester.getSize(find.text('Care mode').first).height;
      expect(care, greaterThan(normal * 1.2));

      await tester.tap(switchRow);
      await settle(tester);
      expect(world.careStore.saved?.enabled, isFalse);
      expect(find.byKey(CareModeSettingsGroup.optionsKey), findsNothing);
      expect(tester.getSize(find.text('Care mode').first).height, normal);
      await world.close(tester);
    });

    phoneTest('the options page changes the options', (tester, viewport) async {
      final world = PhoneWorld();
      world.careStore.initial = const CareModeSettings(enabled: true);
      await world.open(tester, '/me');
      final options = find.byKey(CareModeSettingsGroup.optionsKey);
      await scrollIntoView(tester, options);
      await tester.tap(options);
      await settle(tester);
      expect(find.byKey(const ValueKey('care-mode-screen')), findsOneWidget);

      await tester.tap(find.byKey(CareModeScreen.readAloudKey));
      await settle(tester);
      expect(world.careStore.saved?.readAloud, isFalse);
      await scrollIntoView(tester, find.byKey(CareModeScreen.highContrastKey));
      await tester.tap(find.byKey(CareModeScreen.highContrastKey));
      await settle(tester);
      expect(world.careStore.saved?.highContrast, isTrue);
      await world.close(tester);
    });

    phoneTest('the simple home has no rail, folders or small shortcuts', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      await world.open(tester, '/home');
      expect(find.byType(CircleRail), findsOneWidget);
      expect(find.byKey(const ValueKey('phone-friends-row')), findsOneWidget);
      expect(find.byKey(CareHomeShortcuts.friendsKey), findsNothing);
      await world.close(tester);

      final care = PhoneWorld();
      care.careStore.initial = const CareModeSettings(enabled: true);
      await care.open(tester, '/home');
      expect(find.byType(CircleRail), findsNothing);
      expect(find.byKey(const ValueKey('phone-friends-row')), findsNothing);
      expect(find.byKey(CareHomeShortcuts.friendsKey), findsOneWidget);
      expect(find.byKey(CareHomeShortcuts.momentsKey), findsOneWidget);
      // The chats are still there.
      expect(find.byKey(const ValueKey('home-dm-dm-1')), findsOneWidget);

      // With the simple home off, only the sizes change.
      await care.close(tester);
      final bigOnly = PhoneWorld();
      bigOnly.careStore.initial = const CareModeSettings(
        enabled: true,
        simpleHome: false,
      );
      await bigOnly.open(tester, '/home');
      expect(find.byType(CircleRail), findsOneWidget);
      expect(find.byKey(CareHomeShortcuts.friendsKey), findsNothing);
      await bigOnly.close(tester);
    });

    phoneTest('the tiles open Friends and Moments', (tester, viewport) async {
      final world = PhoneWorld();
      world.careStore.initial = const CareModeSettings(enabled: true);
      await world.open(tester, '/home');
      await tester.tap(find.byKey(CareHomeShortcuts.friendsKey));
      await settle(tester);
      expect(find.byType(ContactsScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Back').first);
      await settle(tester);
      expect(find.byType(ContactsScreen), findsNothing);
      await tester.tap(find.byKey(CareHomeShortcuts.momentsKey));
      await settle(tester);
      expect(find.byType(MomentsScreen), findsOneWidget);
      await world.close(tester);
    });

    phoneTest('buttons and round buttons are at least 56 tall', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      world.careStore.initial = const CareModeSettings(enabled: true);
      await world.open(tester, '/home');
      final search = tester.getSize(
        find
            .descendant(
              of: find.byKey(const ValueKey('phone-home-search')),
              matching: find.byType(WeCordTapTarget),
            )
            .first,
      );
      expect(search.width, greaterThanOrEqualTo(56));
      expect(search.height, greaterThanOrEqualTo(56));
      await world.close(tester);
    });

    phoneTest('the stronger colors option uses the high contrast set', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      world.careStore.initial = const CareModeSettings(
        enabled: true,
        highContrast: true,
      );
      await world.open(tester, '/home');
      expect(
        Theme.of(
          tester.element(find.byType(Scaffold).first),
        ).extension<WeCordTokens>()?.highContrast,
        isTrue,
      );
      await world.close(tester);
    });

    phoneTest('switching keeps the draft in an open chat', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      world.chats.messages = [
        phoneMessage('m1', bart, 'Dinner at seven works', minutesAgo: 5),
      ];
      await world.open(
        tester,
        '${ChatsScreen.path}/dm-1',
        extra: ChatThreadRouteExtra(
          title: bart.displayName,
          type: ConversationType.direct,
        ),
      );
      final composer = find.byKey(const ValueKey('chat-composer-field'));
      await tester.enterText(composer, 'On my way, wait for me');
      await settle(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatThreadScreen)),
      );
      final before = tester.getSize(
        find.textContaining('Dinner at seven').first,
      );

      await container.read(careModeProvider.notifier).setEnabled(true);
      await settle(tester);
      expect(
        tester.widget<TextField>(composer).controller?.text,
        'On my way, wait for me',
      );
      // The same page, now with bigger text.
      expect(
        tester.getSize(find.textContaining('Dinner at seven').first).height,
        greaterThan(before.height),
      );

      await container.read(careModeProvider.notifier).setEnabled(false);
      await settle(tester);
      expect(
        tester.widget<TextField>(composer).controller?.text,
        'On my way, wait for me',
      );
      expect(
        tester.getSize(find.textContaining('Dinner at seven').first),
        before,
      );
      await world.close(tester);
    });

    phoneTest('switching keeps the chats list where it was scrolled', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld();
      await world.open(tester, '/home');
      final container = ProviderScope.containerOf(
        tester.element(
          find.byType(CareHomeShortcuts).evaluate().isEmpty
              ? find.byKey(const ValueKey('phone-messages-list'))
              : find.byType(CareHomeShortcuts),
        ),
      );
      final list = find.byKey(const ValueKey('phone-messages-list'));
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      final state = tester.state(scrollable.first);
      await container.read(careModeProvider.notifier).setEnabled(true);
      await settle(tester);
      expect(list, findsOneWidget);
      // The list is the same widget and state, not a new one.
      expect(tester.state(scrollable.first), same(state));
      await world.close(tester);
    });
  });

  group('read aloud in a chat', () {
    Future<void> openChat(
      WidgetTester tester,
      PhoneWorld world, {
      CareModeSettings? settings,
    }) async {
      world.careStore.initial =
          settings ?? const CareModeSettings(enabled: true);
      world.chats.messages = [
        phoneMessage(
          'm1',
          bart,
          '**Dinner** at seven, bring the photos',
          minutesAgo: 5,
        ),
        phoneMessage('m2', bart, '晚上七点见', minutesAgo: 4),
      ];
      await world.open(
        tester,
        '${ChatsScreen.path}/dm-1',
        extra: ChatThreadRouteExtra(
          title: bart.displayName,
          type: ConversationType.direct,
        ),
      );
    }

    Future<void> longPress(WidgetTester tester, String text) async {
      final message = find.textContaining(text, findRichText: true);
      await tester.longPress(message.first);
      await settle(tester);
    }

    phoneTest('long-press, Read aloud reads the message and can stop', (
      tester,
      viewport,
    ) async {
      final reader = FakeSpeechReader();
      final world = PhoneWorld()..extraOverrides = careVoice(reader);
      await openChat(tester, world);
      await longPress(tester, 'bring the photos');
      expect(find.text('Read aloud'), findsOneWidget);
      // The everyday entries are there, the rare ones are not.
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Create task'), findsNothing);

      await tester.tap(find.text('Read aloud'));
      await settle(tester);
      expect(reader.spoken, hasLength(1));
      expect(reader.spoken.single.text, 'Dinner at seven, bring the photos');
      expect(reader.spoken.single.language, 'en-US');
      expect(find.text('Reading aloud'), findsOneWidget);

      await tester.tap(find.text('Stop'));
      await settle(tester);
      expect(reader.stops, 1);
      expect(find.text('Reading aloud'), findsNothing);
      await world.close(tester);
    });

    phoneTest('reads Chinese in Chinese and closes when it ends', (
      tester,
      viewport,
    ) async {
      final reader = FakeSpeechReader();
      final world = PhoneWorld()..extraOverrides = careVoice(reader);
      await openChat(tester, world);
      await longPress(tester, '晚上七点见');
      await tester.tap(find.text('Read aloud'));
      await settle(tester);
      expect(reader.spoken.single.language, 'zh-CN');
      expect(find.text('Reading aloud'), findsOneWidget);

      reader.finish();
      await settle(tester);
      expect(find.text('Reading aloud'), findsNothing);
      await world.close(tester);
    });

    phoneTest('says so when the device cannot read', (tester, viewport) async {
      final reader = FakeSpeechReader(fails: true);
      final world = PhoneWorld()..extraOverrides = careVoice(reader);
      await openChat(tester, world);
      await longPress(tester, 'bring the photos');
      await tester.tap(find.text('Read aloud'));
      await settle(tester);
      expect(find.text("This device can't read aloud."), findsOneWidget);
      await world.close(tester);
    });

    phoneTest('is not offered when Care mode is off', (tester, viewport) async {
      final world = PhoneWorld()
        ..extraOverrides = careVoice(FakeSpeechReader());
      await openChat(tester, world, settings: const CareModeSettings());
      await longPress(tester, 'bring the photos');
      expect(find.text('Read aloud'), findsNothing);
      // Every entry of the normal menu is still there.
      expect(find.text('Create task'), findsOneWidget);
      await world.close(tester);
    });

    phoneTest('is not offered when the option is off', (
      tester,
      viewport,
    ) async {
      final world = PhoneWorld()
        ..extraOverrides = careVoice(FakeSpeechReader());
      await openChat(
        tester,
        world,
        settings: const CareModeSettings(enabled: true, readAloud: false),
      );
      await longPress(tester, 'bring the photos');
      expect(find.text('Read aloud'), findsNothing);
      await world.close(tester);
    });

    test('has Chinese for the menu entry and the switch', () {
      AppStrings.isChinese = true;
      addTearDown(() => AppStrings.isChinese = false);
      expect(tr('Read aloud'), '朗读');
      expect(tr('Care mode'), '关怀模式');
    });
  });
}
