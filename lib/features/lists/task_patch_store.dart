import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The task changes of one list that the server has not confirmed, kept on
/// this device so they survive closing the app (as unsent note edits do, see
/// NoteDraft). Each entry is the patch of one item: the few fields changed,
/// which `upsert_task_item` applies field by field. A new item's first patch
/// holds its title.
@immutable
class TaskListDraft {
  const TaskListDraft({
    required this.userId,
    required this.listId,
    this.patches = const {},
    this.created = const {},
  });

  factory TaskListDraft.fromJson(Map<String, dynamic> json) {
    final patches = <String, Map<String, Object?>>{};
    final rawPatches = json['patches'];
    if (rawPatches is Map) {
      for (final entry in rawPatches.entries) {
        final value = entry.value;
        if (value is Map && value.isNotEmpty) {
          patches['${entry.key}'] = {
            for (final field in value.entries) '${field.key}': field.value,
          };
        }
      }
    }
    final created = <String, DateTime>{};
    final rawCreated = json['created'];
    if (rawCreated is Map) {
      for (final entry in rawCreated.entries) {
        final at = DateTime.tryParse('${entry.value}');
        if (at != null) {
          created['${entry.key}'] = at;
        }
      }
    }
    return TaskListDraft(
      userId: json['user_id'] as String,
      listId: json['list_id'] as String,
      patches: patches,
      created: created,
    );
  }

  final String userId;
  final String listId;

  /// The waiting patch of each item, by item id.
  final Map<String, Map<String, Object?>> patches;

  /// When the items made on this device (and not stored yet) were made, by
  /// item id. A patch for an item that is neither on the server nor in here
  /// is for something that was deleted, and is dropped.
  final Map<String, DateTime> created;

  bool get isEmpty => patches.isEmpty;

  Map<String, Object?> toJson() => {
    'user_id': userId,
    'list_id': listId,
    'patches': patches,
    'created': {
      for (final entry in created.entries)
        entry.key: entry.value.toUtc().toIso8601String(),
    },
  };
}

/// Where unsent task changes are kept; tests use memory. Everything is per
/// user, so a change made by one account is never sent by the next.
abstract interface class TaskPatchStore {
  Future<TaskListDraft?> load(String userId, String listId);

  /// Saves [draft], or removes the entry when it holds nothing.
  Future<void> save(TaskListDraft draft);

  Future<void> clear(String userId, String listId);

  /// The lists [userId] has waiting changes for.
  Future<List<String>> listIds(String userId);

  /// Forgets everything (on sign-out).
  Future<void> clearAll();
}

class SharedPreferencesTaskPatchStore implements TaskPatchStore {
  const SharedPreferencesTaskPatchStore();

  static const _prefix = 'wecord.lists.patches.';

  static String _key(String userId, String listId) => '$_prefix$userId.$listId';

  @override
  Future<TaskListDraft?> load(String userId, String listId) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key(userId, listId));
    if (raw == null) {
      return null;
    }
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        return null;
      }
      final draft = TaskListDraft.fromJson(json);
      return draft.userId == userId && draft.listId == listId ? draft : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(TaskListDraft draft) async {
    final preferences = await SharedPreferences.getInstance();
    final key = _key(draft.userId, draft.listId);
    if (draft.isEmpty) {
      await preferences.remove(key);
    } else {
      await preferences.setString(key, jsonEncode(draft.toJson()));
    }
  }

  @override
  Future<void> clear(String userId, String listId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key(userId, listId));
  }

  @override
  Future<List<String>> listIds(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    final start = '$_prefix$userId.';
    return [
      for (final key in preferences.getKeys())
        if (key.startsWith(start)) key.substring(start.length),
    ];
  }

  @override
  Future<void> clearAll() async {
    final preferences = await SharedPreferences.getInstance();
    for (final key in preferences.getKeys().toList()) {
      if (key.startsWith(_prefix)) {
        await preferences.remove(key);
      }
    }
  }
}

class InMemoryTaskPatchStore implements TaskPatchStore {
  /// What is stored, as the JSON a real store would keep, by user and list.
  final entries = <String, String>{};

  String _key(String userId, String listId) => '$userId|$listId';

  @override
  Future<TaskListDraft?> load(String userId, String listId) async {
    final raw = entries[_key(userId, listId)];
    return raw == null
        ? null
        : TaskListDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> save(TaskListDraft draft) async {
    final key = _key(draft.userId, draft.listId);
    if (draft.isEmpty) {
      entries.remove(key);
    } else {
      entries[key] = jsonEncode(draft.toJson());
    }
  }

  @override
  Future<void> clear(String userId, String listId) async {
    entries.remove(_key(userId, listId));
  }

  @override
  Future<List<String>> listIds(String userId) async => [
    for (final key in entries.keys)
      if (key.startsWith('$userId|')) key.substring(userId.length + 1),
  ];

  @override
  Future<void> clearAll() async => entries.clear();
}
