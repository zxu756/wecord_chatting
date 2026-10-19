import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// A change to one item row from Realtime (the assignees are separate).
typedef TaskItemChange = TaskItem;

abstract interface class ListsRepository {
  Future<List<TaskListSummary>> listLists(String conversationId);

  Future<TaskList> createList(
    String conversationId, {
    String title = '',
    String? icon,
    String? id,
    List<TaskStatus>? statuses,
    TaskListView view = TaskListView.list,
  });

  Future<TaskSnapshot> getList(String listId);

  /// One task with its list (for a card in the chat).
  Future<TaskSnapshot> getItem(String itemId);

  /// Changes the title, icon, view or statuses. [statusMoves] says where
  /// the items of a removed status go.
  Future<TaskList> updateList(
    String listId, {
    String? title,
    String? icon,
    TaskListView? view,
    List<TaskStatus>? statuses,
    Map<String, String>? statusMoves,
  });

  Future<void> deleteList(String listId);

  /// Sets the list's own fields (up to 20). Values that no longer fit a
  /// changed field are cleared on the server.
  Future<TaskList> setListFields(String listId, List<TaskFieldDef> fields);

  /// Creates or changes an item; [fields] holds only what changes (see
  /// upsert_task_item).
  Future<TaskItem> upsertItem(String listId, Map<String, Object?> fields);

  Future<TaskItem> setItemDone(String itemId, bool done);

  Future<void> deleteItem(String itemId);

  /// Makes a task out of a message (the message menu's "Create task").
  Future<TaskItem> createFromMessage(
    String messageId, {
    String? listId,
    String? title,
    String? itemId,
  });

  Future<List<MessageTask>> messageTasks(String conversationId);

  Future<String> shareItem(String itemId, String conversationId);

  Future<String> shareList(String listId, String conversationId);

  Future<List<TaskNotification>> notifications({int limit = 50});

  Future<void> markNotificationsRead([List<String>? ids]);

  /// Asks the server to push the assignments just made on [itemId]. Never
  /// throws.
  Future<void> notifyAssignments(String itemId);

  Stream<TaskItemChange> itemChanges(String listId);

  /// Something changed in a list that the item rows do not carry: its
  /// settings, or who is assigned.
  Stream<void> listStructureChanges(String listId);

  /// Changes to the lists of a conversation.
  Stream<void> conversationChanges(String conversationId);

  /// New task notifications for the current user.
  Stream<void> notificationChanges();
}

final listsRepositoryProvider = Provider<ListsRepository>((ref) {
  try {
    return SupabaseListsRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedListsRepository();
  }
});

class SupabaseListsRepository implements ListsRepository {
  const SupabaseListsRepository(this._client);

  final SupabaseClient _client;

  Map<String, dynamic> _object(Object? data) {
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    if (data is List && data.isNotEmpty && data.first is Map) {
      return Map<String, dynamic>.from(data.first as Map);
    }
    throw StateError('Unexpected response.');
  }

  List<Map<String, dynamic>> _rows(Object? data) {
    return [
      if (data is List)
        for (final row in data)
          if (row is Map) Map<String, dynamic>.from(row),
    ];
  }

  @override
  Future<List<TaskListSummary>> listLists(String conversationId) async {
    final data = await _client.rpc<Object?>(
      'list_task_lists',
      params: {'p_conversation_id': conversationId},
    );
    return [
      for (final row in _rows(data))
        TaskListSummary.fromJson(row, conversationId: conversationId),
    ];
  }

  @override
  Future<TaskList> createList(
    String conversationId, {
    String title = '',
    String? icon,
    String? id,
    List<TaskStatus>? statuses,
    TaskListView view = TaskListView.list,
  }) async {
    final data = await _client.rpc<Object?>(
      'create_task_list',
      params: {
        'p_conversation_id': conversationId,
        'p_title': title,
        'p_icon': icon,
        'p_id': id,
        'p_statuses': statuses == null
            ? null
            : [for (final status in statuses) status.toJson()],
        'p_default_view': view.value,
      },
    );
    return TaskList.fromJson(_object(data));
  }

  @override
  Future<TaskSnapshot> getList(String listId) async {
    final data = await _client.rpc<Object?>(
      'get_task_list',
      params: {'p_list_id': listId},
    );
    return TaskSnapshot.fromJson(_object(data));
  }

  @override
  Future<TaskSnapshot> getItem(String itemId) async {
    final data = await _client.rpc<Object?>(
      'get_task_item',
      params: {'p_item_id': itemId},
    );
    return TaskSnapshot.fromJson(_object(data));
  }

  @override
  Future<TaskList> updateList(
    String listId, {
    String? title,
    String? icon,
    TaskListView? view,
    List<TaskStatus>? statuses,
    Map<String, String>? statusMoves,
  }) async {
    final data = await _client.rpc<Object?>(
      'update_task_list',
      params: {
        'p_list_id': listId,
        'p_patch': {
          'title': ?title,
          'icon': ?icon,
          if (view != null) 'default_view': view.value,
          if (statuses != null)
            'statuses': [for (final status in statuses) status.toJson()],
          'status_moves': ?statusMoves,
        },
      },
    );
    return TaskList.fromJson(_object(data));
  }

  @override
  Future<void> deleteList(String listId) async {
    await _client.rpc<Object?>(
      'delete_task_list',
      params: {'p_list_id': listId},
    );
  }

  @override
  Future<TaskList> setListFields(
    String listId,
    List<TaskFieldDef> fields,
  ) async {
    final data = await _client.rpc<Object?>(
      'set_task_list_fields',
      params: {
        'p_list_id': listId,
        'p_field_defs': [for (final field in fields) field.toJson()],
      },
    );
    return TaskList.fromJson(_object(data));
  }

  @override
  Future<TaskItem> upsertItem(
    String listId,
    Map<String, Object?> fields,
  ) async {
    final data = await _client.rpc<Object?>(
      'upsert_task_item',
      params: {'p_list_id': listId, 'p_item': fields},
    );
    return TaskItem.fromJson(_object(data));
  }

  @override
  Future<TaskItem> setItemDone(String itemId, bool done) async {
    final data = await _client.rpc<Object?>(
      'set_task_item_done',
      params: {'p_item_id': itemId, 'p_done': done},
    );
    return TaskItem.fromJson(_object(data));
  }

  @override
  Future<void> deleteItem(String itemId) async {
    await _client.rpc<Object?>(
      'delete_task_item',
      params: {'p_item_id': itemId},
    );
  }

  @override
  Future<TaskItem> createFromMessage(
    String messageId, {
    String? listId,
    String? title,
    String? itemId,
  }) async {
    final data = await _client.rpc<Object?>(
      'create_task_from_message',
      params: {
        'p_message_id': messageId,
        'p_list_id': listId,
        'p_title': title,
        'p_item_id': itemId,
      },
    );
    return TaskItem.fromJson(_object(data));
  }

  @override
  Future<List<MessageTask>> messageTasks(String conversationId) async {
    final data = await _client.rpc<Object?>(
      'list_message_tasks',
      params: {'p_conversation_id': conversationId},
    );
    return [for (final row in _rows(data)) MessageTask.fromJson(row)];
  }

  Future<String> _share(String function, Map<String, Object?> params) async {
    final data = await _client.rpc<Object?>(function, params: params);
    final messageId = '$data';
    try {
      await _client.functions.invoke('push', body: {'message_id': messageId});
    } on Object {
      // Push is a courtesy; the card is already in the chat.
    }
    return messageId;
  }

  @override
  Future<String> shareItem(String itemId, String conversationId) => _share(
    'share_task_item',
    {'p_item_id': itemId, 'p_conversation_id': conversationId},
  );

  @override
  Future<String> shareList(String listId, String conversationId) => _share(
    'share_task_list',
    {'p_list_id': listId, 'p_conversation_id': conversationId},
  );

  @override
  Future<List<TaskNotification>> notifications({int limit = 50}) async {
    final data = await _client.rpc<Object?>(
      'list_task_notifications',
      params: {'p_limit': limit},
    );
    return [for (final row in _rows(data)) TaskNotification.fromJson(row)];
  }

  @override
  Future<void> markNotificationsRead([List<String>? ids]) async {
    await _client.rpc<Object?>(
      'mark_task_notifications_read',
      params: {'p_ids': ids},
    );
  }

  @override
  Future<void> notifyAssignments(String itemId) async {
    try {
      await _client.functions.invoke('push', body: {'task_item_id': itemId});
    } on Object {
      // Push is a courtesy; the person is already assigned.
    }
  }

  Stream<T> _stream<T>(
    String name,
    List<({String table, String column, String value})> sources,
    void Function(PostgresChangePayload payload, StreamController<T> out)
    onEvent,
  ) {
    late RealtimeChannel channel;
    late StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () {
        var builder = _client.channel(name);
        for (final source in sources) {
          builder = builder.onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: source.table,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: source.column,
              value: source.value,
            ),
            callback: (payload) => onEvent(payload, controller),
          );
        }
        channel = builder.subscribe();
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }

  @override
  Stream<TaskItemChange> itemChanges(String listId) {
    return _stream<TaskItemChange>(
      'task-items-$listId',
      [(table: 'task_items', column: 'list_id', value: listId)],
      (payload, out) {
        final record = payload.newRecord;
        if (record.isEmpty) {
          return;
        }
        try {
          out.add(TaskItem.fromJson(record));
        } on Object {
          // A row of a shape we do not know; the next fetch has it.
        }
      },
    );
  }

  @override
  Stream<void> listStructureChanges(String listId) {
    return _stream<void>('task-structure-$listId', [
      (table: 'task_item_assignees', column: 'list_id', value: listId),
      (table: 'task_lists', column: 'id', value: listId),
    ], (payload, out) => out.add(null));
  }

  @override
  Stream<void> conversationChanges(String conversationId) {
    return _stream<void>('task-lists-$conversationId', [
      (table: 'task_lists', column: 'conversation_id', value: conversationId),
    ], (payload, out) => out.add(null));
  }

  @override
  Stream<void> notificationChanges() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Stream.empty();
    }
    // Notifications are not published to Realtime (they are private to the
    // reader and read through list_task_notifications); changes to the
    // person's assignments are, which is when a new notification appears.
    return _stream<void>('task-assignments-$userId', [
      (table: 'task_item_assignees', column: 'user_id', value: userId),
    ], (payload, out) => out.add(null));
  }
}

/// Used where Supabase is not set up (tests); every call fails.
class UninitializedListsRepository implements ListsRepository {
  const UninitializedListsRepository();

  static Never _fail() =>
      throw StateError('Supabase must be initialized first.');

  @override
  Future<List<TaskListSummary>> listLists(String conversationId) async =>
      _fail();

  @override
  Future<TaskList> createList(
    String conversationId, {
    String title = '',
    String? icon,
    String? id,
    List<TaskStatus>? statuses,
    TaskListView view = TaskListView.list,
  }) async => _fail();

  @override
  Future<TaskSnapshot> getList(String listId) async => _fail();

  @override
  Future<TaskSnapshot> getItem(String itemId) async => _fail();

  @override
  Future<TaskList> updateList(
    String listId, {
    String? title,
    String? icon,
    TaskListView? view,
    List<TaskStatus>? statuses,
    Map<String, String>? statusMoves,
  }) async => _fail();

  @override
  Future<void> deleteList(String listId) async => _fail();

  @override
  Future<TaskList> setListFields(
    String listId,
    List<TaskFieldDef> fields,
  ) async => _fail();

  @override
  Future<TaskItem> upsertItem(
    String listId,
    Map<String, Object?> fields,
  ) async => _fail();

  @override
  Future<TaskItem> setItemDone(String itemId, bool done) async => _fail();

  @override
  Future<void> deleteItem(String itemId) async => _fail();

  @override
  Future<TaskItem> createFromMessage(
    String messageId, {
    String? listId,
    String? title,
    String? itemId,
  }) async => _fail();

  @override
  Future<List<MessageTask>> messageTasks(String conversationId) async =>
      const [];

  @override
  Future<String> shareItem(String itemId, String conversationId) async =>
      _fail();

  @override
  Future<String> shareList(String listId, String conversationId) async =>
      _fail();

  @override
  Future<List<TaskNotification>> notifications({int limit = 50}) async =>
      const [];

  @override
  Future<void> markNotificationsRead([List<String>? ids]) async {}

  @override
  Future<void> notifyAssignments(String itemId) async {}

  @override
  Stream<TaskItemChange> itemChanges(String listId) => const Stream.empty();

  @override
  Stream<void> listStructureChanges(String listId) => const Stream.empty();

  @override
  Stream<void> conversationChanges(String conversationId) =>
      const Stream.empty();

  @override
  Stream<void> notificationChanges() => const Stream.empty();
}
