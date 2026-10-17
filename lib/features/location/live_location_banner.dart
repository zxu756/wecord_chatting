import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/location/live_location_map_screen.dart';
import 'package:wecord/features/location/live_location_providers.dart';
import 'package:wecord/features/location/live_location_sharer.dart';
import 'package:wecord/features/location/location_format.dart';
import 'package:wecord/features/location/map_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "2 people sharing location" under a chat's header while anyone shares;
/// tap it to open the map. It follows the shares starting and stopping, and
/// disappears when the last one ends. Your own sharing has a Stop button
/// right here.
class LiveLocationBanner extends ConsumerWidget {
  const LiveLocationBanner({
    required this.conversationId,
    this.desktop = false,
    super.key,
  });

  final String conversationId;
  final bool desktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shares =
        ref.watch(liveSharesProvider(conversationId)).value ?? const [];
    final me = ref.watch(locationUserIdProvider);
    final mine = ref.watch(
      liveLocationSharerProvider.select(
        (state) => state.forConversation(conversationId),
      ),
    );
    final others = [
      for (final share in shares)
        if (share.userId != me) share,
    ];
    final count = others.length + (mine != null ? 1 : 0);
    if (count == 0) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final title = mine != null && count == 1
        ? tr("You're sharing your location")
        : (count == 1
              ? tr('1 person sharing location')
              : tr('{count} people sharing location', {'count': count}));

    return Padding(
      padding: desktop
          ? const EdgeInsets.fromLTRB(20, 10, 20, 0)
          : EdgeInsets.zero,
      child: Container(
        key: const ValueKey('live-location-banner'),
        decoration: BoxDecoration(
          color: c.liveSoft,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        child: Row(
          children: [
            Expanded(
              child: WeCordPressable(
                onPressed: () => unawaited(
                  showLiveLocationMap(context, conversationId: conversationId),
                ),
                semanticLabel: title,
                hint: tr('Opens the map'),
                pressedScale: 0.99,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(WeCordRadii.lg),
                ),
                builder: (context, states) => Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
                  child: Row(
                    children: [
                      Icon(Icons.near_me_rounded, size: 18, color: c.liveText),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: c.ink,
                              ),
                            ),
                            if (mine != null)
                              Ticker(
                                interval: const Duration(seconds: 15),
                                builder: (context) => Text(
                                  timeLeftLabel(
                                    mine.remaining(clock.now().toUtc()),
                                  ),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: c.muted,
                                  ),
                                ),
                              )
                            else if (others.isNotEmpty)
                              Text(
                                others.map((s) => s.name).join(', '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: c.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (mine == null)
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: c.liveText,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (mine != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: WeCordButton(
                  key: const ValueKey('live-banner-stop'),
                  label: tr('Stop'),
                  variant: WeCordButtonVariant.danger,
                  size: WeCordButtonSize.small,
                  onPressed: () => unawaited(
                    ref
                        .read(liveLocationSharerProvider.notifier)
                        .stop(conversationId),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
