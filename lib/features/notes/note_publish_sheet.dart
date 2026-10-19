import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wecord/features/notes/notes2_models.dart';
import 'package:wecord/features/notes/notes2_repository.dart';
import 'package:wecord/features/notes/public/public_note.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the sheet where a note is published as a web page, or taken down.
Future<void> showNotePublishSheet(
  BuildContext context, {
  required String noteId,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Publish to the web'),
    builder: (context, _) => NotePublishSheet(noteId: noteId),
  );
}

/// Publishing a note makes a link anyone can open without an account. Off
/// until an editor turns it on; the sheet says what that means before it
/// does, shows the link while it is on, and turns it off for good.
class NotePublishSheet extends ConsumerStatefulWidget {
  const NotePublishSheet({required this.noteId, this.siteUrl, super.key});

  final String noteId;

  /// The site the link is on; this build's by default.
  final String? siteUrl;

  @override
  ConsumerState<NotePublishSheet> createState() => _NotePublishSheetState();
}

class _NotePublishSheetState extends ConsumerState<NotePublishSheet> {
  NotePublication? _state;
  Object? _error;
  var _busy = false;
  var _allowIndexing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final state = await ref
          .read(notes2RepositoryProvider)
          .getPublication(widget.noteId);
      if (mounted) {
        setState(() {
          _state = state;
          _allowIndexing = state.allowIndexing;
          _error = null;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  Future<void> _run(Future<NotePublication?> Function() action) async {
    setState(() => _busy = true);
    try {
      final next = await action();
      if (mounted) {
        setState(() {
          _state = next ?? const NotePublication(canPublish: true);
          _allowIndexing = next?.allowIndexing ?? false;
        });
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('That did not work. Try again.'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _publish() => _run(
    () => ref
        .read(notes2RepositoryProvider)
        .publish(widget.noteId, allowIndexing: _allowIndexing),
  );

  Future<void> _setIndexing(bool value) async {
    setState(() => _allowIndexing = value);
    if (_state?.published == true) {
      await _run(
        () => ref
            .read(notes2RepositoryProvider)
            .publish(widget.noteId, allowIndexing: value),
      );
    }
  }

  Future<void> _unpublish() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Stop sharing this page?')),
        content: Text(
          tr(
            'The link stops working at once. Publishing the note again '
            'makes a new link.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Stop sharing')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _run(() async {
      await ref.read(notes2RepositoryProvider).unpublish(widget.noteId);
      return null;
    });
  }

  String? get _link {
    final token = _state?.token;
    return token == null ? null : publicNoteUrl(token, site: widget.siteUrl);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final state = _state;
    Widget body;
    if (_error != null && state == null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr('Could not load this.'),
            style: TextStyle(color: c.dangerText),
          ),
          const SizedBox(height: 12),
          WeCordButton(
            label: tr('Try again'),
            size: WeCordButtonSize.small,
            onPressed: () {
              setState(() => _error = null);
              unawaited(_load());
            },
          ),
        ],
      );
    } else if (state == null) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    } else if (state.published) {
      body = _published(context, state);
    } else {
      body = _unpublished(context, state);
    }
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: body,
    );
  }

  Widget _warning(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      key: const ValueKey('publish-warning'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.warningSoft,
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.public_rounded, size: 20, color: c.warningText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(
                'Anyone who has the link can read this note, without an '
                'account. Comments and version history are not shown. You '
                'can turn the link off at any time.',
              ),
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: c.warningText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _indexingRow(BuildContext context, {required bool enabled}) {
    final c = context.tokens.colors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Let search engines list this page'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              Text(
                tr('Off by default: the page asks not to be listed.'),
                style: TextStyle(fontSize: 13, height: 1.35, color: c.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        WeCordSwitch(
          value: _allowIndexing,
          semanticLabel: tr('Let search engines list this page'),
          onChanged: enabled && !_busy
              ? (v) => unawaited(_setIndexing(v))
              : null,
        ),
      ],
    );
  }

  Widget _unpublished(BuildContext context, NotePublication state) {
    final c = context.tokens.colors;
    if (!state.canPublish) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          tr('Only people who can edit this note can publish it.'),
          style: TextStyle(fontSize: 14.5, height: 1.4, color: c.muted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tr(
            'Share this note with people who do not use WeCord, as a '
            'read-only web page.',
          ),
          style: TextStyle(fontSize: 14.5, height: 1.4, color: c.muted),
        ),
        const SizedBox(height: 12),
        _warning(context),
        const SizedBox(height: 14),
        _indexingRow(context, enabled: true),
        const SizedBox(height: 18),
        WeCordButton(
          key: const ValueKey('publish-button'),
          label: tr('Publish to the web'),
          expand: true,
          size: WeCordButtonSize.large,
          loading: _busy,
          onPressed: _busy ? null : () => unawaited(_publish()),
        ),
      ],
    );
  }

  Widget _published(BuildContext context, NotePublication state) {
    final c = context.tokens.colors;
    final link = _link;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.public_rounded, size: 18, color: c.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                state.publishedByName == null || state.publishedByName!.isEmpty
                    ? tr('This note is published')
                    : tr('Published by {name}', {
                        'name': state.publishedByName!,
                      }),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: c.success,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (link != null) ...[
          Container(
            key: const ValueKey('publish-link'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.raised,
              borderRadius: BorderRadius.circular(WeCordRadii.md),
            ),
            child: SelectableText(
              link,
              style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: WeCordButton(
                  label: tr('Copy link'),
                  icon: Icons.copy_rounded,
                  variant: WeCordButtonVariant.secondary,
                  size: WeCordButtonSize.medium,
                  onPressed: () {
                    unawaited(Clipboard.setData(ClipboardData(text: link)));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(content: Text(tr('Link copied.'))),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WeCordButton(
                  label: tr('Open'),
                  icon: Icons.open_in_new_rounded,
                  variant: WeCordButtonVariant.secondary,
                  size: WeCordButtonSize.medium,
                  onPressed: () => unawaited(
                    launchUrl(
                      Uri.parse(link),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ] else
          Text(
            tr('Only people who can edit this note can see the link.'),
            style: TextStyle(fontSize: 14, color: c.muted),
          ),
        const SizedBox(height: 14),
        _warning(context),
        if (state.canPublish) ...[
          const SizedBox(height: 14),
          _indexingRow(context, enabled: true),
        ],
        if (state.canWithdraw) ...[
          const SizedBox(height: 18),
          WeCordButton(
            key: const ValueKey('unpublish-button'),
            label: tr('Stop sharing'),
            variant: WeCordButtonVariant.danger,
            expand: true,
            loading: _busy,
            onPressed: _busy ? null : () => unawaited(_unpublish()),
          ),
        ],
      ],
    );
  }
}
