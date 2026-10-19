// Voice channel touches (E6): the channel's status line, the connection
// quality on your own avatar, the "poor connection" hint and audio-only mode.
//
// The pieces here are placed by voice_channel_view.dart (header, tile and
// banner) and circle_channel_sidebar.dart (the status under a channel).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The longest status a voice channel can have; the server keeps to it too.
const maxVoiceChannelStatusLength = 60;

/// How long the connection stays poor before the hint appears, so a blip
/// does not bother anyone.
const poorConnectionHintDelay = Duration(seconds: 4);

/// Whether [quality] is one that makes video hard to receive.
bool voiceConnectionIsPoor(VoiceConnectionQuality quality) =>
    quality == VoiceConnectionQuality.poor ||
    quality == VoiceConnectionQuality.lost;

/// [text] on one line as the server will keep it: runs of white space are
/// one space, trimmed.
String tidyVoiceStatus(String text) =>
    text.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Opens the box to say what the voice channel [channelId] is about. [current]
/// is what it says now. Returns once it is closed.
Future<void> showVoiceStatusSheet(
  BuildContext context,
  WidgetRef ref, {
  required String circleId,
  required String channelId,
  String? current,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Channel status'),
    builder: (sheetContext, _) => VoiceStatusEditor(
      circleId: circleId,
      channelId: channelId,
      current: current,
    ),
  );
}

/// The content of the status sheet: a one-line field, Save and Clear.
class VoiceStatusEditor extends ConsumerStatefulWidget {
  const VoiceStatusEditor({
    required this.circleId,
    required this.channelId,
    this.current,
    super.key,
  });

  final String circleId;
  final String channelId;
  final String? current;

  @override
  ConsumerState<VoiceStatusEditor> createState() => _VoiceStatusEditorState();
}

class _VoiceStatusEditorState extends ConsumerState<VoiceStatusEditor> {
  late final _controller = TextEditingController(text: widget.current ?? '');
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save(String text) async {
    final status = tidyVoiceStatus(text);
    if (status.length > maxVoiceChannelStatusLength) {
      setState(() => _error = tr('A status is at most 60 characters.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(voiceRepositoryProvider)
          .setChannelStatus(channelId: widget.channelId, status: status);
      ref.invalidate(voiceChannelStatusesProvider(widget.circleId));
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on VoiceAccessDeniedException {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = tr(
            'Only people in the voice channel can change its status.',
          );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = tr('Could not change the status. Try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Tell everyone what this channel is about right now.'),
              style: TextStyle(fontSize: 13.5, color: c.muted),
            ),
            const SizedBox(height: 12),
            WeCordTextField(
              fieldKey: const ValueKey('voice-status-field'),
              controller: _controller,
              hint: tr('Playing ranked, watching a movie...'),
              autofocus: true,
              maxLength: maxVoiceChannelStatusLength,
              errorText: _error,
              textInputAction: TextInputAction.done,
              onSubmitted: _saving ? null : (text) => unawaited(_save(text)),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                WeCordButton(
                  key: const ValueKey('voice-status-clear'),
                  label: tr('Clear'),
                  variant: WeCordButtonVariant.secondary,
                  onPressed: _saving ? null : () => unawaited(_save('')),
                ),
                const Spacer(),
                WeCordButton(
                  key: const ValueKey('voice-status-save'),
                  label: tr('Save'),
                  onPressed: _saving
                      ? null
                      : () => unawaited(_save(_controller.text)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A channel's status in one muted line, under its name.
class VoiceChannelStatusText extends StatelessWidget {
  const VoiceChannelStatusText({
    required this.text,
    this.padding = const EdgeInsets.fromLTRB(44, 0, 12, 4),
    super.key,
  });

  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: padding,
      child: Text(
        text,
        key: const ValueKey('voice-channel-status'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: c.muted),
      ),
    );
  }
}

/// The colour of a connection [quality] for a small badge.
Color voiceQualityColor(BuildContext context, VoiceConnectionQuality quality) {
  final c = context.tokens.colors;
  return switch (quality) {
    VoiceConnectionQuality.excellent ||
    VoiceConnectionQuality.good => c.successText,
    VoiceConnectionQuality.poor => c.warningText,
    VoiceConnectionQuality.lost => c.dangerText,
    VoiceConnectionQuality.unknown => c.muted,
  };
}

/// Your connection quality as a small round badge on your own tile.
class VoiceQualityBadge extends StatelessWidget {
  const VoiceQualityBadge({required this.quality, super.key});

  final VoiceConnectionQuality quality;

  @override
  Widget build(BuildContext context) {
    if (quality == VoiceConnectionQuality.unknown) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final label = voiceQualityLabel(quality);
    return Semantics(
      label: label,
      child: Tooltip(
        message: label,
        child: Container(
          key: ValueKey('voice-quality-badge-${quality.name}'),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: c.paper.withValues(alpha: 0.66),
            shape: BoxShape.circle,
          ),
          child: ExcludeSemantics(
            child: Icon(
              voiceQualityIcon(quality),
              size: 16,
              color: voiceQualityColor(context, quality),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Your connection is poor" with a button for audio only, shown under the
/// room's header once the connection has been poor for a few seconds while
/// someone's video is on. It goes away when the connection recovers, audio
/// only is on, or it was dismissed (until the connection recovered once).
class VoiceQualityBanner extends ConsumerStatefulWidget {
  const VoiceQualityBanner({this.delay = poorConnectionHintDelay, super.key});

  final Duration delay;

  @override
  ConsumerState<VoiceQualityBanner> createState() => _VoiceQualityBannerState();
}

class _VoiceQualityBannerState extends ConsumerState<VoiceQualityBanner> {
  Timer? _timer;
  var _poorLongEnough = false;
  var _dismissed = false;

  @override
  void initState() {
    super.initState();
    // Already poor when the room opens.
    final quality = ref.read(voiceSessionProvider)?.quality;
    if (quality != null && voiceConnectionIsPoor(quality)) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer ??= Timer(widget.delay, () {
      if (mounted) {
        setState(() => _poorLongEnough = true);
      }
    });
  }

  void _qualityChanged(VoiceConnectionQuality? quality) {
    if (quality != null && voiceConnectionIsPoor(quality)) {
      _startTimer();
      return;
    }
    _timer?.cancel();
    _timer = null;
    if (_poorLongEnough || _dismissed) {
      setState(() {
        _poorLongEnough = false;
        _dismissed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      voiceSessionProvider.select((session) => session?.quality),
      (previous, next) => _qualityChanged(next),
    );
    final session = ref.watch(voiceSessionProvider);
    if (session == null ||
        !session.isConnected ||
        session.audioOnly ||
        !_poorLongEnough ||
        _dismissed ||
        !session.participants.any(
          (participant) =>
              !participant.isLocal &&
              (participant.cameraEnabled || participant.screenShareEnabled),
        )) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final lost = session.quality == VoiceConnectionQuality.lost;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Container(
          key: const ValueKey('voice-quality-banner'),
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(
            color: c.warningSoft,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
          ),
          child: Row(
            children: [
              Icon(
                voiceQualityIcon(session.quality),
                size: 18,
                color: c.warningText,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  lost
                      ? tr(
                          'Your connection dropped. Switch to audio only to keep the call going?',
                        )
                      : tr(
                          'Your connection is poor. Switch to audio only to keep the call smooth?',
                        ),
                  style: TextStyle(fontSize: 13, color: c.warningText),
                ),
              ),
              const SizedBox(width: 6),
              WeCordButton(
                key: const ValueKey('voice-quality-audio-only'),
                label: tr('Audio only'),
                variant: WeCordButtonVariant.secondary,
                onPressed: () => unawaited(
                  ref
                      .read(voiceSessionProvider.notifier)
                      .setAudioOnly(true)
                      .catchError((Object _) {}),
                ),
              ),
              WeCordIconButton(
                key: const ValueKey('voice-quality-dismiss'),
                tooltip: tr('Dismiss'),
                icon: Icons.close_rounded,
                size: 32,
                iconSize: 18,
                variant: WeCordButtonVariant.ghost,
                onPressed: () => setState(() => _dismissed = true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
