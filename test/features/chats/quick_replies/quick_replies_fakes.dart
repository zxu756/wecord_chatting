import 'package:wecord/features/chats/quick_replies/quick_replies_models.dart';
import 'package:wecord/features/chats/quick_replies/quick_replies_repository.dart';

/// The quick replies and the away reply of one person, in memory. Like the
/// server it refuses a shortcut that is already taken and a 51st phrase.
class FakeQuickRepliesRepository implements QuickRepliesRepository {
  FakeQuickRepliesRepository({
    List<QuickReply> replies = const [],
    this.away = const AwayReply(),
  }) : replies = [...replies];

  List<QuickReply> replies;
  AwayReply away;
  var loads = 0;
  var _next = 1;

  /// The away replies saved, for asserting.
  final savedAway = <AwayReply>[];

  /// Makes the next write fail with this.
  Object? failWrites;

  void _maybeFail() {
    final error = failWrites;
    if (error != null) {
      failWrites = null;
      throw error;
    }
  }

  @override
  Future<List<QuickReply>> load() async {
    loads += 1;
    return [...replies];
  }

  @override
  Future<QuickReply> create({
    required String shortcut,
    required String body,
  }) async {
    _maybeFail();
    final problem = checkQuickReply(shortcut, body);
    if (problem != null) {
      throw QuickReplyException(problem);
    }
    final key = normalizeQuickReplyShortcut(shortcut);
    if (replies.any((reply) => reply.shortcut == key)) {
      throw const QuickReplyException(QuickReplyProblem.taken);
    }
    if (replies.length >= maxQuickReplies) {
      throw const QuickReplyException(QuickReplyProblem.limit);
    }
    final reply = QuickReply(
      id: 'reply-${_next++}',
      shortcut: key,
      body: body.trim(),
    );
    replies = [...replies, reply];
    return reply;
  }

  @override
  Future<void> update(
    String id, {
    required String shortcut,
    required String body,
  }) async {
    _maybeFail();
    final problem = checkQuickReply(shortcut, body);
    if (problem != null) {
      throw QuickReplyException(problem);
    }
    final key = normalizeQuickReplyShortcut(shortcut);
    if (replies.any((reply) => reply.shortcut == key && reply.id != id)) {
      throw const QuickReplyException(QuickReplyProblem.taken);
    }
    replies = [
      for (final reply in replies)
        if (reply.id == id)
          QuickReply(id: id, shortcut: key, body: body.trim())
        else
          reply,
    ];
  }

  @override
  Future<void> delete(String id) async {
    _maybeFail();
    replies = [
      for (final reply in replies)
        if (reply.id != id) reply,
    ];
  }

  @override
  Future<AwayReply> loadAway() async => away;

  @override
  Future<void> saveAway(AwayReply next) async {
    _maybeFail();
    savedAway.add(next);
    away = next;
  }
}
