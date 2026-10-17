import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart'
    show GlassMenuEntry, globalRectOf, showGlassMenu;
import 'package:wecord/features/location/location_models.dart';
import 'package:wecord/features/location/map_widgets.dart';
import 'package:wecord/features/location/open_in_maps.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens a shared place on a full map: a phone page, a window on wide
/// screens.
Future<void> showLocationViewer(
  BuildContext context,
  PlaceInfo place, {
  String? sharedBy,
}) {
  final screen = LocationViewerScreen(place: place, sharedBy: sharedBy);
  return showMapScreen<void>(context, screen);
}

/// Shows a map screen as a full page on phones and in a rounded window on
/// wide screens.
Future<T?> showMapScreen<T>(BuildContext context, Widget screen) {
  final wide = !isCompactWidth(MediaQuery.sizeOf(context).width);
  if (!wide) {
    return Navigator.of(context, rootNavigator: true).push<T>(
      MaterialPageRoute<T>(fullscreenDialog: true, builder: (_) => screen),
    );
  }
  return showDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierColor: context.tokens.colors.scrim,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 700),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(WeCordRadii.xxl),
            boxShadow: dialogContext.tokens.shadows.dialog,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(WeCordRadii.xxl),
            child: screen,
          ),
        ),
      ),
    ),
  );
}

/// A place on a full map with a pin, and what can be done with it: open it
/// in a maps app, copy its address.
class LocationViewerScreen extends ConsumerStatefulWidget {
  const LocationViewerScreen({required this.place, this.sharedBy, super.key});

  final PlaceInfo place;

  /// Who shared it, for the title.
  final String? sharedBy;

  @override
  ConsumerState<LocationViewerScreen> createState() =>
      _LocationViewerScreenState();
}

class _LocationViewerScreenState extends ConsumerState<LocationViewerScreen> {
  final _controller = MapController();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  double _zoom = 16;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  PlaceInfo get _place => widget.place;

  String get _title => _place.hasName
      ? _place.name
      : (_place.hasAddress ? _place.address : tr('Shared location'));

  Future<void> _openIn(MapsApp app) async {
    final opened = await ref
        .read(mapsLauncherProvider)
        .open(mapsUri(app, _place));
    if (!opened && mounted) {
      _say(tr('Could not open the map.'));
    }
  }

  void _openInMaps(BuildContext buttonContext) {
    final apps = mapsAppsFor(
      isWeb: ref.read(mapsIsWebProvider),
      platform: Theme.of(context).platform,
    );
    if (apps.length == 1) {
      unawaited(_openIn(apps.single));
      return;
    }
    unawaited(
      showGlassMenu(
        buttonContext,
        anchor: globalRectOf(buttonContext),
        width: 232,
        entries: [
          for (final app in apps)
            GlassMenuEntry(
              key: ValueKey('open-in-${app.name}'),
              icon: Icons.map_outlined,
              label: tr('Open in {app}', {'app': app.label}),
              onSelected: () => unawaited(_openIn(app)),
            ),
        ],
      ),
    );
  }

  Future<void> _copy() async {
    await ref.read(mapsLauncherProvider).copy(copyableAddress(_place));
    if (mounted) {
      _say(tr('Address copied'));
    }
  }

  void _say(String message) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
    _messenger.currentState?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _zoomBy(double delta) {
    _zoom = (_controller.camera.zoom + delta).clamp(2.0, 19.0);
    _controller.move(_controller.camera.center, _zoom);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final wide = !isCompactWidth(MediaQuery.sizeOf(context).width);
    final safe = MediaQuery.paddingOf(context);
    final touch = usesTouchInput(context);
    final cardWidth = wide ? 380.0 : null;
    return ScaffoldMessenger(
      key: _messenger,
      child: Scaffold(
        backgroundColor: c.panel,
        body: Stack(
          children: [
            Positioned.fill(
              child: WeCordMap(
                key: const ValueKey('location-viewer-map'),
                center: _place.point,
                zoom: _zoom,
                controller: _controller,
                attributionInsets: EdgeInsets.fromLTRB(
                  8,
                  0,
                  8,
                  wide ? 8 : 250 + safe.bottom,
                ),
                children: [
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _place.point,
                        width: 56,
                        height: 56,
                        alignment: Alignment.topCenter,
                        child: const MapPin(size: 56),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              left: 12,
              top: 12 + safe.top,
              child: GlassMapButton(
                key: const ValueKey('location-viewer-close'),
                icon: wide
                    ? Icons.close_rounded
                    : Icons.arrow_back_ios_new_rounded,
                tooltip: wide ? tr('Close') : tr('Back'),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            if (!touch)
              Positioned(
                right: 12,
                top: 12 + safe.top,
                child: Column(
                  children: [
                    GlassMapButton(
                      icon: Icons.add_rounded,
                      tooltip: tr('Zoom in'),
                      onPressed: () => _zoomBy(1),
                    ),
                    const SizedBox(height: 8),
                    GlassMapButton(
                      icon: Icons.remove_rounded,
                      tooltip: tr('Zoom out'),
                      onPressed: () => _zoomBy(-1),
                    ),
                  ],
                ),
              ),
            Positioned(
              left: wide ? 16 : 12,
              right: wide ? null : 12,
              bottom: (wide ? 16 : 12) + safe.bottom,
              width: cardWidth,
              child: _PlaceCard(
                title: _title,
                address: _place.hasName ? _place.address : '',
                sharedBy: widget.sharedBy,
                onOpen: _openInMaps,
                onCopy: () => unawaited(_copy()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.title,
    required this.address,
    required this.sharedBy,
    required this.onOpen,
    required this.onCopy,
  });

  final String title;
  final String address;
  final String? sharedBy;
  final void Function(BuildContext buttonContext) onOpen;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xxl),
        boxShadow: context.tokens.shadows.float,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sharedBy != null) ...[
            Text(
              tr('Shared by {name}', {'name': sharedBy}),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.subtle,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Semantics(
            header: true,
            child: Text(
              title,
              key: const ValueKey('location-viewer-title'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: c.ink,
              ),
            ),
          ),
          if (address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              address,
              key: const ValueKey('location-viewer-address'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: c.muted, height: 1.35),
            ),
          ],
          const SizedBox(height: 14),
          Builder(
            builder: (buttonContext) => WeCordButton(
              key: const ValueKey('location-open-in-maps'),
              label: tr('Open in Maps'),
              icon: Icons.map_outlined,
              variant: WeCordButtonVariant.primary,
              size: WeCordButtonSize.medium,
              expand: true,
              onPressed: () => onOpen(buttonContext),
            ),
          ),
          const SizedBox(height: 8),
          WeCordButton(
            key: const ValueKey('location-copy-address'),
            label: tr('Copy address'),
            icon: Icons.copy_rounded,
            variant: WeCordButtonVariant.secondary,
            size: WeCordButtonSize.medium,
            expand: true,
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}
