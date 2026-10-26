import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/view_once.dart';
import 'package:wecord/features/screen_capture/screen_capture_service.dart';
import 'package:wecord/features/screen_capture/view_once_screenshots.dart';
import 'package:wecord/shared/models/message.dart';

import '../../mobile/phone_test_support.dart';
import '../chat_privacy/chat_privacy_fakes.dart';

class _FakeViewOnce implements ViewOnceRepository {
  final opened = <String>[];
  var opens = <String, List<ViewOnceOpen>>{};

  @override
  Future<ViewOnceFile> open(String messageId) async {
    opened.add(messageId);
    return const ViewOnceFile(
      url: 'https://example.invalid/x.jpg',
      isVideo: false,
    );
  }

  @override
  Stream<List<ViewOnceOpen>> watchOpens(String messageId) =>
      Stream.value(opens[messageId] ?? const []);
}

ChatMessage _once({String senderId = 'user-2'}) {
  return ChatMessage(
    id: 'once-1',
    conversationId: 'dm-1',
    senderId: senderId,
    type: MessageType.image,
    body: '',
    createdAt: DateTime.utc(2026, 10, 28, 9),
    attachment: const {
      'kind': 'image',
      'bucket': 'chat-images',
      'path': 'dm-1/once.jpg',
      'mime_type': 'image/jpeg',
      'size': 10,
      'view_once': true,
    },
  );
}

void main() {
  final capture = FakeScreenCapture();
  late FakeViewOnceScreenshots reports;
  late _FakeViewOnce once;

  setUp(() {
    reports = FakeViewOnceScreenshots();
    once = _FakeViewOnce();
  });

  Future<PhoneWorld> pump(
    WidgetTester tester,
    Widget child, {
    ScreenCaptureService? service,
  }) async {
    usePhoneViewport(tester, notchedPhone);
    final world = PhoneWorld();
    world.extraOverrides = [
      screenCaptureServiceProvider.overrideWithValue(service ?? capture),
      viewOnceScreenshotRepositoryProvider.overrideWithValue(reports),
      viewOnceRepositoryProvider.overrideWithValue(once),
    ];
    await pumpStandalone(tester, world, child);
    return world;
  }

  const file = ViewOnceFile(
    url: 'https://example.invalid/x.jpg',
    isVideo: false,
  );

  group('the viewer', () {
    testWidgets('a screenshot is reported and the viewer says so', (
      tester,
    ) async {
      final service = FakeScreenCapture();
      await pump(
        tester,
        const ViewOnceViewer(file: file, messageId: 'once-1'),
        service: service,
      );
      expect(
        find.textContaining('this device tells the sender', findRichText: true),
        findsNothing,
      );
      service.emit(ScreenCaptureEvent.screenshot);
      await settle(tester);
      expect(reports.reported, [('once-1', ViewOnceCaptureKind.screenshot)]);
      expect(
        find.text('Screenshot noticed. The sender is told.'),
        findsOneWidget,
      );
      // Still visible: a screenshot is over by the time it is noticed.
      expect(find.byKey(const ValueKey('view-once-covered')), findsNothing);
    });

    testWidgets('a recording hides the picture until it stops', (tester) async {
      final service = FakeScreenCapture();
      await pump(
        tester,
        const ViewOnceViewer(file: file, messageId: 'once-1'),
        service: service,
      );
      expect(find.byType(Image), findsOneWidget);
      service.emit(ScreenCaptureEvent.recordingStarted);
      await settle(tester);
      expect(find.byKey(const ValueKey('view-once-covered')), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(reports.reported, [('once-1', ViewOnceCaptureKind.recording)]);
      expect(
        find.text('Screen recording noticed. The sender is told.'),
        findsOneWidget,
      );
      service.emit(ScreenCaptureEvent.recordingStopped);
      await settle(tester);
      expect(find.byKey(const ValueKey('view-once-covered')), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('a screen that is already recorded starts covered', (
      tester,
    ) async {
      await pump(
        tester,
        const ViewOnceViewer(file: file, messageId: 'once-1'),
        service: FakeScreenCapture(recording: true),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('view-once-covered')), findsOneWidget);
      expect(reports.reported, [('once-1', ViewOnceCaptureKind.recording)]);
    });

    testWidgets('a device that cannot tell says so and reports nothing', (
      tester,
    ) async {
      await pump(
        tester,
        const ViewOnceViewer(file: file, messageId: 'once-1'),
        service: const UnsupportedScreenCaptureService(),
      );
      expect(
        find.textContaining("this device can't notice them"),
        findsOneWidget,
      );
      expect(reports.reported, isEmpty);
    });

    testWidgets('without a message nothing is reported', (tester) async {
      final service = FakeScreenCapture();
      await pump(tester, const ViewOnceViewer(file: file), service: service);
      service.emit(ScreenCaptureEvent.screenshot);
      await settle(tester);
      expect(reports.reported, isEmpty);
    });
  });

  group('the message', () {
    testWidgets('is not opened while the screen is recorded', (tester) async {
      await pump(
        tester,
        Scaffold(
          body: ViewOnceMessageContent(
            message: _once(),
            textColor: Colors.black,
          ),
        ),
        service: FakeScreenCapture(recording: true),
      );
      await tester.tap(find.byKey(const ValueKey('view-once-once-1')));
      await settle(tester);
      expect(
        find.text(
          'Stop recording your screen, then open it. It can only be opened once.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('view-once-confirm')), findsNothing);
      expect(once.opened, isEmpty);
    });

    testWidgets('the reminder says whether this device will tell the sender', (
      tester,
    ) async {
      await pump(
        tester,
        Scaffold(
          body: ViewOnceMessageContent(
            message: _once(),
            textColor: Colors.black,
          ),
        ),
        service: FakeScreenCapture(),
      );
      await tester.tap(find.byKey(const ValueKey('view-once-once-1')));
      await settle(tester);
      expect(
        find.text(
          'If this device notices a screenshot or a screen recording, the sender is told.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('on a device that cannot tell, the reminder says that', (
      tester,
    ) async {
      await pump(
        tester,
        Scaffold(
          body: ViewOnceMessageContent(
            message: _once(),
            textColor: Colors.black,
          ),
        ),
        service: const UnsupportedScreenCaptureService(),
      );
      await tester.tap(find.byKey(const ValueKey('view-once-once-1')));
      await settle(tester);
      expect(
        find.text(
          "This device can't notice screenshots, so the sender is not told about them.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('the sender sees what the other phone reported', (
      tester,
    ) async {
      reports.reports['once-1'] = [
        ViewOnceCaptureReport(
          userId: 'user-2',
          kind: ViewOnceCaptureKind.screenshot,
          reportedAt: DateTime.utc(2026, 10, 28, 9, 5),
        ),
      ];
      once.opens['once-1'] = [
        ViewOnceOpen(
          userId: 'user-2',
          openedAt: DateTime.utc(2026, 10, 28, 9, 4),
        ),
      ];
      await pump(
        tester,
        Scaffold(
          body: ViewOnceMessageContent(
            message: _once(senderId: 'user-1'),
            textColor: Colors.black,
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Opened · Screenshot taken'), findsOneWidget);
    });

    testWidgets('the sender with no report sees the status as before', (
      tester,
    ) async {
      once.opens['once-1'] = [
        ViewOnceOpen(
          userId: 'user-2',
          openedAt: DateTime.utc(2026, 10, 28, 9, 4),
        ),
      ];
      await pump(
        tester,
        Scaffold(
          body: ViewOnceMessageContent(
            message: _once(senderId: 'user-1'),
            textColor: Colors.black,
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Opened'), findsOneWidget);
    });
  });
}
