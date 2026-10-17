import 'package:flutter/material.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What the person agreed to share.
class LiveShareChoice {
  const LiveShareChoice({required this.duration, required this.precise});

  final Duration duration;
  final bool precise;
}

/// The lengths offered.
const liveShareDurations = <Duration>[
  Duration(minutes: 15),
  Duration(hours: 1),
  Duration(hours: 8),
];

/// Asks for consent to share live location in a chat, every time: how long,
/// precise or approximate, and what sharing means. Returns null when the
/// person backs out.
Future<LiveShareChoice?> showLiveLocationConsent(BuildContext context) {
  return showWeCordSheet<LiveShareChoice>(
    context,
    builder: (context, _) => const LiveLocationConsentSheet(),
  );
}

class LiveLocationConsentSheet extends StatefulWidget {
  const LiveLocationConsentSheet({super.key});

  @override
  State<LiveLocationConsentSheet> createState() =>
      _LiveLocationConsentSheetState();
}

class _LiveLocationConsentSheetState extends State<LiveLocationConsentSheet> {
  var _duration = liveShareDurations.first;
  var _precise = false;

  String _label(Duration duration) {
    return switch (duration.inMinutes) {
      15 => tr('15 minutes'),
      60 => tr('1 hour'),
      _ => tr('8 hours'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              tr('Share live location'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              'Everyone in this chat sees where you are on a map while you share.',
            ),
            style: TextStyle(fontSize: 15, color: c.muted, height: 1.35),
          ),
          const SizedBox(height: 18),
          SettingsSectionHeader(tr('For how long')),
          const SizedBox(height: 8),
          WeCordSegmented<Duration>(
            key: const ValueKey('live-duration'),
            expand: true,
            height: 40,
            semanticLabel: tr('For how long'),
            selected: _duration,
            onChanged: (value) => setState(() => _duration = value),
            segments: [
              for (final duration in liveShareDurations)
                WeCordSegment(
                  value: duration,
                  label: _label(duration),
                  key: ValueKey('live-duration-${duration.inMinutes}'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsGroup(
            color: c.well,
            children: [
              SettingsRow.toggle(
                title: tr('Precise location'),
                subtitle: _precise
                    ? tr('Shares exactly where you are.')
                    : tr('Shares an approximate spot, within about 500 m.'),
                icon: Icons.my_location_rounded,
                tone: SettingsTone.accent,
                value: _precise,
                onChanged: (value) => setState(() => _precise = value),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Note(
            icon: Icons.lock_outline_rounded,
            text: tr(
              'Only members of this chat can see it. It is not saved: it stops when time runs out, when you tap Stop or when you leave the chat.',
            ),
          ),
          const SizedBox(height: 10),
          _Note(
            icon: Icons.pause_circle_outline_rounded,
            text: tr('Sharing pauses when WeCord is closed.'),
          ),
          const SizedBox(height: 20),
          WeCordButton(
            key: const ValueKey('live-start'),
            label: tr('Start sharing'),
            icon: Icons.near_me_rounded,
            variant: WeCordButtonVariant.accent,
            size: WeCordButtonSize.large,
            expand: true,
            onPressed: () => Navigator.of(
              context,
            ).pop(LiveShareChoice(duration: _duration, precise: _precise)),
          ),
          const SizedBox(height: 8),
          WeCordButton(
            key: const ValueKey('live-cancel'),
            label: tr('Cancel'),
            variant: WeCordButtonVariant.ghost,
            size: WeCordButtonSize.large,
            expand: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Icon(icon, size: 20, color: c.muted)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13.5, color: c.muted, height: 1.4),
          ),
        ),
      ],
    );
  }
}
