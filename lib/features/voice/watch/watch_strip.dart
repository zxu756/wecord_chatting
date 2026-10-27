import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/message_markdown_text.dart'
    show linkLauncherProvider;
import 'package:wecord/features/safety/link_risk.dart' show displayHost;
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_ui.dart';
import 'package:wecord/features/voice/watch/watch_controller.dart';
import 'package:wecord/features/voice/watch/watch_protocol.dart';
import 'package:wecord/features/voice/watch/watch_sheets.dart';
import 'package:wecord/features/voice/watch/watch_sources.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The button in a call that starts watching together, or shows what is on
/// (E4). Nothing shows on a stage, where only speakers can reach the room.
class WatchTogetherButton extends ConsumerWidget {
  const WatchTogetherButton({this.size, super.key});

  /// The button's size; the header size by default.
  final double? size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(voiceSessionProvider);
    final watch = ref.watch(watchTogetherProvider);
    if (session == null ||
        !session.isConnected ||
        session.stageListener ||
        session.stage) {
      return const SizedBox.shrink();
    }
    final active = watch.active;
    return VoiceControlButton(
      key: const ValueKey('voice-watch-button'),
      icon: active ? Icons.live_tv_rounded : Icons.live_tv_outlined,
      tooltip: active ? tr('Watching together') : tr('Watch together'),
      on: active,
      size: size ?? (usesTouchInput(context) ? 42 : 38),
      onPressed: () => unawaited(
        active ? showWatchManageSheet(context) : showWatchStartSheet(context),
      ),
    );
  }
}

/// Wraps [child] in a column under the watching bar. Used where a call's
/// picture area is shared with the people.
class WatchTogetherStrip extends StatelessWidget {
  const WatchTogetherStrip({
    this.compact = false,
    this.idleEntry = false,
    super.key,
  });

  /// A smaller picture, for the call card in a chat.
  final bool compact;

  /// While nothing is on, show a small "Watch together" button here. For
  /// narrow headers that have no room for the round button.
  final bool idleEntry;

  @override
  Widget build(BuildContext context) {
    // On a wide window the bar stays a comfortable size.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: _StripBody(compact: compact, idleEntry: idleEntry),
      ),
    );
  }
}

class _StripBody extends ConsumerWidget {
  const _StripBody({required this.compact, required this.idleEntry});

  final bool compact;
  final bool idleEntry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(voiceSessionProvider);
    final watch = ref.watch(watchTogetherProvider);
    if (session == null || !session.isConnected) {
      return const SizedBox.shrink();
    }
    if (!watch.active) {
      if (!idleEntry || session.stageListener || session.stage) {
        return const SizedBox.shrink();
      }
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
          child: WeCordButton(
            key: const ValueKey('voice-watch-entry'),
            label: tr('Watch together'),
            icon: Icons.live_tv_outlined,
            variant: WeCordButtonVariant.ghost,
            size: WeCordButtonSize.small,
            onPressed: () => unawaited(showWatchStartSheet(context)),
          ),
        ),
      );
    }
    final c = context.tokens.colors;
    final controller = ref.read(watchTogetherProvider.notifier);
    final me = _localId(session);
    final host = watch.hostId == me ? null : watch.nameOf(watch.hostId ?? '');
    final source = watch.source;
    final audio = source?.isAudio ?? false;

    if (watch.dismissed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Container(
          key: const ValueKey('watch-strip-dismissed'),
          padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
            border: Border.all(color: c.lineSoft),
          ),
          child: Row(
            children: [
              Icon(Icons.live_tv_outlined, size: 18, color: c.ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('The call is watching together, but not on your screen'),
                  style: TextStyle(fontSize: 13.5, color: c.ink),
                ),
              ),
              WeCordButton(
                key: const ValueKey('watch-strip-resume'),
                label: tr('Watch again'),
                variant: WeCordButtonVariant.ghost,
                onPressed: controller.rejoin,
              ),
            ],
          ),
        ),
      );
    }

    final subtitle = watch.hostId == me
        ? tr('You started this')
        : tr('Started by {name}', {'name': host ?? tr('Someone')});
    final reduce = WeCordMotion.reduceMotion(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: AnimatedSize(
        duration: reduce ? Duration.zero : WeCordMotion.quick,
        alignment: Alignment.topCenter,
        child: Container(
          key: const ValueKey('watch-strip'),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
            border: Border.all(color: c.lineSoft),
          ),
          // Never taller than most of the screen: at large text sizes the
          // bar scrolls instead of pushing the people out of the room.
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 2, 0),
                    child: Row(
                      children: [
                        Icon(
                          audio
                              ? Icons.headphones_rounded
                              : Icons.live_tv_rounded,
                          size: 18,
                          color: c.ink,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  watch.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: c.ink,
                                  ),
                                ),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: c.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        VoiceControlButton(
                          key: const ValueKey('watch-strip-menu'),
                          icon: Icons.more_horiz_rounded,
                          tooltip: tr('Watching options'),
                          size: usesTouchInput(context) ? 40 : 34,
                          packed: true,
                          onPressed: () =>
                              unawaited(showWatchManageSheet(context)),
                        ),
                      ],
                    ),
                  ),
                  _Media(compact: compact),
                  const _Cue(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? _localId(VoiceSession session) {
  for (final participant in session.participants) {
    if (participant.isLocal) {
      return participant.userId;
    }
  }
  return null;
}

/// The picture or the reason there is none, and the controls.
class _Media extends ConsumerWidget {
  const _Media({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watch = ref.watch(watchTogetherProvider);
    final controller = ref.read(watchTogetherProvider.notifier);
    final c = context.tokens.colors;
    final source = watch.source;
    final screen = MediaQuery.sizeOf(context);
    // Large text leaves less room: the picture gives way first.
    final large = MediaQuery.textScalerOf(context).scale(10) > 14;
    final maxPicture = screen.height * (compact ? 0.22 : (large ? 0.18 : 0.3));

    Widget note(String text, {List<Widget> actions = const []}) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: actions),
            ],
          ],
        ),
      );
    }

    Widget openInBrowser() {
      final embed = source is WatchEmbedSource ? source : null;
      return WeCordButton(
        key: const ValueKey('watch-open-browser'),
        label: tr('Open in browser'),
        icon: Icons.open_in_new_rounded,
        variant: WeCordButtonVariant.secondary,
        onPressed: embed == null
            ? null
            : () => unawaited(
                ref.read(linkLauncherProvider)(context, embed.pageUri),
              ),
      );
    }

    switch (watch.load) {
      case WatchLoad.idle:
        return const SizedBox.shrink();
      case WatchLoad.loading:
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: c.ink),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr('Loading…'),
                  style: TextStyle(fontSize: 13.5, color: c.muted),
                ),
              ),
            ],
          ),
        );
      case WatchLoad.needsConsent:
        final link = source is WatchLinkSource ? source : null;
        return note(
          watch.consent == WatchConsent.dataSaving
              ? tr('Audio only is on, so the video is not loaded.')
              : tr(
                  'This is a link to a file on {site}. Loading it shows that site your connection.',
                  {'site': link == null ? '' : displayHost(link.url)},
                ),
          actions: [
            WeCordButton(
              key: const ValueKey('watch-accept'),
              label: watch.consent == WatchConsent.dataSaving
                  ? tr('Load it anyway')
                  : tr('Load it'),
              variant: WeCordButtonVariant.primary,
              onPressed: controller.acceptConsent,
            ),
          ],
        );
      case WatchLoad.failed:
        return note(
          source is WatchEmbedSource
              ? tr('The video could not be loaded on this device.')
              : tr(
                  'This device could not load it. You may not have access to the file, or it is a format your device can not play.',
                ),
          actions: [
            WeCordButton(
              key: const ValueKey('watch-retry'),
              label: tr('Try again'),
              variant: WeCordButtonVariant.secondary,
              onPressed: controller.retry,
            ),
            if (source is WatchEmbedSource) openInBrowser(),
          ],
        );
      case WatchLoad.external:
        final embed = source is WatchEmbedSource ? source : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            note(
              tr(
                'This app can not play {site} inside the call. Open it in your browser and press play when you are told to.',
                {'site': embed?.label ?? ''},
              ),
              actions: [openInBrowser()],
            ),
            if (controller.canControl) const _CueButtons(),
          ],
        );
      case WatchLoad.ready:
        final player = controller.player;
        if (player == null) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (player.hasSurface)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxPicture),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(WeCordRadii.md),
                        child: player.buildSurface(context),
                      ),
                    ),
                  ),
                ),
              ),
            if (player.remoteControl)
              const _Controls()
            else ...[
              note(
                controller.canControl
                    ? tr(
                        'Everyone presses play themselves. Use the buttons to tell the call when.',
                      )
                    : tr(
                        'Everyone presses play themselves. Wait for the host to say when.',
                      ),
              ),
              if (controller.canControl) const _CueButtons(),
            ],
          ],
        );
    }
  }
}

/// "Everyone play now" and "pause" hints, for players the app can not drive.
class _CueButtons extends ConsumerWidget {
  const _CueButtons();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(watchTogetherProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          WeCordButton(
            key: const ValueKey('watch-cue-play'),
            label: tr('Tell everyone to play'),
            icon: Icons.play_arrow_rounded,
            variant: WeCordButtonVariant.secondary,
            onPressed: () => unawaited(controller.sendCue(WatchCueAction.play)),
          ),
          WeCordButton(
            key: const ValueKey('watch-cue-pause'),
            label: tr('Tell everyone to pause'),
            icon: Icons.pause_rounded,
            variant: WeCordButtonVariant.secondary,
            onPressed: () =>
                unawaited(controller.sendCue(WatchCueAction.pause)),
          ),
        ],
      ),
    );
  }
}

/// What someone told the call to do with a player the app can not drive.
class _Cue extends ConsumerWidget {
  const _Cue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cue = ref.watch(watchTogetherProvider.select((s) => s.cue));
    final names = ref.watch(watchTogetherProvider.select((s) => s.names));
    if (cue == null) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final name = names[cue.fromId] ?? tr('Someone');
    final text = cue.action == WatchCueAction.play
        ? tr('{name}: press play now', {'name': name})
        : tr('{name}: pause for a moment', {'name': name});
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('watch-cue'),
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(WeCordRadii.md),
        ),
        child: Row(
          children: [
            Icon(
              cue.action == WatchCueAction.play
                  ? Icons.play_circle_outline_rounded
                  : Icons.pause_circle_outline_rounded,
              size: 20,
              color: c.ink,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "1:05" or "1:02:03".
String formatWatchTime(Duration time) {
  final total = time.inSeconds < 0 ? 0 : time.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  }
  return '$minutes:$ss';
}

/// Play / pause, the position and the time, kept fresh twice a second.
class _Controls extends ConsumerStatefulWidget {
  const _Controls();

  @override
  ConsumerState<_Controls> createState() => _ControlsState();
}

class _ControlsState extends ConsumerState<_Controls> {
  Timer? _timer;
  double? _scrub;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _scrub == null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final watch = ref.watch(watchTogetherProvider);
    final controller = ref.read(watchTogetherProvider.notifier);
    final session = ref.watch(voiceSessionProvider);
    final c = context.tokens.colors;
    final player = controller.player;
    if (player == null || session == null) {
      return const SizedBox.shrink();
    }
    final canControl = controller.canControl;
    final length = controller.duration;
    final position = controller.position;
    final fraction = length == null || length.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0);
    final me = _localId(session);
    final host = watch.hostId == me ? null : watch.nameOf(watch.hostId ?? '');
    final behind = watch.playing && !player.isPlaying && !player.isBuffering;
    final String status;
    if (canControl && watch.controlOpen) {
      status = tr('Everyone can control');
    } else if (canControl) {
      status = tr('You control the playback');
    } else {
      status = tr('Following {name}', {'name': host ?? tr('the host')});
    }
    final touch = usesTouchInput(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              VoiceControlButton(
                key: const ValueKey('watch-play'),
                icon: watch.playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                tooltip: watch.playing ? tr('Pause') : tr('Play'),
                size: touch ? 42 : 38,
                packed: true,
                onPressed: canControl
                    ? () => unawaited(controller.togglePlay())
                    : null,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: c.ink,
                    inactiveTrackColor: c.lineSoft,
                    thumbColor: c.ink,
                    disabledActiveTrackColor: c.muted,
                    disabledInactiveTrackColor: c.lineSoft,
                    disabledThumbColor: c.muted,
                    overlayShape: SliderComponentShape.noOverlay,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                      disabledThumbRadius: 5,
                    ),
                  ),
                  child: Slider(
                    key: const ValueKey('watch-slider'),
                    value: (_scrub ?? fraction).clamp(0.0, 1.0),
                    semanticFormatterCallback: (value) =>
                        tr('Playback position {time}', {
                          'time': formatWatchTime(
                            length == null ? position : length * value,
                          ),
                        }),
                    onChanged: canControl && length != null
                        ? (value) => setState(() => _scrub = value)
                        : null,
                    onChangeEnd: canControl && length != null
                        ? (value) {
                            setState(() => _scrub = null);
                            unawaited(controller.seekTo(length * value));
                          }
                        : null,
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48),
                child: Text(
                  length == null
                      ? formatWatchTime(position)
                      : '${formatWatchTime(position)} / ${formatWatchTime(length)}',
                  key: const ValueKey('watch-time'),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 12,
                    color: c.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          if (behind)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: WeCordButton(
                key: const ValueKey('watch-catch-up'),
                label: tr('Catch up'),
                icon: Icons.fast_forward_rounded,
                variant: WeCordButtonVariant.ghost,
                onPressed: () => unawaited(controller.resync()),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    status,
                    key: const ValueKey('watch-status'),
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
                ),
                VoiceControlButton(
                  key: const ValueKey('watch-mute'),
                  icon: watch.muted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  tooltip: watch.muted
                      ? tr('Unmute for me')
                      : tr('Mute for me'),
                  on: watch.muted,
                  size: touch ? 40 : 34,
                  packed: true,
                  onPressed: () => controller.setMuted(!watch.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
