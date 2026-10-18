import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wecord/features/legal/legal_document.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens a policy page above the current page. A page on the app's own
/// navigator, so it also works inside the settings window and before sign-in.
Future<void> openLegalDocument(BuildContext context, LegalDocument document) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: RouteSettings(name: document.path),
      builder: (context) => LegalDocumentScreen(document: document),
    ),
  );
}

/// One policy page (`/legal/guidelines`, `/legal/privacy`, `/legal/terms`):
/// the bundled Markdown in the app's language. A link to another policy
/// (`wecord:privacy`) opens that page.
class LegalDocumentScreen extends StatefulWidget {
  const LegalDocumentScreen({required this.document, this.bundle, super.key});

  final LegalDocument document;

  /// Where the text comes from; the app's assets by default.
  final AssetBundle? bundle;

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  Future<String>? _text;
  LegalDocument? _loadedDocument;
  bool? _loadedChinese;

  /// The text of the page in the app's language; loaded again when the
  /// page or the language changes.
  Future<String> _textFor(BuildContext context) {
    final chinese = AppStrings.isChinese;
    if (_text == null ||
        _loadedDocument != widget.document ||
        _loadedChinese != chinese) {
      _loadedDocument = widget.document;
      _loadedChinese = chinese;
      _text = widget.document.load(
        bundle: widget.bundle ?? DefaultAssetBundle.of(context),
        chinese: chinese,
      );
    }
    return _text!;
  }

  void _back() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    final router = GoRouter.maybeOf(context);
    router?.go('/');
  }

  void _tapLink(String? href) {
    if (href == null) {
      return;
    }
    final uri = Uri.tryParse(href);
    if (uri == null) {
      return;
    }
    if (uri.scheme == 'wecord') {
      final target = LegalDocument.fromSlug(uri.path);
      if (target != null) {
        unawaited(openLegalDocument(context, target));
      }
      return;
    }
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SettingsPage(
      key: ValueKey('legal-${widget.document.slug}'),
      title: widget.document.title,
      onBack: _back,
      maxWidth: 760,
      children: [
        const SizedBox(height: 8),
        FutureBuilder<String>(
          future: _textFor(context),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text(
                    tr('Could not load this page.'),
                    style: TextStyle(color: c.muted),
                  ),
                ),
              );
            }
            final text = snapshot.data;
            if (text == null) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return MarkdownBody(
              key: const ValueKey('legal-body'),
              data: text,
              styleSheet: _styleSheet(context),
              onTapLink: (text, href, title) => _tapLink(href),
            );
          },
        ),
      ],
    );
  }
}

MarkdownStyleSheet _styleSheet(BuildContext context) {
  final tokens = context.tokens;
  final c = tokens.colors;
  final body = TextStyle(fontSize: 15.5, height: 1.6, color: c.ink);
  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: body,
    pPadding: const EdgeInsets.only(bottom: 2),
    a: body.copyWith(
      color: c.accentText,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: c.accentText,
    ),
    h1: TextStyle(
      fontSize: 24,
      height: 1.25,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.4,
      color: c.ink,
    ),
    h1Padding: const EdgeInsets.only(top: 16, bottom: 4),
    h2: TextStyle(
      fontSize: 18,
      height: 1.3,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.2,
      color: c.ink,
    ),
    h2Padding: const EdgeInsets.only(top: 22, bottom: 2),
    listBullet: body,
    listIndent: 20,
    strong: body.copyWith(fontWeight: FontWeight.w700),
    em: body.copyWith(fontStyle: FontStyle.italic, color: c.muted),
    // The "Draft - pending owner review" note on top of every page.
    blockquote: body.copyWith(color: c.warningText, fontSize: 14.5),
    blockquoteDecoration: BoxDecoration(
      color: c.warningSoft,
      borderRadius: BorderRadius.circular(WeCordRadii.md),
    ),
    blockquotePadding: const EdgeInsets.all(14),
  );
}
