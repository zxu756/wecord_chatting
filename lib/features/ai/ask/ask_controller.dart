import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/ask/ask_models.dart';
import 'package:wecord/features/ai/ask/ask_repository.dart';
import 'package:wecord/features/search/message_search_models.dart';

enum AskPhase { idle, loading, answered, failed }

/// Where a question stands: nothing asked, waiting, answered (or "not
/// found"), or failed.
@immutable
class AskState {
  const AskState({
    this.phase = AskPhase.idle,
    this.question = '',
    this.scope = const EverywhereScope(),
    this.answer,
    this.error,
  });

  final AskPhase phase;

  /// The question the answer (or the wait) belongs to.
  final String question;

  /// Where it was asked.
  final MessageSearchScope scope;
  final AskAnswer? answer;
  final Object? error;
}

/// Asks one question at a time. Asking again replaces the last answer; an
/// answer that arrives after a newer question, or after the person left, is
/// dropped.
class AskController extends Notifier<AskState> {
  var _generation = 0;

  @override
  AskState build() => const AskState();

  Future<void> ask(String question, MessageSearchScope scope) async {
    final text = question.trim();
    if (text.isEmpty || state.phase == AskPhase.loading) {
      return;
    }
    final generation = ++_generation;
    state = AskState(phase: AskPhase.loading, question: text, scope: scope);
    try {
      final answer = await ref
          .read(askRepositoryProvider)
          .ask(question: text, scope: scope);
      if (!ref.mounted || generation != _generation) {
        return;
      }
      state = AskState(
        phase: AskPhase.answered,
        question: text,
        scope: scope,
        answer: answer,
      );
      // Today's count moved.
      ref.invalidate(aiStatusProvider);
    } on Object catch (error) {
      if (!ref.mounted || generation != _generation) {
        return;
      }
      state = AskState(
        phase: AskPhase.failed,
        question: text,
        scope: scope,
        error: error,
      );
    }
  }

  /// Forgets the answer (the scope changed, or the box was emptied).
  void clear() {
    _generation++;
    state = const AskState();
  }
}

final askControllerProvider =
    NotifierProvider.autoDispose<AskController, AskState>(AskController.new);
