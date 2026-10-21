import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/quick_replies/quick_replies_models.dart';
import 'package:wecord/features/chats/quick_replies/quick_replies_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// How long the away auto-reply stays on once it is switched on.
enum AwayDuration {
  untilOff('Until I turn it off'),
  oneHour('1 hour'),
  fourHours('4 hours'),
  oneDay('1 day'),
  oneWeek('1 week');

  const AwayDuration(this._label);

  final String _label;

  String get label => tr(_label);

  /// When it ends if switched on at [now]; null: until switched off.
  DateTime? endsAt(DateTime now) => switch (this) {
    AwayDuration.untilOff => null,
    AwayDuration.oneHour => now.add(const Duration(hours: 1)),
    AwayDuration.fourHours => now.add(const Duration(hours: 4)),
    AwayDuration.oneDay => now.add(const Duration(days: 1)),
    AwayDuration.oneWeek => now.add(const Duration(days: 7)),
  };
}

/// A few words on the auto-reply for a settings row: "Off", "On", "On until
/// Oct 28, 6:00 PM".
String awayReplySummary(BuildContext context, AwayReply away, DateTime now) {
  final quiet = away.duringQuietHours;
  if (!away.isOn(now)) {
    return quiet ? tr('Off, except in quiet hours') : tr('Off');
  }
  final end = away.until;
  final base = end == null
      ? tr('On')
      : tr('On until {time}', {'time': _formatMoment(context, end)});
  return quiet ? '$base · ${tr('also in quiet hours')}' : base;
}

String _formatMoment(BuildContext context, DateTime moment) {
  final local = moment.toLocal();
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatMediumDate(local)}, '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

/// Opens the sheet to set the away auto-reply. Resolves to true when it was
/// saved.
Future<bool?> showAwayReplySheet(BuildContext context) {
  return showWeCordSheet<bool>(
    context,
    title: tr('Auto-reply when away'),
    builder: (context, _) => const AwayReplySheet(),
  );
}

class AwayReplySheet extends ConsumerStatefulWidget {
  const AwayReplySheet({super.key});

  @override
  ConsumerState<AwayReplySheet> createState() => _AwayReplySheetState();
}

class _AwayReplySheetState extends ConsumerState<AwayReplySheet> {
  final _messageController = TextEditingController();
  var _loaded = false;
  var _enabled = false;
  var _duringQuietHours = false;

  /// The end time already stored and still ahead, offered as "keep".
  DateTime? _currentEnd;
  var _keepCurrent = false;
  var _duration = AwayDuration.untilOff;
  var _saving = false;
  String? _errorText;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _load(AwayReply away) {
    _loaded = true;
    final now = DateTime.now();
    _messageController.text = away.message;
    _enabled = away.isOn(now);
    _duringQuietHours = away.duringQuietHours;
    final end = away.until;
    if (_enabled && end != null) {
      _currentEnd = end;
      _keepCurrent = true;
    }
  }

  Future<void> _save({required bool enabled}) async {
    final message = _messageController.text.trim();
    if ((enabled || _duringQuietHours) && message.isEmpty) {
      setState(() => _errorText = tr('Write what the reply says first.'));
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      final until = !enabled
          ? null
          : _keepCurrent
          ? _currentEnd
          : _duration.endsAt(DateTime.now());
      await ref
          .read(quickRepliesRepositoryProvider)
          .saveAway(
            AwayReply(
              enabled: enabled,
              message: message,
              until: until,
              duringQuietHours: _duringQuietHours,
            ),
          );
      ref.invalidate(awayReplyProvider);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorText = tr('Could not save the auto-reply. Try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final away = ref.watch(awayReplyProvider);
    if (!_loaded) {
      final value = away.value;
      if (value != null) {
        _load(value);
      } else if (away.hasError) {
        _loaded = true;
      } else {
        return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        );
      }
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(
                  'Friends who write to you in a private chat get this message, once a day each. Groups and bots are not answered, and it is marked as an auto-reply.',
                ),
                style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
              ),
              const SizedBox(height: 12),
              WeCordTextField(
                fieldKey: const ValueKey('away-reply-message'),
                controller: _messageController,
                enabled: !_saving,
                label: tr('Message'),
                hint: tr("I'm away right now and will reply when I'm back."),
                maxLength: maxAwayMessageLength,
                minLines: 2,
                maxLines: 5,
                onChanged: (_) => setState(() => _errorText = null),
              ),
              const SizedBox(height: 8),
              SettingsGroup(
                separatorIndent: 14,
                children: [
                  SettingsRow.toggle(
                    key: const ValueKey('away-reply-enabled'),
                    title: tr('Reply automatically'),
                    value: _enabled,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _enabled = value),
                  ),
                  SettingsRow.toggle(
                    key: const ValueKey('away-reply-quiet-hours'),
                    title: tr('Also in quiet hours'),
                    subtitle: tr(
                      'Replies while your quiet hours are on, even with the switch above off.',
                    ),
                    value: _duringQuietHours,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _duringQuietHours = value),
                  ),
                ],
              ),
              if (_enabled) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
                  child: Text(
                    tr('Switch off after'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.subtle,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (_currentEnd != null)
                      WeCordChip(
                        key: const ValueKey('away-reply-duration-keep'),
                        label: tr('Keep {time}', {
                          'time': _formatMoment(context, _currentEnd!),
                        }),
                        selected: _keepCurrent,
                        onPressed: _saving
                            ? null
                            : () => setState(() => _keepCurrent = true),
                      ),
                    for (final duration in AwayDuration.values)
                      WeCordChip(
                        key: ValueKey('away-reply-duration-${duration.name}'),
                        label: duration.label,
                        selected: !_keepCurrent && duration == _duration,
                        onPressed: _saving
                            ? null
                            : () => setState(() {
                                _keepCurrent = false;
                                _duration = duration;
                              }),
                      ),
                  ],
                ),
              ],
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: TextStyle(fontSize: 13.5, color: c.dangerText),
                ),
              ],
              const SizedBox(height: 20),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                overflowSpacing: 8,
                spacing: 8,
                children: [
                  WeCordButton(
                    label: tr('Cancel'),
                    variant: WeCordButtonVariant.secondary,
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                  WeCordButton(
                    key: const ValueKey('away-reply-save'),
                    label: tr('Save'),
                    loading: _saving,
                    onPressed: _saving
                        ? null
                        : () => unawaited(_save(enabled: _enabled)),
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
