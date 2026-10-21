import 'package:wecord/shared/l10n/l10n.dart';

/// Limits the server enforces (see `202610230210_onboarding_guide_rpcs.sql`).
abstract final class CircleGuideLimits {
  static const prompts = 5;
  static const options = 12;
  static const rolesPerOption = 5;
  static const channelsPerOption = 5;
  static const tasks = 10;
  static const promptTitle = 100;
  static const optionLabel = 60;
  static const taskTitle = 80;
}

/// A role an answer gives, as the member sees it.
class GuideRoleRef {
  const GuideRoleRef({required this.id, required this.name, this.color});

  factory GuideRoleRef.fromJson(Map<String, dynamic> json) => GuideRoleRef(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    color: (json['color'] as num?)?.toInt(),
  );

  final String id;
  final String name;

  /// 0xRRGGBB, or null.
  final int? color;
}

/// A channel an answer points at.
class GuideChannelRef {
  const GuideChannelRef({required this.id, required this.name});

  factory GuideChannelRef.fromJson(Map<String, dynamic> json) =>
      GuideChannelRef(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
      );

  final String id;
  final String name;
}

/// One answer to pick from.
class GuideOption {
  const GuideOption({
    required this.id,
    required this.label,
    this.emoji,
    this.selected = false,
    this.roles = const [],
    this.channels = const [],
  });

  factory GuideOption.fromJson(Map<String, dynamic> json) => GuideOption(
    id: json['id'] as String,
    label: json['label'] as String? ?? '',
    emoji: json['emoji'] as String?,
    selected: json['selected'] == true,
    roles: _list(json['roles'], GuideRoleRef.fromJson),
    channels: _list(json['channels'], GuideChannelRef.fromJson),
  );

  final String id;
  final String label;
  final String? emoji;
  final bool selected;
  final List<GuideRoleRef> roles;
  final List<GuideChannelRef> channels;
}

/// A question.
class GuidePrompt {
  const GuidePrompt({
    required this.id,
    required this.title,
    required this.options,
    this.required = false,
    this.singleSelect = false,
  });

  factory GuidePrompt.fromJson(Map<String, dynamic> json) => GuidePrompt(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    required: json['required'] == true,
    singleSelect: json['single_select'] == true,
    options: _list(json['options'], GuideOption.fromJson),
  );

  final String id;
  final String title;
  final bool required;
  final bool singleSelect;
  final List<GuideOption> options;
}

/// What a newcomer task asks for. Reading the rules, a page and the avatar
/// work themselves out from the member's own state; a visit is ticked off by
/// the app.
enum GuideTaskAction {
  readRules('read_rules'),
  visitChannel('visit_channel'),
  sendMessage('send_message'),
  setAvatar('set_avatar'),

  /// A page of the circle's knowledge base (required reading).
  readPage('read_page');

  const GuideTaskAction(this.value);

  final String value;

  static GuideTaskAction fromJson(Object? value) {
    for (final action in values) {
      if (action.value == value) {
        return action;
      }
    }
    return GuideTaskAction.sendMessage;
  }

  /// The kind, as the editor lists it.
  String get label => switch (this) {
    readRules => tr('Read the rules'),
    visitChannel => tr('Visit a channel'),
    sendMessage => tr('Send a message'),
    setAvatar => tr('Set a profile picture'),
    readPage => tr('Read a page'),
  };

  /// A title to start from.
  String get suggestedTitle => switch (this) {
    readRules => tr('Read the rules'),
    visitChannel => tr('Have a look around'),
    sendMessage => tr('Introduce yourself'),
    setAvatar => tr('Add a profile picture'),
    readPage => tr('Read the welcome page'),
  };

  bool get needsPage => this == readPage;
  bool get needsChannel => this == visitChannel;
  bool get takesChannel => this == visitChannel || this == sendMessage;
}

/// One task of the newcomer list, with the member's progress.
class GuideTask {
  const GuideTask({
    required this.id,
    required this.title,
    required this.action,
    this.channelId,
    this.channelName,
    this.pageId,
    this.pageTitle,
    this.done = false,
  });

  factory GuideTask.fromJson(Map<String, dynamic> json) => GuideTask(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    action: GuideTaskAction.fromJson(json['action']),
    channelId: json['channel_id'] as String?,
    channelName: json['channel_name'] as String?,
    pageId: json['page_id'] as String?,
    pageTitle: json['page_title'] as String?,
    done: json['done'] == true,
  );

  final String id;
  final String title;
  final GuideTaskAction action;
  final String? channelId;
  final String? channelName;

  /// The knowledge base page of a "read a page" task, and its title.
  final String? pageId;
  final String? pageTitle;
  final bool done;
}

/// A circle's guide for the current member (`get_circle_guide`).
class CircleGuide {
  const CircleGuide({
    this.enabled = false,
    this.prompts = const [],
    this.tasks = const [],
    this.answered = false,
    this.dismissed = false,
    this.needsAnswers = false,
    this.newMember = false,
  });

  factory CircleGuide.fromJson(Map<String, dynamic> json) => CircleGuide(
    enabled: json['enabled'] == true,
    prompts: _list(json['prompts'], GuidePrompt.fromJson),
    tasks: _list(json['tasks'], GuideTask.fromJson),
    answered: json['answered'] == true,
    dismissed: json['dismissed'] == true,
    needsAnswers: json['needs_answers'] == true,
    newMember: json['new_member'] == true,
  );

  final bool enabled;
  final List<GuidePrompt> prompts;
  final List<GuideTask> tasks;

  /// The member has answered the questions.
  final bool answered;

  /// The member put the guide card away.
  final bool dismissed;

  /// Ask the member now: the circle has questions they have not answered
  /// and they joined after it began asking.
  final bool needsAnswers;

  /// The member joined after the circle had a guide: it is shown to them on
  /// the circle without being asked for. Older members open it from the
  /// circle menu.
  final bool newMember;

  /// The card at the top of the circle shows: the guide is theirs, they have
  /// not put it away, and something is still open.
  bool get showsCard => enabled && newMember && !dismissed && hasOpenWork;

  int get doneCount => tasks.where((task) => task.done).length;
  int get taskCount => tasks.length;
  bool get hasPrompts => prompts.isNotEmpty;
  bool get hasTasks => tasks.isNotEmpty;

  /// Every task is done (a guide with no tasks is not complete).
  bool get tasksComplete => tasks.isNotEmpty && doneCount == tasks.length;

  /// Something is still open for the member: a task, or questions they have
  /// not answered.
  bool get hasOpenWork =>
      (hasPrompts && !answered) || (hasTasks && !tasksComplete);

  /// A required question the member has not picked anything for.
  bool get missingRequired => prompts.any(
    (prompt) => prompt.required && !prompt.options.any((o) => o.selected),
  );
}

/// One option in the editor, with the roles and channels it hands out.
class GuideOptionDraftData {
  const GuideOptionDraftData({
    this.id,
    this.label = '',
    this.emoji,
    this.roleIds = const [],
    this.channelIds = const [],
  });

  factory GuideOptionDraftData.fromJson(Map<String, dynamic> json) =>
      GuideOptionDraftData(
        id: json['id'] as String?,
        label: json['label'] as String? ?? '',
        emoji: json['emoji'] as String?,
        roleIds: _strings(json['role_ids']),
        channelIds: _strings(json['channel_ids']),
      );

  final String? id;
  final String label;
  final String? emoji;
  final List<String> roleIds;
  final List<String> channelIds;

  Map<String, dynamic> toJson() => {
    'id': ?id,
    'label': label.trim(),
    'emoji': ?(emoji == null || emoji!.trim().isEmpty ? null : emoji!.trim()),
    'role_ids': roleIds,
    'channel_ids': channelIds,
  };
}

/// One question in the editor.
class GuidePromptDraftData {
  const GuidePromptDraftData({
    this.id,
    this.title = '',
    this.required = false,
    this.singleSelect = false,
    this.options = const [],
  });

  factory GuidePromptDraftData.fromJson(Map<String, dynamic> json) =>
      GuidePromptDraftData(
        id: json['id'] as String?,
        title: json['title'] as String? ?? '',
        required: json['required'] == true,
        singleSelect: json['single_select'] == true,
        options: _list(json['options'], GuideOptionDraftData.fromJson),
      );

  final String? id;
  final String title;
  final bool required;
  final bool singleSelect;
  final List<GuideOptionDraftData> options;

  Map<String, dynamic> toJson() => {
    'id': ?id,
    'title': title.trim(),
    'required': required,
    'single_select': singleSelect,
    'options': [for (final option in options) option.toJson()],
  };
}

/// One task in the editor.
class GuideTaskDraftData {
  const GuideTaskDraftData({
    this.id,
    this.title = '',
    this.action = GuideTaskAction.sendMessage,
    this.channelId,
    this.pageId,
    this.pageTitle,
  });

  factory GuideTaskDraftData.fromJson(Map<String, dynamic> json) =>
      GuideTaskDraftData(
        id: json['id'] as String?,
        title: json['title'] as String? ?? '',
        action: GuideTaskAction.fromJson(json['action']),
        channelId: json['channel_id'] as String?,
        pageId: json['page_id'] as String?,
        pageTitle: json['page_title'] as String?,
      );

  final String? id;
  final String title;
  final GuideTaskAction action;
  final String? channelId;

  /// The page of a "read a page" task, and its title (for the editor).
  final String? pageId;
  final String? pageTitle;

  Map<String, dynamic> toJson() => {
    'id': ?id,
    'title': title.trim(),
    'action': action.value,
    if (action.takesChannel) 'channel_id': channelId,
    if (action.needsPage) 'page_id': pageId,
  };
}

/// The editor's view of a circle's guide (`get_circle_guide_config`).
class CircleGuideConfig {
  const CircleGuideConfig({
    this.prompts = const [],
    this.tasks = const [],
    this.greetingChannelId,
    this.greetingStickerId,
    this.assignableRoleIds = const {},
  });

  factory CircleGuideConfig.fromJson(Map<String, dynamic> json) =>
      CircleGuideConfig(
        prompts: _list(json['prompts'], GuidePromptDraftData.fromJson),
        tasks: _list(json['tasks'], GuideTaskDraftData.fromJson),
        greetingChannelId: json['greeting_channel_id'] as String?,
        greetingStickerId: json['greeting_sticker_id'] as String?,
        assignableRoleIds: _strings(json['assignable_role_ids']).toSet(),
      );

  final List<GuidePromptDraftData> prompts;
  final List<GuideTaskDraftData> tasks;
  final String? greetingChannelId;
  final String? greetingStickerId;

  /// Roles an answer may give today: the editor offers only these.
  final Set<String> assignableRoleIds;
}

/// What a new-member card in a channel carries in its attachment
/// (`kind: newcomer`, see `202610230220_onboarding_greeting.sql`).
class NewcomerNotice {
  const NewcomerNotice({
    required this.userId,
    required this.userLabel,
    this.stickerId,
  });

  static NewcomerNotice? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null || json['kind'] != 'newcomer') {
      return null;
    }
    final userId = json['user_id'];
    if (userId is! String) {
      return null;
    }
    return NewcomerNotice(
      userId: userId,
      userLabel: json['user_label'] as String? ?? '',
      stickerId: json['sticker_id'] as String?,
    );
  }

  final String userId;
  final String userLabel;

  /// The circle's sticker for saying hello, if it chose one.
  final String? stickerId;
}

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) parse) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is Map) parse(Map<String, dynamic>.from(item)),
  ];
}

List<String> _strings(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is String) item,
  ];
}
