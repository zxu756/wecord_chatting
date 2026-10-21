import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/events/chat_events_providers.dart';
import 'package:wecord/features/chats/time_tokens/time_token.dart';
import 'package:wecord/features/circles/circle_events_screen.dart';
import 'package:wecord/shared/models/event_extras.dart';
import 'package:wecord/features/events2/events2_repository.dart';
import 'package:wecord/features/qr/qr_card.dart';
import 'package:wecord/features/qr/qr_link_handler.dart' show openQrScanner;
import 'package:wecord/shared/config/site_url.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Where a check-in link opens in the app (and on the web, after the site's
/// origin): `/checkin/<code>`.
const checkInRoutePrefix = '/checkin';

String checkInPath(String code) => '$checkInRoutePrefix/$code';

/// The link an event's check-in QR code carries.
String checkInUrl(String code, {String? site}) {
  return '${site ?? authRedirectUrl()}${checkInPath(code)}';
}

final _bareCodePattern = RegExp(r'^[a-z0-9]{12}$');
final _linkCodePattern = RegExp(r'^/checkin/([A-Za-z0-9]{12})/?$');

/// The code of a check-in path (`/checkin/<code>`), or null.
String? parseCheckInPath(String path) {
  return _linkCodePattern.firstMatch(path)?.group(1)!.toLowerCase();
}

/// Whether [input] is a bare check-in code.
bool isCheckInCode(String input) =>
    _bareCodePattern.hasMatch(input.trim().toLowerCase());

/// The route a browser's address (`https://site/checkin/<code>`) stands for,
/// or null for any other. The web app keeps its own routes after a `#`, so a
/// link without one (as people share it) needs this to find its page.
String? checkInLocationFor(Uri base) {
  if (base.fragment.isNotEmpty && base.fragment != '/') {
    return null;
  }
  final code = parseCheckInPath(base.path);
  return code == null ? null : checkInPath(code);
}

/// What an organiser shows at the door: a QR code that checks people in.
Future<void> showEventCheckInSheet(
  BuildContext context, {
  required EventKind kind,
  required String eventId,
  required String title,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Check-in code'),
    builder: (context, _) =>
        EventCheckInCodeSheet(kind: kind, eventId: eventId, title: title),
  );
}

class EventCheckInCodeSheet extends ConsumerStatefulWidget {
  const EventCheckInCodeSheet({
    required this.kind,
    required this.eventId,
    required this.title,
    super.key,
  });

  final EventKind kind;
  final String eventId;
  final String title;

  @override
  ConsumerState<EventCheckInCodeSheet> createState() =>
      _EventCheckInCodeSheetState();
}

class _EventCheckInCodeSheetState extends ConsumerState<EventCheckInCodeSheet> {
  EventCheckInCode? _code;
  EventFailure? _failure;
  var _loading = true;
  var _renewed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool renew = false}) async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final code = await ref
          .read(events2RepositoryProvider)
          .createCheckInCode(widget.kind, widget.eventId);
      if (mounted) {
        setState(() {
          _code = code;
          _renewed = renew;
        });
      }
    } on EventException catch (error) {
      if (mounted) {
        setState(() => _failure = error.failure);
      }
    } on Object {
      if (mounted) {
        setState(() => _failure = EventFailure.other);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final code = _code;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: const ValueKey('event-check-in-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: code != null
                  ? QrCard(
                      data: checkInUrl(code.code),
                      title: widget.title,
                      subtitle: tr('Check-in'),
                      hint: tr('Scan to check in'),
                      note: tr(
                        'Works until {time}. A new code cancels this one.',
                        {'time': formatClock(code.expiresAt.toLocal())},
                      ),
                      semanticLabel: tr('Check-in QR code for {name}', {
                        'name': widget.title,
                      }),
                      avatarBuilder: (size) => Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          color: c.accentSoft,
                          borderRadius: BorderRadius.circular(WeCordRadii.lg),
                        ),
                        child: Icon(
                          Icons.how_to_reg_rounded,
                          color: c.accentText,
                          size: size * 0.5,
                        ),
                      ),
                    )
                  : Container(
                      width: QrCard.width,
                      height: 300,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: c.well,
                        borderRadius: BorderRadius.circular(WeCordRadii.xxl),
                      ),
                      child: _failure != null
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _failure!.message,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: c.muted,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                WeCordButton(
                                  key: const ValueKey('event-check-in-retry'),
                                  label: tr('Try again'),
                                  size: WeCordButtonSize.small,
                                  variant: WeCordButtonVariant.secondary,
                                  onPressed: () => unawaited(_load()),
                                ),
                              ],
                            )
                          : const CircularProgressIndicator(),
                    ),
            ),
            if (_renewed)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    tr('A new code was made.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            SettingsGroup(
              color: c.well,
              children: [
                SettingsRow(
                  key: const ValueKey('event-check-in-renew'),
                  icon: Icons.refresh_rounded,
                  tone: SettingsTone.accent,
                  title: tr('Make a new code'),
                  subtitle: tr('The code on screen stops working'),
                  showChevron: false,
                  onTap: _loading ? null : () => unawaited(_load(renew: true)),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
              child: Text(
                tr(
                  'People who can see the event check in from its page, with '
                  'Scan. Check-in opens two hours before the start.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: c.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Checks the signed-in person in with a scanned or opened [code], and says
/// how it went. Returns the result, or null when it did not work.
Future<EventCheckInResult?> performEventCheckIn(
  BuildContext context,
  WidgetRef ref,
  String code,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final result = await ref.read(events2RepositoryProvider).checkIn(code);
    switch (result.kind) {
      case EventKind.chat:
        ref.invalidate(chatEventsProvider(result.scopeId));
      case EventKind.circle:
        ref.invalidate(circleEventsProvider);
    }
    if (context.mounted) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            result.already
                ? tr('You were already checked in to {title}.', {
                    'title': result.title,
                  })
                : tr('Checked in to {title}.', {'title': result.title}),
          ),
        ),
      );
    }
    return result;
  } on EventException catch (error) {
    messenger?.showSnackBar(SnackBar(content: Text(error.failure.message)));
  } on Object {
    messenger?.showSnackBar(
      SnackBar(content: Text(EventFailure.other.message)),
    );
  }
  return null;
}

/// The page of a `/checkin/<code>` link: checks the person in and says so.
class EventCheckInLinkScreen extends ConsumerStatefulWidget {
  const EventCheckInLinkScreen({required this.code, super.key});

  static const path = checkInRoutePrefix;

  final String code;

  @override
  ConsumerState<EventCheckInLinkScreen> createState() =>
      _EventCheckInLinkScreenState();
}

class _EventCheckInLinkScreenState
    extends ConsumerState<EventCheckInLinkScreen> {
  EventCheckInResult? _result;
  EventFailure? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(Future.microtask(_run));
  }

  Future<void> _run() async {
    setState(() {
      _result = null;
      _failure = null;
    });
    try {
      final result = await ref
          .read(events2RepositoryProvider)
          .checkIn(widget.code);
      switch (result.kind) {
        case EventKind.chat:
          ref.invalidate(chatEventsProvider(result.scopeId));
        case EventKind.circle:
          ref.invalidate(circleEventsProvider);
      }
      if (mounted) {
        setState(() => _result = result);
      }
    } on EventException catch (error) {
      if (mounted) {
        setState(() => _failure = error.failure);
      }
    } on Object {
      if (mounted) {
        setState(() => _failure = EventFailure.other);
      }
    }
  }

  void _openEvent(EventCheckInResult result) {
    final location = switch (result.kind) {
      EventKind.chat => '/chats/${result.scopeId}',
      EventKind.circle => CircleEventsScreen.pathFor(
        result.scopeId,
        eventId: result.eventId,
      ),
    };
    context.go(location);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final result = _result;
    final failure = _failure;
    final waiting = result == null && failure == null;
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(
        backgroundColor: c.paper,
        title: Text(tr('Check-in')),
        leading: BackButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (waiting)
                  const CircularProgressIndicator()
                else ...[
                  Icon(
                    result != null
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 56,
                    color: result != null ? c.success : c.dangerText,
                  ),
                  const SizedBox(height: 14),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      result != null
                          ? (result.already
                                ? tr('You were already checked in.')
                                : tr("You're checked in."))
                          : failure!.message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: c.ink,
                      ),
                    ),
                  ),
                  if (result != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      result.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: c.muted),
                    ),
                    const SizedBox(height: 20),
                    WeCordButton(
                      key: const ValueKey('event-check-in-open'),
                      label: tr('Open the event'),
                      variant: WeCordButtonVariant.accent,
                      size: WeCordButtonSize.large,
                      onPressed: () => _openEvent(result),
                    ),
                  ] else ...[
                    const SizedBox(height: 20),
                    WeCordButton(
                      key: const ValueKey('event-check-in-retry-link'),
                      label: tr('Try again'),
                      variant: WeCordButtonVariant.secondary,
                      size: WeCordButtonSize.large,
                      onPressed: () => unawaited(_run()),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether people can check in to an event now: from two hours before the
/// start until three hours after the end (as the server decides).
bool eventCheckInOpen({
  required DateTime startsAt,
  required DateTime endsAt,
  required DateTime now,
}) {
  return !now.isBefore(startsAt.subtract(const Duration(hours: 2))) &&
      now.isBefore(endsAt.add(const Duration(hours: 3)));
}

/// On an event: "You're checked in", or a button that scans the organiser's QR
/// code while check-in is open. Nothing otherwise.
class EventCheckInRow extends ConsumerWidget {
  const EventCheckInRow({required this.extras, required this.open, super.key});

  final EventExtras extras;

  /// See [eventCheckInOpen]; false for a cancelled event.
  final bool open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    if (extras.myCheckedIn) {
      return Row(
        key: const ValueKey('event-checked-in'),
        children: [
          Icon(Icons.check_circle_rounded, size: 20, color: c.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr("You're checked in."),
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
          ),
        ],
      );
    }
    if (!open || extras.myWaitlisted) {
      return const SizedBox.shrink();
    }
    return WeCordButton(
      key: const ValueKey('event-check-in-scan'),
      label: tr('Scan to check in'),
      icon: Icons.qr_code_scanner_rounded,
      variant: WeCordButtonVariant.secondary,
      size: WeCordButtonSize.medium,
      expand: true,
      onPressed: () => unawaited(openQrScanner(context, ref)),
    );
  }
}
