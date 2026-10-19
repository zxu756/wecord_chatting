import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Whether a status means not started, under way or finished.
enum TaskStatusKind {
  todo('todo'),
  active('active'),
  done('done');

  const TaskStatusKind(this.value);

  final String value;

  static TaskStatusKind fromValue(Object? value) {
    for (final kind in values) {
      if (kind.value == value) {
        return kind;
      }
    }
    return todo;
  }
}

/// A column of a list: To do, In progress, Done, or the list's own.
@immutable
class TaskStatus {
  const TaskStatus({required this.id, required this.name, required this.kind});

  factory TaskStatus.fromJson(Map<String, dynamic> json) {
    return TaskStatus(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      kind: TaskStatusKind.fromValue(json['kind']),
    );
  }

  /// The statuses a new list starts with.
  static const defaults = [
    TaskStatus(id: 'todo', name: 'To do', kind: TaskStatusKind.todo),
    TaskStatus(id: 'doing', name: 'In progress', kind: TaskStatusKind.active),
    TaskStatus(id: 'done', name: 'Done', kind: TaskStatusKind.done),
  ];

  final String id;
  final String name;
  final TaskStatusKind kind;

  /// The name shown: the three default names are translated, custom ones
  /// are the author's words.
  String get label => switch (name) {
    'To do' => tr('To do'),
    'In progress' => tr('In progress'),
    'Done' => tr('Done'),
    _ => name,
  };

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'kind': kind.value};

  TaskStatus copyWith({String? name, TaskStatusKind? kind}) =>
      TaskStatus(id: id, name: name ?? this.name, kind: kind ?? this.kind);

  @override
  bool operator ==(Object other) =>
      other is TaskStatus &&
      other.id == id &&
      other.name == name &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(id, name, kind);
}

enum TaskPriority {
  none(0),
  low(1),
  medium(2),
  high(3);

  const TaskPriority(this.value);

  final int value;

  static TaskPriority fromValue(Object? value) {
    for (final priority in values) {
      if (priority.value == value) {
        return priority;
      }
    }
    return none;
  }

  String get label => switch (this) {
    none => tr('No priority'),
    low => tr('Low'),
    medium => tr('Medium'),
    high => tr('High'),
  };
}

/// What kind of value a list's own field holds.
enum TaskFieldType {
  number('number'),
  select('select'),
  link('link'),
  person('person');

  const TaskFieldType(this.value);

  final String value;

  static TaskFieldType? fromValue(Object? value) {
    for (final type in values) {
      if (type.value == value) {
        return type;
      }
    }
    return null;
  }

  String get label => switch (this) {
    number => tr('Number'),
    select => tr('Single choice'),
    link => tr('Link'),
    person => trIn('task-field', 'Person'),
  };
}

/// One choice of a single-choice field.
@immutable
class TaskFieldOption {
  const TaskFieldOption({required this.id, required this.name});

  factory TaskFieldOption.fromJson(Map<String, dynamic> json) =>
      TaskFieldOption(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
      );

  final String id;
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is TaskFieldOption && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// A field a list defines for its tasks (up to 20 per list).
@immutable
class TaskFieldDef {
  const TaskFieldDef({
    required this.id,
    required this.name,
    required this.type,
    this.options = const [],
  });

  static TaskFieldDef? tryFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final type = TaskFieldType.fromValue(json['type']);
    final id = json['id'];
    if (type == null || id is! String) {
      return null;
    }
    return TaskFieldDef(
      id: id,
      name: json['name'] as String? ?? '',
      type: type,
      options: [
        for (final option in (json['options'] as List<dynamic>? ?? const []))
          if (option is Map)
            TaskFieldOption.fromJson(Map<String, dynamic>.from(option)),
      ],
    );
  }

  final String id;
  final String name;
  final TaskFieldType type;

  /// The choices of a single-choice field.
  final List<TaskFieldOption> options;

  TaskFieldOption? optionById(Object? id) {
    for (final option in options) {
      if (option.id == id) {
        return option;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type.value,
    if (type == TaskFieldType.select)
      'options': [for (final option in options) option.toJson()],
  };

  TaskFieldDef copyWith({
    String? name,
    TaskFieldType? type,
    List<TaskFieldOption>? options,
  }) => TaskFieldDef(
    id: id,
    name: name ?? this.name,
    type: type ?? this.type,
    options: options ?? this.options,
  );

  @override
  bool operator ==(Object other) =>
      other is TaskFieldDef &&
      other.id == id &&
      other.name == name &&
      other.type == type &&
      listEquals(other.options, options);

  @override
  int get hashCode => Object.hash(id, name, type, Object.hashAll(options));
}

/// How often a repeating task comes back.
enum TaskRepeatUnit {
  daily('daily'),
  weekly('weekly'),
  monthly('monthly'),
  yearly('yearly');

  const TaskRepeatUnit(this.value);

  final String value;

  static TaskRepeatUnit? fromValue(Object? value) {
    for (final unit in values) {
      if (unit.value == value) {
        return unit;
      }
    }
    return null;
  }
}

/// A repeat rule: every [interval] days, weeks, months or years, counted
/// from the task's date. [tzOffset] (minutes east of UTC) says where "the
/// day" is, so an all-day task stays on the day the person set.
@immutable
class TaskRecurrence {
  const TaskRecurrence({required this.unit, this.interval = 1, this.tzOffset});

  static TaskRecurrence? tryFromJson(Object? json) {
    var map = json;
    if (map is String && map.startsWith('{')) {
      try {
        map = jsonDecode(map);
      } on Object {
        return null;
      }
    }
    if (map is! Map) {
      return null;
    }
    final unit = TaskRepeatUnit.fromValue(map['freq']);
    if (unit == null) {
      return null;
    }
    return TaskRecurrence(
      unit: unit,
      interval: ((map['interval'] as num?)?.toInt() ?? 1).clamp(1, 99),
      tzOffset: (map['tz_offset'] as num?)?.toInt(),
    );
  }

  /// A rule for a task set up here, counting days in this device's time zone.
  factory TaskRecurrence.here(TaskRepeatUnit unit, {int interval = 1}) =>
      TaskRecurrence(
        unit: unit,
        interval: interval,
        tzOffset: DateTime.now().timeZoneOffset.inMinutes,
      );

  final TaskRepeatUnit unit;
  final int interval;
  final int? tzOffset;

  Map<String, Object?> toJson() => {
    'freq': unit.value,
    'interval': interval,
    'tz_offset': ?tzOffset,
  };

  /// "Every day", "Every 2 weeks".
  String get label {
    if (interval == 1) {
      return switch (unit) {
        TaskRepeatUnit.daily => tr('Every day'),
        TaskRepeatUnit.weekly => tr('Every week'),
        TaskRepeatUnit.monthly => tr('Every month'),
        TaskRepeatUnit.yearly => tr('Every year'),
      };
    }
    final args = {'count': interval};
    return switch (unit) {
      TaskRepeatUnit.daily => tr('Every {count} days', args),
      TaskRepeatUnit.weekly => tr('Every {count} weeks', args),
      TaskRepeatUnit.monthly => tr('Every {count} months', args),
      TaskRepeatUnit.yearly => tr('Every {count} years', args),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is TaskRecurrence &&
      other.unit == unit &&
      other.interval == interval;

  @override
  int get hashCode => Object.hash(unit, interval);
}

enum TaskListView {
  list('list'),
  board('board');

  const TaskListView(this.value);

  final String value;

  static TaskListView fromValue(Object? value) =>
      value == 'board' ? board : list;
}

/// A task list's own fields.
@immutable
class TaskList {
  const TaskList({
    required this.id,
    required this.conversationId,
    required this.title,
    required this.icon,
    required this.statuses,
    this.fieldDefs = const [],
    this.defaultView = TaskListView.list,
    this.createdBy,
    this.canEdit = false,
    this.canManage = false,
  });

  factory TaskList.fromJson(Map<String, dynamic> json) {
    return TaskList(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      title: json['title'] as String? ?? '',
      icon: json['icon'] as String? ?? defaultIcon,
      statuses: [
        for (final status in (json['statuses'] as List<dynamic>? ?? const []))
          TaskStatus.fromJson(Map<String, dynamic>.from(status as Map)),
      ],
      fieldDefs: [
        for (final def in (json['field_defs'] as List<dynamic>? ?? const []))
          ?TaskFieldDef.tryFromJson(def),
      ],
      defaultView: TaskListView.fromValue(json['default_view']),
      createdBy: json['created_by'] as String?,
      canEdit: json['can_edit'] == true,
      canManage: json['can_manage'] == true,
    );
  }

  static const defaultIcon = '✅';

  final String id;
  final String conversationId;
  final String title;
  final String icon;
  final List<TaskStatus> statuses;

  /// The list's own fields, in the order they are shown.
  final List<TaskFieldDef> fieldDefs;
  final TaskListView defaultView;
  final String? createdBy;
  final bool canEdit;
  final bool canManage;

  TaskFieldDef? fieldById(String id) {
    for (final def in fieldDefs) {
      if (def.id == id) {
        return def;
      }
    }
    return null;
  }

  TaskStatus? statusById(String id) {
    for (final status in statuses) {
      if (status.id == id) {
        return status;
      }
    }
    return null;
  }

  /// The status a finished item moves to.
  TaskStatus? get doneStatus =>
      statuses.where((s) => s.kind == TaskStatusKind.done).firstOrNull;

  /// The status an item returns to when it is unchecked.
  TaskStatus? get todoStatus =>
      statuses.where((s) => s.kind == TaskStatusKind.todo).firstOrNull;

  TaskList copyWith({
    String? title,
    String? icon,
    List<TaskStatus>? statuses,
    List<TaskFieldDef>? fieldDefs,
    TaskListView? defaultView,
  }) {
    return TaskList(
      id: id,
      conversationId: conversationId,
      title: title ?? this.title,
      icon: icon ?? this.icon,
      statuses: statuses ?? this.statuses,
      fieldDefs: fieldDefs ?? this.fieldDefs,
      defaultView: defaultView ?? this.defaultView,
      createdBy: createdBy,
      canEdit: canEdit,
      canManage: canManage,
    );
  }
}

/// A list as listed in a conversation, with its counts.
@immutable
class TaskListSummary {
  const TaskListSummary({
    required this.id,
    required this.conversationId,
    required this.title,
    required this.icon,
    required this.defaultView,
    required this.openCount,
    required this.doneCount,
    required this.mineCount,
    required this.overdueCount,
    required this.canEdit,
  });

  factory TaskListSummary.fromJson(
    Map<String, dynamic> json, {
    required String conversationId,
  }) {
    return TaskListSummary(
      id: json['id'] as String,
      conversationId: conversationId,
      title: json['title'] as String? ?? '',
      icon: json['icon'] as String? ?? TaskList.defaultIcon,
      defaultView: TaskListView.fromValue(json['default_view']),
      openCount: (json['open_count'] as num?)?.toInt() ?? 0,
      doneCount: (json['done_count'] as num?)?.toInt() ?? 0,
      mineCount: (json['mine_count'] as num?)?.toInt() ?? 0,
      overdueCount: (json['overdue_count'] as num?)?.toInt() ?? 0,
      canEdit: json['can_edit'] == true,
    );
  }

  final String id;
  final String conversationId;
  final String title;
  final String icon;
  final TaskListView defaultView;
  final int openCount;
  final int doneCount;
  final int mineCount;
  final int overdueCount;
  final bool canEdit;
}

/// One task.
@immutable
class TaskItem {
  const TaskItem({
    required this.id,
    required this.listId,
    required this.title,
    required this.status,
    this.details = '',
    this.priority = TaskPriority.none,
    this.dueAt,
    this.dueHasTime = false,
    this.pos = 'V',
    this.sourceMessageId,
    this.createdBy,
    this.createdAt,
    this.completedAt,
    this.assignees = const [],
    this.deleted = false,
    this.custom = const {},
    this.parentId,
    this.recurrence,
  });

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    return TaskItem(
      id: json['id'] as String,
      listId: json['list_id'] as String,
      title: json['title'] as String? ?? '',
      details: json['details'] as String? ?? '',
      status: json['status'] as String? ?? 'todo',
      priority: TaskPriority.fromValue(json['priority']),
      dueAt: DateTime.tryParse('${json['due_at']}')?.toLocal(),
      dueHasTime: json['due_has_time'] == true,
      pos: json['pos'] as String? ?? 'V',
      sourceMessageId: json['source_message_id'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.tryParse('${json['created_at']}'),
      completedAt: DateTime.tryParse('${json['completed_at']}'),
      assignees: [
        for (final id in (json['assignees'] as List<dynamic>? ?? const []))
          '$id',
      ],
      deleted: json['deleted'] == true || json['deleted_at'] != null,
      custom: _customFrom(json['custom']),
      parentId: json['parent_id'] as String?,
      recurrence: TaskRecurrence.tryFromJson(json['recurrence']),
    );
  }

  static Map<String, Object?> _customFrom(Object? raw) {
    var value = raw;
    if (value is String && value.startsWith('{')) {
      try {
        value = jsonDecode(value);
      } on Object {
        return const {};
      }
    }
    if (value is! Map) {
      return const {};
    }
    return {
      for (final entry in value.entries)
        if (entry.value != null) '${entry.key}': entry.value as Object?,
    };
  }

  final String id;
  final String listId;
  final String title;
  final String details;

  /// The id of one of the list's statuses.
  final String status;
  final TaskPriority priority;
  final DateTime? dueAt;

  /// False for "all day" dates.
  final bool dueHasTime;

  /// Orders the item among those of its status.
  final String pos;
  final String? sourceMessageId;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final List<String> assignees;
  final bool deleted;

  /// The values of the list's own fields, by field id: a number, the id of a
  /// choice, a link or a user id.
  final Map<String, Object?> custom;

  /// The task this is a subtask of (one level only).
  final String? parentId;

  /// How the task repeats, when it does.
  final TaskRecurrence? recurrence;

  bool get isSubtask => parentId != null;

  bool get isDone => completedAt != null;

  /// Not finished and past its date.
  bool isOverdue(DateTime now) {
    final due = dueAt;
    return due != null && !isDone && due.isBefore(now);
  }

  bool isAssignedTo(String? userId) =>
      userId != null && assignees.contains(userId);

  TaskItem copyWith({
    String? listId,
    String? title,
    String? details,
    String? status,
    TaskPriority? priority,
    Object? dueAt = _keep,
    bool? dueHasTime,
    String? pos,
    List<String>? assignees,
    Object? completedAt = _keep,
    bool? deleted,
    Map<String, Object?>? custom,
    Object? parentId = _keep,
    Object? recurrence = _keep,
  }) {
    return TaskItem(
      id: id,
      listId: listId ?? this.listId,
      title: title ?? this.title,
      details: details ?? this.details,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      dueAt: identical(dueAt, _keep) ? this.dueAt : dueAt as DateTime?,
      dueHasTime: dueHasTime ?? this.dueHasTime,
      pos: pos ?? this.pos,
      sourceMessageId: sourceMessageId,
      createdBy: createdBy,
      createdAt: createdAt,
      completedAt: identical(completedAt, _keep)
          ? this.completedAt
          : completedAt as DateTime?,
      assignees: assignees ?? this.assignees,
      deleted: deleted ?? this.deleted,
      custom: custom ?? this.custom,
      parentId: identical(parentId, _keep)
          ? this.parentId
          : parentId as String?,
      recurrence: identical(recurrence, _keep)
          ? this.recurrence
          : recurrence as TaskRecurrence?,
    );
  }

  static const _keep = Object();
}

/// A list with its items, as fetched.
@immutable
class TaskSnapshot {
  const TaskSnapshot({required this.list, required this.items});

  factory TaskSnapshot.fromJson(Map<String, dynamic> json) {
    return TaskSnapshot(
      list: TaskList.fromJson(Map<String, dynamic>.from(json['list'] as Map)),
      items: [
        for (final item in (json['items'] as List<dynamic>? ?? const []))
          TaskItem.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
    );
  }

  final TaskList list;
  final List<TaskItem> items;
}

enum TaskNotificationKind {
  assigned,
  dueSoon,
  overdue;

  static TaskNotificationKind fromValue(Object? value) => switch (value) {
    'due_soon' => dueSoon,
    'overdue' => overdue,
    _ => assigned,
  };
}

/// An assignment or a due reminder in the notifications.
@immutable
class TaskNotification {
  const TaskNotification({
    required this.id,
    required this.kind,
    required this.itemId,
    required this.listId,
    required this.conversationId,
    required this.title,
    required this.createdAt,
    required this.isUnread,
    required this.isDone,
    this.actorName,
    this.actorAvatarUrl,
    this.listTitle,
    this.dueAt,
  });

  factory TaskNotification.fromJson(Map<String, dynamic> json) {
    return TaskNotification(
      id: json['id'] as String,
      kind: TaskNotificationKind.fromValue(json['kind']),
      itemId: json['item_id'] as String,
      listId: json['list_id'] as String,
      conversationId: json['conversation_id'] as String,
      title: json['title'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      isUnread: json['is_unread'] == true,
      isDone: json['is_done'] == true,
      actorName: json['actor_name'] as String?,
      actorAvatarUrl: json['actor_avatar_url'] as String?,
      listTitle: json['list_title'] as String?,
      dueAt: DateTime.tryParse('${json['due_at']}')?.toLocal(),
    );
  }

  final String id;
  final TaskNotificationKind kind;
  final String itemId;
  final String listId;
  final String conversationId;
  final String title;
  final DateTime createdAt;
  final bool isUnread;
  final bool isDone;
  final String? actorName;
  final String? actorAvatarUrl;
  final String? listTitle;
  final DateTime? dueAt;
}

/// A task made from a message.
@immutable
class MessageTask {
  const MessageTask({
    required this.messageId,
    required this.itemId,
    required this.listId,
    required this.title,
    required this.isDone,
  });

  factory MessageTask.fromJson(Map<String, dynamic> json) {
    return MessageTask(
      messageId: json['message_id'] as String,
      itemId: json['item_id'] as String,
      listId: json['list_id'] as String,
      title: json['title'] as String? ?? '',
      isDone: json['is_done'] == true,
    );
  }

  final String messageId;
  final String itemId;
  final String listId;
  final String title;
  final bool isDone;

  MessageTask copyWith({bool? isDone}) => MessageTask(
    messageId: messageId,
    itemId: itemId,
    listId: listId,
    title: title,
    isDone: isDone ?? this.isDone,
  );
}
