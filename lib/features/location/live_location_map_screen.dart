import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:wecord/features/location/location_actions.dart';
import 'package:wecord/features/location/live_location_providers.dart';
import 'package:wecord/features/location/live_location_sharer.dart';
import 'package:wecord/features/location/location_format.dart';
import 'package:wecord/features/location/location_models.dart';
import 'package:wecord/features/location/location_viewer_screen.dart'
    show showMapScreen;
import 'package:wecord/features/location/map_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the map of everyone sharing their location in a chat.
Future<void> showLiveLocationMap(
  BuildContext context, {
  required String conversationId,
}) {
  return showMapScreen<void>(
    context,
    LiveLocationMapScreen(conversationId: conversationId),
  );
}

/// One person on the live map.
class _Sharer {
  const _Sharer({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.isYou,
    required this.precise,
    required this.endsAt,
    required this.position,
    required this.unavailable,
  });

  final String userId;
  final String name;
  final String? avatarUrl;
  final bool isYou;
  final bool precise;
  final DateTime endsAt;
  final LivePosition? position;

  /// The server did not let this device listen to them.
  final bool unavailable;
}

/// Everyone who shares their location in a chat, on one map, moving as they
/// do, with who they are and how fresh each position is.
class LiveLocationMapScreen extends ConsumerStatefulWidget {
  const LiveLocationMapScreen({required this.conversationId, super.key});

  final String conversationId;

  @override
  ConsumerState<LiveLocationMapScreen> createState() =>
      _LiveLocationMapScreenState();
}

class _LiveLocationMapScreenState extends ConsumerState<LiveLocationMapScreen> {
  final _map = MapController();
  var _mapReady = false;

  /// Whose positions the camera has been fitted to; it follows again when
  /// someone new appears, until the person moves the map themselves.
  Set<String> _fitted = {};
  var _userMoved = false;
  double _panelHeight = 220;

  /// Moves "5 s ago", "12 min left" and the paused marks along.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _map.dispose();
    super.dispose();
  }

  List<_Sharer> _sharers() {
    final id = widget.conversationId;
    final me = ref.watch(locationUserIdProvider);
    final shares = ref.watch(liveSharesProvider(id)).value ?? const [];
    final positions = ref.watch(livePositionsProvider(id));
    final mine = ref.watch(
      liveLocationSharerProvider.select((state) => state.forConversation(id)),
    );
    LivePosition? ownPosition() {
      final point = mine?.lastPoint;
      final at = mine?.lastSentAt;
      return point == null || at == null
          ? null
          : LivePosition(point: point, at: at);
    }

    final result = <_Sharer>[];
    var sawMine = false;
    for (final share in shares) {
      final isYou = share.userId == me;
      sawMine = sawMine || isYou;
      result.add(
        _Sharer(
          userId: share.userId,
          name: share.name,
          avatarUrl: share.avatarUrl,
          isYou: isYou,
          precise: share.precise,
          endsAt: share.endsAt,
          position: isYou ? ownPosition() : positions.latest[share.userId],
          unavailable: positions.unavailable.contains(share.userId),
        ),
      );
    }
    if (mine != null && !sawMine && me != null) {
      result.add(
        _Sharer(
          userId: me,
          name: tr('You'),
          avatarUrl: null,
          isYou: true,
          precise: mine.precise,
          endsAt: mine.endsAt,
          position: ownPosition(),
          unavailable: false,
        ),
      );
    }
    // You first, then in the order they started.
    result.sort((a, b) => a.isYou == b.isYou ? 0 : (a.isYou ? -1 : 1));
    return result;
  }

  bool _isPaused(_Sharer sharer) {
    final position = sharer.position;
    if (position == null) {
      return false;
    }
    final staleAfter = ref.read(liveLocationTimingProvider).staleAfter;
    return clock.now().toUtc().difference(position.at) > staleAfter;
  }

  void _fitToPeople(List<_Sharer> sharers) {
    if (!_mapReady || _userMoved) {
      return;
    }
    final located = [
      for (final s in sharers)
        if (s.position != null) s,
    ];
    final ids = {for (final s in located) s.userId};
    if (ids.isEmpty || ids.difference(_fitted).isEmpty) {
      return;
    }
    _fitted = ids;
    _fitAll(located);
  }

  void _fitAll(List<_Sharer> located) {
    if (!_mapReady || located.isEmpty) {
      return;
    }
    final points = [for (final s in located) s.position!.point];
    if (points.length == 1) {
      _map.move(points.single, 15.5);
      return;
    }
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        maxZoom: 16,
        padding: EdgeInsets.fromLTRB(70, 110, 70, _panelHeight + 70),
      ),
    );
  }

  void _focus(_Sharer sharer) {
    final position = sharer.position;
    if (position == null || !_mapReady) {
      return;
    }
    _userMoved = true;
    _map.move(position.point, 16);
  }

  Future<void> _stop() async {
    await ref
        .read(liveLocationSharerProvider.notifier)
        .stop(widget.conversationId);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final wide = !isCompactWidth(MediaQuery.sizeOf(context).width);
    final safe = MediaQuery.paddingOf(context);
    final sharers = _sharers();
    final located = [
      for (final s in sharers)
        if (s.position != null) s,
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fitToPeople(sharers);
      }
    });
    final first = located.isEmpty ? null : located.first.position!.point;
    final touch = usesTouchInput(context);

    return Scaffold(
      backgroundColor: c.panel,
      body: Stack(
        children: [
          Positioned.fill(
            child: WeCordMap(
              key: const ValueKey('live-location-map'),
              center: first ?? const LatLng(25, 10),
              zoom: first == null ? 2 : 15.5,
              controller: _map,
              onMapReady: () {
                _mapReady = true;
                _fitToPeople(sharers);
              },
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) {
                  _userMoved = true;
                }
              },
              // Beside the panel, not under it.
              attributionInsets: EdgeInsets.fromLTRB(
                wide ? 432 : 8,
                0,
                8,
                wide ? 8 : _panelHeight + 8,
              ),
              children: [
                MarkerLayer(
                  markers: [
                    for (final s in located)
                      Marker(
                        point: s.position!.point,
                        width: 104,
                        height: 92,
                        child: PersonMapMarker(
                          key: ValueKey('live-marker-${s.userId}'),
                          name: s.name,
                          avatarUrl: s.avatarUrl,
                          isYou: s.isYou,
                          paused: _isPaused(s),
                        ),
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
              key: const ValueKey('live-map-close'),
              icon: wide
                  ? Icons.close_rounded
                  : Icons.arrow_back_ios_new_rounded,
              tooltip: wide ? tr('Close') : tr('Back'),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Positioned(
            right: 12,
            top: 12 + safe.top,
            child: Column(
              children: [
                GlassMapButton(
                  key: const ValueKey('live-map-fit'),
                  icon: Icons.zoom_out_map_rounded,
                  tooltip: tr('Show everyone'),
                  onPressed: located.isEmpty
                      ? null
                      : () {
                          _userMoved = false;
                          _fitAll(located);
                        },
                ),
                if (!touch) ...[
                  const SizedBox(height: 8),
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
              ],
            ),
          ),
          Positioned(
            left: wide ? 16 : 0,
            right: wide ? null : 0,
            bottom: wide ? 16 : 0,
            width: wide ? 400 : null,
            child: _SizeReporter(
              onHeight: (height) {
                if ((height - _panelHeight).abs() > 1) {
                  setState(() => _panelHeight = height);
                }
              },
              child: _SharersPanel(
                conversationId: widget.conversationId,
                sharers: sharers,
                isPaused: _isPaused,
                onFocus: _focus,
                onStop: () => unawaited(_stop()),
                wide: wide,
                bottomInset: wide ? 0 : safe.bottom,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _zoomBy(double delta) {
    if (!_mapReady) {
      return;
    }
    _userMoved = true;
    final zoom = (_map.camera.zoom + delta).clamp(2.0, 19.0);
    _map.move(_map.camera.center, zoom);
  }
}

/// Reports its child's height after layout.
class _SizeReporter extends StatefulWidget {
  const _SizeReporter({required this.onHeight, required this.child});

  final ValueChanged<double> onHeight;
  final Widget child;

  @override
  State<_SizeReporter> createState() => _SizeReporterState();
}

class _SizeReporterState extends State<_SizeReporter> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final box = context.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        widget.onHeight(box.size.height);
      }
    });
    return widget.child;
  }
}

class _SharersPanel extends ConsumerWidget {
  const _SharersPanel({
    required this.conversationId,
    required this.sharers,
    required this.isPaused,
    required this.onFocus,
    required this.onStop,
    required this.wide,
    required this.bottomInset,
  });

  final String conversationId;
  final List<_Sharer> sharers;
  final bool Function(_Sharer sharer) isPaused;
  final void Function(_Sharer sharer) onFocus;
  final VoidCallback onStop;
  final bool wide;
  final double bottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final count = sharers.length;
    final sharing = sharers.any((s) => s.isYou);
    final title = count == 0
        ? tr('Nobody is sharing location right now')
        : (count == 1
              ? tr('1 person sharing location')
              : tr('{count} people sharing location', {'count': count}));
    final maxHeight = MediaQuery.sizeOf(context).height * (wide ? 0.6 : 0.5);
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: wide
            ? BorderRadius.circular(WeCordRadii.xxl)
            : const BorderRadius.vertical(
                top: Radius.circular(WeCordRadii.xxl),
              ),
        boxShadow: context.tokens.shadows.float,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Row(
              children: [
                if (count > 0) ...[
                  const ExcludeSemantics(child: _LiveDot()),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    liveRegion: true,
                    child: Text(
                      title,
                      key: const ValueKey('live-map-title'),
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: c.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              children: [
                for (final sharer in sharers)
                  _SharerRow(
                    key: ValueKey('live-row-${sharer.userId}'),
                    sharer: sharer,
                    paused: isPaused(sharer),
                    onTap: () => onFocus(sharer),
                    onStop: onStop,
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 14 + bottomInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!sharing) ...[
                  WeCordButton(
                    key: const ValueKey('live-map-share'),
                    label: tr('Share my location'),
                    icon: Icons.near_me_rounded,
                    variant: WeCordButtonVariant.accent,
                    size: WeCordButtonSize.medium,
                    expand: true,
                    onPressed: () => unawaited(
                      shareLiveLocationFlow(
                        context,
                        ref,
                        conversationId: conversationId,
                        openMap: false,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        Icons.pause_circle_outline_rounded,
                        size: 16,
                        color: c.subtle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tr(
                          'Sharing pauses when WeCord is closed. Positions are not saved.',
                        ),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.subtle,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: c.live, shape: BoxShape.circle),
    );
  }
}

class _SharerRow extends StatelessWidget {
  const _SharerRow({
    required this.sharer,
    required this.paused,
    required this.onTap,
    required this.onStop,
    super.key,
  });

  final _Sharer sharer;
  final bool paused;
  final VoidCallback onTap;
  final VoidCallback onStop;

  String _subtitle() {
    final now = clock.now().toUtc();
    final approx = sharer.precise ? '' : ' · ${tr('Approximate')}';
    if (sharer.isYou) {
      return '${tr('Sharing')} · ${timeLeftLabel(sharer.endsAt.difference(now))}$approx';
    }
    final position = sharer.position;
    if (position == null) {
      return sharer.unavailable
          ? tr("Can't see this location")
          : tr('Waiting for their location...');
    }
    final age = now.difference(position.at);
    if (paused) {
      return tr('Paused · last seen {ago}', {'ago': agoLabel(age)});
    }
    return '${tr('Updated {ago}', {'ago': agoLabel(age)})}$approx';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final canFocus = sharer.position != null;
    final subtitle = _subtitle();
    final name = sharer.isYou ? tr('You') : sharer.name;
    return WeCordPressable(
      onPressed: canFocus ? onTap : null,
      semanticLabel: '$name, $subtitle',
      hint: canFocus ? tr('Shows them on the map') : null,
      pressedScale: 0.99,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) => Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: states.contains(WidgetState.hovered) ? c.raised : null,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        child: Row(
          children: [
            ExcludeSemantics(child: PersonAvatar(name: sharer.name, size: 40)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: paused ? c.warningText : c.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (sharer.isYou)
              WeCordButton(
                key: const ValueKey('live-stop'),
                label: tr('Stop'),
                variant: WeCordButtonVariant.danger,
                size: WeCordButtonSize.small,
                onPressed: onStop,
              ),
          ],
        ),
      ),
    );
  }
}
