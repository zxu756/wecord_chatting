import 'dart:async';

import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';

/// An [AiRepository] for tests: answers are set up front, calls recorded.
class FakeAiRepository implements AiRepository {
  /// Thrown by [status] when set (AI not set up, say).
  Object? statusError;
  var statusValue = const AiStatus(dailyLimit: 50, used: 3);

  /// The summary [summarize] gives; null means nothing to summarize.
  AiSummary? summary = const AiSummary(
    text: '- Ana asked about lunch.\n- Ben suggested noon.',
    messageCount: 24,
    summarizedCount: 24,
    firstMessageId: 'message-2',
  );

  /// Thrown by every call except [status] when set.
  Object? error;

  /// Holds the next answer until completed (for the loading state).
  Completer<void>? gate;

  /// What [rewrite] and [translate] give back.
  String rewritten = 'Polished text.';
  String translated = 'Translated text.';

  final summarizeCalls =
      <
        ({
          String conversationId,
          String? afterMessageId,
          bool recent,
          AiLanguage language,
        })
      >[];
  final rewriteCalls =
      <({AiRewriteMode mode, String text, AiLanguage? target})>[];
  final translateCalls = <({String text, AiLanguage target})>[];
  var statusCalls = 0;

  /// Circles that turned AI off.
  final disabledCircles = <String>{};
  final circleSwitchCalls = <(String, bool)>[];

  /// Thrown by [setCircleAiEnabled] when set.
  Object? circleSwitchError;

  Future<void> _wait() async {
    await gate?.future;
    if (error case final error?) {
      throw error;
    }
  }

  @override
  Future<AiStatus> status() async {
    statusCalls++;
    if (statusError case final error?) {
      throw error;
    }
    return statusValue;
  }

  @override
  Future<AiSummary?> summarize({
    required String conversationId,
    String? afterMessageId,
    bool useStoredMarker = false,
    bool recent = false,
    AiLanguage language = AiLanguage.english,
  }) async {
    summarizeCalls.add((
      conversationId: conversationId,
      afterMessageId: afterMessageId,
      recent: recent,
      language: language,
    ));
    await _wait();
    return summary;
  }

  @override
  Future<String> rewrite({
    required AiRewriteMode mode,
    required String text,
    AiLanguage? target,
    String? conversationId,
  }) async {
    rewriteCalls.add((mode: mode, text: text, target: target));
    await _wait();
    return rewritten;
  }

  @override
  Future<String> translate({
    required String text,
    required AiLanguage target,
    String? conversationId,
  }) async {
    translateCalls.add((text: text, target: target));
    await _wait();
    return translated;
  }

  @override
  Future<bool> circleAiEnabled(String circleId) async =>
      !disabledCircles.contains(circleId);

  @override
  Future<void> setCircleAiEnabled(
    String circleId, {
    required bool enabled,
  }) async {
    circleSwitchCalls.add((circleId, enabled));
    if (circleSwitchError case final error?) {
      throw error;
    }
    if (enabled) {
      disabledCircles.remove(circleId);
    } else {
      disabledCircles.add(circleId);
    }
  }
}
