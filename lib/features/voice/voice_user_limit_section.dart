import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// The highest user limit a voice channel can have.
const maxVoiceUserLimit = 99;

/// Channel settings → User limit, for a voice channel: how many people may
/// be in it at once (0 for no limit). Members who can move members join
/// anyway.
class VoiceUserLimitSection extends ConsumerStatefulWidget {
  const VoiceUserLimitSection({
    required this.circleId,
    required this.channelId,
    this.enabled = true,
    super.key,
  });

  final String circleId;
  final String channelId;
  final bool enabled;

  @override
  ConsumerState<VoiceUserLimitSection> createState() =>
      _VoiceUserLimitSectionState();
}

class _VoiceUserLimitSectionState extends ConsumerState<VoiceUserLimitSection> {
  /// The value being dragged, before it is saved.
  double? _dragging;
  var _saving = false;

  Future<void> _save(int limit) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(voiceRepositoryProvider)
          .setUserLimit(channelId: widget.channelId, limit: limit);
      ref.invalidate(voiceChannelUserLimitsProvider(widget.circleId));
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not change the user limit.'))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _dragging = null;
        });
      }
    }
  }

  String _label(int limit) {
    if (limit <= 0) {
      return tr('No limit');
    }
    return limit == 1 ? tr('1 person') : tr('{count} people', {'count': limit});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final limits = ref.watch(voiceChannelUserLimitsProvider(widget.circleId));
    final saved = limits.valueOrNull?[widget.channelId] ?? 0;
    final value = _dragging ?? saved.toDouble();
    return Column(
      key: const ValueKey('voice-user-limit-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            tr('User limit'),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        ListTile(
          title: Text(
            _label(value.round()),
            key: const ValueKey('voice-user-limit-value'),
          ),
          subtitle: Text(
            tr(
              'How many people can be in this voice channel at once. Members '
              'who can move members can still join.',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Slider(
            key: const ValueKey('voice-user-limit-slider'),
            value: value,
            max: maxVoiceUserLimit.toDouble(),
            divisions: maxVoiceUserLimit,
            label: _label(value.round()),
            onChanged: !widget.enabled || _saving || limits.isLoading
                ? null
                : (next) => setState(() => _dragging = next),
            onChangeEnd: (next) {
              if (next.round() != saved) {
                _save(next.round());
              } else {
                setState(() => _dragging = null);
              }
            },
          ),
        ),
      ],
    );
  }
}
