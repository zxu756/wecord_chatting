import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/scheduled_calls/scheduled_calls.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/chat_event.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The green "In progress · Join" of an event with a call, from 15 minutes
/// before it starts until it ends. Nothing for any other event or time.
///
/// While the person is in that call already it says "Open call" instead.
class ScheduledCallJoinButton extends ConsumerStatefulWidget {
  const ScheduledCallJoinButton({
    required this.event,
    required this.now,
    this.onJoined,
    this.compact = false,
    super.key,
  });

  final ChatEvent event;

  /// The current time (the clock the cards share).
  final DateTime now;

  /// Called once the person is in the call (a sheet closes itself here).
  final VoidCallback? onJoined;

  /// A short "Join" for tight places (the strip under the header).
  final bool compact;

  @override
  ConsumerState<ScheduledCallJoinButton> createState() =>
      _ScheduledCallJoinButtonState();
}

class _ScheduledCallJoinButtonState
    extends ConsumerState<ScheduledCallJoinButton> {
  var _joining = false;

  Future<void> _join() async {
    if (_joining) {
      return;
    }
    WeCordHaptics.selection();
    final connected = inCallOf(
      ref.read(voiceSessionProvider),
      widget.event.conversationId,
    );
    setState(() => _joining = true);
    final joined =
        connected || await joinScheduledCall(context, ref, widget.event);
    if (!mounted) {
      return;
    }
    setState(() => _joining = false);
    if (joined) {
      widget.onJoined?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = ScheduledCall.phaseAt(widget.event, widget.now);
    if (phase != ScheduledCallPhase.opening &&
        phase != ScheduledCallPhase.live) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final connected = inCallOf(
      ref.watch(voiceSessionProvider),
      widget.event.conversationId,
    );
    final label = connected
        ? tr('Open call')
        : widget.compact
        ? tr('Join')
        : ScheduledCall.joinLabel(phase);
    return WeCordPressable(
      key: ValueKey('scheduled-call-join-${widget.event.id}'),
      semanticLabel: label,
      onPressed: _joining ? null : _join,
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          curve: WeCordMotion.standard,
          constraints: BoxConstraints(minHeight: widget.compact ? 36 : 44),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 12 : 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: hovered
                ? Color.alphaBlend(c.onLive.withValues(alpha: 0.12), c.live)
                : c.live,
            borderRadius: BorderRadius.circular(WeCordRadii.pill),
          ),
          child: Row(
            mainAxisSize: widget.compact ? MainAxisSize.min : MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ExcludeSemantics(
                child: _joining
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.onLive,
                        ),
                      )
                    : Icon(Icons.call_rounded, size: 18, color: c.onLive),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: widget.compact ? 1 : 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: c.onLive,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
