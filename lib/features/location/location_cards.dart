import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/location/live_location_map_screen.dart';
import 'package:wecord/features/location/live_location_providers.dart';
import 'package:wecord/features/location/location_format.dart';
import 'package:wecord/features/location/location_models.dart';
import 'package:wecord/features/location/location_viewer_screen.dart';
import 'package:wecord/features/location/map_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A place in a chat: a small map with a pin, its name and its address.
/// Tap it to open the place on a full map.
class LocationMessageCard extends StatelessWidget {
  const LocationMessageCard({
    required this.place,
    required this.textColor,
    this.sharedBy,
    this.width = 248,
    super.key,
  });

  final PlaceInfo place;

  /// The message's text color: the card sits straight on the bubble.
  final Color textColor;
  final String? sharedBy;
  final double width;

  @override
  Widget build(BuildContext context) {
    final title = place.hasName
        ? place.name
        : (place.hasAddress ? place.address : tr('Shared location'));
    final address = place.hasName ? place.address : '';
    return WeCordPressable(
      key: const ValueKey('location-card'),
      onPressed: () =>
          unawaited(showLocationViewer(context, place, sharedBy: sharedBy)),
      semanticLabel: tr('Location: {place}', {
        'place': [title, address].where((p) => p.isNotEmpty).join(', '),
      }),
      hint: tr('Opens the map'),
      pressedScale: 0.99,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      builder: (context, states) => SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(WeCordRadii.md),
              child: SizedBox(
                height: width * 0.54,
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    child: WeCordMap(
                      center: place.point,
                      zoom: 15.5,
                      interactive: false,
                      attributionInsets: const EdgeInsets.fromLTRB(5, 0, 5, 5),
                      children: [
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: place.point,
                              width: 44,
                              height: 44,
                              alignment: Alignment.topCenter,
                              child: const MapPin(size: 44),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: textColor.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Live location" in a chat: who is sharing and for how long, or that it
/// ended. Tap it while it runs to open the map.
class LiveLocationMessageCard extends ConsumerWidget {
  const LiveLocationMessageCard({
    required this.card,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.textColor,
    super.key,
  });

  final LiveLocationAttachment card;
  final String conversationId;
  final String senderId;
  final String senderName;
  final Color textColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shares = ref.watch(liveSharesProvider(conversationId));
    final now = clock.now().toUtc();
    // The card names a share; only the sender's own, in this chat, counts.
    final share = shares.value
        ?.where((s) => s.id == card.shareId && s.userId == senderId)
        .firstOrNull;
    final loading = !shares.hasValue && !shares.hasError;
    final running = share != null && share.isRunningAt(now);
    final ended = !loading && !running;
    final title = ended ? tr('Live location ended') : tr('Live location');
    final sharing = tr('{name} is sharing', {'name': senderName});
    final subtitle = ended
        ? tr('{name} stopped sharing', {'name': senderName})
        : (share == null
              ? sharing
              : '$sharing · ${timeLeftLabel(share.endsAt.difference(now))}');
    final c = context.tokens.colors;
    final content = Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ended ? c.faint.withValues(alpha: 0.3) : c.live,
              shape: BoxShape.circle,
            ),
            child: Icon(
              ended ? Icons.location_off_outlined : Icons.near_me_rounded,
              size: 20,
              color: ended ? textColor : c.onLive,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    color: textColor.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
          if (running) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: textColor.withValues(alpha: 0.72),
            ),
          ],
        ],
      ),
    );
    return WeCordPressable(
      key: const ValueKey('live-location-card'),
      onPressed: running
          ? () => unawaited(
              showLiveLocationMap(context, conversationId: conversationId),
            )
          : null,
      semanticLabel: '$title, $subtitle',
      hint: running ? tr('Opens the map') : null,
      pressedScale: 0.99,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      builder: (context, states) => content,
    );
  }
}
