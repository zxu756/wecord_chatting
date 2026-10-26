import 'dart:async';

import 'package:wecord/features/chat_privacy/chat_privacy_repository.dart';
import 'package:wecord/features/screen_capture/screen_capture_service.dart';
import 'package:wecord/features/screen_capture/view_once_screenshots.dart';

/// Advanced chat privacy as the server keeps it: a direct chat has one switch
/// for each person and stays restricted while any is on; a group has one.
class FakeChatPrivacyRepository implements ChatPrivacyRepository {
  FakeChatPrivacyRepository({
    Map<String, ChatPrivacy> chats = const {},
    this.me = 'user-1',
  }) : chats = {...chats};

  final Map<String, ChatPrivacy> chats;
  final String me;

  /// Fails the next [set].
  Object? failure;
  final changes = <(String, bool)>[];

  @override
  Future<ChatPrivacy> read(String conversationId) async =>
      chats[conversationId] ?? ChatPrivacy.open;

  @override
  Future<bool> set(String conversationId, bool enabled) async {
    if (failure case final error?) {
      failure = null;
      throw error;
    }
    changes.add((conversationId, enabled));
    final now = chats[conversationId] ?? ChatPrivacy.open;
    final by = {...now.requestedBy};
    if (enabled) {
      by.add(me);
    } else {
      by.remove(me);
    }
    chats[conversationId] = ChatPrivacy(
      restricted: by.isNotEmpty,
      requestedBy: by,
    );
    return by.isNotEmpty;
  }
}

/// The phone's screenshot and recording signals, driven by the test.
class FakeScreenCapture implements ScreenCaptureService {
  FakeScreenCapture({this.detects = true, this.recording = false});

  @override
  final bool detects;
  bool recording;

  final _events = StreamController<ScreenCaptureEvent>.broadcast();

  @override
  Future<bool> isRecording() async => recording;

  @override
  Stream<ScreenCaptureEvent> get events => _events.stream;

  void emit(ScreenCaptureEvent event) {
    recording = switch (event) {
      ScreenCaptureEvent.recordingStarted => true,
      ScreenCaptureEvent.recordingStopped => false,
      ScreenCaptureEvent.screenshot => recording,
    };
    _events.add(event);
  }
}

/// Reports sent for view-once messages, and the ones to show the sender.
class FakeViewOnceScreenshots implements ViewOnceScreenshotRepository {
  final reported = <(String, ViewOnceCaptureKind)>[];
  final reports = <String, List<ViewOnceCaptureReport>>{};

  @override
  Future<bool> report(String messageId, ViewOnceCaptureKind kind) async {
    reported.add((messageId, kind));
    return true;
  }

  @override
  Stream<List<ViewOnceCaptureReport>> watch(String messageId) =>
      Stream.value(reports[messageId] ?? const []);
}
