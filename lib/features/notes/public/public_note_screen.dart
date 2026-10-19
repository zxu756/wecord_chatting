import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wecord/features/notes/note_history.dart' show NoteBlocksPreview;
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/public/page_meta.dart';
import 'package:wecord/features/notes/public/public_note.dart';
import 'package:wecord/features/notes/public/public_note_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A published note, read only, for anybody holding the link (`/n/<token>`):
/// no account, no comments, no history. It asks search engines not to list it
/// unless the author chose otherwise, and does not pass the link on to the
/// sites it links to.
class PublicNoteScreen extends ConsumerStatefulWidget {
  const PublicNoteScreen({required this.token, super.key});

  final String token;

  @override
  ConsumerState<PublicNoteScreen> createState() => _PublicNoteScreenState();
}

class _PublicNoteScreenState extends ConsumerState<PublicNoteScreen> {
  @override
  void initState() {
    super.initState();
    // Not listed until the note says the author wants it to be.
    setPublicPageMeta(allowIndexing: false);
  }

  @override
  void dispose() {
    clearPublicPageMeta();
    super.dispose();
  }

  Future<void> _open(String url) async {
    if (!isSafeWebLink(url)) {
      return;
    }
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _goHome() {
    final router = GoRouter.maybeOf(context);
    router?.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final note = ref.watch(publicNoteProvider(widget.token));
    ref.listen(publicNoteProvider(widget.token), (previous, next) {
      final data = next.value;
      if (data != null) {
        setPublicPageMeta(
          allowIndexing: data.allowIndexing,
          title: data.title.isEmpty ? tr('Untitled') : data.title,
        );
      }
    });

    Widget body = note.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      error: (error, stackTrace) => error is PublicNoteGoneException
          ? _Message(
              key: const ValueKey('public-note-gone'),
              icon: Icons.link_off_rounded,
              title: tr('This page is not available'),
              message: tr(
                'The link may have been turned off, or the note was '
                'deleted.',
              ),
              action: WeCordButton(
                label: tr('Open WeCord'),
                size: WeCordButtonSize.medium,
                onPressed: _goHome,
              ),
            )
          : _Message(
              key: const ValueKey('public-note-error'),
              icon: Icons.cloud_off_rounded,
              title: tr('Could not open the page'),
              message: tr('Check your connection and try again.'),
              action: WeCordButton(
                label: tr('Try again'),
                size: WeCordButtonSize.medium,
                onPressed: () =>
                    ref.invalidate(publicNoteProvider(widget.token)),
              ),
            ),
      data: (data) => _PublicNoteBody(
        note: data,
        onOpenLink: (url) => unawaited(_open(url)),
        onOpenApp: _goHome,
      ),
    );

    return Scaffold(
      backgroundColor: c.panel,
      body: SafeArea(child: body),
    );
  }
}

class _PublicNoteBody extends StatelessWidget {
  const _PublicNoteBody({
    required this.note,
    required this.onOpenLink,
    required this.onOpenApp,
  });

  final PublicNote note;
  final void Function(String url) onOpenLink;
  final VoidCallback onOpenApp;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final title = note.title.trim().isEmpty ? tr('Untitled') : note.title;
    final updated = note.updatedAt;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          key: const ValueKey('public-note'),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
          children: [
            Semantics(
              header: true,
              child: Text(
                '${note.icon} $title',
                style: TextStyle(
                  fontSize: 30,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: c.ink,
                ),
              ),
            ),
            if (updated != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  tr('Last edited {time}', {
                    'time': MaterialLocalizations.of(
                      context,
                    ).formatMediumDate(updated.toLocal()),
                  }),
                  style: TextStyle(fontSize: 13, color: c.subtle),
                ),
              ),
            const SizedBox(height: 18),
            NoteBlocksPreview(
              blocks: note.blocks,
              onOpenLink: onOpenLink,
              imageBuilder: (context, block) => _PublicPicture(block: block),
            ),
            const SizedBox(height: 32),
            Divider(height: 1, color: c.lineSoft),
            const SizedBox(height: 16),
            Text(
              tr(
                'This page was published from a WeCord note. Anyone with '
                'the link can read it.',
              ),
              style: TextStyle(fontSize: 13, height: 1.4, color: c.subtle),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: WeCordButton(
                label: tr('Open WeCord'),
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.small,
                onPressed: onOpenApp,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicPicture extends StatelessWidget {
  const _PublicPicture({required this.block});

  final NoteBlock block;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final url = block.props['url'];
    final name = '${block.props['name'] ?? ''}';
    Widget placeholder() => Container(
      height: 96,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      child: Icon(Icons.image_outlined, color: c.faint, size: 28),
    );
    if (url is! String || !url.startsWith('https://')) {
      return placeholder();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WeCordRadii.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: Semantics(
            image: true,
            label: name.isEmpty ? tr('Picture') : name,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              errorBuilder: (context, error, stackTrace) => placeholder(),
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: c.faint),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.5, height: 1.4, color: c.muted),
              ),
              const SizedBox(height: 18),
              action,
            ],
          ),
        ),
      ),
    );
  }
}
