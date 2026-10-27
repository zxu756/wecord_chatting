import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/on_device/on_device_ai.dart';
import 'package:wecord/features/ai/on_device/on_device_chat_reader.dart';
import 'package:wecord/features/ai/on_device/on_device_gate.dart';

/// An on-device model for tests: answers are set up front, calls recorded.
class FakeOnDeviceBackend implements OnDeviceAiBackend {
  FakeOnDeviceBackend({
    this.supported = true,
    this.status = const OnDeviceAiStatus.available(),
  });

  final bool supported;
  OnDeviceAiStatus status;

  /// Thrown by every request when set.
  Object? error;

  /// Thrown by the request numbered [errorOnCall] (1 based) only, when set.
  Object? errorOnNth;
  int errorOnCall = 0;

  var availabilityCalls = 0;
  final summarizeCalls =
      <({List<String> lines, AiLanguage language, bool recent, bool merge})>[];
  final rewriteCalls = <({AiRewriteMode mode, String text})>[];
  final translateCalls = <({String text, AiLanguage target})>[];
  var _requests = 0;

  /// What a summary request answers: bullets numbered by request.
  String Function(int request, List<String> lines, bool merge)? summaryFor;

  void _fail() {
    _requests++;
    if (error case final error?) {
      throw error;
    }
    if (errorOnNth != null && _requests == errorOnCall) {
      throw errorOnNth!;
    }
  }

  @override
  bool get isSupportedPlatform => supported;

  @override
  Future<OnDeviceAiStatus> availability() async {
    availabilityCalls++;
    return status;
  }

  @override
  Future<String> summarize({
    required List<String> lines,
    required AiLanguage language,
    required bool recent,
    bool merge = false,
  }) async {
    summarizeCalls.add((
      lines: lines,
      language: language,
      recent: recent,
      merge: merge,
    ));
    _fail();
    return summaryFor?.call(_requests, lines, merge) ??
        '- Summary ${summarizeCalls.length}';
  }

  @override
  Future<String> rewrite({
    required AiRewriteMode mode,
    required String text,
  }) async {
    rewriteCalls.add((mode: mode, text: text));
    _fail();
    return 'device: $text';
  }

  @override
  Future<String> translate({
    required String text,
    required AiLanguage target,
  }) async {
    translateCalls.add((text: text, target: target));
    _fail();
    return '${target.code}: $text';
  }
}

/// A gate for tests that records what it was asked and can say no.
class FakeOnDeviceGate implements OnDeviceAiGate {
  Object? error;
  final checks = <String?>[];

  @override
  Future<void> check({String? conversationId}) async {
    checks.add(conversationId);
    if (error case final error?) {
      throw error;
    }
  }
}

/// A chat reader for tests.
class FakeOnDeviceReader implements OnDeviceChatReader {
  OnDeviceChatLog? log = const OnDeviceChatLog(
    lines: ['Ana: Lunch at noon?', 'Ben: Yes.'],
    total: 2,
    firstMessageId: 'm1',
  );
  List<OnDeviceMessageText> messages = const [];
  final logRequests =
      <({String conversationId, String? afterMessageId, bool recent})>[];
  final messageRequests = <List<String>>[];

  @override
  Future<OnDeviceChatLog?> loadLog({
    required String conversationId,
    String? afterMessageId,
    bool useStoredMarker = false,
    bool recent = false,
  }) async {
    logRequests.add((
      conversationId: conversationId,
      afterMessageId: afterMessageId,
      recent: recent,
    ));
    return log;
  }

  @override
  Future<List<OnDeviceMessageText>> loadMessages({
    required String conversationId,
    required List<String> ids,
  }) async {
    messageRequests.add(ids);
    return [
      for (final message in messages)
        if (ids.contains(message.id)) message,
    ];
  }
}
