import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/safety/link_check_repository.dart';
import 'package:wecord/features/safety/link_risk.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Shows the warning page for a link that looks unsafe and answers whether
/// the person chose to open it anyway. Going back (or the system back
/// gesture) is "no".
Future<bool> showLinkWarning(
  BuildContext context, {
  required Uri uri,
  required LinkRisk risk,
  String? redirectHost,
  String? conversationId,
  String? circleId,
}) async {
  final open = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (context) => LinkWarningScreen(
        uri: uri,
        risk: risk,
        redirectHost: redirectHost,
        conversationId: conversationId,
        circleId: circleId,
      ),
    ),
  );
  return open ?? false;
}

/// The words for each reason a link looks risky.
String linkRiskReasonText(LinkRiskReason reason) => switch (reason) {
  LinkRiskReason.credentialsInUrl => tr(
    'What comes before the @ in the address is not the website you will visit.',
  ),
  LinkRiskReason.ipAddress => tr(
    'It points to a number instead of a website name.',
  ),
  LinkRiskReason.punycode => tr('The website name uses look-alike characters.'),
  LinkRiskReason.shortLink => tr(
    "It is a short link, so you can't see where it goes.",
  ),
  LinkRiskReason.lookalikeBrand => tr(
    "The name looks like a well-known site, but it isn't.",
  ),
  LinkRiskReason.brandInSubdomain => tr(
    "A well-known site's name is used to hide the real address.",
  ),
  LinkRiskReason.riskyTld => tr(
    'It ends in an extension often used by throwaway sites.',
  ),
  LinkRiskReason.loginWords => tr(
    'The address asks you to log in, verify or claim something.',
  ),
  LinkRiskReason.manySubdomains => tr('The address is unusually long.'),
  LinkRiskReason.manyHyphens => tr('The name is stuffed with hyphens.'),
  LinkRiskReason.downloadFile => tr('It downloads an app or a program.'),
  LinkRiskReason.plainHttpLogin => tr(
    "The page isn't encrypted (http), yet it asks for something.",
  ),
  LinkRiskReason.redirectsRisky => tr('It sends you on to a riskier address.'),
};

/// "This link looks unsafe": what is odd about the address, an optional
/// "Ask AI" second opinion, and a choice that defaults to not opening it.
class LinkWarningScreen extends ConsumerStatefulWidget {
  const LinkWarningScreen({
    required this.uri,
    required this.risk,
    this.redirectHost,
    this.conversationId,
    this.circleId,
    super.key,
  });

  final Uri uri;
  final LinkRisk risk;

  /// Where the link ends after its redirects, when that is another host.
  final String? redirectHost;

  /// The chat the link was in, for the circle's and the group's AI switches.
  final String? conversationId;
  final String? circleId;

  @override
  ConsumerState<LinkWarningScreen> createState() => _LinkWarningScreenState();
}

class _LinkWarningScreenState extends ConsumerState<LinkWarningScreen> {
  LinkCheckResult? _answer;
  Object? _error;
  var _asking = false;

  Future<void> _ask() async {
    setState(() {
      _asking = true;
      _error = null;
    });
    try {
      final answer = await ref
          .read(linkCheckRepositoryProvider)
          .check(
            url: widget.uri.toString(),
            chinese: AppStrings.isChinese,
            conversationId: widget.conversationId,
          );
      if (mounted) {
        setState(() {
          _answer = answer;
          _asking = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _asking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final host = displayHost(widget.uri);
    final canAsk = ref.watch(aiAvailableProvider(widget.circleId));
    final redirectHost = widget.redirectHost;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: c.dangerSoft,
                        borderRadius: BorderRadius.circular(WeCordRadii.xl),
                      ),
                      child: ExcludeSemantics(
                        child: Icon(
                          Icons.gpp_maybe_rounded,
                          size: 30,
                          color: c.dangerText,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    header: true,
                    child: Text(
                      tr('This link looks unsafe'),
                      key: const ValueKey('link-warning-title'),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        color: c.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      'WeCord looked at the address only, not at the page. '
                      'Open it only if you trust the person who sent it.',
                    ),
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: c.muted,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    key: const ValueKey('link-warning-address'),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.well,
                      borderRadius: BorderRadius.circular(WeCordRadii.lg),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('This link goes to'),
                          style: TextStyle(fontSize: 12.5, color: c.muted),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          host,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.uri.toString(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: c.muted,
                          ),
                        ),
                        if (redirectHost != null && redirectHost != host) ...[
                          const SizedBox(height: 10),
                          Text(
                            tr('Then it redirects to {host}', {
                              'host': redirectHost,
                            }),
                            key: const ValueKey('link-warning-redirect'),
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: c.dangerText,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    tr('Why it looks risky'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final reason in widget.risk.reasons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: ExcludeSemantics(
                              child: Icon(
                                Icons.error_outline_rounded,
                                size: 18,
                                color: c.warningText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              linkRiskReasonText(reason),
                              style: TextStyle(
                                fontSize: 14.5,
                                height: 1.4,
                                color: c.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (canAsk) ...[
                    const SizedBox(height: 12),
                    _AiSecondOpinion(
                      asking: _asking,
                      answer: _answer,
                      error: _error,
                      onAsk: () => unawaited(_ask()),
                    ),
                  ],
                  const SizedBox(height: 24),
                  WeCordButton(
                    key: const ValueKey('link-warning-back'),
                    label: tr('Go back'),
                    expand: true,
                    autofocus: true,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(height: 8),
                  WeCordButton(
                    key: const ValueKey('link-warning-open'),
                    label: tr('Open anyway'),
                    variant: WeCordButtonVariant.ghost,
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AiSecondOpinion extends StatelessWidget {
  const _AiSecondOpinion({
    required this.asking,
    required this.answer,
    required this.error,
    required this.onAsk,
  });

  final bool asking;
  final LinkCheckResult? answer;
  final Object? error;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final answer = this.answer;
    if (answer == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WeCordButton(
            key: const ValueKey('link-warning-ask-ai'),
            label: tr('Ask AI to check this link'),
            icon: Icons.auto_awesome_rounded,
            variant: WeCordButtonVariant.secondary,
            loading: asking,
            onPressed: onAsk,
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              'Sends the address (without anything after a ?) and the '
              "page's title to the AI. Nothing from your chat.",
            ),
            style: TextStyle(fontSize: 12.5, height: 1.4, color: c.muted),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              key: const ValueKey('link-warning-ai-error'),
              aiErrorMessage(error!),
              style: TextStyle(fontSize: 13.5, color: c.dangerText),
            ),
          ],
        ],
      );
    }
    final (label, tint, soft) = switch (answer.verdict) {
      LinkVerdict.safe => (
        tr('AI thinks it looks fine'),
        c.successText,
        c.successSoft,
      ),
      LinkVerdict.suspicious => (
        tr('AI finds it suspicious'),
        c.warningText,
        c.warningSoft,
      ),
      LinkVerdict.dangerous => (
        tr('AI thinks it is dangerous'),
        c.dangerText,
        c.dangerSoft,
      ),
      LinkVerdict.unknown => (tr("AI can't tell"), c.muted, c.raised),
    };
    return Container(
      key: const ValueKey('link-warning-ai-answer'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Icon(Icons.auto_awesome_rounded, size: 16, color: tint),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: tint,
                  ),
                ),
              ),
            ],
          ),
          if (answer.reason case final reason?) ...[
            const SizedBox(height: 4),
            Text(
              reason,
              style: TextStyle(fontSize: 14, height: 1.4, color: c.ink),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            tr('AI can be wrong. It has not opened the link.'),
            style: TextStyle(fontSize: 12.5, color: c.muted),
          ),
        ],
      ),
    );
  }
}
