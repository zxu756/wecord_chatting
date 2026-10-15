import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/message_author.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/inbox/inbox_screen.dart';
import 'package:wecord/features/presence/presence_indicator.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/presence/presence_status_sheet.dart';
import 'package:wecord/features/settings/custom_status_sheet.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

/// Colors of the phone home: the rail a shade darker than the panel beside
/// it, in both themes.
abstract final class PhoneHomeColors {
  static bool _light(ColorScheme colors) =>
      colors.brightness == Brightness.light;

  static Color rail(ColorScheme colors) => _light(colors)
      ? colors.surfaceContainerHigh
      : colors.surfaceContainerLowest;

  /// Rail icons that are neither selected nor hovered.
  static Color railItem(ColorScheme colors) => _light(colors)
      ? colors.surfaceContainerLowest
      : colors.surfaceContainerHigh;

  static Color panel(ColorScheme colors) => _light(colors)
      ? colors.surfaceContainerLowest
      : colors.surfaceContainerLow;

  /// Buttons, tiles and the user panel on top of the panel.
  static Color raised(ColorScheme colors) => _light(colors)
      ? colors.surfaceContainerHigh
      : colors.surfaceContainerHighest;
}

/// Builds the panel beside the rail; lists end [bottomInset] above the
/// bottom so the floating user panel doesn't cover their last rows.
typedef PhoneHomePanelBuilder =
    Widget Function(BuildContext context, double bottomInset);

/// The phone home, edge to edge: the circle rail runs down the left from
/// under the status bar, a panel with a rounded top-left corner fills the
/// rest, and the user panel floats at the bottom above the home indicator
/// (with the voice panel above it during a call).
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

  static const panelRadius = 28.0;

  @override
  ConsumerState<PhoneHomeFrame> createState() => _PhoneHomeFrameState();
}

class _PhoneHomeFrameState extends ConsumerState<PhoneHomeFrame> {
  static const _gap = 8.0;

  /// Height of the floating panels, measured after layout.
  var _floatingHeight = PhoneUserPanel.height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final padding = MediaQuery.paddingOf(context);
    final railColor = PhoneHomeColors.rail(colors);
    // On phones with a home indicator the panel sits just above it.
    final floatingBottom = padding.bottom > 0 ? padding.bottom : _gap;
    final bottomInset = floatingBottom + _floatingHeight + _gap;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: WeCordTheme.overlayStyleFor(theme.brightness),
      child: Material(
        key: const ValueKey('phone-home'),
        color: railColor,
        child: Stack(
          children: [
            Positioned.fill(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CircleRail(
                    homeSelected: widget.homeSelected,
                    selectedCircleId: widget.selectedCircleId,
                    color: railColor,
                    itemColor: PhoneHomeColors.railItem(colors),
                    padding: EdgeInsets.only(
                      top: padding.top + 4,
                      bottom: bottomInset + _gap,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: padding.top + _gap),
                      child: ClipRRect(
                        key: const ValueKey('phone-home-panel'),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(PhoneHomeFrame.panelRadius),
                        ),
                        child: Material(
                          color: PhoneHomeColors.panel(colors),
                          child: MediaQuery.removePadding(
                            context: context,
                            removeTop: true,
                            removeBottom: true,
                            removeLeft: true,
                            child: Builder(
                              builder: (context) =>
                                  widget.panelBuilder(context, bottomInset),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                        borderRadius: BorderRadius.circular(16),
                        child: VoiceConnectedPanel(
                          onOpen: (session) =>
                              context.push(voiceSessionPath(session)),
                        ),
                      ),
                      const SizedBox(height: _gap),
                    ],
                    const PhoneUserPanel(),
                  ],
                ),
              ),
            ),
          ],
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

/// The signed-in user floating at the bottom of the phone home: avatar
/// with presence (opens the profile and settings), name and status (opens
/// the status picker) and a bell for notifications.
class PhoneUserPanel extends ConsumerWidget {
  const PhoneUserPanel({super.key});

  static const height = 60.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final background = PhoneHomeColors.raised(colors);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    // Invisible (or online status hidden) shows as such here, though
    // others see the user offline.
    final presence = ref.watch(ownPresenceProvider);
    final status = activeCustomStatus(profile?.customStatus);
    final name = profile == null
        ? ''
        : profile.displayName.trim().isNotEmpty
        ? profile.displayName
        : profile.username;
    final inboxCount = ref.watch(inboxBadgeCountProvider);

    final radius = BorderRadius.circular(22);
    return DecoratedBox(
      key: const ValueKey('phone-user-panel'),
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.45 : 0.12,
            ),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: background,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: height),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Tooltip(
                  message: tr('You'),
                  child: InkResponse(
                    key: const ValueKey('phone-user-panel-avatar'),
                    radius: 24,
                    onTap: () => context.push(SettingsScreen.path),
                    child: SizedBox.square(
                      dimension: 44,
                      child: Center(
                        child: PresenceAvatar(
                          title: name,
                          avatarUrl: profile?.avatarUrl,
                          radius: 18,
                          presence: presence,
                          borderColor: background,
                          dotKey: ValueKey(
                            'phone-user-panel-presence-${presence.value}',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: InkWell(
                    key: const ValueKey('phone-user-panel-status'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: profile == null
                        ? null
                        : () => showPresenceStatusSheet(
                            context,
                            onEditCustomStatus: () async {
                              final saved = await showCustomStatusSheet(
                                context,
                                current: status,
                              );
                              if (saved == true) {
                                ref.invalidate(currentProfileProvider);
                              }
                            },
                          ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.keyboard_arrow_down,
                                size: 18,
                                color: colors.onSurfaceVariant,
                              ),
                            ],
                          ),
                          Text(
                            status?.label ?? presence.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const ValueKey('phone-notifications-button'),
                  tooltip: tr('Notifications'),
                  style: IconButton.styleFrom(
                    backgroundColor: PhoneHomeColors.panel(colors),
                    minimumSize: const Size.square(44),
                  ),
                  onPressed: () => context.push(InboxScreen.path),
                  icon: Badge(
                    isLabelVisible: inboxCount > 0,
                    label: Text(inboxCount > 99 ? '99+' : '$inboxCount'),
                    child: const Icon(Icons.notifications_none),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An avatar with a [PresenceIndicator] in its bottom-right corner,
/// outlined in [borderColor] (the background behind it).
class PresenceAvatar extends StatelessWidget {
  const PresenceAvatar({
    required this.title,
    required this.avatarUrl,
    required this.radius,
    required this.borderColor,
    this.presence,
    this.showPresence = true,
    this.dotKey,
    super.key,
  });

  final String title;
  final String? avatarUrl;
  final double radius;
  final Color borderColor;

  /// Null shows them offline.
  final PresenceStatus? presence;

  /// False hides the indicator (group chats).
  final bool showPresence;
  final Key? dotKey;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        FallbackAvatar(title: title, avatarUrl: avatarUrl, radius: radius),
        if (showPresence)
          Positioned(
            right: -2,
            bottom: -2,
            child: PresenceIndicator(
              key: dotKey,
              status: presence,
              borderColor: borderColor,
              size: (radius * 0.7).clamp(12.0, 16.0),
            ),
          ),
      ],
    );
  }
}
