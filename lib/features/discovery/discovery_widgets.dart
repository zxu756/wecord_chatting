import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/join_requests/join_gate.dart';
import 'package:wecord/features/circles/join_requests/join_request_models.dart';
import 'package:wecord/features/circles/join_requests/join_requests_repository.dart';
import 'package:wecord/features/discovery/circle_discovery_repository.dart';
import 'package:wecord/features/profile/report_user_sheet.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "1 member" / "12 members".
String discoveryMemberCount(int count) =>
    count == 1 ? tr('1 member') : tr('{count} members', {'count': count});

/// "3 online".
String discoveryOnlineCount(int count) =>
    tr('{count} online', {'count': count});

/// A circle's cover, as on its channel list: the circle's color with thin
/// diagonal lines.
class CircleCoverArt extends StatelessWidget {
  const CircleCoverArt({required this.name, this.child, super.key});

  final String name;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: WeCordAvatarColors.forSeed(name)),
      child: CustomPaint(painter: const _CoverStripesPainter(), child: child),
    );
  }
}

class _CoverStripesPainter extends CustomPainter {
  const _CoverStripesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 2;
    const gap = 18.0;
    const slope = 0.58;
    for (var x = -size.height / slope; x < size.width; x += gap) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height / slope, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CoverStripesPainter oldDelegate) => false;
}

/// The circle's squircle on a ring of the panel color, for sitting on the
/// edge of its cover.
class _RingedCircleAvatar extends StatelessWidget {
  const _RingedCircleAvatar({
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ring = size >= 64 ? 4.0 : 3.0;
    return Container(
      padding: EdgeInsets.all(ring),
      decoration: ShapeDecoration(
        color: context.tokens.colors.panel,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular((size + ring * 2) / 3),
        ),
      ),
      child: CircleNetworkAvatar(name: name, url: url, size: size, thing: true),
    );
  }
}

/// A small "#tag" pill.
class DiscoveryTagChip extends StatelessWidget {
  const DiscoveryTagChip(this.tag, {this.onPanel = true, super.key});

  final String tag;

  /// On a white panel (raised fill) rather than on a well.
  final bool onPanel;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: onPanel ? c.raised : c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.pill),
      ),
      child: Text(
        '#$tag',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: c.muted,
          height: 1.25,
        ),
      ),
    );
  }
}

/// Members and members online, with their dots.
class DiscoveryCounts extends StatelessWidget {
  const DiscoveryCounts({
    required this.memberCount,
    required this.onlineCount,
    this.fontSize = 12.5,
    super.key,
  });

  final int memberCount;
  final int onlineCount;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      color: c.muted,
    );
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PresenceDot(color: c.success, size: 8),
            const SizedBox(width: 5),
            Text(discoveryOnlineCount(onlineCount), style: style),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PresenceDot(color: c.faint, size: 8),
            const SizedBox(width: 5),
            Text(discoveryMemberCount(memberCount), style: style),
          ],
        ),
      ],
    );
  }
}

/// A public circle in the discovery grid: cover, squircle, name,
/// description, counts and tags. A "Joined" mark when the user is in it.
class DiscoveryCircleCard extends StatelessWidget {
  const DiscoveryCircleCard({
    required this.circle,
    required this.onOpen,
    super.key,
  });

  /// The card's height at the normal text size.
  static const baseHeight = 262.0;

  /// The card's height in grids and rows: [baseHeight], taller as the text
  /// size grows (the card's text takes about 110 of it).
  static double heightOf(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    return baseHeight + (scale > 1 ? (scale - 1) * 110 : 0);
  }

  final DiscoverableCircle circle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final description = circle.description?.trim() ?? '';
    final category = circle.category;
    return WeCordPressable(
      key: ValueKey('discovery-card-${circle.id}'),
      onPressed: onOpen,
      semanticLabel: circle.name,
      pressedScale: 0.98,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          curve: WeCordMotion.standard,
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(WeCordRadii.xl),
            boxShadow: hovered ? tokens.shadows.float : tokens.shadows.hairline,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 104,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      bottom: 26,
                      child: CircleCoverArt(name: circle.name),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 0,
                      child: _RingedCircleAvatar(
                        name: circle.name,
                        url: circle.avatarUrl,
                        size: 48,
                      ),
                    ),
                    if (circle.isMember)
                      Positioned(
                        right: 10,
                        top: 10,
                        child: _CoverBadge(
                          key: const ValueKey('discovery-card-joined'),
                          icon: Icons.check_rounded,
                          label: tr('Joined'),
                        ),
                      )
                    else if (category != null)
                      Positioned(
                        right: 10,
                        top: 10,
                        child: _CoverBadge(
                          icon: category.icon,
                          label: category.label,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        circle.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(
                          description.isEmpty
                              ? tr('No description yet.')
                              : description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.4,
                            color: description.isEmpty ? c.subtle : c.muted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DiscoveryCounts(
                        memberCount: circle.memberCount,
                        onlineCount: circle.onlineCount,
                      ),
                      if (circle.tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height:
                              22 *
                              math.max(
                                1,
                                MediaQuery.textScalerOf(context).scale(10) / 10,
                              ),
                          child: ClipRect(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final tag in circle.tags)
                                  DiscoveryTagChip(tag),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A white pill on a cover (category, "Joined").
class _CoverBadge extends StatelessWidget {
  const _CoverBadge({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 170),
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(WeCordRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows a public circle's preview: a sheet on phones, a centred panel on
/// wide screens. [onJoined] runs after joining (with the circle's id),
/// before the circle opens.
Future<void> showDiscoverableCirclePreview(
  BuildContext context, {
  required DiscoverableCircle circle,
  ValueChanged<String>? onJoined,
}) {
  if (circleWideLayout(context)) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final tokens = dialogContext.tokens;
        return Dialog(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          clipBehavior: Clip.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WeCordRadii.xxl),
          ),
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 760),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.colors.panel,
                borderRadius: BorderRadius.circular(WeCordRadii.xxl),
                boxShadow: tokens.shadows.dialog,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(WeCordRadii.xxl),
                child: DiscoverableCirclePreviewView(
                  circle: circle,
                  onJoined: onJoined,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  return showWeCordSheet<void>(
    context,
    detents: const [0.62, 0.94],
    builder: (sheetContext, scrollController) => DiscoverableCirclePreviewView(
      circle: circle,
      onJoined: onJoined,
      scrollController: scrollController,
      inSheet: true,
    ),
  );
}

/// A public circle before joining: cover, name, counts, description and
/// tags, its rules (when onboarding is on), the channels a new member
/// sees, and Join (or Open when already a member).
class DiscoverableCirclePreviewView extends ConsumerStatefulWidget {
  const DiscoverableCirclePreviewView({
    required this.circle,
    this.onJoined,
    this.scrollController,
    this.inSheet = false,
    super.key,
  });

  /// What the list knows, shown while the preview loads.
  final DiscoverableCircle circle;
  final ValueChanged<String>? onJoined;
  final ScrollController? scrollController;
  final bool inSheet;

  @override
  ConsumerState<DiscoverableCirclePreviewView> createState() =>
      _DiscoverableCirclePreviewViewState();
}

class _DiscoverableCirclePreviewViewState
    extends ConsumerState<DiscoverableCirclePreviewView> {
  var _joining = false;
  var _cancelling = false;
  String? _error;

  /// Answers to the circle's questions, by question id.
  var _answers = <String, String>{};

  String get _circleId => widget.circle.id;

  JoinStateKey get _joinKey => (circleId: _circleId, inviteCode: null);

  Future<void> _join(CircleJoinState? state) async {
    setState(() {
      _joining = true;
      _error = null;
    });
    final String circleId;
    try {
      circleId = await ref
          .read(circleDiscoveryRepositoryProvider)
          .join(
            _circleId,
            answers: (state?.needsReview ?? false) ? _answers : null,
          );
    } on DiscoveryJoinException catch (error) {
      if (mounted) {
        setState(() {
          _joining = false;
          _error = error.message;
        });
        ref
          ..invalidate(discoverableCirclePreviewProvider(_circleId))
          ..invalidate(circleJoinStateProvider(_joinKey));
      }
      return;
    }
    WeCordHaptics.medium();
    ref.invalidate(circleSummariesProvider);
    ref.invalidate(discoverableCirclePreviewProvider(_circleId));
    if (state?.needsReview ?? false) {
      // A request was made, not a membership: show it waiting (unless the
      // server let the person straight in).
      ref
        ..invalidate(circleJoinStateProvider(_joinKey))
        ..invalidate(myJoinRequestsProvider);
      final after = await ref.read(circleJoinStateProvider(_joinKey).future);
      if (!mounted) {
        return;
      }
      if (!(after?.isMember ?? false)) {
        setState(() => _joining = false);
        return;
      }
    }
    widget.onJoined?.call(circleId);
    if (!mounted) {
      return;
    }
    _openCircle(circleId);
  }

  Future<void> _cancelRequest() async {
    setState(() => _cancelling = true);
    try {
      await ref.read(joinRequestsRepositoryProvider).cancel(_circleId);
    } on Object {
      // The next look at the state shows where it stands.
    }
    ref
      ..invalidate(circleJoinStateProvider(_joinKey))
      ..invalidate(myJoinRequestsProvider);
    if (mounted) {
      setState(() => _cancelling = false);
    }
  }

  /// The questions to answer, or where the request stands.
  Widget _joinPanel(CircleJoinState state) {
    final c = context.tokens.colors;
    if (state.isPending ||
        state.isDenied ||
        state.closed ||
        (state.mode == CircleJoinMode.inviteOnly)) {
      return JoinStatusPanel(
        state: state,
        viaInvite: false,
        cancelling: _cancelling,
        onCancel: () => unawaited(_cancelRequest()),
      );
    }
    if (!state.needsReview) {
      return const SizedBox.shrink();
    }
    return Column(
      key: const ValueKey('discovery-join-questions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          state.questions.isEmpty
              ? tr('The moderators of this circle approve everyone who joins.')
              : tr(
                  'The moderators of this circle approve everyone who joins. '
                  'Answer their questions to send your request.',
                ),
          style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
        ),
        if (state.questions.isNotEmpty) ...[
          const SizedBox(height: 14),
          JoinQuestionsForm(
            questions: state.questions,
            enabled: !_joining,
            onChanged: (answers) => setState(() => _answers = answers),
          ),
        ],
      ],
    );
  }

  void _openCircle(String circleId) {
    final router = GoRouter.maybeOf(context);
    Navigator.of(context).pop();
    router?.go('${CircleRoutes.path}/$circleId');
  }

  Future<void> _report(String name) async {
    final reported = await showReportSheet(
      context,
      title: tr('Report {name}', {'name': name}),
      onSubmit: (reason, details) => ref
          .read(circleDiscoveryRepositoryProvider)
          .report(circleId: _circleId, reason: reason, details: details),
    );
    if (reported == true && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(tr('Thanks. We will review this circle.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final preview = ref.watch(discoverableCirclePreviewProvider(_circleId));
    final loaded = preview.value;
    final circle = loaded?.circle ?? widget.circle;
    // Where the person stands in joining: null while unknown, then Join
    // works the way it always did and the server decides.
    final joinState = circle.isMember
        ? null
        : ref.watch(circleJoinStateProvider(_joinKey)).value;
    final description = circle.description?.trim() ?? '';
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final body = <Widget>[
      SizedBox(
        height: 150,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              bottom: 40,
              child: CircleCoverArt(name: circle.name),
            ),
            Positioned(
              left: 20,
              bottom: 0,
              child: _RingedCircleAvatar(
                name: circle.name,
                url: circle.avatarUrl,
                size: 72,
              ),
            ),
            Positioned(
              right: 12,
              top: 12,
              child: _PreviewMenuButton(
                onReport: () => unawaited(_report(circle.name)),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                circle.name,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: c.ink,
                ),
              ),
            ),
            const SizedBox(height: 6),
            DiscoveryCounts(
              memberCount: circle.memberCount,
              onlineCount: circle.onlineCount,
              fontSize: 13,
            ),
            if (circle.category != null || circle.language != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (circle.category case final category?)
                    _InfoPill(icon: category.icon, label: category.label),
                  if (circle.language case final language?)
                    _InfoPill(
                      icon: Icons.translate_rounded,
                      label: DiscoveryLanguages.label(language),
                    ),
                ],
              ),
            ],
            if (description.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                description,
                style: TextStyle(fontSize: 15, height: 1.45, color: c.ink),
              ),
            ],
            if (circle.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in circle.tags) DiscoveryTagChip(tag),
                ],
              ),
            ],
          ],
        ),
      ),
      ...switch (preview) {
        AsyncData(:final value) => _details(context, value),
        AsyncError() => [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Text(
              tr('Could not load this circle.'),
              style: TextStyle(fontSize: 14, color: c.dangerText),
            ),
          ),
        ],
        _ => [
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      },
      if (joinState != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: _joinPanel(joinState),
        ),
      const SizedBox(height: 16),
    ];

    final scroll = ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.zero,
      shrinkWrap: !widget.inSheet,
      children: body,
    );

    final action = Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        16 + (widget.inSheet ? bottomInset : 0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error case final error?) ...[
            Text(
              error,
              key: const ValueKey('discovery-join-error'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: c.dangerText),
            ),
            const SizedBox(height: 10),
          ],
          _primaryAction(loaded, circle, joinState),
        ],
      ),
    );

    return Material(
      color: c.panel,
      child: Column(
        mainAxisSize: widget.inSheet ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.inSheet)
            Expanded(child: scroll)
          else
            Flexible(child: scroll),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.lineSoft)),
            ),
            child: action,
          ),
        ],
      ),
    );
  }

  Widget _primaryAction(
    DiscoverableCirclePreview? preview,
    DiscoverableCircle circle,
    CircleJoinState? joinState,
  ) {
    if (preview?.isBanned ?? false) {
      return WeCordButton(
        key: const ValueKey('discovery-banned'),
        label: tr("You're banned from this circle."),
        variant: WeCordButtonVariant.secondary,
        size: WeCordButtonSize.large,
        expand: true,
        onPressed: null,
      );
    }
    if (circle.isMember) {
      return WeCordButton(
        key: const ValueKey('discovery-open'),
        label: tr('Open'),
        size: WeCordButtonSize.large,
        expand: true,
        onPressed: () => _openCircle(circle.id),
      );
    }
    final plan = planJoinButton(
      joinState,
      viaInvite: false,
      now: DateTime.now().toUtc(),
    );
    final needsAnswers =
        plan.kind == JoinButtonKind.sendRequest &&
        !joinAnswersComplete(joinState!.questions, _answers);
    return WeCordButton(
      key: const ValueKey('discovery-join'),
      label: _joining
          ? (plan.kind == JoinButtonKind.sendRequest
                ? tr('Sending…')
                : tr('Joining…'))
          : plan.label,
      icon: plan.enabled ? Icons.add_rounded : null,
      variant: plan.enabled
          ? WeCordButtonVariant.accent
          : WeCordButtonVariant.secondary,
      size: WeCordButtonSize.large,
      expand: true,
      loading: _joining,
      onPressed: _joining || preview == null || !plan.enabled || needsAnswers
          ? null
          : () => unawaited(_join(joinState)),
    );
  }

  List<Widget> _details(
    BuildContext context,
    DiscoverableCirclePreview preview,
  ) {
    final c = context.tokens.colors;
    return [
      if (preview.rules.isNotEmpty) ...[
        _SectionTitle(tr('Rules')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            key: const ValueKey('discovery-preview-rules'),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
            decoration: BoxDecoration(
              color: c.well,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, rule) in preview.rules.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.accentSoft,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: c.accentText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            rule,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: c.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            tr('You accept these rules after joining, before you can chat.'),
            style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.4),
          ),
        ),
      ],
      if (preview.channels.isNotEmpty) ...[
        _SectionTitle(tr('Channels')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            key: const ValueKey('discovery-preview-channels'),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: c.well,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            child: Column(
              children: [
                for (final channel in preview.channels)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Icon(channel.icon, size: 18, color: c.subtle),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: c.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.tokens.colors.subtle,
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(WeCordRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: c.muted),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewMenuButton extends StatelessWidget {
  const _PreviewMenuButton({required this.onReport});

  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return WeCordPressable(
      key: const ValueKey('discovery-preview-menu'),
      tooltip: tr('More'),
      semanticLabel: tr('More'),
      shape: const CircleBorder(),
      pressedScale: 0.92,
      onPressed: () async {
        final box = context.findRenderObject() as RenderBox?;
        final choice = await showCircleActionMenu<String>(
          context,
          position: box?.localToGlobal(box.size.bottomRight(Offset.zero)),
          items: [
            CircleMenuItem(
              value: 'report',
              label: tr('Report circle'),
              icon: Icons.flag_outlined,
              destructive: true,
            ),
          ],
        );
        if (choice == 'report') {
          onReport();
        }
      },
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: hovered ? 0.36 : 0.25),
          ),
          child: const Icon(
            Icons.more_horiz_rounded,
            size: 20,
            color: Colors.white,
          ),
        );
      },
    );
  }
}
