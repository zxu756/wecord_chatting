import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/events/chat_events_repository.dart';
import 'package:wecord/features/chats/time_tokens/time_token.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/chat_event.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the event form for a new event of [conversationId], or to edit
/// [event]. Returns the saved event, or null when cancelled.
Future<ChatEvent?> showChatEventEditor(
  BuildContext context, {
  required String conversationId,
  ChatEvent? event,
}) {
  return showWeCordSheet<ChatEvent>(
    context,
    title: event == null ? tr('New event') : tr('Edit event'),
    detents: const [0.92],
    builder: (context, scrollController) => ChatEventEditor(
      conversationId: conversationId,
      event: event,
      scrollController: scrollController,
    ),
  );
}

/// Which reminders an event asks for.
enum _Reminder {
  none([]),
  quarterHour([15]),
  hour([60]),
  both([15, 60]);

  const _Reminder(this.leads);

  final List<int> leads;

  static _Reminder of(List<int> leads) {
    final set = leads.toSet();
    if (set.containsAll(const [15, 60])) return both;
    if (set.contains(15)) return quarterHour;
    if (set.contains(60)) return hour;
    return none;
  }
}

class ChatEventEditor extends ConsumerStatefulWidget {
  const ChatEventEditor({
    required this.conversationId,
    this.event,
    this.scrollController,
    this.clock,
    super.key,
  });

  final String conversationId;
  final ChatEvent? event;
  final ScrollController? scrollController;

  /// The current time; the real one by default.
  final DateTime Function()? clock;

  @override
  ConsumerState<ChatEventEditor> createState() => _ChatEventEditorState();
}

class _ChatEventEditorState extends ConsumerState<ChatEventEditor> {
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _linkController = TextEditingController();
  final _descriptionController = TextEditingController();
  late DateTime _startsAt;
  DateTime? _endsAt;
  var _reminder = _Reminder.quarterHour;
  var _pin = false;
  var _saving = false;
  String? _errorText;

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    if (event != null) {
      _titleController.text = event.title;
      _locationController.text = event.locationText ?? '';
      _linkController.text = event.linkUrl ?? '';
      _descriptionController.text = event.description ?? '';
      _startsAt = event.startsAt.toLocal();
      _endsAt = event.endsAt?.toLocal();
      _reminder = _Reminder.of(event.reminderLeads);
    } else {
      // The next full hour at least half an hour away.
      final soon = _now.add(const Duration(minutes: 90));
      _startsAt = DateTime(soon.year, soon.month, soon.day, soon.hour);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _linkController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final now = _now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateUtils.dateOnly(initial.isBefore(now) ? initial : now),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) {
      return null;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) {
      return null;
    }
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickStart() async {
    final picked = await _pickDateTime(_startsAt);
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      final end = _endsAt;
      // Keep the event's length when its start moves.
      if (end != null) {
        _endsAt = picked.add(end.difference(_startsAt));
      }
      _startsAt = picked;
    });
  }

  Future<void> _pickEnd() async {
    final picked = await _pickDateTime(
      _endsAt ?? _startsAt.add(const Duration(hours: 1)),
    );
    if (picked != null && mounted) {
      setState(() => _endsAt = picked);
    }
  }

  /// A link as the server wants it: with a scheme.
  String? get _link {
    final text = _linkController.text.trim();
    if (text.isEmpty) {
      return null;
    }
    return RegExp(r'^https?://', caseSensitive: false).hasMatch(text)
        ? text
        : 'https://$text';
  }

  String? _validate() {
    if (_titleController.text.trim().isEmpty) {
      return tr('Give the event a title.');
    }
    final endsAt = _endsAt;
    if (endsAt != null && !endsAt.isAfter(_startsAt)) {
      return tr('The event must end after it starts.');
    }
    if (widget.event == null && _startsAt.isBefore(_now)) {
      return tr('Pick a time that has not passed yet.');
    }
    final link = _link;
    if (link != null) {
      final uri = Uri.tryParse(link);
      if (uri == null || uri.host.isEmpty || link.contains(RegExp(r'\s'))) {
        return tr('That link does not look right.');
      }
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _errorText = problem);
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    final draft = ChatEventDraft(
      title: _titleController.text,
      startsAt: _startsAt,
      endsAt: _endsAt,
      description: _descriptionController.text,
      location: _locationController.text,
      link: _link,
      reminderLeads: _reminder.leads,
      pin: _pin,
    );
    final repository = ref.read(chatEventsRepositoryProvider);
    try {
      final event = widget.event;
      final saved = event == null
          ? await repository.createEvent(widget.conversationId, draft)
          : await repository.updateEvent(event.id, draft);
      if (mounted) {
        Navigator.of(context).pop(saved);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorText = widget.event == null
              ? tr('Could not create the event. Try again.')
              : tr('Could not save the event. Try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final editing = widget.event != null;
    final now = _now;
    String dateTime(DateTime value) =>
        '${formatDateShort(value, now: now)} · ${formatClock(value, use24Hour: use24Hour)}';

    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 +
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        WeCordTextField(
          fieldKey: const ValueKey('chat-event-title-field'),
          controller: _titleController,
          label: tr('Title'),
          hint: tr('Climbing night'),
          autofocus: !editing,
          enabled: !_saving,
          maxLength: ChatEvent.maxTitleLength,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        SettingsGroup(
          separatorIndent: 58,
          color: c.well,
          children: [
            SettingsRow(
              key: const ValueKey('chat-event-start'),
              icon: Icons.schedule_rounded,
              title: tr('Starts'),
              value: dateTime(_startsAt),
              onTap: _saving ? null : _pickStart,
            ),
            if (_endsAt == null)
              SettingsRow(
                key: const ValueKey('chat-event-add-end'),
                icon: Icons.add_rounded,
                title: tr('Add end time'),
                onTap: _saving ? null : _pickEnd,
              )
            else
              SettingsRow(
                key: const ValueKey('chat-event-end'),
                icon: Icons.flag_outlined,
                title: tr('Ends'),
                value: dateTime(_endsAt!),
                onTap: _saving ? null : _pickEnd,
                trailing: WeCordIconButton(
                  tooltip: tr('Remove end time'),
                  icon: Icons.close_rounded,
                  size: 32,
                  iconSize: 16,
                  variant: WeCordButtonVariant.ghost,
                  onPressed: _saving
                      ? null
                      : () => setState(() => _endsAt = null),
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Text(
            tr('Everyone sees the time in their own time zone ({zone}).', {
              'zone': utcOffsetLabel(_startsAt),
            }),
            style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.4),
          ),
        ),
        const SizedBox(height: 14),
        WeCordTextField(
          fieldKey: const ValueKey('chat-event-location-field'),
          controller: _locationController,
          label: tr('Where'),
          hint: tr('A place (optional)'),
          prefixIcon: Icons.place_outlined,
          enabled: !_saving,
          maxLength: ChatEvent.maxLocationLength,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 10),
        WeCordTextField(
          fieldKey: const ValueKey('chat-event-link-field'),
          controller: _linkController,
          label: tr('Link'),
          hint: tr('Meeting or map link (optional)'),
          prefixIcon: Icons.link_rounded,
          keyboardType: TextInputType.url,
          enabled: !_saving,
          maxLength: ChatEvent.maxLinkLength,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 10),
        WeCordTextField(
          fieldKey: const ValueKey('chat-event-description-field'),
          controller: _descriptionController,
          label: tr('Description'),
          hint: tr('What should people know? (optional)'),
          enabled: !_saving,
          minLines: 3,
          maxLines: 6,
          maxLength: ChatEvent.maxDescriptionLength,
        ),
        const SizedBox(height: 14),
        Semantics(
          header: true,
          child: Text(
            tr('Remind people who are going or maybe'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.muted,
            ),
          ),
        ),
        const SizedBox(height: 8),
        WeCordSegmented<_Reminder>(
          expand: true,
          semanticLabel: tr('Reminders'),
          selected: _reminder,
          onChanged: _saving
              ? null
              : (value) => setState(() => _reminder = value),
          segments: [
            WeCordSegment(value: _Reminder.none, label: tr('None')),
            WeCordSegment(value: _Reminder.quarterHour, label: tr('15 min')),
            WeCordSegment(value: _Reminder.hour, label: tr('1 hour')),
            WeCordSegment(value: _Reminder.both, label: tr('Both')),
          ],
        ),
        if (!editing) ...[
          const SizedBox(height: 10),
          SettingsGroup(
            separatorIndent: 14,
            color: c.well,
            children: [
              SettingsRow.toggle(
                key: const ValueKey('chat-event-pin'),
                icon: Icons.push_pin_outlined,
                title: tr('Pin to chat header'),
                subtitle: tr('Keeps the event in view at the top of the chat.'),
                value: _pin,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _pin = value),
              ),
            ],
          ),
        ],
        if (_errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _errorText!,
                key: const ValueKey('chat-event-error'),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: c.dangerText,
                ),
              ),
            ),
          ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: WeCordButton(
                label: tr('Cancel'),
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.large,
                expand: true,
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: WeCordButton(
                key: const ValueKey('chat-event-save'),
                label: editing ? tr('Save') : tr('Create'),
                variant: WeCordButtonVariant.accent,
                size: WeCordButtonSize.large,
                expand: true,
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
