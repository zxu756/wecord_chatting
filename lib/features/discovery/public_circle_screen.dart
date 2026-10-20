import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/discovery/circle_discovery_repository.dart';
import 'package:wecord/features/discovery/discovery_widgets.dart';
import 'package:wecord/features/discovery/public_circle_link.dart';
import 'package:wecord/features/discovery/public_circle_repository.dart';
import 'package:wecord/features/home/home_screen.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// `/c/<slug>` in the app: the page the "Open in WeCord" button of a public
/// circle's web page leads to. A member goes straight into the circle; anyone
/// else sees the circle's preview (rules, channels, join or request to join),
/// the same one Explore opens. A circle that is private, taken down or gone
/// is "not available", the same page for all of them.
class PublicCircleScreen extends ConsumerWidget {
  const PublicCircleScreen({required this.slug, super.key});

  static const path = publicCircleRoutePrefix;

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = ref.watch(resolvedCircleSlugProvider(slug));
    return CirclePageScaffold(
      title: tr('Circle'),
      constrainBody: false,
      body: resolved.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => CircleEmptyState(
          icon: Icons.error_outline_rounded,
          title: tr('Could not load this circle'),
          message: errorText(error),
          action: WeCordButton(
            variant: WeCordButtonVariant.onPaper,
            onPressed: () => ref.invalidate(resolvedCircleSlugProvider(slug)),
            label: tr('Try again'),
          ),
        ),
        data: (circle) {
          if (circle == null) {
            return CircleEmptyState(
              icon: Icons.link_off_rounded,
              title: tr('This circle is not available'),
              message: tr(
                'The link may be wrong, or the circle may not be public.',
              ),
              action: WeCordButton(
                variant: WeCordButtonVariant.onPaper,
                onPressed: () => context.go(HomeScreen.path),
                label: tr('Back to home'),
              ),
            );
          }
          if (circle.isMember) {
            return _GoToCircle(circleId: circle.circleId);
          }
          return _PublicCircleBody(circleId: circle.circleId);
        },
      ),
    );
  }
}

/// Sends a member on to their circle once the page is up.
class _GoToCircle extends StatefulWidget {
  const _GoToCircle({required this.circleId});

  final String circleId;

  @override
  State<_GoToCircle> createState() => _GoToCircleState();
}

class _GoToCircleState extends State<_GoToCircle> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.go('${CircleRoutes.path}/${widget.circleId}');
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _PublicCircleBody extends ConsumerStatefulWidget {
  const _PublicCircleBody({required this.circleId});

  final String circleId;

  @override
  ConsumerState<_PublicCircleBody> createState() => _PublicCircleBodyState();
}

class _PublicCircleBodyState extends ConsumerState<_PublicCircleBody> {
  var _shown = false;

  void _open(DiscoverableCircle circle) {
    unawaited(showDiscoverableCirclePreview(context, circle: circle));
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(
      discoverableCirclePreviewProvider(widget.circleId),
    );
    return preview.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => CircleEmptyState(
        icon: Icons.link_off_rounded,
        title: tr('This circle is not available'),
        message: tr('The link may be wrong, or the circle may not be public.'),
        action: WeCordButton(
          variant: WeCordButtonVariant.onPaper,
          onPressed: () => context.go(HomeScreen.path),
          label: tr('Back to home'),
        ),
      ),
      data: (data) {
        final circle = data.circle;
        if (!_shown) {
          _shown = true;
          // The preview opens by itself, as it would from Explore; closing it
          // leaves the circle's card below.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _open(circle);
            }
          });
        }
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: SizedBox(
                height: DiscoveryCircleCard.heightOf(context),
                child: DiscoveryCircleCard(
                  circle: circle,
                  onOpen: () => _open(circle),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
