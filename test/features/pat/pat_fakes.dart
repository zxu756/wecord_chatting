import 'package:clock/clock.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/pat/pat_repository.dart';
import 'package:wecord/shared/models/message.dart';

import '../../mobile/phone_test_support.dart';

/// Pats without a server: remembers who was patted and what was taken back.
class FakePatRepository implements PatRepository {
  final pats = <({String conversationId, String userId})>[];
  final undone = <String>[];
  PatFailure? failPat;
  PatFailure? failUndo;
  String currentSuffix = '';
  final savedSuffixes = <String>[];
  Object? failSetSuffix;

  @override
  Future<String> pat({
    required String conversationId,
    required String userId,
  }) async {
    pats.add((conversationId: conversationId, userId: userId));
    if (failPat case final failure?) {
      throw PatException(failure);
    }
    return 'pat-message-${pats.length}';
  }

  @override
  Future<void> undo(String messageId) async {
    undone.add(messageId);
    if (failUndo case final failure?) {
      throw PatException(failure);
    }
  }

  @override
  Future<String> suffix() async => currentSuffix;

  @override
  Future<String> setSuffix(String value) async {
    if (failSetSuffix case final error?) {
      throw error;
    }
    savedSuffixes.add(value);
    currentSuffix = value.trim();
    return currentSuffix;
  }
}

List<Override> patOverrides(FakePatRepository repository) => [
  patRepositoryProvider.overrideWithValue(repository),
];

/// A pat line as the server stores it.
ChatMessage patMessage(
  String id, {
  required String actorId,
  required String targetId,
  String actorName = 'Ada',
  String targetName = 'Bart',
  String suffix = '',
  bool undone = false,
  Duration age = const Duration(seconds: 20),
  String conversationId = 'dm-1',
}) {
  return ChatMessage(
    id: id,
    conversationId: conversationId,
    senderId: actorId,
    type: MessageType.system,
    body: undone
        ? '$actorName took back a pat'
        : '$actorName patted $targetName',
    createdAt: clock.now().toUtc().subtract(age),
    attachment: {
      'kind': 'pat',
      'actor_id': actorId,
      'target_id': targetId,
      'actor_name': actorName,
      'target_name': targetName,
      'suffix': suffix,
      if (undone) 'undone': true,
    },
  );
}

/// Opens the direct chat with Bart (dm-1) showing [extra] after the usual
/// messages, with the chat not muted.
Future<void> openChatWithPats(
  WidgetTester tester,
  PhoneWorld world, {
  List<ChatMessage> extra = const [],
  bool muted = false,
}) async {
  world.chats
    ..messages = [...richMessages(), ...extra]
    ..conversations = [
      for (final conversation in world.chats.conversations)
        conversation.id == 'dm-1'
            ? conversation.copyWith(isMuted: muted)
            : conversation,
    ];
  await world.open(tester, '/chats/dm-1');
}
