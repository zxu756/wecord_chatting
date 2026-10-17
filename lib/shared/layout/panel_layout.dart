import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

/// The columns of the wide layout the user can resize. The circle rail
/// stays fixed; the sidebar is shared by Home's direct messages and a
/// circle's channels.
enum ResizablePanel {
  sidebar(
    min: WeCordSizes.sidebarMin,
    initial: WeCordSizes.sidebarDefault,
    max: WeCordSizes.sidebarMax,
  ),
  members(
    min: WeCordSizes.memberListMin,
    initial: WeCordSizes.memberListDefault,
    max: WeCordSizes.memberListMax,
  ),
  profile(
    min: WeCordSizes.profilePanelMin,
    initial: WeCordSizes.profilePanelDefault,
    max: WeCordSizes.profilePanelMax,
  ),

  /// A conversation's notes and lists.
  docs(
    min: WeCordSizes.docsPanelMin,
    initial: WeCordSizes.docsPanelDefault,
    max: WeCordSizes.docsPanelMax,
  );

  const ResizablePanel({
    required this.min,
    required this.initial,
    required this.max,
  });

  final double min;
  final double initial;
  final double max;

  /// Right panels close when dragged this far below their minimum; the
  /// sidebar only stops at its minimum.
  static const collapseSlack = 60.0;

  bool get collapsible => this != sidebar;

  /// Dragging narrower than this closes the panel; null for the sidebar.
  double? get collapseBelow => collapsible ? min - collapseSlack : null;

  double clamp(double width) => width.clamp(min, max).toDouble();
}

/// The widths the user chose for the wide layout's columns and which right
/// panels they closed, as remembered on this device.
@immutable
class PanelLayout {
  const PanelLayout({
    this.sidebarWidth = WeCordSizes.sidebarDefault,
    this.membersWidth = WeCordSizes.memberListDefault,
    this.profileWidth = WeCordSizes.profilePanelDefault,
    this.docsWidth = WeCordSizes.docsPanelDefault,
    this.membersCollapsed = false,
    this.profileCollapsed = false,
    this.docsCollapsed = true,
  });

  /// Reads what [toJson] wrote, clamping widths to their ranges; anything
  /// missing or malformed falls back to the default.
  factory PanelLayout.fromJson(Map<String, Object?> json) {
    double width(String key, ResizablePanel panel) => switch (json[key]) {
      final num value when value.isFinite => panel.clamp(value.toDouble()),
      _ => panel.initial,
    };
    return PanelLayout(
      sidebarWidth: width('sidebar', ResizablePanel.sidebar),
      membersWidth: width('members', ResizablePanel.members),
      profileWidth: width('profile', ResizablePanel.profile),
      docsWidth: width('docs', ResizablePanel.docs),
      membersCollapsed: json['membersCollapsed'] == true,
      profileCollapsed: json['profileCollapsed'] == true,
      // Closed until somebody opens it.
      docsCollapsed: json['docsCollapsed'] != false,
    );
  }

  final double sidebarWidth;
  final double membersWidth;
  final double profileWidth;
  final double docsWidth;

  /// The user closed the circle member list.
  final bool membersCollapsed;

  /// The user closed the direct chat's profile panel.
  final bool profileCollapsed;

  /// The notes and lists panel is closed (it starts closed).
  final bool docsCollapsed;

  double widthOf(ResizablePanel panel) => switch (panel) {
    ResizablePanel.sidebar => sidebarWidth,
    ResizablePanel.members => membersWidth,
    ResizablePanel.profile => profileWidth,
    ResizablePanel.docs => docsWidth,
  };

  bool collapsedOf(ResizablePanel panel) => switch (panel) {
    ResizablePanel.sidebar => false,
    ResizablePanel.members => membersCollapsed,
    ResizablePanel.profile => profileCollapsed,
    ResizablePanel.docs => docsCollapsed,
  };

  PanelLayout withWidth(ResizablePanel panel, double width) {
    final clamped = panel.clamp(width);
    return PanelLayout(
      sidebarWidth: panel == ResizablePanel.sidebar ? clamped : sidebarWidth,
      membersWidth: panel == ResizablePanel.members ? clamped : membersWidth,
      profileWidth: panel == ResizablePanel.profile ? clamped : profileWidth,
      docsWidth: panel == ResizablePanel.docs ? clamped : docsWidth,
      membersCollapsed: membersCollapsed,
      profileCollapsed: profileCollapsed,
      docsCollapsed: docsCollapsed,
    );
  }

  PanelLayout withCollapsed(ResizablePanel panel, bool collapsed) {
    return PanelLayout(
      sidebarWidth: sidebarWidth,
      membersWidth: membersWidth,
      profileWidth: profileWidth,
      docsWidth: docsWidth,
      membersCollapsed: panel == ResizablePanel.members
          ? collapsed
          : membersCollapsed,
      profileCollapsed: panel == ResizablePanel.profile
          ? collapsed
          : profileCollapsed,
      docsCollapsed: panel == ResizablePanel.docs ? collapsed : docsCollapsed,
    );
  }

  Map<String, Object?> toJson() => {
    'sidebar': sidebarWidth,
    'members': membersWidth,
    'profile': profileWidth,
    'docs': docsWidth,
    'membersCollapsed': membersCollapsed,
    'profileCollapsed': profileCollapsed,
    'docsCollapsed': docsCollapsed,
  };

  @override
  bool operator ==(Object other) =>
      other is PanelLayout &&
      other.sidebarWidth == sidebarWidth &&
      other.membersWidth == membersWidth &&
      other.profileWidth == profileWidth &&
      other.docsWidth == docsWidth &&
      other.membersCollapsed == membersCollapsed &&
      other.profileCollapsed == profileCollapsed &&
      other.docsCollapsed == docsCollapsed;

  @override
  int get hashCode => Object.hash(
    sidebarWidth,
    membersWidth,
    profileWidth,
    docsWidth,
    membersCollapsed,
    profileCollapsed,
    docsCollapsed,
  );

  @override
  String toString() => 'PanelLayout(${toJson()})';
}

/// The sidebar's width in [available] (everything right of the rail): the
/// chosen [width], shrunk toward its minimum when the centre content would
/// get narrower than [WeCordSizes.contentMin].
double resolveSidebarWidth(double width, double available) {
  final room = available - WeCordSizes.contentMin;
  return math.min(width, math.max(room, ResizablePanel.sidebar.min));
}

/// Where a right panel goes in a row of [rowWidth] (content plus panel).
typedef SidePanelPlacement = ({bool shown, double width, double maxWidth});

/// Places a right [panel] at its chosen [width]: hidden when the user
/// [collapsed] it, or when the content would get narrower than
/// [WeCordSizes.contentMin] (it comes back when there is room again).
/// [forced] shows it anyway, at its minimum, after the user asked for it
/// while there wasn't room.
SidePanelPlacement resolveSidePanel(
  ResizablePanel panel, {
  required double width,
  required bool collapsed,
  required double rowWidth,
  bool forced = false,
}) {
  final room = rowWidth - WeCordSizes.contentMin;
  final maxWidth = math.max(panel.min, math.min(panel.max, room));
  if (collapsed) {
    return (shown: false, width: width, maxWidth: maxWidth);
  }
  if (width <= room) {
    return (shown: true, width: width, maxWidth: maxWidth);
  }
  if (forced) {
    return (
      shown: true,
      width: math.max(panel.min, math.min(width, room)),
      maxWidth: maxWidth,
    );
  }
  return (shown: false, width: width, maxWidth: maxWidth);
}

const _panelLayoutKey = 'wecord.layout.panels';

/// Where the panel widths are kept; tests swap in memory.
abstract interface class PanelLayoutStore {
  Future<PanelLayout?> load();

  Future<void> save(PanelLayout layout);
}

class SharedPreferencesPanelLayoutStore implements PanelLayoutStore {
  const SharedPreferencesPanelLayoutStore();

  @override
  Future<PanelLayout?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_panelLayoutKey);
    if (raw == null) {
      return null;
    }
    final json = jsonDecode(raw);
    return json is Map<String, Object?> ? PanelLayout.fromJson(json) : null;
  }

  @override
  Future<void> save(PanelLayout layout) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_panelLayoutKey, jsonEncode(layout.toJson()));
  }
}

class InMemoryPanelLayoutStore implements PanelLayoutStore {
  InMemoryPanelLayoutStore([this.layout]);

  PanelLayout? layout;

  @override
  Future<PanelLayout?> load() async => layout;

  @override
  Future<void> save(PanelLayout layout) async => this.layout = layout;
}

final panelLayoutStoreProvider = Provider<PanelLayoutStore>(
  (ref) => const SharedPreferencesPanelLayoutStore(),
);

/// The wide layout's column widths and closed panels, remembered on this
/// device. While a divider is dragged the width lives in [PanelLayoutController.liveWidth]
/// instead, so only the row being resized rebuilds; the state changes
/// (and is saved) when the drag ends.
final panelLayoutProvider =
    NotifierProvider<PanelLayoutController, PanelLayout>(
      PanelLayoutController.new,
    );

class PanelLayoutController extends Notifier<PanelLayout> {
  var _changed = false;

  final _live = {
    for (final panel in ResizablePanel.values)
      panel: ValueNotifier<double?>(null),
  };

  @override
  PanelLayout build() {
    ref.read(panelLayoutStoreProvider).load().then((layout) {
      // A change made while loading wins over the saved layout.
      if (layout != null && !_changed) {
        state = layout;
      }
    }, onError: (Object _) {});
    return const PanelLayout();
  }

  /// The width of [panel] while its divider is dragged (0 while the drag
  /// would close it), or null at rest.
  ValueListenable<double?> liveWidth(ResizablePanel panel) => _live[panel]!;

  /// Shows [width] while dragging, without saving it.
  void preview(ResizablePanel panel, double width) {
    _live[panel]!.value = width;
  }

  /// Keeps [width] (clamped to the panel's range) and opens the panel.
  Future<void> setWidth(ResizablePanel panel, double width) {
    _live[panel]!.value = null;
    return _save(state.withWidth(panel, width).withCollapsed(panel, false));
  }

  /// Back to the default width.
  Future<void> reset(ResizablePanel panel) => setWidth(panel, panel.initial);

  /// Opens or closes a right panel.
  Future<void> setCollapsed(ResizablePanel panel, bool collapsed) {
    _live[panel]!.value = null;
    return _save(state.withCollapsed(panel, collapsed));
  }

  Future<void> _save(PanelLayout layout) async {
    _changed = true;
    if (layout == state) {
      return;
    }
    state = layout;
    try {
      await ref.read(panelLayoutStoreProvider).save(layout);
    } on Object {
      // Still applies for this session.
    }
  }
}
