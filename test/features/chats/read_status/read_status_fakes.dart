import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/chats/read_status/read_receipts_setting.dart';
import 'package:wecord/features/chats/read_status/read_reminder_notices.dart';
import 'package:wecord/features/chats/read_status/read_status_models.dart';
import 'package:wecord/features/chats/read_status/read_status_repository.dart';

/// The read list of each message id; a message without an entry has none.
/// [listError] makes reading the list throw, [remindError] the reminder.
class FakeReadStatusRepository implements ReadStatusRepository {
  FakeReadStatusRepository([Map<String, List<MemberReadStatus>>? lists])
    : lists = lists ?? {};

  final Map<String, List<MemberReadStatus>> lists;
  Object? listError;
  Object? remindError;
  final reminded = <String>{};
  final reads = <String>[];
  final reminds = <String>[];

  @override
  Future<List<MemberReadStatus>> statuses(String messageId) async {
    reads.add(messageId);
    final error = listError;
    if (error != null) {
      if (error is ReadStatusException &&
          error.problem == ReadStatusProblem.other) {
        // A transient failure: the next read works.
        listError = null;
      }
      throw error;
    }
    return lists[messageId] ?? const [];
  }

  @override
  Future<bool> wasReminded(String messageId) async =>
      reminded.contains(messageId);

  @override
  Future<int> remind(String messageId) async {
    reminds.add(messageId);
    final error = remindError;
    if (error != null) {
      throw error;
    }
    if (!reminded.add(messageId)) {
      throw const ReadStatusException(ReadStatusProblem.alreadyReminded);
    }
    return (lists[messageId] ?? const [])
        .where((m) => m.state == ReadState.unread)
        .length;
  }
}

Override readStatusOverride(FakeReadStatusRepository repository) =>
    readStatusRepositoryProvider.overrideWithValue(repository);

MemberReadStatus member(
  String id,
  String name,
  ReadState state, {
  String? avatarUrl,
}) => MemberReadStatus(
  userId: id,
  name: name,
  state: state,
  avatarUrl: avatarUrl,
);

class FakeReadReceiptsRepository implements ReadReceiptsRepository {
  FakeReadReceiptsRepository({this.enabled = true});

  bool enabled;
  Object? saveError;
  final saved = <bool>[];

  @override
  Future<bool> load() async => enabled;

  @override
  Future<void> save(bool value) async {
    final error = saveError;
    if (error != null) {
      throw error;
    }
    saved.add(value);
    enabled = value;
  }
}

Override readReceiptsOverride(FakeReadReceiptsRepository repository) =>
    readReceiptsRepositoryProvider.overrideWithValue(repository);

class FakeReadReminderNoticesRepository
    implements ReadReminderNoticesRepository {
  FakeReadReminderNoticesRepository([List<ReadReminderNotice>? notices])
    : notices = notices ?? [];

  final List<ReadReminderNotice> notices;
  final dismissed = <String>[];

  @override
  Future<List<ReadReminderNotice>> list() async => [
    for (final notice in notices)
      if (!dismissed.contains(notice.id)) notice,
  ];

  @override
  Future<void> markRead(List<String> ids) async => dismissed.addAll(ids);
}
