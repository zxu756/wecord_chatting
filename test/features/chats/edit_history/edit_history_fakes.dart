import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/chats/edit_history/edit_history_repository.dart';
import 'package:wecord/features/chats/edit_history/edit_version.dart';

/// Edit histories by message id, newest first; a message without an entry
/// has none. [failures] makes the next reads throw.
class FakeEditHistoryRepository implements EditHistoryRepository {
  FakeEditHistoryRepository([Map<String, List<MessageEditVersion>>? versions])
    : versionsByMessage = versions ?? {};

  final Map<String, List<MessageEditVersion>> versionsByMessage;
  int failures = 0;
  final reads = <String>[];

  @override
  Future<List<MessageEditVersion>> versions(String messageId) async {
    reads.add(messageId);
    if (failures > 0) {
      failures -= 1;
      throw StateError('offline');
    }
    return versionsByMessage[messageId] ?? const [];
  }
}

Override editHistoryOverride(FakeEditHistoryRepository repository) =>
    editHistoryRepositoryProvider.overrideWithValue(repository);

/// An earlier version of a message.
MessageEditVersion editVersion(int version, String body, DateTime editedAt) =>
    MessageEditVersion(version: version, body: body, editedAt: editedAt);
