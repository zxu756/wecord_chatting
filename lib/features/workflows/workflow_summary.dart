import 'package:flutter/material.dart';
import 'package:wecord/features/later/schedule_repeat.dart';
import 'package:wecord/features/workflows/workflow_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// What starts a workflow, in a line: "Every Monday 9:00", "When someone
/// reacts with 👍 in #general".
String workflowTriggerSummary(
  BuildContext context,
  WorkflowTrigger trigger, [
  WorkflowOptions options = const WorkflowOptions(),
]) {
  final channel = options.channelName(trigger.channelId);
  switch (trigger.kind) {
    case WorkflowTriggerKind.memberJoined:
      return tr('When someone joins');
    case WorkflowTriggerKind.reaction:
      final emoji = trigger.emoji ?? '';
      return channel == null
          ? tr('When someone reacts with {emoji}', {'emoji': emoji})
          : tr('When someone reacts with {emoji} in {channel}', {
              'emoji': emoji,
              'channel': channel,
            });
    case WorkflowTriggerKind.keyword:
      final words = trigger.words.join(', ');
      return channel == null
          ? tr('When a message has {words}', {'words': words})
          : tr('When a message has {words} in {channel}', {
              'words': words,
              'channel': channel,
            });
    case WorkflowTriggerKind.schedule:
      return describeRepeat(
        workflowRepeatOf(trigger),
        MaterialLocalizations.of(context),
        alwaysUse24HourFormat: true,
      );
    case WorkflowTriggerKind.formSubmitted:
      final title = options.formTitle(trigger.formId);
      return title == null
          ? tr('When someone submits a form')
          : tr('When someone submits {form}', {'form': title});
  }
}

/// The schedule of a trigger as the repeat rule the scheduled messages use.
ScheduleRepeat workflowRepeatOf(WorkflowTrigger trigger) {
  final parts = trigger.time.split(':');
  return ScheduleRepeat(
    kind: RepeatKind.fromWire(trigger.recurrence) ?? RepeatKind.daily,
    zone: trigger.zone,
    day: trigger.day,
    hour: int.tryParse(parts.first),
    minute: parts.length > 1 ? int.tryParse(parts[1]) : 0,
    until: trigger.until == null ? null : DateTime.tryParse(trigger.until!),
  );
}

/// One step, in a line: "Send a message to #welcome".
String workflowActionSummary(
  WorkflowAction action, [
  WorkflowOptions options = const WorkflowOptions(),
]) {
  final channel = options.channelName(action.channelId);
  switch (action.kind) {
    case WorkflowActionKind.sendMessage:
      return channel == null
          ? tr('Send a message')
          : tr('Send a message to {channel}', {'channel': channel});
    case WorkflowActionKind.sendDm:
      return tr('Send a direct message');
    case WorkflowActionKind.addRole:
      final role = options.roleName(action.roleId);
      return role == null
          ? tr('Give a role')
          : tr('Give the role {role}', {'role': role});
    case WorkflowActionKind.createTask:
      return tr('Create a task');
    case WorkflowActionKind.sendForm:
      final form = options.formTitle(action.formId);
      return form == null
          ? tr('Send a form')
          : tr('Send the form {form}', {'form': form});
  }
}
