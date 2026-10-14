import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_event.dart';

/// Opens the form that schedules an event in [detail]'s circle, or edits
/// [event]. Returns the saved event, or null when cancelled.
Future<CircleEvent?> showCircleEventEditor(
  BuildContext context, {
  required CircleDetail detail,
  CircleEvent? event,
  DateTime? now,
}) {
  return showModalBottomSheet<CircleEvent>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) =>
        CircleEventEditorSheet(detail: detail, event: event, now: now),
  );
}

/// Title, description, start and optional end, and where: a voice or text
/// channel the current user can see, or a place described in text.
class CircleEventEditorSheet extends ConsumerStatefulWidget {
  const CircleEventEditorSheet({
    required this.detail,
    this.event,
    this.now,
    super.key,
  });

  final CircleDetail detail;

  /// The event to edit; null to create one.
  final CircleEvent? event;

  /// The current time, for tests.
  final DateTime? now;

  @override
  ConsumerState<CircleEventEditorSheet> createState() =>
      _CircleEventEditorSheetState();
}

class _CircleEventEditorSheetState
    extends ConsumerState<CircleEventEditorSheet> {
  late final _titleController = TextEditingController(
    text: widget.event?.title ?? '',
  );
  late final _descriptionController = TextEditingController(
    text: widget.event?.description ?? '',
  );
  late final _locationController = TextEditingController(
    text: widget.event?.locationText ?? '',
  );
  late DateTime _startsAt;
  DateTime? _endsAt;
  late CircleEventLocationType _locationType;
  String? _channelId;
  var _saving = false;
  String? _errorText;

  DateTime get _now => widget.now ?? DateTime.now();

  /// Channels an event can take place in, by kind. The circle only lists
  /// channels the current user can see.
  List<CircleChannel> _channelsFor(CircleEventLocationType type) {
    final kind = switch (type) {
      CircleEventLocationType.voice => CircleChannelKind.voice,
      CircleEventLocationType.text => CircleChannelKind.text,
      CircleEventLocationType.external => null,
    };
    return [
      for (final channel in widget.detail.channels)
        if (channel.kind == kind) channel,
    ];
  }

  List<CircleEventLocationType> get _locationTypes => [
    for (final type in CircleEventLocationType.values)
      if (type == CircleEventLocationType.external ||
          _channelsFor(type).isNotEmpty ||
          type == widget.event?.locationType)
        type,
  ];

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    if (event != null) {
      _startsAt = event.startsAt.toLocal();
      _endsAt = event.endsAt?.toLocal();
      _locationType = event.locationType;
      _channelId = event.channelId;
    } else {
      // The next full hour at least half an hour away.
      final soon = _now.add(const Duration(minutes: 90));
      _startsAt = DateTime(soon.year, soon.month, soon.day, soon.hour);
      _locationType = _channelsFor(CircleEventLocationType.text).isNotEmpty
          ? CircleEventLocationType.text
          : CircleEventLocationType.external;
      _channelId = _channelsFor(_locationType).firstOrNull?.id;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _setLocationType(CircleEventLocationType type) {
    setState(() {
      _locationType = type;
      final channels = _channelsFor(type);
      if (!channels.any((channel) => channel.id == _channelId)) {
        _channelId = channels.firstOrNull?.id;
      }
    });
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateUtils.dateOnly(initial.isBefore(_now) ? initial : _now),
      lastDate: _now.add(const Duration(days: 365 * 2)),
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

  String? _validate() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      return tr('Give the event a title.');
    }
    final endsAt = _endsAt;
    if (endsAt != null && !endsAt.isAfter(_startsAt)) {
      return tr('The event must end after it starts.');
    }
    final effectiveEnd = endsAt ?? _startsAt.add(CircleEvent.defaultDuration);
    if (!effectiveEnd.isAfter(_now)) {
      return tr('Pick a time that has not passed yet.');
    }
    if (_locationType == CircleEventLocationType.external) {
      if (_locationController.text.trim().isEmpty) {
        return tr('Say where the event takes place.');
      }
    } else if (_channelId == null ||
        !_channelsFor(_locationType).any((c) => c.id == _channelId)) {
      return tr('Choose a channel.');
    }
    return null;
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    final repository = ref.read(circlesRepositoryProvider);
    final external = _locationType == CircleEventLocationType.external;
    try {
      final event = widget.event;
      final saved = event == null
          ? await repository.createEvent(
              circleId: widget.detail.circle.id,
              title: _titleController.text,
              description: _descriptionController.text,
              locationType: _locationType,
              channelId: external ? null : _channelId,
              locationText: external ? _locationController.text : null,
              startsAt: _startsAt,
              endsAt: _endsAt,
            )
          : await repository.updateEvent(
              eventId: event.id,
              title: _titleController.text,
              description: _descriptionController.text,
              locationType: _locationType,
              channelId: external ? null : _channelId,
              locationText: external ? _locationController.text : null,
              startsAt: _startsAt,
              endsAt: _endsAt,
            );
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
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    String dateTime(DateTime value) =>
        '${localizations.formatMediumDate(value)} · '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value), alwaysUse24HourFormat: use24Hour)}';
    final channels = _channelsFor(_locationType);
    final endsAt = _endsAt;
    final editing = widget.event != null;

    return SafeArea(
      child: Padding(
        // Lifts the sheet above the keyboard, so the form scrolls within
        // the space left instead of hiding behind it.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                editing ? tr('Edit event') : tr('New event'),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('event-title-field'),
                controller: _titleController,
                autofocus: !editing,
                enabled: !_saving,
                maxLength: CircleEvent.maxTitleLength,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: tr('Title'),
                ),
              ),
              const SizedBox(height: 8),
              Text(tr('Starts'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                key: const ValueKey('event-start-button'),
                onPressed: _saving ? null : _pickStart,
                icon: const Icon(Icons.event_outlined),
                label: Text(dateTime(_startsAt)),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                key: const ValueKey('event-end-switch'),
                contentPadding: EdgeInsets.zero,
                title: Text(tr('End time')),
                subtitle: endsAt == null
                    ? Text(tr('Without one, the event lasts 2 hours.'))
                    : null,
                value: endsAt != null,
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _endsAt = value
                            ? _startsAt.add(const Duration(hours: 1))
                            : null;
                      }),
              ),
              if (endsAt != null)
                OutlinedButton.icon(
                  key: const ValueKey('event-end-button'),
                  onPressed: _saving ? null : _pickEnd,
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text(dateTime(endsAt)),
                ),
              const SizedBox(height: 12),
              Text(tr('Where'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              SegmentedButton<CircleEventLocationType>(
                key: const ValueKey('event-location-type'),
                showSelectedIcon: false,
                segments: [
                  for (final type in _locationTypes)
                    ButtonSegment(
                      value: type,
                      icon: Icon(switch (type) {
                        CircleEventLocationType.voice =>
                          Icons.volume_up_outlined,
                        CircleEventLocationType.text => Icons.tag,
                        CircleEventLocationType.external =>
                          Icons.place_outlined,
                      }),
                      label: Text(switch (type) {
                        CircleEventLocationType.voice => tr('Voice'),
                        CircleEventLocationType.text => tr('Text'),
                        CircleEventLocationType.external => tr('Elsewhere'),
                      }),
                    ),
                ],
                selected: {_locationType},
                onSelectionChanged: _saving
                    ? null
                    : (selection) => _setLocationType(selection.single),
              ),
              const SizedBox(height: 10),
              if (_locationType == CircleEventLocationType.external)
                TextField(
                  key: const ValueKey('event-location-field'),
                  controller: _locationController,
                  enabled: !_saving,
                  maxLength: CircleEvent.maxLocationLength,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: tr('Location'),
                    hintText: tr('An address, a park, a link…'),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  // Keyed by kind, so switching kinds starts from that kind's choice.
                  key: ValueKey('event-channel-field-${_locationType.value}'),
                  initialValue: channels.any((c) => c.id == _channelId)
                      ? _channelId
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: tr('Channel'),
                  ),
                  items: [
                    for (final channel in channels)
                      DropdownMenuItem(
                        value: channel.id,
                        child: Text(
                          '# ${channel.name}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _channelId = value),
                ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('event-description-field'),
                controller: _descriptionController,
                enabled: !_saving,
                minLines: 2,
                maxLines: 6,
                maxLength: CircleEvent.maxDescriptionLength,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: tr('Description (optional)'),
                  alignLabelWithHint: true,
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 4),
                Text(
                  _errorText!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(tr('Cancel')),
                  ),
                  FilledButton(
                    key: const ValueKey('event-save'),
                    onPressed: _saving ? null : _save,
                    child: Text(editing ? tr('Save') : tr('Create')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
