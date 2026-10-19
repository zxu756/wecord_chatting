import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/chats/chats_repository.dart'
    show ChatImageUpload;
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/feature_flags/feature_flags_providers.dart';
import 'package:wecord/features/feedback/feedback_entry.dart';
import 'package:wecord/features/feedback/feedback_repository.dart';
import 'package:wecord/features/feedback/feedback_screen.dart';
import 'package:wecord/features/photo_editor/photo_editor_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A small PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEElEQVR4nGMIqDgBRwzEcQCC0hkBcFCiJwAAAABJRU5ErkJggg==',
);

class _FakeFiles implements FeedbackFiles {
  _FakeFiles({this.userId = 'user-1'});

  @override
  final String? userId;

  final uploaded = <String, Uint8List>{};
  final removed = <String>[];
  Object? uploadError;

  @override
  Future<void> upload(String path, Uint8List bytes) async {
    final error = uploadError;
    if (error != null) {
      throw error;
    }
    uploaded[path] = bytes;
  }

  @override
  Future<void> remove(String path) async => removed.add(path);
}

class _FakeFeedbackRepository implements FeedbackRepository {
  final sent =
      <({String message, String platform, String version, Uint8List? shot})>[];
  Object? error;

  @override
  Future<void> submit({
    required String message,
    required String platform,
    required String version,
    Uint8List? screenshot,
  }) async {
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    sent.add((
      message: message,
      platform: platform,
      version: version,
      shot: screenshot,
    ));
  }
}

class _FakePicker implements ImagePickerService {
  _FakePicker(this.upload);

  final ChatImageUpload? upload;
  var picks = 0;

  @override
  Future<ChatImageUpload?> pickImage() async {
    picks++;
    return upload;
  }
}

ChatImageUpload _picture() => ChatImageUpload(
  bytes: _png,
  fileName: 'IMG_0001.HEIC',
  mimeType: 'image/heic',
);

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('sending', () {
    test('a message alone makes one call and no upload', () async {
      final files = _FakeFiles();
      final calls = <(String, Map<String, dynamic>)>[];
      final repository = SupabaseFeedbackRepository(
        (name, params) async {
          calls.add((name, params));
          return 'id-1';
        },
        files,
        newId: () => 'uuid-1',
      );
      await repository.submit(
        message: '  It crashes  ',
        platform: 'ios',
        version: '1.4.0',
      );
      expect(files.uploaded, isEmpty);
      expect(calls, hasLength(1));
      expect(calls.single.$1, 'submit_feedback');
      expect(calls.single.$2, {
        'feedback_message': 'It crashes',
        'client_platform': 'ios',
        'client_version': '1.4.0',
        'screenshot_object_path': null,
      });
    });

    test('a screenshot goes into the sender\'s own folder first', () async {
      final files = _FakeFiles();
      final calls = <Map<String, dynamic>>[];
      final repository = SupabaseFeedbackRepository(
        (name, params) async {
          // The file is already there when the server is asked.
          expect(files.uploaded, hasLength(1));
          calls.add(params);
          return 'id-1';
        },
        files,
        newId: () => 'uuid-1',
      );
      await repository.submit(
        message: 'See',
        platform: 'web',
        version: '1.4.0',
        screenshot: _png,
      );
      expect(files.uploaded.keys, ['user-1/uuid-1.jpg']);
      expect(calls.single['screenshot_object_path'], 'user-1/uuid-1.jpg');
    });

    test('a refused message leaves no file behind', () async {
      final files = _FakeFiles();
      final repository = SupabaseFeedbackRepository(
        (name, params) async => throw PostgrestException(
          message: 'Too many feedback messages. Try again later.',
          code: 'PB429',
        ),
        files,
        newId: () => 'uuid-1',
      );
      await expectLater(
        repository.submit(
          message: 'See',
          platform: 'web',
          version: '1.4.0',
          screenshot: _png,
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect(files.removed, ['user-1/uuid-1.jpg']);
    });

    test('a failed upload sends nothing', () async {
      final files = _FakeFiles()..uploadError = StateError('offline');
      var asked = false;
      final repository = SupabaseFeedbackRepository((name, params) async {
        asked = true;
        return null;
      }, files);
      await expectLater(
        repository.submit(
          message: 'See',
          platform: 'web',
          version: '1.4.0',
          screenshot: _png,
        ),
        throwsStateError,
      );
      expect(asked, isFalse);
    });

    test('nobody signed in cannot attach a file', () async {
      final repository = SupabaseFeedbackRepository(
        (name, params) async => null,
        _FakeFiles(userId: null),
      );
      await expectLater(
        repository.submit(
          message: 'See',
          platform: 'web',
          version: '1.4.0',
          screenshot: _png,
        ),
        throwsStateError,
      );
    });
  });

  group('the page', () {
    late _FakeFeedbackRepository repository;

    Future<void> open(
      WidgetTester tester, {
      _FakePicker? picker,
      Future<Uint8List?> Function(Uint8List, String)? prepare,
    }) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      repository = _FakeFeedbackRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedbackRepositoryProvider.overrideWithValue(repository),
            appVersionProvider.overrideWithValue('1.4.0'),
            appPlatformProvider.overrideWithValue('web'),
            if (picker != null)
              imagePickerServiceProvider.overrideWithValue(picker),
            feedbackScreenshotPreparerProvider.overrideWithValue(
              prepare ?? (bytes, name) async => bytes,
            ),
          ],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: const FeedbackScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    bool sendEnabled(WidgetTester tester) =>
        tester
            .widget<WeCordButton>(find.byKey(FeedbackScreen.sendKey))
            .onPressed !=
        null;

    testWidgets('says what is added and what is not', (tester) async {
      await open(tester);
      expect(
        find.text(
          'We add your WeCord version (1.4.0) and your platform (web). '
          'Nothing from your chats is sent.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('cannot send an empty message', (tester) async {
      await open(tester);
      expect(sendEnabled(tester), isFalse);
      await tester.enterText(find.byKey(FeedbackScreen.messageKey), '   ');
      await tester.pump();
      expect(sendEnabled(tester), isFalse);
      await tester.enterText(find.byKey(FeedbackScreen.messageKey), 'Hello');
      await tester.pump();
      expect(sendEnabled(tester), isTrue);
    });

    testWidgets('sends the message with the version and platform', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(
        find.byKey(FeedbackScreen.messageKey),
        'The send button is hidden',
      );
      await tester.pump();
      await tester.tap(find.byKey(FeedbackScreen.sendKey));
      await tester.pumpAndSettle();
      expect(repository.sent, hasLength(1));
      expect(repository.sent.single.message, 'The send button is hidden');
      expect(repository.sent.single.platform, 'web');
      expect(repository.sent.single.version, '1.4.0');
      expect(repository.sent.single.shot, isNull);
      expect(find.text('Thank you, we got it.'), findsOneWidget);
      expect(find.byKey(FeedbackScreen.sendKey), findsNothing);
    });

    testWidgets('a screenshot is shown before it is sent, and can be removed', (
      tester,
    ) async {
      final picker = _FakePicker(_picture());
      Uint8List? preparedFrom;
      await open(
        tester,
        picker: picker,
        prepare: (bytes, name) async {
          preparedFrom = bytes;
          return Uint8List.fromList([...bytes, 1]);
        },
      );
      expect(find.byKey(FeedbackScreen.addScreenshotKey), findsOneWidget);
      await tester.tap(find.byKey(FeedbackScreen.addScreenshotKey));
      await tester.pumpAndSettle();
      expect(picker.picks, 1);
      expect(preparedFrom, _png);
      expect(
        find.byKey(const ValueKey('feedback-screenshot-preview')),
        findsOneWidget,
      );
      expect(
        find.text('Cover anything private before you send it.'),
        findsOneWidget,
      );
      expect(find.byKey(FeedbackScreen.editScreenshotKey), findsOneWidget);

      await tester.tap(find.byKey(FeedbackScreen.removeScreenshotKey));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('feedback-screenshot-preview')),
        findsNothing,
      );
      expect(find.byKey(FeedbackScreen.addScreenshotKey), findsOneWidget);
    });

    testWidgets('the screenshot that was prepared is the one sent', (
      tester,
    ) async {
      await open(
        tester,
        picker: _FakePicker(_picture()),
        prepare: (bytes, name) async => Uint8List.fromList([...bytes, 9]),
      );
      await tester.tap(find.byKey(FeedbackScreen.addScreenshotKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(FeedbackScreen.messageKey), 'See');
      await tester.pump();
      await tester.tap(find.byKey(FeedbackScreen.sendKey));
      await tester.pumpAndSettle();
      expect(repository.sent.single.shot, Uint8List.fromList([..._png, 9]));
    });

    testWidgets('hiding private parts opens the photo editor', (tester) async {
      await open(tester, picker: _FakePicker(_picture()));
      await tester.tap(find.byKey(FeedbackScreen.addScreenshotKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(FeedbackScreen.editScreenshotKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(PhotoEditorScreen), findsOneWidget);
    });

    testWidgets('a picture that cannot be read says so', (tester) async {
      await open(
        tester,
        picker: _FakePicker(_picture()),
        prepare: (bytes, name) async => null,
      );
      await tester.tap(find.byKey(FeedbackScreen.addScreenshotKey));
      await tester.pumpAndSettle();
      expect(
        find.text('That picture could not be read. Try another.'),
        findsOneWidget,
      );
      expect(find.byKey(FeedbackScreen.addScreenshotKey), findsOneWidget);
    });

    testWidgets('choosing nothing changes nothing', (tester) async {
      await open(tester, picker: _FakePicker(null));
      await tester.tap(find.byKey(FeedbackScreen.addScreenshotKey));
      await tester.pumpAndSettle();
      expect(find.byKey(FeedbackScreen.addScreenshotKey), findsOneWidget);
      expect(find.byKey(const ValueKey('feedback-problem')), findsNothing);
    });

    testWidgets(
      'too many messages in an hour is said plainly, and kept for a retry',
      (tester) async {
        await open(tester);
        repository.error = PostgrestException(
          message: 'Too many feedback messages. Try again later.',
          code: 'PB429',
        );
        await tester.enterText(find.byKey(FeedbackScreen.messageKey), 'Again');
        await tester.pump();
        await tester.tap(find.byKey(FeedbackScreen.sendKey));
        await tester.pumpAndSettle();
        expect(
          find.text('Too many feedback messages. Try again later.'),
          findsOneWidget,
        );
        // The text is still there.
        expect(find.text('Again'), findsOneWidget);
        repository.error = null;
        await tester.tap(find.byKey(FeedbackScreen.sendKey));
        await tester.pumpAndSettle();
        expect(repository.sent, hasLength(1));
      },
    );

    testWidgets('in Chinese the refusal is in Chinese', (tester) async {
      AppStrings.isChinese = true;
      await open(tester);
      repository.error = PostgrestException(
        message: 'Too many feedback messages. Try again later.',
        code: 'PB429',
      );
      await tester.enterText(find.byKey(FeedbackScreen.messageKey), 'Again');
      await tester.pump();
      await tester.tap(find.byKey(FeedbackScreen.sendKey));
      await tester.pumpAndSettle();
      expect(find.text('反馈发得太频繁了，请稍后再试。'), findsOneWidget);
    });
  });

  testWidgets('Settings has a Feedback and help row that opens the page', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWithValue('1.4.0'),
          appPlatformProvider.overrideWithValue('web'),
        ],
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: const Scaffold(body: FeedbackSettingsEntry()),
        ),
      ),
    );
    expect(find.text('Feedback and help'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-feedback')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('feedback-screen')), findsOneWidget);
    expect(find.byKey(FeedbackScreen.messageKey), findsOneWidget);
  });
}
