import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice/mini_player/active_speaker.dart';
import 'package:wecord/features/voice/mini_player/call_surfaces.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_ui.dart';
import 'package:wecord/features/voice/voice_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Floats the call's mini player over [child] (the app) while the user is
/// in a call and nothing on screen shows it: they went to another chat,
/// circle or setting. This is the in-app picture in picture on every
/// platform; neither livekit_client nor flutter_webrtc offers the system's
/// (see docs/design/calls-more.md).
class CallMiniPlayerHost extends ConsumerWidget {
  const CallMiniPlayerHost({required this.child, this.onOpen, super.key});

  final Widget child;

  /// Brings the call's own page back.
  final ValueChanged<VoiceSession>? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(voiceSessionProvider);
    final hidden = ref.watch(
      callSurfacesProvider.select((surfaces) => surfaces.isNotEmpty),
    );
    final show = session != null && session.isConnected && !hidden;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        if (show)
          Positioned.fill(
            // Text outside a page needs a Material for its style.
            child: Material(
              type: MaterialType.transparency,
              child: CallMiniPlayer(
                key: const ValueKey('call-mini-player-host'),
                session: session,
                onOpen: onOpen,
              ),
            ),
          ),
      ],
    );
  }
}

/// The corners the mini player snaps to.
enum MiniPlayerCorner { topLeft, topRight, bottomLeft, bottomRight }

/// The window's size: a bit wider on desktops.
Size miniPlayerSize({required bool wide}) =>
    wide ? const Size(244, 150) : const Size(188, 120);

/// Where the window's top-left sits in [corner], inside [area] with the
/// [padding] of the system bars, keeping [leftClearance] from the left (the
/// circle rail), [topClearance] from the top and [bottomClearance] above the
/// bottom (the floating user panel and the composer).
Offset miniPlayerOffset({
  required MiniPlayerCorner corner,
  required Size area,
  required Size window,
  required EdgeInsets padding,
  double margin = 12,
  double leftClearance = 0,
  double topClearance = 0,
  double bottomClearance = 0,
}) {
  final left = padding.left + margin + leftClearance;
  final right = math.max(
    left,
    area.width - padding.right - margin - window.width,
  );
  final top = padding.top + margin + topClearance;
  final bottom = math.max(
    top,
    area.height - padding.bottom - margin - bottomClearance - window.height,
  );
  return switch (corner) {
    MiniPlayerCorner.topLeft => Offset(left, top),
    MiniPlayerCorner.topRight => Offset(right, top),
    MiniPlayerCorner.bottomLeft => Offset(left, bottom),
    MiniPlayerCorner.bottomRight => Offset(right, bottom),
  };
}

/// The corner [position] (a window's top-left, moving with [velocity] in
/// pixels per second) settles in: a flick carries it a little further.
MiniPlayerCorner nearestMiniPlayerCorner({
  required Offset position,
  required Offset velocity,
  required Size area,
  required Size window,
}) {
  final center = position + Offset(window.width / 2, window.height / 2);
  final thrown = center + velocity * 0.12;
  final right = thrown.dx > area.width / 2;
  final bottom = thrown.dy > area.height / 2;
  return switch ((right, bottom)) {
    (false, false) => MiniPlayerCorner.topLeft,
    (true, false) => MiniPlayerCorner.topRight,
    (false, true) => MiniPlayerCorner.bottomLeft,
    (true, true) => MiniPlayerCorner.bottomRight,
  };
}

/// The draggable window: the active speaker's video or avatar with mute and
/// leave buttons. Tapping it returns to the call.
class CallMiniPlayer extends ConsumerStatefulWidget {
  const CallMiniPlayer({required this.session, this.onOpen, super.key});

  final VoiceSession session;
  final ValueChanged<VoiceSession>? onOpen;

  @override
  ConsumerState<CallMiniPlayer> createState() => _CallMiniPlayerState();
}

class _CallMiniPlayerState extends ConsumerState<CallMiniPlayer> {
  var _corner = MiniPlayerCorner.bottomRight;

  /// The window's top-left while it is being dragged.
  Offset? _dragging;
  String? _lastSpeakerId;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final speaker = activeSpeakerOf(
      session.participants,
      previousId: _lastSpeakerId,
    );
    if (speaker != null && !speaker.isLocal && speaker.isSpeaking) {
      _lastSpeakerId = speaker.userId;
    }
    final wide = isWideLayout(MediaQuery.sizeOf(context).width);
    final size = miniPlayerSize(wide: wide);

    return VoiceRoomTheme(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final area = constraints.biggest;
          final padding = MediaQuery.paddingOf(context);
          Offset cornerOffset(MiniPlayerCorner corner) => miniPlayerOffset(
            corner: corner,
            area: area,
            window: size,
            padding: padding,
            // Wide windows have the circle rail on the left (and the macOS
            // traffic lights over it) and the page starts below the top gap.
            leftClearance: wide ? WeCordSizes.railDesktop : 0,
            topClearance: wide ? 10 : 0,
            // Phones keep clear of the voice panel and the user panel (or the
            // composer) floating at the bottom.
            bottomClearance: wide ? 0 : 172,
          );
          final offset = _dragging ?? cornerOffset(_corner);
          final moving = _dragging != null;
          final spring = WeCordMotion.smooth;
          return Stack(
            children: [
              AnimatedPositioned(
                key: const ValueKey('call-mini-player-position'),
                duration: moving ? Duration.zero : spring.durationOf(context),
                curve: spring.curve,
                left: offset.dx,
                top: offset.dy,
                width: size.width,
                height: size.height,
                child: _MiniPlayerWindow(
                  session: session,
                  speaker: speaker,
                  onOpen: widget.onOpen,
                  onDragStart: () =>
                      setState(() => _dragging = cornerOffset(_corner)),
                  onDragUpdate: (delta) {
                    final current = _dragging ?? cornerOffset(_corner);
                    setState(() {
                      _dragging = Offset(
                        (current.dx + delta.dx).clamp(
                          0.0,
                          math.max(0.0, area.width - size.width),
                        ),
                        (current.dy + delta.dy).clamp(
                          0.0,
                          math.max(0.0, area.height - size.height),
                        ),
                      );
                    });
                  },
                  onDragEnd: (velocity) {
                    final position = _dragging ?? cornerOffset(_corner);
                    setState(() {
                      _corner = nearestMiniPlayerCorner(
                        position: position,
                        velocity: velocity,
                        area: area,
                        window: size,
                      );
                      _dragging = null;
                    });
                  },
                  onMoveTo: (corner) => setState(() => _corner = corner),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MiniPlayerWindow extends ConsumerWidget {
  const _MiniPlayerWindow({
    required this.session,
    required this.speaker,
    required this.onOpen,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onMoveTo,
  });

  final VoiceSession session;
  final VoiceCallParticipant? speaker;
  final ValueChanged<VoiceSession>? onOpen;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final ValueChanged<Offset> onDragEnd;
  final ValueChanged<MiniPlayerCorner> onMoveTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final controller = ref.read(voiceSessionProvider.notifier);
    final muted = session.selfMute || session.serverMute;
    final speaker = this.speaker;
    final name = speaker == null
        ? session.channelName
        : (speaker.isLocal
              ? tr('{name} (you)', {'name': speaker.name})
              : speaker.name);
    final video = speaker?.cameraView;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(WeCordRadii.xl),
    );
    final label = tr('Call in {name}. Tap to return.', {
      'name': session.channelName,
    });

    Widget media;
    if (video != null) {
      media = video(context);
    } else {
      media = Align(
        alignment: const Alignment(0, -0.35),
        child: VoiceAvatar(
          name: speaker?.name ?? session.channelName,
          avatarUrl: speaker == null
              ? null
              : _avatarUrl(ref, session, speaker.userId),
          speaking: speaker?.isSpeaking ?? false,
          size: 48,
        ),
      );
    }

    final window = DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        color: c.paper,
        shadows: context.tokens.shadows.float,
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: WeCordPressable(
                key: const ValueKey('call-mini-player-open'),
                semanticLabel: label,
                excludeSemantics: true,
                shape: shape,
                pressedScale: 1,
                minTapSize: Size.zero,
                onPressed: onOpen == null ? null : () => onOpen!(session),
                builder: (context, states) => ColoredBox(
                  color: c.paper,
                  child: Stack(fit: StackFit.expand, children: [media]),
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              right: 8,
              child: IgnorePointer(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 3, 9, 3),
                    decoration: BoxDecoration(
                      color: c.paper.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(WeCordRadii.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (speaker != null && !speaker.microphoneEnabled) ...[
                          Icon(Icons.mic_off_rounded, size: 12, color: c.ink),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            name,
                            key: const ValueKey('call-mini-player-name'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: c.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  VoiceRoundButton(
                    key: const ValueKey('call-mini-player-mute'),
                    tooltip: voiceMuteTooltip(session),
                    icon: muted
                        ? Icons.mic_off_rounded
                        : Icons.mic_none_rounded,
                    fill: muted ? c.dangerSoft : c.raised,
                    foreground: muted ? c.dangerText : c.ink,
                    size: 34,
                    onPressed: session.isConnected && !session.serverMute
                        ? () => runVoiceAction(context, controller.toggleMute)
                        : null,
                  ),
                  VoiceRoundButton(
                    key: const ValueKey('call-mini-player-leave'),
                    tooltip: tr('Disconnect'),
                    icon: Icons.call_end_rounded,
                    fill: c.danger,
                    foreground: c.onDanger,
                    size: 34,
                    onPressed: controller.leave,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Semantics(
      container: true,
      customSemanticsActions: {
        for (final (corner, text) in [
          (MiniPlayerCorner.topLeft, tr('Move to top left')),
          (MiniPlayerCorner.topRight, tr('Move to top right')),
          (MiniPlayerCorner.bottomLeft, tr('Move to bottom left')),
          (MiniPlayerCorner.bottomRight, tr('Move to bottom right')),
        ])
          CustomSemanticsAction(label: text): () => onMoveTo(corner),
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: GestureDetector(
          key: const ValueKey('call-mini-player-drag'),
          behavior: HitTestBehavior.deferToChild,
          onPanStart: (_) => onDragStart(),
          onPanUpdate: (details) => onDragUpdate(details.delta),
          onPanEnd: (details) => onDragEnd(details.velocity.pixelsPerSecond),
          onPanCancel: () => onDragEnd(Offset.zero),
          child: window,
        ),
      ),
    );
  }
}

/// A person's picture in the call, from what the app already knows about
/// the chat's or channel's members.
String? _avatarUrl(WidgetRef ref, VoiceSession session, String userId) {
  final circleId = session.circleId;
  if (circleId != null) {
    final members = ref.watch(voiceStatesProvider(circleId)).value;
    for (final member in members ?? const []) {
      if (member.userId == userId) {
        return member.avatarUrl;
      }
    }
    return null;
  }
  final call = ref.watch(directCallInProvider(session.conversationId));
  for (final participant in call?.participants ?? const []) {
    if (participant.userId == userId) {
      return participant.avatarUrl;
    }
  }
  return null;
}
