import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_event.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the form that schedules an event in [detail]'s circle, or edits
/// [event]. Returns the saved event, or null when cancelled.
Future<CircleEvent?> showCircleEventEditor(
  BuildContext context, {
  required CircleDetail detail,
  CircleEvent? event,
  DateTime? now,
}) {
  return showCircleFormSheet<CircleEvent>(
    context,
    builder: (context) =>
        CircleEventEditorSheet(detail: detail, event: event, now: now),
  );
}

/// Shows a long form as a sheet on phones (lifted above the keyboard by
/// the form itself) and as a centred rounded panel on wide screens.
Future<T?> showCircleFormSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  if (circleWideLayout(context)) {
    final tokens = context.tokens;
    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: tokens.colors.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.xxl),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: builder(context),
        ),
      ),
    );
  }
  return showWeCordSheet<T>(context, builder: (context, _) => builder(context));
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

  Future<void> _pickChannel(List<CircleChannel> channels) async {
    final picked = await showCircleActionMenu<String>(
      context,
      title: tr('Channel'),
      items: [
        for (final channel in channels)
          CircleMenuItem(
            value: channel.id,
            icon: channel.isVoice ? Icons.volume_up_outlined : Icons.tag,
            label: channel.name,
          ),
      ],
    );
    if (picked != null && mounted) {
      setState(() => _channelId = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    String dateTime(DateTime value) =>
        '${localizations.formatMediumDate(value)} · '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value), alwaysUse24HourFormat: use24Hour)}';
    final channels = _channelsFor(_locationType);
    final endsAt = _endsAt;
    final editing = widget.event != null;
    final selectedChannel = channels
        .where((channel) => channel.id == _channelId)
        .firstOrNull;

    return CircleFormBody(
      title: editing ? tr('Edit event') : tr('New event'),
      errorText: _errorText,
      actions: [
        WeCordButton(
          label: tr('Cancel'),
          variant: WeCordButtonVariant.secondary,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        WeCordButton(
          key: const ValueKey('event-save'),
          label: editing ? tr('Save') : tr('Create'),
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
      children: [
        WeCordTextField(
          fieldKey: const ValueKey('event-title-field'),
          controller: _titleController,
          autofocus: !editing,
          enabled: !_saving,
          maxLength: CircleEvent.maxTitleLength,
          textInputAction: TextInputAction.next,
          label: tr('Title'),
        ),
        const SizedBox(height: 4),
        CircleFormLabel(tr('Starts')),
        CirclePickerField(
          key: const ValueKey('event-start-button'),
          icon: Icons.event_outlined,
          label: dateTime(_startsAt),
          onPressed: _saving ? null : _pickStart,
        ),
        const SizedBox(height: 10),
        SettingsGroup(
          color: context.tokens.colors.well,
          children: [
            SettingsRow.toggle(
              key: const ValueKey('event-end-switch'),
              icon: Icons.timelapse_rounded,
              title: tr('End time'),
              subtitle: endsAt == null
                  ? tr('Without one, the event lasts 2 hours.')
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
          ],
        ),
        if (endsAt != null) ...[
          const SizedBox(height: 10),
          CirclePickerField(
            key: const ValueKey('event-end-button'),
            icon: Icons.event_available_outlined,
            label: dateTime(endsAt),
            onPressed: _saving ? null : _pickEnd,
          ),
        ],
        const SizedBox(height: 6),
        CircleFormLabel(tr('Where')),
        WeCordSegmented<CircleEventLocationType>(
          key: const ValueKey('event-location-type'),
          expand: true,
          height: 40,
          semanticLabel: tr('Where'),
          segments: [
            for (final type in _locationTypes)
              WeCordSegment(
                value: type,
                icon: switch (type) {
                  CircleEventLocationType.voice => Icons.volume_up_outlined,
                  CircleEventLocationType.text => Icons.tag,
                  CircleEventLocationType.external => Icons.place_outlined,
                },
                label: switch (type) {
                  CircleEventLocationType.voice => tr('Voice'),
                  CircleEventLocationType.text => tr('Text'),
                  CircleEventLocationType.external => tr('Elsewhere'),
                },
              ),
          ],
          selected: _locationType,
          onChanged: _saving ? null : _setLocationType,
        ),
        const SizedBox(height: 12),
        if (_locationType == CircleEventLocationType.external)
          WeCordTextField(
            fieldKey: const ValueKey('event-location-field'),
            controller: _locationController,
            enabled: !_saving,
            maxLength: CircleEvent.maxLocationLength,
            label: tr('Location'),
            hint: tr('An address, a park, a link…'),
          )
        else ...[
          CircleFormLabel(tr('Channel')),
          CirclePickerField(
            // Keyed by kind, so switching kinds starts from that kind's
            // choice.
            key: ValueKey('event-channel-field-${_locationType.value}'),
            icon: _locationType == CircleEventLocationType.voice
                ? Icons.volume_up_outlined
                : Icons.tag,
            label: selectedChannel?.name ?? tr('Choose a channel.'),
            trailingIcon: Icons.unfold_more_rounded,
            onPressed: _saving || channels.isEmpty
                ? null
                : () => _pickChannel(channels),
          ),
          const SizedBox(height: 12),
        ],
        WeCordTextField(
          fieldKey: const ValueKey('event-description-field'),
          controller: _descriptionController,
          enabled: !_saving,
          minLines: 2,
          maxLines: 6,
          maxLength: CircleEvent.maxDescriptionLength,
          keyboardType: TextInputType.multiline,
          label: tr('Description (optional)'),
        ),
      ],
    );
  }
}

/// A form in a sheet or dialog: title, [children], an error line and
/// [actions] (main action last). Scrolls above the keyboard.
class CircleFormBody extends StatelessWidget {
  const CircleFormBody({
    required this.title,
    required this.children,
    required this.actions,
    this.errorText,
    super.key,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final wide = circleWideLayout(context);
    final errorText = this.errorText;
    return SafeArea(
      top: false,
      child: Padding(
        // Lifts the form above the keyboard, so it scrolls within the
        // space left instead of hiding behind it.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, wide ? 22 : 6, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: c.ink,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ...children,
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  errorText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.dangerText,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final (index, action) in actions.indexed) ...[
                    if (index > 0) const SizedBox(width: 10),
                    if (wide) action else Expanded(child: action),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small muted label above a form control.
class CircleFormLabel extends StatelessWidget {
  const CircleFormLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6, top: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: context.tokens.colors.muted,
        ),
      ),
    );
  }
}

/// A field-like button that opens a picker (date, channel).
class CirclePickerField extends StatelessWidget {
  const CirclePickerField({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.trailingIcon = Icons.chevron_right_rounded,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final IconData trailingIcon;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    const radius = BorderRadius.all(Radius.circular(WeCordRadii.lg));
    return WeCordPressable(
      onPressed: onPressed,
      pressedScale: 0.99,
      semanticLabel: label,
      shape: const RoundedRectangleBorder(borderRadius: radius),
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedOpacity(
          duration: WeCordMotion.quick,
          opacity: onPressed == null ? 0.5 : 1,
          child: AnimatedContainer(
            duration: WeCordMotion.quick,
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: hovered
                  ? Color.alphaBlend(c.ink.withValues(alpha: 0.04), c.raised)
                  : c.raised,
              borderRadius: radius,
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: c.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ),
                Icon(trailingIcon, size: 20, color: c.faint),
              ],
            ),
          ),
        );
      },
    );
  }
}
