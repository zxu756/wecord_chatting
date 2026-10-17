import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/features/voice_input/voice_input_settings.dart';
import 'package:wecord/features/voice_input/voice_recognizer.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../chats/chat_thread_screen_test.dart' as chat_fakes;
import 'fake_voice_recognizer.dart';

Widget app(FakeVoiceRecognizer recognizer, {bool? show}) {
  final chats = chat_fakes.FakeChatsRepository()
    ..conversations = [
      const ConversationSummary(
        id: 'conversation-1',
        type: ConversationType.group,
        unreadCount: 0,
        title: 'Hike club',
      ),
    ];
  return ProviderScope(
    overrides: [
      chatsRepositoryProvider.overrideWithValue(chats),
      voiceRecognizerProvider.overrideWithValue(recognizer),
      voiceInputStoreProvider.overrideWithValue(
        InMemoryVoiceInputStore(show: show),
      ),
      settingsRepositoryProvider.overrideWithValue(
        chat_fakes.FakeSettingsRepository(),
      ),
      onlineUserIdsProvider.overrideWith(
        (ref) => const Stream<Set<String>>.empty(),
      ),
      authRepositoryProvider.overrideWithValue(
        chat_fakes.FakeAuthRepository()
          ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
      ),
    ],
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: const ChatThreadScreen(conversationId: 'conversation-1'),
    ),
  );
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  const voiceButton = ValueKey('composer-voice-input-button');
  const field = ValueKey('chat-composer-field');

  testWidgets('on a phone voice input takes the GIF button\'s place', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(app(FakeVoiceRecognizer()));
    await tester.pump();

    expect(find.byKey(voiceButton), findsOneWidget);
    expect(find.byTooltip('Send GIF'), findsNothing);
    // GIFs are still in the Attach menu.
    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await tester.pumpAndSettle();
    expect(find.text('Send GIF'), findsOneWidget);
  });

  testWidgets('wide screens add it beside the emoji button', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(FakeVoiceRecognizer()));
    await tester.pump();

    expect(find.byKey(voiceButton), findsOneWidget);
    expect(find.byTooltip('Send GIF'), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-mic-button')), findsOneWidget);
  });

  testWidgets('where the platform cannot dictate nothing changes', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(app(FakeVoiceRecognizer(supported: false)));
    await tester.pump();

    expect(find.byKey(voiceButton), findsNothing);
    expect(find.byTooltip('Send GIF'), findsOneWidget);
  });

  testWidgets('the Settings switch hides it', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(FakeVoiceRecognizer(), show: false));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(voiceButton), findsNothing);
    expect(find.byTooltip('Send GIF'), findsOneWidget);
  });

  testWidgets(
    'speaking fills the message box, ready to edit and send as text',
    (tester) async {
      phone(tester);
      final recognizer = FakeVoiceRecognizer();
      await tester.pumpWidget(app(recognizer));
      await tester.pump();

      await tester.tap(find.byKey(voiceButton));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('voice-input-panel')), findsOneWidget);

      recognizer.session.say('see you at the gate');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byKey(field)).controller!.text,
        'see you at the gate',
      );
      // Text is there, so the phone offers Send rather than the microphone.
      expect(
        find.byKey(const ValueKey('composer-send-button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('voice-done')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-input-panel')), findsNothing);
      expect(
        tester.widget<TextField>(find.byKey(field)).controller!.text,
        'see you at the gate',
      );

      // It is ordinary text now: it can be edited.
      await tester.enterText(find.byKey(field), 'see you at the north gate');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byKey(field)).controller!.text,
        'see you at the north gate',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
