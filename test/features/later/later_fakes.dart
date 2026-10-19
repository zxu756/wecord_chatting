import 'package:wecord/features/later/reminders_repository.dart';
import 'package:wecord/features/later/schedule_repeat.dart';
import 'package:wecord/features/later/saved_messages_repository.dart';
import 'package:wecord/features/later/scheduled_messages_repository.dart';
import 'package:wecord/features/push/push_gateway.dart';
import 'package:wecord/features/push/push_repository.dart';

/// An in-memory scheduled message queue.
class FakeScheduledMessagesRepository implements ScheduledMessagesRepository {
  FakeScheduledMessagesRepository([List<ScheduledMessage> initial = const []])
    : messages = [...initial];

  final List<ScheduledMessage> messages;
  final created = <({String conversationId, String body, DateTime sendAt})>[];

  /// The repeat of each message made, in order (null: sent once).
  final createdRepeats = <ScheduleRepeat?>[];
  final sentNow = <String>[];
  final deleted = <String>[];
  var _next = 0;

  /// Fails every write with this.
  Object? failWith;

  @override
  Future<List<ScheduledMessage>> list(String conversationId) async => [
    for (final message in messages)
      if (message.conversationId == conversationId) message,
  ]..sort((a, b) => a.sendAt.compareTo(b.sendAt));

  @override
  Future<ScheduledMessage> create({
    required String conversationId,
    required String body,
    required DateTime sendAt,
    List<Map<String, dynamic>> mentions = const [],
    ScheduleRepeat? repeat,
  }) async {
    if (failWith case final error?) {
      throw error;
    }
    created.add((conversationId: conversationId, body: body, sendAt: sendAt));
    createdRepeats.add(repeat);
    final message = ScheduledMessage(
      id: 'scheduled-${_next++}',
      conversationId: conversationId,
      body: body,
      sendAt: sendAt.toUtc(),
      mentions: mentions,
      repeat: repeat?.startingAt(sendAt),
    );
    messages.add(message);
    return message;
  }

  @override
  Future<ScheduledMessage> update(
    String id, {
    required String body,
    required DateTime sendAt,
    required List<Map<String, dynamic>> mentions,
    ScheduleRepeat? repeat,
  }) async {
    if (failWith case final error?) {
      throw error;
    }
    final index = messages.indexWhere((message) => message.id == id);
    final updated = ScheduledMessage(
      id: id,
      conversationId: messages[index].conversationId,
      body: body,
      sendAt: sendAt.toUtc(),
      mentions: mentions,
      repeat: repeat?.startingAt(sendAt),
    );
    messages[index] = updated;
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    if (failWith case final error?) {
      throw error;
    }
    deleted.add(id);
    messages.removeWhere((message) => message.id == id);
  }

  @override
  Future<String> sendNow(String id) async {
    if (failWith case final error?) {
      throw error;
    }
    sentNow.add(id);
    messages.removeWhere((message) => message.id == id);
    return 'sent-$id';
  }
}

/// A push repository that remembers the messages it was asked to push.
class RecordingPushRepository implements PushRepository {
  final notified = <String>[];

  @override
  Future<String> vapidPublicKey() async =>
      throw const PushNotConfiguredException();

  @override
  Future<void> register(
    PushSubscriptionInfo subscription, {
    String language = 'en',
    String? userAgent,
    String? timeZone,
  }) async {}

  @override
  Future<void> unregister(String endpoint) async {}

  @override
  Future<void> notifySent(String messageId) async => notified.add(messageId);

  @override
  Future<void> notifyCall(String callId) async {}
}

/// In-memory reminders.
class FakeRemindersRepository implements RemindersRepository {
  FakeRemindersRepository([List<MessageReminder> initial = const []])
    : reminders = [...initial];

  final List<MessageReminder> reminders;
  final setCalls = <({String messageId, DateTime at})>[];
  final dismissed = <String>[];

  /// What the next claim returns (and then clears).
  var due = <LocalReminder>[];
  var claims = 0;
  var failClaims = false;
  Object? failSetWith;

  @override
  Future<List<MessageReminder>> list() async => [...reminders];

  @override
  Future<void> set(String messageId, DateTime remindAt) async {
    if (failSetWith case final error?) {
      throw error;
    }
    setCalls.add((messageId: messageId, at: remindAt));
  }

  @override
  Future<void> dismiss(String id) async {
    dismissed.add(id);
    reminders.removeWhere((reminder) => reminder.id == id);
  }

  @override
  Future<List<LocalReminder>> claimDue() async {
    claims++;
    if (failClaims) {
      throw StateError('offline');
    }
    final result = due;
    due = [];
    return result;
  }
}

/// In-memory saved messages, Moments, links, notes and folders.
class FakeSavedMessagesRepository implements SavedMessagesRepository {
  FakeSavedMessagesRepository([
    List<SavedMessage> initial = const [],
    List<SavedFolder> folders = const [],
  ]) : entries = [...initial],
       folderList = [...folders];

  final List<SavedMessage> entries;
  final List<SavedFolder> folderList;
  final saved = <String>[];
  final savedItems = <({SavedKind kind, String targetId})>[];
  final links = <({String url, String? title, String? folderId})>[];
  final notes =
      <
        ({
          String? title,
          String? body,
          int pictures,
          String? folderId,
          List<String> tags,
        })
      >[];
  final removed = <String>[];
  final removedImages = <String>[];
  final updates = <({String id, Map<String, Object?> patch})>[];
  final searches = <String>[];
  final doneCalls = <({String id, bool done})>[];
  final renamedTags = <({String from, String to})>[];
  var failWrites = false;
  var failSearch = false;
  var _made = 0;

  /// What [search] answers, when set; otherwise entries whose text has every
  /// word.
  Set<String>? searchAnswer;

  void _check() {
    if (failWrites) {
      throw StateError('offline');
    }
  }

  @override
  Future<List<SavedMessage>> list() async => [...entries];

  @override
  Future<void> save(String messageId) async {
    _check();
    saved.add(messageId);
    entries.insert(
      0,
      SavedMessage(
        id: 'saved-${entries.length}',
        messageId: messageId,
        conversationId: 'conversation-1',
        savedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> saveItem(SavedKind kind, String targetId) async {
    _check();
    savedItems.add((kind: kind, targetId: targetId));
    entries.insert(
      0,
      SavedMessage(
        id: 'saved-${_made++}-$targetId',
        kind: kind,
        messageId: targetId,
        savedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<String> saveLink({
    required String url,
    String? title,
    String? folderId,
    List<String> tags = const [],
  }) async {
    _check();
    links.add((url: url, title: title, folderId: folderId));
    final id = 'link-${_made++}';
    entries.insert(
      0,
      SavedMessage(
        id: id,
        kind: SavedKind.link,
        url: url,
        title: title,
        folderId: folderId,
        tags: tags,
        savedAt: DateTime.now(),
      ),
    );
    return id;
  }

  @override
  Future<String> createNote({
    String? title,
    String? body,
    List<SavedNotePicture> pictures = const [],
    String? folderId,
    List<String> tags = const [],
  }) async {
    _check();
    notes.add((
      title: title,
      body: body,
      pictures: pictures.length,
      folderId: folderId,
      tags: tags,
    ));
    final id = 'note-${_made++}';
    entries.insert(
      0,
      SavedMessage(
        id: id,
        kind: (title ?? '').trim().isEmpty && pictures.isEmpty
            ? SavedKind.text
            : SavedKind.note,
        title: title,
        body: body ?? '',
        images: [
          for (final (index, _) in pictures.indexed)
            SavedImage(path: 'user/$id-$index.jpg'),
        ],
        folderId: folderId,
        tags: tags,
        savedAt: DateTime.now(),
      ),
    );
    return id;
  }

  @override
  Future<void> remove(String id, {List<SavedImage> images = const []}) async {
    _check();
    removed.add(id);
    removedImages.addAll([for (final image in images) image.path]);
    entries.removeWhere((entry) => entry.id == id);
  }

  SavedMessage _copy(
    SavedMessage entry, {
    DateTime? doneAt,
    bool clearDone = false,
    String? folderId,
    bool setFolder = false,
    List<String>? tags,
    String? note,
    bool setNote = false,
    String? title,
    bool setTitle = false,
    String? body,
    List<SavedImage>? images,
  }) {
    return SavedMessage(
      id: entry.id,
      kind: entry.kind,
      messageId: entry.messageId,
      conversationId: entry.conversationId,
      circleId: entry.circleId,
      savedAt: entry.savedAt,
      doneAt: clearDone ? null : (doneAt ?? entry.doneAt),
      senderId: entry.senderId,
      senderName: entry.senderName,
      senderAvatarUrl: entry.senderAvatarUrl,
      body: body ?? entry.body,
      type: entry.type,
      messageCreatedAt: entry.messageCreatedAt,
      available: entry.available,
      folderId: setFolder ? folderId : entry.folderId,
      tags: tags ?? entry.tags,
      note: setNote ? note : entry.note,
      title: setTitle ? title : entry.title,
      url: entry.url,
      images: images ?? entry.images,
      extra: entry.extra,
    );
  }

  @override
  Future<void> setDone(String id, {required bool done}) async {
    _check();
    doneCalls.add((id: id, done: done));
    final index = entries.indexWhere((entry) => entry.id == id);
    entries[index] = _copy(
      entries[index],
      doneAt: done ? DateTime.now() : null,
      clearDone: !done,
    );
  }

  @override
  Future<void> update(String id, Map<String, Object?> patch) async {
    _check();
    updates.add((id: id, patch: patch));
    final index = entries.indexWhere((entry) => entry.id == id);
    final entry = entries[index];
    final images = patch['images'];
    if (images is List) {
      final kept = {for (final image in images) (image as Map)['path']};
      removedImages.addAll([
        for (final image in entry.images)
          if (!kept.contains(image.path)) image.path,
      ]);
    }
    entries[index] = _copy(
      entry,
      setFolder: patch.containsKey('folder_id'),
      folderId: patch['folder_id'] as String?,
      tags: patch['tags'] == null
          ? null
          : [for (final tag in patch['tags']! as List) '$tag'],
      setNote: patch.containsKey('note'),
      note: patch['note'] as String?,
      setTitle: patch.containsKey('title'),
      title: patch['title'] as String?,
      body: patch['body'] as String?,
      images: images is List
          ? [
              for (final image in images)
                SavedImage(path: (image as Map)['path'] as String),
            ]
          : null,
    );
  }

  @override
  Future<Set<String>> search(String query) async {
    if (failSearch) {
      throw StateError('offline');
    }
    searches.add(query);
    final answer = searchAnswer;
    if (answer != null) {
      return answer;
    }
    final words = query.toLowerCase().split(RegExp(r'\s+'));
    return {
      for (final entry in entries)
        if (words.every(
          (word) => [
            entry.body,
            entry.title,
            entry.note,
            entry.url,
            ...entry.tags,
          ].any((text) => (text ?? '').toLowerCase().contains(word)),
        ))
          entry.id,
    };
  }

  @override
  Future<List<SavedFolder>> folders() async => [...folderList];

  @override
  Future<String> createFolder(String name) async {
    _check();
    final id = 'folder-${_made++}';
    folderList.add(SavedFolder(id: id, name: name));
    return id;
  }

  @override
  Future<void> renameFolder(String id, String name) async {
    _check();
    final index = folderList.indexWhere((folder) => folder.id == id);
    folderList[index] = SavedFolder(id: id, name: name);
  }

  @override
  Future<void> deleteFolder(String id) async {
    _check();
    folderList.removeWhere((folder) => folder.id == id);
    for (final (index, entry) in entries.indexed.toList()) {
      if (entry.folderId == id) {
        entries[index] = _copy(entry, setFolder: true, folderId: null);
      }
    }
  }

  @override
  Future<int> renameTag(String from, String to) async {
    _check();
    renamedTags.add((from: from, to: to));
    var changed = 0;
    for (final (index, entry) in entries.indexed.toList()) {
      if (entry.tags.any((t) => t.toLowerCase() == from.toLowerCase())) {
        changed++;
        entries[index] = _copy(
          entry,
          tags: [
            for (final tag in entry.tags)
              if (tag.toLowerCase() != from.toLowerCase())
                tag
              else if (to.isNotEmpty)
                to,
          ],
        );
      }
    }
    return changed;
  }

  @override
  Future<String> signedUrl(String path) async => 'https://files.test/$path';
}
