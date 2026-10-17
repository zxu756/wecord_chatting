import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:wecord/features/location/location_models.dart';
import 'package:wecord/features/location/location_service.dart';
import 'package:wecord/features/location/location_viewer_screen.dart'
    show showMapScreen;
import 'package:wecord/features/location/map_widgets.dart';
import 'package:wecord/features/location/places_service.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the place picker and returns what the person chose to send (null
/// when they backed out).
Future<PlaceInfo?> showLocationPicker(BuildContext context) {
  return showMapScreen<PlaceInfo>(context, const LocationPickerScreen());
}

/// Picks a place to send: the map opens on where the person is (once they
/// allow it), a pin stays in the middle while they drag the map, and under
/// it are what the pin points at, the places nearby and a search.
class LocationPickerScreen extends ConsumerStatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  ConsumerState<LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
}

enum _Load { idle, loading, done, failed }

class _LocationPickerScreenState extends ConsumerState<LocationPickerScreen> {
  static const _worldCenter = LatLng(25, 10);

  final _map = MapController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  LocationAccess? _access;
  LatLng? _me;
  LatLng _center = _worldCenter;
  double _zoom = 2;
  var _mapReady = false;

  /// What the pin points at, once looked up.
  PlaceInfo? _pin;
  var _pinLoad = _Load.idle;
  List<PlaceInfo> _nearby = const [];
  var _nearbyLoad = _Load.idle;
  LatLng? _nearbyFor;

  /// A row chosen from the list (nearby or a search result); null: the pin.
  PlaceInfo? _chosen;
  var _dragging = false;
  var _requestId = 0;
  Timer? _settleTimer;

  var _query = '';
  List<PlaceInfo> _results = const [];
  var _searchLoad = _Load.idle;
  Timer? _searchTimer;
  var _searchId = 0;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() => setState(() {}));
    unawaited(_locate());
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _searchTimer?.cancel();
    _map.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // The device's position ----------------------------------------------------

  /// Asks for permission (the system prompt) and centres the map on the
  /// person.
  Future<void> _locate({bool prompt = true}) async {
    final service = ref.read(locationServiceProvider);
    var access = await service.access();
    if (access == LocationAccess.denied && prompt) {
      access = await service.requestAccess();
    }
    if (!mounted) {
      return;
    }
    setState(() => _access = access);
    if (access != LocationAccess.granted) {
      return;
    }
    try {
      final position = await service.currentPosition();
      if (!mounted) {
        return;
      }
      setState(() => _me = position.point);
      _moveTo(position.point, 16.5);
      unawaited(_settle());
    } on LocationUnavailable {
      // The map stays where it is; the person can still search and drag.
    }
  }

  Future<void> _allowLocation() async {
    final service = ref.read(locationServiceProvider);
    if (_access == LocationAccess.deniedForever) {
      await service.openSettings();
      return;
    }
    await _locate();
  }

  void _moveTo(LatLng point, double zoom) {
    _center = point;
    _zoom = zoom;
    if (_mapReady) {
      _map.move(point, zoom);
    }
  }

  // The pin and what is near it ------------------------------------------------

  void _onCameraMoved(MapCamera camera, bool hasGesture) {
    _center = camera.center;
    _zoom = camera.zoom;
    if (!hasGesture) {
      return;
    }
    _settleTimer?.cancel();
    if (!_dragging || _chosen != null) {
      setState(() {
        _dragging = true;
        _chosen = null;
      });
    }
    _settleTimer = Timer(
      const Duration(milliseconds: 650),
      () => unawaited(_settle()),
    );
  }

  /// Looks up what the pin points at and, if it moved far enough, what is
  /// near it.
  Future<void> _settle() async {
    final point = _center;
    final id = ++_requestId;
    final places = ref.read(placesServiceProvider);
    setState(() {
      _dragging = false;
      _pinLoad = _Load.loading;
    });
    final needNearby =
        _nearbyFor == null || distanceMeters(_nearbyFor!, point) > 60;
    if (needNearby) {
      setState(() => _nearbyLoad = _Load.loading);
      unawaited(() async {
        try {
          final found = await places.nearby(point);
          if (mounted && id == _requestId) {
            setState(() {
              _nearby = found;
              _nearbyFor = point;
              _nearbyLoad = _Load.done;
            });
          }
        } on Object {
          if (mounted && id == _requestId) {
            setState(() => _nearbyLoad = _Load.failed);
          }
        }
      }());
    }
    try {
      final place = await places.reverse(point);
      if (mounted && id == _requestId) {
        setState(() {
          _pin = (place ?? PlaceInfo(point: point)).copyWith(point: point);
          _pinLoad = _Load.done;
        });
      }
    } on Object {
      if (mounted && id == _requestId) {
        setState(() {
          _pin = PlaceInfo(point: point);
          _pinLoad = _Load.failed;
        });
      }
    }
  }

  bool get _pinIsMe => _me != null && distanceMeters(_me!, _center) < 40;

  /// The title of the row for the pin: where the person is, a named place or
  /// just a dropped pin.
  String _pinTitle() {
    final pin = _pin;
    if (_pinIsMe) {
      return tr('Current location');
    }
    if (pin != null && pin.hasName) {
      return pin.name;
    }
    return tr('Dropped pin');
  }

  /// What would be sent right now.
  PlaceInfo _selected() {
    final chosen = _chosen;
    if (chosen != null) {
      return chosen;
    }
    final pin = _pin;
    final point = _center;
    final name = _pinIsMe && !(pin?.hasName ?? false)
        ? tr('Current location')
        : (pin != null && pin.hasName ? pin.name : tr('Dropped pin'));
    return PlaceInfo(point: point, name: name, address: pin?.address ?? '');
  }

  void _choose(PlaceInfo place) {
    _settleTimer?.cancel();
    _searchFocus.unfocus();
    setState(() {
      _chosen = place;
      _dragging = false;
      _query = '';
      _results = const [];
      _searchLoad = _Load.idle;
      _searchController.clear();
    });
    _moveTo(place.point, 17);
  }

  void _choosePin() {
    setState(() => _chosen = null);
  }

  // Search ----------------------------------------------------------------------

  void _onQueryChanged(String value) {
    _searchTimer?.cancel();
    final query = value.trim();
    setState(() {
      _query = query;
      if (query.length < 2) {
        _results = const [];
        _searchLoad = _Load.idle;
      }
    });
    if (query.length < 2) {
      return;
    }
    _searchTimer = Timer(
      const Duration(milliseconds: 550),
      () => unawaited(_search(query)),
    );
  }

  Future<void> _search(String query) async {
    final id = ++_searchId;
    setState(() => _searchLoad = _Load.loading);
    try {
      final found = await ref
          .read(placesServiceProvider)
          .search(query, near: _me ?? (_zoom > 6 ? _center : null));
      if (mounted && id == _searchId) {
        setState(() {
          _results = found;
          _searchLoad = _Load.done;
        });
      }
    } on Object {
      if (mounted && id == _searchId) {
        setState(() => _searchLoad = _Load.failed);
      }
    }
  }

  void _clearSearch() {
    _searchTimer?.cancel();
    _searchId++;
    _searchController.clear();
    setState(() {
      _query = '';
      _results = const [];
      _searchLoad = _Load.idle;
    });
  }

  // Build -------------------------------------------------------------------------

  void _send() {
    Navigator.of(context).pop(_selected());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final wide = !isCompactWidth(MediaQuery.sizeOf(context).width);
    final safe = MediaQuery.paddingOf(context);
    final searching = _query.isNotEmpty || _searchFocus.hasFocus;

    final map = _MapArea(
      map: _map,
      center: _center,
      zoom: _zoom,
      // The pin already marks the spot when it is on the person.
      me: _pinIsMe ? null : _me,
      dragging: _dragging,
      onReady: () => _mapReady = true,
      onMoved: _onCameraMoved,
      attributionBottom: wide ? 8 : 40,
    );

    Widget controls(double bottom) => Positioned(
      right: 12,
      bottom: bottom,
      child: GlassMapButton(
        key: const ValueKey('location-my-location'),
        icon: Icons.my_location_rounded,
        tooltip: tr('My location'),
        onPressed: () {
          if (_access == LocationAccess.granted && _me != null) {
            _moveTo(_me!, 16.5);
            unawaited(_settle());
          } else {
            unawaited(_allowLocation());
          }
        },
      ),
    );

    final panel = _PickerPanel(
      searchController: _searchController,
      searchFocus: _searchFocus,
      onQueryChanged: _onQueryChanged,
      onClearSearch: _clearSearch,
      query: _query,
      searchLoad: _searchLoad,
      results: _results,
      pinTitle: _pinTitle(),
      pin: _pin,
      pinLoad: _pinLoad,
      pinPoint: _center,
      pinChosen: _chosen == null,
      nearby: _nearby,
      nearbyLoad: _nearbyLoad,
      chosen: _chosen,
      access: _access,
      onAllowLocation: () => unawaited(_allowLocation()),
      onChoosePin: _choosePin,
      onChoose: _choose,
      onSend: _send,
      sendLabel: tr('Send'),
      bottomInset: wide ? 0 : safe.bottom,
    );

    final close = Positioned(
      left: 12,
      top: 12 + (wide ? 0 : safe.top),
      child: GlassMapButton(
        key: const ValueKey('location-picker-close'),
        icon: Icons.close_rounded,
        tooltip: tr('Close'),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    );

    if (wide) {
      return Scaffold(
        backgroundColor: c.panel,
        body: Row(
          children: [
            SizedBox(
              width: 380,
              child: ColoredBox(color: c.panel, child: _withTitle(panel)),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: map),
                  controls(36),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final panelHeight = searching
        ? (screenHeight - keyboard - safe.top - 8).clamp(260.0, screenHeight)
        : (screenHeight * 0.46).clamp(300.0, 460.0) + safe.bottom;
    return Scaffold(
      backgroundColor: c.panel,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: panelHeight - 28,
            child: map,
          ),
          if (!searching) ...[close, controls(panelHeight + 12)],
          Positioned(
            left: 0,
            right: 0,
            bottom: keyboard,
            height: panelHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.panel,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(WeCordRadii.xxl),
                ),
                boxShadow: context.tokens.shadows.float,
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(WeCordRadii.xxl),
                ),
                child: _withTitle(panel, grabber: true),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _withTitle(Widget panel, {bool grabber = false}) {
    final c = context.tokens.colors;
    final wide = !isCompactWidth(MediaQuery.sizeOf(context).width);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (grabber)
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 2),
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: c.track,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, wide ? 18 : 8, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    tr('Send location'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: c.ink,
                    ),
                  ),
                ),
              ),
              if (wide)
                WeCordIconButton(
                  key: const ValueKey('location-picker-close'),
                  icon: Icons.close_rounded,
                  tooltip: tr('Close'),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
            ],
          ),
        ),
        Expanded(child: panel),
      ],
    );
  }
}

/// The map with the pin in the middle (and the person's own dot).
class _MapArea extends StatelessWidget {
  const _MapArea({
    required this.map,
    required this.center,
    required this.zoom,
    required this.me,
    required this.dragging,
    required this.onReady,
    required this.onMoved,
    required this.attributionBottom,
  });

  final MapController map;
  final LatLng center;
  final double zoom;
  final LatLng? me;
  final bool dragging;
  final VoidCallback onReady;
  final void Function(MapCamera camera, bool hasGesture) onMoved;
  final double attributionBottom;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr('Map. Drag it to move the pin, or choose from the list.'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          WeCordMap(
            key: const ValueKey('location-picker-map'),
            center: center,
            zoom: zoom,
            controller: map,
            attributionInsets: EdgeInsets.fromLTRB(8, 0, 8, attributionBottom),
            onPositionChanged: onMoved,
            onMapReady: onReady,
            children: [
              if (me != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: me!,
                      width: 24,
                      height: 24,
                      child: const MyLocationDot(),
                    ),
                  ],
                ),
            ],
          ),
          IgnorePointer(
            child: Center(
              child: Padding(
                // The pin's tip is the middle of the map.
                padding: const EdgeInsets.only(bottom: 56),
                child: MapPin(
                  key: const ValueKey('location-center-pin'),
                  size: 56,
                  lifted: dragging,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Under the map: search, the pin's place, nearby places, Send.
class _PickerPanel extends StatelessWidget {
  const _PickerPanel({
    required this.searchController,
    required this.searchFocus,
    required this.onQueryChanged,
    required this.onClearSearch,
    required this.query,
    required this.searchLoad,
    required this.results,
    required this.pinTitle,
    required this.pin,
    required this.pinLoad,
    required this.pinPoint,
    required this.pinChosen,
    required this.nearby,
    required this.nearbyLoad,
    required this.chosen,
    required this.access,
    required this.onAllowLocation,
    required this.onChoosePin,
    required this.onChoose,
    required this.onSend,
    required this.sendLabel,
    required this.bottomInset,
  });

  final TextEditingController searchController;
  final FocusNode searchFocus;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearSearch;
  final String query;
  final _Load searchLoad;
  final List<PlaceInfo> results;
  final String pinTitle;
  final PlaceInfo? pin;
  final _Load pinLoad;
  final LatLng pinPoint;
  final bool pinChosen;
  final List<PlaceInfo> nearby;
  final _Load nearbyLoad;
  final PlaceInfo? chosen;
  final LocationAccess? access;
  final VoidCallback onAllowLocation;
  final VoidCallback onChoosePin;
  final ValueChanged<PlaceInfo> onChoose;
  final VoidCallback onSend;
  final String sendLabel;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final searching = query.isNotEmpty;
    final locationNotice = switch (access) {
      LocationAccess.denied => (
        tr('Allow location to start from where you are.'),
        tr('Allow location'),
      ),
      LocationAccess.deniedForever => (
        tr('Location is off for WeCord. You can still search or move the map.'),
        tr('Open settings'),
      ),
      LocationAccess.serviceOff => (
        tr(
          'Location services are off on this device. You can still search or move the map.',
        ),
        null,
      ),
      _ => null,
    };

    final rows = <Widget>[];
    if (searching) {
      if (searchLoad == _Load.loading) {
        rows.add(const _Hint.loading());
      } else if (searchLoad == _Load.failed) {
        rows.add(
          _Hint(
            text: tr(
              "Couldn't search right now. Check your connection and try again.",
            ),
          ),
        );
      } else if (searchLoad == _Load.done && results.isEmpty) {
        rows.add(_Hint(text: tr('No places found.')));
      }
      for (final place in results) {
        rows.add(
          _PlaceRow(
            key: ValueKey(
              'search-result-${place.point.latitude}-${place.point.longitude}',
            ),
            icon: Icons.place_outlined,
            title: place.hasName ? place.name : place.address,
            subtitle: place.hasName ? place.address : '',
            distance: place.distanceMeters,
            selected: false,
            onTap: () => onChoose(place),
          ),
        );
      }
    } else {
      rows.add(
        _PlaceRow(
          key: const ValueKey('location-pin-row'),
          icon: Icons.location_on_rounded,
          tone: SettingsTone.accent,
          title: pinTitle,
          subtitle: pinLoad == _Load.loading
              ? tr('Finding the address...')
              : (pin?.hasAddress == true
                    ? pin!.address
                    : '${pinPoint.latitude.toStringAsFixed(5)}, '
                          '${pinPoint.longitude.toStringAsFixed(5)}'),
          selected: pinChosen,
          onTap: onChoosePin,
        ),
      );
      if (nearby.isNotEmpty) {
        rows.add(_SectionLabel(tr('Nearby places')));
      }
      for (final place in nearby) {
        rows.add(
          _PlaceRow(
            key: ValueKey('nearby-${place.name}'),
            icon: Icons.storefront_outlined,
            title: place.name,
            subtitle: place.address,
            distance: place.distanceMeters,
            selected: chosen == place,
            onTap: () => onChoose(place),
          ),
        );
      }
      if (nearbyLoad == _Load.loading && nearby.isEmpty) {
        rows.add(const _Hint.loading());
      } else if (nearbyLoad == _Load.failed && nearby.isEmpty) {
        rows.add(
          _Hint(
            text: tr(
              "Couldn't load nearby places. You can still send the pin.",
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _SearchField(
            controller: searchController,
            focusNode: searchFocus,
            onChanged: onQueryChanged,
            onClear: onClearSearch,
          ),
        ),
        if (locationNotice != null && !searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _LocationNotice(
              text: locationNotice.$1,
              action: locationNotice.$2,
              onAction: onAllowLocation,
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: rows,
          ),
        ),
        if (!searching)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12 + bottomInset),
            child: WeCordButton(
              key: const ValueKey('location-send'),
              label: sendLabel,
              icon: Icons.send_rounded,
              variant: WeCordButtonVariant.accent,
              size: WeCordButtonSize.large,
              expand: true,
              onPressed: onSend,
            ),
          )
        else
          SizedBox(height: bottomInset),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: c.muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const ValueKey('location-search-field'),
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(fontSize: 15, color: c.ink),
              decoration: InputDecoration(
                hintText: tr('Search for a place'),
                hintStyle: TextStyle(fontSize: 15, color: c.muted),
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            WeCordIconButton(
              icon: Icons.close_rounded,
              tooltip: tr('Clear search'),
              onPressed: onClear,
              size: 32,
              iconSize: 18,
              variant: WeCordButtonVariant.ghost,
            ),
        ],
      ),
    );
  }
}

class _LocationNotice extends StatelessWidget {
  const _LocationNotice({
    required this.text,
    required this.action,
    required this.onAction,
  });

  final String text;
  final String? action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: c.warningSoft,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      child: Row(
        children: [
          Icon(Icons.location_off_outlined, size: 20, color: c.warningText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: c.ink, height: 1.3),
            ),
          ),
          if (action != null)
            WeCordButton(
              key: const ValueKey('location-allow'),
              label: action!,
              onPressed: onAction,
              variant: WeCordButtonVariant.secondary,
              size: WeCordButtonSize.small,
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: c.subtle,
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text}) : loading = false;

  const _Hint.loading() : text = '', loading = true;

  final String text;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Center(
        child: loading
            ? SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: c.muted,
                ),
              )
            : Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: c.muted),
              ),
      ),
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.distance,
    this.tone = SettingsTone.neutral,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final double? distance;
  final bool selected;
  final VoidCallback onTap;
  final SettingsTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final details = [
      if (subtitle.isNotEmpty) subtitle,
      if (distance != null) formatDistance(distance!),
    ].join(' · ');
    return WeCordPressable(
      onPressed: onTap,
      selected: selected,
      semanticLabel: details.isEmpty ? title : '$title, $details',
      pressedScale: 0.99,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? c.raised
                : (hovered ? c.raised.withValues(alpha: 0.6) : null),
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
          ),
          child: Row(
            children: [
              SettingsIconTile(icon: icon, tone: tone, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.muted),
                      ),
                  ],
                ),
              ),
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 22,
                    color: c.accent,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
