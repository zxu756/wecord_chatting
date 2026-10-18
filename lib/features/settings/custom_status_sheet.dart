import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/message_reactions.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/features/profile/profile_social_repository.dart';
import 'package:wecord/features/profile/status_visibility_picker.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the sheet to set, change or clear the current user's status.
/// Resolves to true when the status was saved or cleared.
Future<bool?> showCustomStatusSheet(
  BuildContext context, {
  CustomStatus? current,
}) {
  return showWeCordSheet<bool>(
    context,
    title: tr('Set a status'),
    builder: (context, _) => CustomStatusSheet(current: current),
  );
}

class CustomStatusSheet extends ConsumerStatefulWidget {
  const CustomStatusSheet({this.current, super.key});

  final CustomStatus? current;

  @override
  ConsumerState<CustomStatusSheet> createState() => _CustomStatusSheetState();
}

class _CustomStatusSheetState extends ConsumerState<CustomStatusSheet> {
  late final _textController = TextEditingController(
    text: widget.current?.text,
  );
  late String? _emoji = widget.current?.emoji;
  var _duration = CustomStatusDuration.never;
  StatusVisibility? _visibility;
  var _saving = false;
  String? _errorText;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _isEmpty =>
      (_emoji?.trim().isEmpty ?? true) && _textController.text.trim().isEmpty;

  Future<void> _pickEmoji() async {
    final emoji = await showEmojiReactionPicker(
      context,
      title: tr('Status emoji'),
    );
    if (emoji != null && mounted) {
      setState(() => _emoji = emoji);
    }
  }

  Future<void> _save({required bool clear}) async {
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await ref
          .read(settingsRepositoryProvider)
          .setCustomStatus(
            emoji: clear ? null : _emoji,
            text: clear ? null : _textController.text,
            expiresAt: clear ? null : _duration.expiresAt(DateTime.now()),
          );
      // Who can see it, when that was changed.
      final visibility = _visibility;
      if (!clear && visibility != null) {
        await ref
            .read(profileSocialRepositoryProvider)
            .setStatusVisibility(visibility);
        ref.invalidate(myProfileExtrasProvider);
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorText = clear
              ? tr('Could not clear status. Try again.')
              : tr('Could not save status. Try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final emoji = _emoji;
    return SafeArea(
      top: false,
      child: Padding(
        // Lifts the sheet above the keyboard, so the content scrolls
        // within the space left instead of hiding behind it.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WeCordPressable(
                    key: const ValueKey('custom-status-emoji'),
                    tooltip: emoji == null
                        ? tr('Choose emoji')
                        : tr('Change emoji'),
                    semanticLabel: emoji == null
                        ? tr('Choose emoji')
                        : tr('Change emoji'),
                    shape: const CircleBorder(),
                    pressedScale: 0.92,
                    onPressed: _saving ? null : _pickEmoji,
                    builder: (context, states) => AnimatedContainer(
                      duration: WeCordMotion.quick,
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: states.contains(WidgetState.hovered)
                            ? c.raisedStrong
                            : c.raised,
                        shape: BoxShape.circle,
                      ),
                      child: emoji == null
                          ? Icon(
                              Icons.add_reaction_outlined,
                              size: 22,
                              color: c.ink,
                            )
                          : Text(emoji, style: const TextStyle(fontSize: 24)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: WeCordTextField(
                      fieldKey: const ValueKey('custom-status-text'),
                      controller: _textController,
                      enabled: !_saving,
                      maxLength: CustomStatus.maxTextLength,
                      hint: tr("What's happening?"),
                      suffix: _isEmpty
                          ? null
                          : IconButton(
                              tooltip: tr('Remove emoji and text'),
                              icon: Icon(
                                Icons.close_rounded,
                                size: 20,
                                color: c.muted,
                              ),
                              onPressed: () => setState(() {
                                _emoji = null;
                                _textController.clear();
                              }),
                            ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
                child: Text(
                  tr('Clear after'),
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
                  for (final duration in CustomStatusDuration.values)
                    WeCordChip(
                      key: ValueKey('custom-status-duration-${duration.name}'),
                      label: duration.label,
                      selected: duration == _duration,
                      onPressed: _saving
                          ? null
                          : () => setState(() => _duration = duration),
                    ),
                ],
              ),
              StatusVisibilityPicker(
                onChanged: (choice) => _visibility = choice,
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: TextStyle(fontSize: 13.5, color: c.dangerText),
                ),
              ],
              const SizedBox(height: 20),
              // Stacks the buttons when they do not fit on one line.
              OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.end,
                overflowSpacing: 8,
                children: [
                  if (widget.current != null)
                    WeCordButton(
                      key: const ValueKey('custom-status-clear'),
                      label: tr('Clear status'),
                      icon: Icons.backspace_outlined,
                      variant: WeCordButtonVariant.ghost,
                      onPressed: _saving ? null : () => _save(clear: true),
                    )
                  else
                    const SizedBox.shrink(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      WeCordButton(
                        label: tr('Cancel'),
                        variant: WeCordButtonVariant.secondary,
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      WeCordButton(
                        key: const ValueKey('custom-status-save'),
                        label: tr('Save'),
                        loading: _saving,
                        onPressed: _saving || _isEmpty
                            ? null
                            : () => _save(clear: false),
                      ),
                    ],
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
