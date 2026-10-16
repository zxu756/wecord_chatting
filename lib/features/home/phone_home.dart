import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/home/home_avatars.dart';
import 'package:wecord/features/inbox/inbox_screen.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/presence/presence_status_sheet.dart';
import 'package:wecord/features/settings/custom_status_sheet.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Colors of the phone home, for code that only has a ColorScheme: the
/// rail, its items and the white panel beside it (design tokens).
abstract final class PhoneHomeColors {
  static WeCordPalette _palette(ColorScheme colors) =>
      colors.brightness == Brightness.dark
      ? WeCordPalette.dark
      : WeCordPalette.light;

  static Color rail(ColorScheme colors) => _palette(colors).rail;

  /// Rail icons that are not selected.
  static Color railItem(ColorScheme colors) => _palette(colors).railItem;

  static Color panel(ColorScheme colors) => _palette(colors).panel;

  /// Buttons and tiles on top of the panel.
  static Color raised(ColorScheme colors) => _palette(colors).raised;
}

/// Builds the panel beside the rail; lists end [bottomInset] above the
/// bottom so the floating user panel doesn't cover their last rows.
typedef PhoneHomePanelBuilder =
    Widget Function(BuildContext context, double bottomInset);

/// The phone home, edge to edge: the circle rail runs down the left from
/// under the status bar, a white panel with a 28 top-left corner fills the
/// rest, and the glass user panel floats at the bottom across both, above
/// the home indicator (with the voice panel above it during a call).
class PhoneHomeFrame extends ConsumerStatefulWidget {
  const PhoneHomeFrame({
    required this.panelBuilder,
    this.homeSelected = false,
    this.selectedCircleId,
    super.key,
  });

  final PhoneHomePanelBuilder panelBuilder;

  /// Whether the rail highlights Home.
  final bool homeSelected;

  /// The circle the rail highlights.
  final String? selectedCircleId;

  static const panelRadius = WeCordRadii.xxl;

  @override
  ConsumerState<PhoneHomeFrame> createState() => _PhoneHomeFrameState();
}

class _PhoneHomeFrameState extends ConsumerState<PhoneHomeFrame>
    with WidgetsBindingObserver {
  static const _gap = 10.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The keyboard coming and going; a scaffold above may already have
  /// taken it out of this frame's MediaQuery.
  @override
  void didChangeMetrics() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Height of the floating panels, measured after layout.
  var _floatingHeight = FloatingUserPanel.phoneHeight;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final padding = MediaQuery.paddingOf(context);
    // The panel starts just under the status bar; the rail's first item a
    // little lower.
    final panelTop = math.max(padding.top, 12.0);
    // On phones with a home indicator the user panel sits just above it.
    final floatingBottom = math.max(padding.bottom, 12.0);
    // While the keyboard is up the floating panels hide, so they don't
    // sit over the list's rows. The frame stops above the keyboard itself
    // unless a scaffold above already made room for it.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardUp = keyboard > 0 || View.of(context).viewInsets.bottom > 0;
    final bottomInset = keyboardUp
        ? _gap
        : floatingBottom + _floatingHeight + _gap;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: WeCordTheme.overlayStyleFor(tokens.brightness),
      child: Material(
        key: const ValueKey('phone-home'),
        color: c.rail,
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: Stack(
            children: [
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(left: padding.left),
                      child: CircleRail(
                        phone: true,
                        homeSelected: widget.homeSelected,
                        selectedCircleId: widget.selectedCircleId,
                        padding: EdgeInsets.only(
                          top: panelTop + 7,
                          bottom: bottomInset + _gap,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: panelTop),
                        child: PanelSurface(
                          key: const ValueKey('phone-home-panel'),
                          child: Material(
                            type: MaterialType.transparency,
                            child: MediaQuery.removePadding(
                              context: context,
                              removeTop: true,
                              removeBottom: true,
                              removeLeft: true,
                              child: MediaQuery.removeViewInsets(
                                context: context,
                                removeBottom: true,
                                child: Builder(
                                  builder: (context) =>
                                      widget.panelBuilder(context, bottomInset),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!keyboardUp)
                Positioned(
                  left: _gap + padding.left,
                  right: _gap + padding.right,
                  bottom: floatingBottom,
                  child: _SizeReporter(
                    onSize: (size) {
                      if (mounted && size.height != _floatingHeight) {
                        setState(() => _floatingHeight = size.height);
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (ref.watch(voiceSessionProvider) != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(WeCordRadii.xl),
                            child: VoiceConnectedPanel(
                              onOpen: (session) =>
                                  context.push(voiceSessionPath(session)),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        const PhoneUserPanel(),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Calls [onSize] after layout whenever its child's size changes.
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSizeReporter(onSize);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) {
    renderObject.onSize = onSize;
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final current = size;
    if (current != _reported) {
      _reported = current;
      WidgetsBinding.instance.addPostFrameCallback((_) => onSize(current));
    }
  }
}

/// The signed-in user's name for panels: display name, else username.
String userPanelName(Profile? profile) {
  if (profile == null) {
    return '';
  }
  return profile.displayName.trim().isNotEmpty
      ? profile.displayName
      : profile.username;
}

/// "Online · Planning the weekend": presence, then the custom status.
String userPanelStatusLine(PresenceStatus presence, CustomStatus? status) {
  final custom = status?.label.trim() ?? '';
  return custom.isEmpty ? presence.label : '${presence.label} · $custom';
}

/// Opens the presence picker, with the custom status behind it.
Future<void> showUserStatusPicker(
  BuildContext context,
  WidgetRef ref,
  CustomStatus? status,
) {
  return showPresenceStatusSheet(
    context,
    onEditCustomStatus: () async {
      final saved = await showCustomStatusSheet(context, current: status);
      if (saved == true) {
        ref.invalidate(currentProfileProvider);
      }
    },
  );
}

/// The signed-in user floating in glass at the bottom of the phone home:
/// avatar with presence (opens the profile and settings), name and status
/// (opens the status picker) and a bell for notifications.
class PhoneUserPanel extends ConsumerWidget {
  const PhoneUserPanel({super.key});

  static const height = FloatingUserPanel.phoneHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final profile = ref.watch(currentProfileProvider).value;
    // Invisible (or online status hidden) shows as such here, though
    // others see the user offline.
    final presence = ref.watch(ownPresenceProvider);
    final status = activeCustomStatus(profile?.customStatus);
    final name = userPanelName(profile);
    final inboxCount = ref.watch(inboxBadgeCountProvider);

    return KeyedSubtree(
      key: const ValueKey('phone-user-panel'),
      child: FloatingUserPanel(
        key: const ValueKey('phone-user-panel-status'),
        title: name,
        subtitle: userPanelStatusLine(presence, status),
        semanticLabel: tr('Set your status'),
        onTap: profile == null
            ? null
            : () => showUserStatusPicker(context, ref, status),
        avatar: WeCordPressable(
          key: const ValueKey('phone-user-panel-avatar'),
          tooltip: tr('You'),
          semanticLabel: tr('You'),
          shape: const CircleBorder(),
          onPressed: () => context.push(SettingsScreen.path),
          builder: (context, states) => ResolvedAvatar(
            name: name,
            avatarUrl: profile?.avatarUrl,
            showPresence: true,
            presence: presence,
            ringColor: tokens.glass.solidFill,
            dotKey: ValueKey('phone-user-panel-presence-${presence.value}'),
          ),
        ),
        actions: [
          WeCordIconButton(
            key: const ValueKey('phone-notifications-button'),
            icon: Icons.notifications_none_rounded,
            tooltip: tr('Notifications'),
            variant: WeCordButtonVariant.onPaper,
            size: 46,
            iconSize: 22,
            badgeCount: inboxCount,
            onPressed: () => context.push(InboxScreen.path),
          ),
        ],
      ),
    );
  }
}
