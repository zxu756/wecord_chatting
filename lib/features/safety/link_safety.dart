import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/link_preview_card.dart'
    show linkPreviewProvider;
import 'package:wecord/features/safety/link_risk.dart';
import 'package:wecord/features/safety/link_warning_screen.dart';

/// Which chat a link was tapped in, so that "Ask AI" on the warning page can
/// honour that chat's circle and group AI switches. Provided around each
/// message of the chat page; absent elsewhere.
class LinkChatScope extends InheritedWidget {
  const LinkChatScope({
    required this.conversationId,
    required this.circleId,
    required super.child,
    super.key,
  });

  final String conversationId;
  final String? circleId;

  static LinkChatScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LinkChatScope>();

  @override
  bool updateShouldNotify(LinkChatScope oldWidget) =>
      conversationId != oldWidget.conversationId ||
      circleId != oldWidget.circleId;
}

/// The hosts a person chose to open anyway in this session: asking again
/// for the same host every time would only teach people to tap through.
class AllowedRiskyHosts extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void allow(String host) => state = {...state, host};
}

final allowedRiskyHostsProvider =
    NotifierProvider<AllowedRiskyHosts, Set<String>>(AllowedRiskyHosts.new);

/// What to do with a link before it opens: the address is scored by the app's
/// own rules and by what the link-preview function found out (a short link's
/// real destination), when the preview is already there. Links that look
/// high-risk get the warning page first; everything else opens at once.
///
/// Returns whether the link may open.
Future<bool> confirmLinkSafety(BuildContext context, Ref ref, Uri uri) async {
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return true;
  }
  var risk = assessLink(uri.toString());
  String? redirectHost;
  // A preview that is already loaded may know where a short link ends; this
  // never waits for one.
  final previewProvider = linkPreviewProvider(uri.toString());
  final preview = ref.exists(previewProvider)
      ? ref.read(previewProvider).value
      : null;
  if (preview != null) {
    final server = LinkRisk(
      level: LinkRiskLevel.fromName(preview.riskLevel),
      reasons: [
        for (final code in preview.riskReasons) ?LinkRiskReason.fromCode(code),
      ],
    );
    risk = risk.worst(server);
    if (server.reasons.contains(LinkRiskReason.redirectsRisky)) {
      redirectHost = preview.finalHost;
    }
  }
  if (!risk.isHigh) {
    return true;
  }
  final host = displayHost(uri);
  if (ref.read(allowedRiskyHostsProvider).contains(host)) {
    return true;
  }
  if (!context.mounted) {
    return false;
  }
  final scope = LinkChatScope.maybeOf(context);
  final open = await showLinkWarning(
    context,
    uri: uri,
    risk: risk,
    redirectHost: redirectHost,
    conversationId: scope?.conversationId,
    circleId: scope?.circleId,
  );
  if (open) {
    ref.read(allowedRiskyHostsProvider.notifier).allow(host);
  }
  return open;
}
