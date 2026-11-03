import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wecord/features/browser/in_app_browser_screen.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_ui.dart';
import 'package:wecord/features/voice/watch_together/watch_media.dart';
import 'package:wecord/features/voice/watch_together/watch_protocol.dart';
import 'package:wecord/features/voice/watch_together/watch_together_controller.dart';
import 'package:wecord/features/voice/watch_together/watch_together_sheets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens a web page link for someone who can not watch it in step: in
/// WeCord's own browser where there is one, in the system browser
/// otherwise. Replaced in tests.
typedef WatchLinkOpener = Future<void> Function(BuildContext context, Uri uri);

final watchLinkOpenerProvider = Provider<WatchLinkOpener>((ref) {
  return (context, uri) async {
    if (inAppBrowserSupported) {
      await openInAppBrowser(context, uri);
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      // Nothing handles the link; the page stays as it is.
    }
  };
});

/// The most of the screen's height the picture takes.
const _maxPictureShare = 0.34;

/// The watching panel of a call (E4): the picture and its controls, a
/// notice when watching ended, and a slim bar for people who stopped or hid
/// it. Shows nothing while nothing is on. Sits in the voice room under the
/// header and in the call card of a chat; it reads the dark voice room's
/// colors.
///
/// The host plays, pauses and seeks; everyone else follows, and can mute,
/// hide the picture or stop watching on their own side without changing
/// anything for the others.
class WatchTogetherPanel extends StatelessWidget {
  const WatchTogetherPanel({this.pictureShare = _maxPictureShare, super.key});

  /// The most of the screen's height the picture takes.
  final double pictureShare;

  @override
  Widget build(BuildContext context) {
    // On a wide window the panel stays a comfortable size.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: _PanelBody(
          maxPicture: MediaQuery.sizeOf(context).height * pictureShare,
        ),
      ),
    );
  }
}

class _PanelBody extends ConsumerWidget {
  const _PanelBody({required this.maxPicture});

  final double maxPicture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(voiceSessionProvider);
    final watch = ref.watch(watchTogetherProvider);
    if (session == null || !session.isConnected) {
      return const SizedBox.shrink();
    }
    final notice = watch.notice == WatchNotice.none
        ? null
        : _NoticeBar(watch: watch);
    if (!watch.active) {
      return notice ?? const SizedBox.shrink();
    }
    final Widget content;
    if (watch.dismissed) {
      content = _SlimBar(
        key: const ValueKey('watch-bar-dismissed'),
        icon: _iconOf(watch.link),
        text: tr('{name} is watching together', {
          'name': watch.hostName ?? tr('Someone'),
        }),
        action: tr('Join'),
        onAction: ref.read(watchTogetherProvider.notifier).rejoin,
      );
    } else if (watch.hidden) {
      content = _SlimBar(
        key: const ValueKey('watch-bar-hidden'),
        icon: _iconOf(watch.link),
        text: tr('Picture hidden'),
        action: tr('Show'),
        onAction: () =>
            ref.read(watchTogetherProvider.notifier).setHidden(false),
      );
    } else {
      content = _WatchCard(watch: watch, maxPicture: maxPicture);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [?notice, content]);
  }
}

IconData _iconOf(WatchLink? link) {
  return switch (link?.kind) {
    WatchLinkKind.audio => Icons.headphones_rounded,
    WatchLinkKind.webPage => Icons.language_rounded,
    _ => Icons.smart_display_rounded,
  };
}

// ------------------------------------------------------------- the notice --

class _NoticeBar extends ConsumerWidget {
  const _NoticeBar({required this.watch});

  final WatchTogetherState watch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final name = watch.noticeName ?? tr('The host');
    final text = watch.notice == WatchNotice.hostEnded
        ? tr('{name} ended watching together', {'name': name})
        : tr('{name} left, so watching together ended', {'name': name});
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Container(
          key: const ValueKey('watch-notice'),
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
            border: Border.all(color: c.lineSoft),
          ),
          child: Row(
            children: [
              Icon(Icons.stop_circle_outlined, size: 18, color: c.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ),
              WeCordPressable(
                onPressed: ref.read(watchTogetherProvider.notifier).clearNotice,
                tooltip: tr('Close'),
                semanticLabel: tr('Close'),
                shape: const CircleBorder(),
                builder: (context, states) =>
                    Icon(Icons.close_rounded, size: 18, color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ the slim bar --

class _SlimBar extends StatelessWidget {
  const _SlimBar({
    required this.icon,
    required this.text,
    required this.action,
    required this.onAction,
    super.key,
  });

  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
          border: Border.all(color: c.lineSoft),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: c.ink),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
            ),
            WeCordButton(
              label: action,
              variant: WeCordButtonVariant.secondary,
              size: WeCordButtonSize.small,
              onPressed: onAction,
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- the card --

class _WatchCard extends ConsumerWidget {
  const _WatchCard({required this.watch, required this.maxPicture});

  final WatchTogetherState watch;
  final double maxPicture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final controller = ref.read(watchTogetherProvider.notifier);
    final link = watch.link!;
    final player = controller.player;
    final kindTitle = switch (link.kind) {
      WatchLinkKind.audio => tr('Listening together'),
      WatchLinkKind.webPage => tr('Sharing a web page'),
      _ => tr('Watching together'),
    };
    final subtitle = watch.isHost
        ? tr('You are the host')
        : tr('Hosted by {name}', {'name': watch.hostName ?? tr('Someone')});
    final touch = usesTouchInput(context);
    final size = touch ? 42.0 : 36.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Semantics(
        container: true,
        label: kindTitle,
        child: Container(
          key: const ValueKey('watch-card'),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
            border: Border.all(color: c.lineSoft),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 6, 2),
                child: Row(
                  children: [
                    Icon(_iconOf(link), size: 18, color: c.ink),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            watch.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: c.ink,
                            ),
                          ),
                          Text(
                            '$kindTitle · $subtitle',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: c.muted),
                          ),
                        ],
                      ),
                    ),
                    VoiceControlButton(
                      key: const ValueKey('watch-more'),
                      icon: Icons.more_horiz_rounded,
                      tooltip: tr('More'),
                      size: size,
                      onPressed: () =>
                          unawaited(showWatchTogetherSheet(context, ref)),
                    ),
                  ],
                ),
              ),
              if (link.synced && player != null)
                _SyncedBody(
                  key: ValueKey('watch-body-${watch.playerEpoch}'),
                  watch: watch,
                  player: player,
                  size: size,
                  maxPicture: maxPicture,
                )
              else if (!link.synced)
                _WebPageBody(watch: watch),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebPageBody extends ConsumerWidget {
  const _WebPageBody({required this.watch});

  final WatchTogetherState watch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final link = watch.link!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: c.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(
                    'This kind of link can only be played by each person on their own, so the progress cannot be kept in step.',
                  ),
                  key: const ValueKey('watch-web-note'),
                  style: TextStyle(fontSize: 13, height: 1.35, color: c.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  link.uri.host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ),
              WeCordButton(
                key: const ValueKey('watch-open-link'),
                label: inAppBrowserSupported
                    ? tr('Open here')
                    : tr('Open in browser'),
                icon: Icons.open_in_new_rounded,
                size: WeCordButtonSize.small,
                onPressed: () => unawaited(
                  ref.read(watchLinkOpenerProvider)(context, link.uri),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncedBody extends ConsumerWidget {
  const _SyncedBody({
    required this.watch,
    required this.player,
    required this.size,
    required this.maxPicture,
    super.key,
  });

  final WatchTogetherState watch;
  final WatchMediaPlayer player;
  final double size;
  final double maxPicture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(watchTogetherProvider.notifier);
    final link = watch.link!;
    return ValueListenableBuilder<WatchMediaValue>(
      valueListenable: player,
      builder: (context, value, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Stage(
              watch: watch,
              player: player,
              value: value,
              maxHeight: maxPicture,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
              child: Row(
                children: [
                  if (watch.isHost)
                    VoiceControlButton(
                      key: const ValueKey('watch-play'),
                      icon: (watch.anchor?.playing ?? false)
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      tooltip: (watch.anchor?.playing ?? false)
                          ? tr('Pause')
                          : tr('Play'),
                      size: size,
                      onPressed: value.ready
                          ? () => unawaited(
                              (watch.anchor?.playing ?? false)
                                  ? controller.pause()
                                  : controller.play(),
                            )
                          : null,
                    ),
                  Expanded(
                    child: _Progress(
                      watch: watch,
                      value: value,
                      onSeek: controller.seek,
                    ),
                  ),
                  VoiceControlButton(
                    key: const ValueKey('watch-mute'),
                    icon: watch.muted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    tooltip: watch.muted
                        ? tr('Unmute on my side')
                        : tr('Mute on my side'),
                    on: watch.muted,
                    size: size,
                    onPressed: () =>
                        unawaited(controller.setMuted(!watch.muted)),
                  ),
                  if (!link.isAudio)
                    VoiceControlButton(
                      key: const ValueKey('watch-hide'),
                      icon: Icons.visibility_off_outlined,
                      tooltip: tr('Hide picture'),
                      size: size,
                      onPressed: () => controller.setHidden(true),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The picture (or the sound's tile) with what covers it while loading,
/// when it failed, and when a tap is needed to start.
class _Stage extends ConsumerWidget {
  const _Stage({
    required this.watch,
    required this.player,
    required this.value,
    required this.maxHeight,
  });

  final WatchTogetherState watch;
  final WatchMediaPlayer player;
  final WatchMediaValue value;
  final double maxHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final link = watch.link!;
    final controller = ref.read(watchTogetherProvider.notifier);
    final isAudio = link.isAudio;

    Widget? cover;
    if (value.failed) {
      cover = _FailedCover(
        link: link,
        failure: value.failure ?? WatchMediaFailure.cannotPlay,
      );
    } else if (!value.ready) {
      cover = Center(
        key: const ValueKey('watch-loading'),
        child: Semantics(
          label: tr('Loading…'),
          child: SizedBox.square(
            dimension: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: c.ink),
          ),
        ),
      );
    } else if (watch.needsTap) {
      cover = Semantics(
        button: true,
        label: tr('Tap to join in'),
        child: GestureDetector(
          key: const ValueKey('watch-tap-to-play'),
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(controller.tapToPlay()),
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.45),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.play_circle_fill_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr('Tap to join in'),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else if (value.buffering && !isAudio) {
      cover = Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              key: const ValueKey('watch-buffering'),
              strokeWidth: 2,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      );
    }

    if (isAudio) {
      return SizedBox(
        height: 84,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: c.raised),
            Center(
              child: Icon(
                value.playing
                    ? Icons.graphic_eq_rounded
                    : Icons.music_note_rounded,
                size: 40,
                color: c.muted,
              ),
            ),
            ?cover,
          ],
        ),
      );
    }

    final ratio = value.ready
        ? value.aspectRatio.clamp(0.5, 2.4).toDouble()
        : 16 / 9;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: AspectRatio(
          aspectRatio: ratio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              if (value.ready) player.buildView(context),
              ?cover,
            ],
          ),
        ),
      ),
    );
  }
}

class _FailedCover extends ConsumerWidget {
  const _FailedCover({required this.link, required this.failure});

  final WatchLink link;
  final WatchMediaFailure failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final text = failure == WatchMediaFailure.timeout
        ? tr('The link took too long to load.')
        : tr('This link cannot be played on this device.');
    final hlsOnWeb = kIsWeb && link.kind == WatchLinkKind.hls;
    return ColoredBox(
      key: const ValueKey('watch-failed'),
      color: c.raised,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 24, color: c.muted),
              const SizedBox(height: 6),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              if (hlsOnWeb) ...[
                const SizedBox(height: 4),
                Text(
                  tr(
                    'Some browsers cannot play HLS streams. Safari can; otherwise try an MP4 link.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: c.muted,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              WeCordButton(
                key: const ValueKey('watch-open-link'),
                label: tr('Open in browser'),
                icon: Icons.open_in_new_rounded,
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.small,
                onPressed: () => unawaited(
                  ref.read(watchLinkOpenerProvider)(context, link.uri),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The host's seek bar; a plain progress line for everyone else.
class _Progress extends StatefulWidget {
  const _Progress({
    required this.watch,
    required this.value,
    required this.onSeek,
  });

  final WatchTogetherState watch;
  final WatchMediaValue value;
  final Future<void> Function(Duration position) onSeek;

  @override
  State<_Progress> createState() => _ProgressState();
}

class _ProgressState extends State<_Progress> {
  double? _dragging;

  static String _clock(Duration d) {
    final total = d.inSeconds < 0 ? 0 : d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final value = widget.value;
    final total = value.duration.inMilliseconds;
    final live = value.position.inMilliseconds;
    final shown = (_dragging ?? live.toDouble())
        .clamp(0.0, total > 0 ? total.toDouble() : 1.0)
        .toDouble();
    final label =
        '${_clock(Duration(milliseconds: shown.round()))}'
        ' / ${_clock(value.duration)}';
    final enabled = widget.watch.isHost && value.ready && total > 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        // With very large text the time would push the row past the card:
        // it may take at most half the row, shrinking past that.
        final maxTimeWidth = constraints.maxWidth / 2;
        return Row(
          children: [
            Expanded(
              child: widget.watch.isHost
                  ? SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                        activeTrackColor: c.ink,
                        inactiveTrackColor: c.track,
                        thumbColor: c.ink,
                      ),
                      child: SizedBox(
                        height: 48,
                        child: Slider(
                          key: const ValueKey('watch-seek'),
                          value: shown,
                          max: total > 0 ? total.toDouble() : 1.0,
                          semanticFormatterCallback: (_) => label,
                          onChanged: enabled
                              ? (v) => setState(() => _dragging = v)
                              : null,
                          onChangeEnd: enabled
                              ? (v) {
                                  setState(() => _dragging = null);
                                  unawaited(
                                    widget.onSeek(
                                      Duration(milliseconds: v.round()),
                                    ),
                                  );
                                }
                              : null,
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          key: const ValueKey('watch-progress'),
                          value: total > 0 ? shown / total : 0.0,
                          minHeight: 3,
                          color: c.ink,
                          backgroundColor: c.track,
                          semanticsLabel: label,
                        ),
                      ),
                    ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxTimeWidth),
              child: ExcludeSemantics(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    key: const ValueKey('watch-time'),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: c.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
        );
      },
    );
  }
}
