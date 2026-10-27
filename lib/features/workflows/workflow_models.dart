import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// What starts a workflow (migration 202610281310).
enum WorkflowTriggerKind {
  memberJoined('member_joined'),
  reaction('reaction'),
  keyword('keyword'),
  schedule('schedule'),
  formSubmitted('form_submitted');

  const WorkflowTriggerKind(this.wire);

  final String wire;

  static WorkflowTriggerKind? fromWire(Object? value) {
    for (final kind in values) {
      if (kind.wire == value) {
        return kind;
      }
    }
    return null;
  }

  String get label => switch (this) {
    memberJoined => tr('Someone joins'),
    reaction => tr('Someone reacts to a message'),
    keyword => tr('A message has a keyword'),
    schedule => tr('On a schedule'),
    formSubmitted => tr('A form is submitted'),
  };

  /// Whether the event has a person ({member}, send a DM, add a role).
  bool get hasMember => this != schedule;

  /// Whether the event is about a message (a task can be made from it).
  bool get hasMessage => this == reaction || this == keyword;
}

/// What a workflow does, in order.
enum WorkflowActionKind {
  sendMessage('send_message'),
  sendDm('send_dm'),
  addRole('add_role'),
  createTask('create_task'),
  sendForm('send_form');

  const WorkflowActionKind(this.wire);

  final String wire;

  static WorkflowActionKind? fromWire(Object? value) {
    for (final kind in values) {
      if (kind.wire == value) {
        return kind;
      }
    }
    return null;
  }

  String get label => switch (this) {
    sendMessage => tr('Send a message'),
    sendDm => tr('Send a direct message'),
    addRole => tr('Give a role'),
    createTask => tr('Create a task'),
    sendForm => tr('Send a form'),
  };

  /// Whether the action works in a channel (a circle picks one).
  bool get usesChannel =>
      this == sendMessage || this == createTask || this == sendForm;
}

/// Why a workflow does not run.
enum WorkflowPauseReason {
  manual('manual'),
  creatorLostPermission('creator_lost_permission'),
  creatorGone('creator_gone'),
  failures('failures'),
  finished('finished');

  const WorkflowPauseReason(this.wire);

  final String wire;

  static WorkflowPauseReason? fromWire(Object? value) {
    for (final reason in values) {
      if (reason.wire == value) {
        return reason;
      }
    }
    return null;
  }

  String get label => switch (this) {
    manual => tr('Paused'),
    creatorLostPermission => tr(
      'Paused: the person who made it can no longer manage this place.',
    ),
    creatorGone => tr('Paused: the person who made it left.'),
    failures => tr('Paused after it failed 5 times in a row.'),
    finished => tr('Finished: its last day has passed.'),
  };
}

/// The limits the server enforces, so the editor can say them.
@immutable
class WorkflowLimits {
  const WorkflowLimits({
    this.maxPerCircle = 20,
    this.maxPerGroup = 5,
    this.maxActions = 5,
    this.maxRunsPerDay = 200,
    this.maxText = 500,
    this.maxKeywords = 10,
  });

  factory WorkflowLimits.fromJson(Map<String, dynamic> json) {
    int read(String key, int fallback) =>
        (json[key] as num?)?.toInt() ?? fallback;
    return WorkflowLimits(
      maxPerCircle: read('max_per_circle', 20),
      maxPerGroup: read('max_per_group', 5),
      maxActions: read('max_actions', 5),
      maxRunsPerDay: read('max_runs_per_day', 200),
      maxText: read('max_text', 500),
      maxKeywords: read('max_keywords', 10),
    );
  }

  final int maxPerCircle;
  final int maxPerGroup;
  final int maxActions;
  final int maxRunsPerDay;
  final int maxText;
  final int maxKeywords;
}

/// One step of a workflow: the kind and what it was set up with
/// (`text`, `channel_id`, `role_id`, `form_id`, `title`, `from_message`,
/// `date_in_title`, `deadline_days`).
@immutable
class WorkflowAction {
  const WorkflowAction(this.kind, [this.config = const {}]);

  static WorkflowAction? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final kind = WorkflowActionKind.fromWire(json['type']);
    if (kind == null) {
      return null;
    }
    final config = Map<String, Object?>.from(json)..remove('type');
    return WorkflowAction(kind, config);
  }

  final WorkflowActionKind kind;
  final Map<String, Object?> config;

  Map<String, Object?> toJson() => {'type': kind.wire, ...config};

  String? get text => config['text'] as String?;
  String? get title => config['title'] as String?;
  String? get channelId => config['channel_id'] as String?;
  String? get roleId => config['role_id'] as String?;
  String? get formId => config['form_id'] as String?;
  bool get fromMessage => config['from_message'] == true;
  bool get dateInTitle => config['date_in_title'] != false;
  int? get deadlineDays => (config['deadline_days'] as num?)?.toInt();
}

/// What starts a workflow and how it is set up (`emoji`, `channel_id`,
/// `words`, `recurrence`, `day`, `time`, `zone`, `until`, `form_id`).
@immutable
class WorkflowTrigger {
  const WorkflowTrigger(this.kind, [this.config = const {}]);

  static WorkflowTrigger? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final kind = WorkflowTriggerKind.fromWire(json['kind']);
    if (kind == null) {
      return null;
    }
    final config = json['config'];
    return WorkflowTrigger(
      kind,
      config is Map ? Map<String, Object?>.from(config) : const {},
    );
  }

  final WorkflowTriggerKind kind;
  final Map<String, Object?> config;

  Map<String, Object?> toJson() => {'kind': kind.wire, 'config': config};

  String? get emoji => config['emoji'] as String?;
  String? get channelId => config['channel_id'] as String?;
  String? get formId => config['form_id'] as String?;
  String get recurrence => (config['recurrence'] as String?) ?? 'daily';
  String get time => (config['time'] as String?) ?? '09:00';
  String? get zone => config['zone'] as String?;
  int? get day => (config['day'] as num?)?.toInt();
  String? get until => config['until'] as String?;
  List<String> get words => [
    for (final word in (config['words'] as List?) ?? const []) '$word',
  ];
}

/// A workflow of a circle or a group chat.
@immutable
class Workflow {
  const Workflow({
    required this.id,
    required this.name,
    required this.trigger,
    required this.actions,
    required this.enabled,
    this.circleId,
    this.conversationId,
    this.pausedReason,
    this.creatorName,
    this.createdByMe = false,
    this.nextRunAt,
    this.lastRunAt,
    this.runsToday = 0,
    this.lastStatus,
  });

  static Workflow? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final trigger = WorkflowTrigger.fromJson(json['trigger']);
    if (trigger == null) {
      return null;
    }
    final creator = json['created_by'];
    return Workflow(
      id: json['id'] as String,
      circleId: json['circle_id'] as String?,
      conversationId: json['conversation_id'] as String?,
      name: (json['name'] as String?) ?? '',
      trigger: trigger,
      actions: [
        for (final item in (json['actions'] as List?) ?? const [])
          ?WorkflowAction.fromJson(item),
      ],
      enabled: json['enabled'] == true,
      pausedReason: WorkflowPauseReason.fromWire(json['paused_reason']),
      creatorName: creator is Map ? creator['name'] as String? : null,
      createdByMe: json['created_by_me'] == true,
      nextRunAt: _time(json['next_run_at']),
      lastRunAt: _time(json['last_run_at']),
      runsToday: (json['runs_today'] as num?)?.toInt() ?? 0,
      lastStatus: json['last_status'] as String?,
    );
  }

  final String id;
  final String? circleId;
  final String? conversationId;
  final String name;
  final WorkflowTrigger trigger;
  final List<WorkflowAction> actions;
  final bool enabled;
  final WorkflowPauseReason? pausedReason;
  final String? creatorName;
  final bool createdByMe;
  final DateTime? nextRunAt;
  final DateTime? lastRunAt;
  final int runsToday;
  final String? lastStatus;

  /// Paused by the system rather than by a person: it needs somebody to look
  /// at it before it is turned back on.
  bool get needsAttention =>
      !enabled &&
      pausedReason != null &&
      pausedReason != WorkflowPauseReason.manual;
}

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// What a person can open with a workflow list.
@immutable
class WorkflowList {
  const WorkflowList({
    this.canManage = true,
    this.limits = const WorkflowLimits(),
    this.workflows = const [],
  });

  factory WorkflowList.fromJson(Map<String, dynamic> json) {
    final limits = json['limits'];
    return WorkflowList(
      canManage: json['can_manage'] != false,
      limits: limits is Map
          ? WorkflowLimits.fromJson(Map<String, dynamic>.from(limits))
          : const WorkflowLimits(),
      workflows: [
        for (final item in (json['workflows'] as List?) ?? const [])
          ?Workflow.fromJson(item),
      ],
    );
  }

  final bool canManage;
  final WorkflowLimits limits;
  final List<Workflow> workflows;
}

@immutable
class WorkflowChannel {
  const WorkflowChannel({required this.id, required this.name});

  final String id;
  final String name;
}

@immutable
class WorkflowRoleOption {
  const WorkflowRoleOption({required this.id, required this.name});

  final String id;
  final String name;
}

@immutable
class WorkflowFormOption {
  const WorkflowFormOption({
    required this.id,
    required this.title,
    this.anonymous = false,
  });

  final String id;
  final String title;
  final bool anonymous;
}

/// The channels, roles and forms a workflow can point at.
@immutable
class WorkflowOptions {
  const WorkflowOptions({
    this.channels = const [],
    this.roles = const [],
    this.forms = const [],
  });

  factory WorkflowOptions.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> maps(String key) => [
      for (final item in (json[key] as List?) ?? const [])
        if (item is Map) Map<String, dynamic>.from(item),
    ];
    return WorkflowOptions(
      channels: [
        for (final c in maps('channels'))
          WorkflowChannel(
            id: c['id'] as String,
            name: (c['name'] as String?) ?? '',
          ),
      ],
      roles: [
        for (final r in maps('roles'))
          WorkflowRoleOption(
            id: r['id'] as String,
            name: (r['name'] as String?) ?? '',
          ),
      ],
      forms: [
        for (final f in maps('forms'))
          WorkflowFormOption(
            id: f['id'] as String,
            title: (f['title'] as String?) ?? '',
            anonymous: f['anonymous'] == true,
          ),
      ],
    );
  }

  final List<WorkflowChannel> channels;
  final List<WorkflowRoleOption> roles;
  final List<WorkflowFormOption> forms;

  String? channelName(String? id) {
    for (final channel in channels) {
      if (channel.id == id) {
        return channel.name;
      }
    }
    return null;
  }

  String? roleName(String? id) {
    for (final role in roles) {
      if (role.id == id) {
        return role.name;
      }
    }
    return null;
  }

  String? formTitle(String? id) {
    for (final form in forms) {
      if (form.id == id) {
        return form.title;
      }
    }
    return null;
  }
}

/// One action of one run, as the log shows it.
@immutable
class WorkflowStep {
  const WorkflowStep({required this.action, required this.status, this.detail});

  final String action;

  /// ok, skipped or failed.
  final String status;
  final String? detail;

  WorkflowActionKind? get kind => WorkflowActionKind.fromWire(action);
}

/// One run of a workflow.
@immutable
class WorkflowRun {
  const WorkflowRun({
    required this.id,
    required this.status,
    required this.createdAt,
    this.skipReason,
    this.actorName,
    this.steps = const [],
    this.error,
  });

  factory WorkflowRun.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'];
    return WorkflowRun(
      id: json['id'] as String,
      status: (json['status'] as String?) ?? 'queued',
      skipReason: json['skip_reason'] as String?,
      actorName: actor is Map ? actor['name'] as String? : null,
      steps: [
        for (final item in (json['results'] as List?) ?? const [])
          if (item is Map)
            WorkflowStep(
              action: (item['action'] as String?) ?? '',
              status: (item['status'] as String?) ?? 'ok',
              detail: item['detail'] as String?,
            ),
      ],
      error: json['error'] as String?,
      createdAt: _time(json['created_at']) ?? DateTime.now(),
    );
  }

  final String id;
  final String status;
  final String? skipReason;
  final String? actorName;
  final List<WorkflowStep> steps;
  final String? error;
  final DateTime createdAt;

  String get statusLabel => switch (status) {
    'succeeded' => tr('Done'),
    'failed' => tr('Failed'),
    'skipped' => tr('Skipped'),
    'running' => tr('Running'),
    _ => trIn('workflows', 'Waiting'),
  };

  /// Why a run did not happen, or what went wrong, in words.
  String? get reasonLabel {
    if (status == 'skipped' && skipReason != null) {
      return workflowSkipReason(skipReason!);
    }
    if (status == 'failed') {
      final failed = steps.where((s) => s.status == 'failed');
      if (failed.isNotEmpty) {
        return tr("It couldn't finish this step.");
      }
      return tr("It couldn't run.");
    }
    return null;
  }
}

/// A run that did not happen, or an action that was left out, in words.
String workflowSkipReason(String code) => switch (code) {
  'expired' => tr('Too late: it was waiting for more than a day.'),
  'paused' => tr('The workflow was paused.'),
  'circle_suspended' => tr('The circle is suspended.'),
  'creator_lost_permission' => tr(
    'The person who made it can no longer manage this place, so it paused.',
  ),
  'daily_limit' => tr('The daily limit of runs was reached.'),
  'missed' => tr('The time passed while the app was not running it.'),
  _ => tr('Skipped.'),
};

/// What an action that was left out of a run was held back for.
String workflowStepDetail(String code) => switch (code) {
  'no_channel' => tr('The channel is gone.'),
  'automod' => tr('The circle rules held the message back.'),
  'no_member' => tr('The person is not a member any more.'),
  'left' => tr('The person left.'),
  'blocked' => tr('The person is blocked, or blocked the sender.'),
  'not_friends' => tr('Direct messages only go to friends.'),
  'has_role' => tr('The person already has the role.'),
  'role_not_allowed' => tr('The role cannot be given by a workflow.'),
  'message_gone' => tr('The message is gone.'),
  'chat_restricted' => tr('The chat is restricted.'),
  'disappearing' => tr('Disappearing messages are on.'),
  'form_gone' => tr('The form is gone.'),
  _ => tr('Skipped.'),
};

/// Which refusal the server gave.
enum WorkflowFailureKind {
  textInvalid,
  triggerInvalid,
  actionsInvalid,
  actionInvalid,
  channelInvalid,
  roleInvalid,
  formInvalid,
  formAnonymous,
  needsMember,
  needsMessage,
  limitReached,
  notAllowed,
  gone,
  finished,
  other,
}

class WorkflowException implements Exception {
  const WorkflowException(this.kind);

  factory WorkflowException.fromPostgrest(PostgrestException error) {
    final kind = switch (error.message) {
      'workflow_text_invalid' => WorkflowFailureKind.textInvalid,
      'workflow_trigger_invalid' => WorkflowFailureKind.triggerInvalid,
      'workflow_actions_invalid' => WorkflowFailureKind.actionsInvalid,
      'workflow_action_invalid' => WorkflowFailureKind.actionInvalid,
      'workflow_channel_invalid' => WorkflowFailureKind.channelInvalid,
      'workflow_role_invalid' => WorkflowFailureKind.roleInvalid,
      'workflow_form_invalid' => WorkflowFailureKind.formInvalid,
      'workflow_form_anonymous' => WorkflowFailureKind.formAnonymous,
      'workflow_needs_member' => WorkflowFailureKind.needsMember,
      'workflow_needs_message' => WorkflowFailureKind.needsMessage,
      'workflow_limit_reached' => WorkflowFailureKind.limitReached,
      'workflow_not_allowed' => WorkflowFailureKind.notAllowed,
      'workflow_not_found' => WorkflowFailureKind.gone,
      'workflow_finished' => WorkflowFailureKind.finished,
      _ when error.code == '42501' => WorkflowFailureKind.notAllowed,
      _ => WorkflowFailureKind.other,
    };
    return WorkflowException(kind);
  }

  final WorkflowFailureKind kind;

  /// What to tell the person.
  String get message => switch (kind) {
    WorkflowFailureKind.textInvalid => tr(
      'Check the name and the texts: none of them can be empty.',
    ),
    WorkflowFailureKind.triggerInvalid => tr('Check what starts the workflow.'),
    WorkflowFailureKind.actionsInvalid => tr(
      'A workflow needs between 1 and 5 actions.',
    ),
    WorkflowFailureKind.actionInvalid => tr('Check the actions.'),
    WorkflowFailureKind.channelInvalid => tr('Pick a channel for this step.'),
    WorkflowFailureKind.roleInvalid => tr('Pick a role that can be given.'),
    WorkflowFailureKind.formInvalid => tr('Pick a form from this place.'),
    WorkflowFailureKind.formAnonymous => tr(
      'Workflows cannot use anonymous forms.',
    ),
    WorkflowFailureKind.needsMember => tr(
      'This step needs a person, but a schedule has none.',
    ),
    WorkflowFailureKind.needsMessage => tr(
      'Only a reaction or a keyword has a message to make a task from.',
    ),
    WorkflowFailureKind.limitReached => tr(
      'This place has reached its limit of workflows.',
    ),
    WorkflowFailureKind.notAllowed => tr("You can't manage workflows here."),
    WorkflowFailureKind.gone => tr("This workflow isn't available any more."),
    WorkflowFailureKind.finished => tr(
      'Its last day has passed. Change the last day to turn it on.',
    ),
    WorkflowFailureKind.other => tr("That didn't work. Try again."),
  };

  @override
  String toString() => 'WorkflowException($kind)';
}
