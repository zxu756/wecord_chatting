import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:wecord/features/whiteboard/whiteboard_controller.dart';
import 'package:wecord/features/whiteboard/whiteboard_export.dart';
import 'package:wecord/features/whiteboard/whiteboard_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The saved versions of a board: look at one, go back to it, or save one
/// by hand.
Future<void> showWhiteboardVersions(
  BuildContext context,
  WhiteboardController controller,
) {
  return showWeCordSheet<void>(
    context,
    title: tr('Earlier versions'),
    detents: const [0.6, 0.92],
    builder: (context, scrollController) => _VersionsBody(
      controller: controller,
      scrollController: scrollController,
    ),
  );
}

String whiteboardVersionKindLabel(String kind) {
  return switch (kind) {
    'manual' => tr('Saved by hand'),
    'restore' => tr('Before a restore or clear'),
    _ => tr('Saved automatically'),
  };
}

String formatWhiteboardTime(BuildContext context, DateTime time) {
  final local = time.toLocal();
  final l10n = MaterialLocalizations.of(context);
  return '${l10n.formatShortDate(local)} ${l10n.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

class _VersionsBody extends StatefulWidget {
  const _VersionsBody({required this.controller, required this.scrollController});

  final WhiteboardController controller;
  final ScrollController? scrollController;

  @override
  State<_VersionsBody> createState() => _VersionsBodyState();
}

class _VersionsBodyState extends State<_VersionsBody> {
  List<WhiteboardVersionSummary>? _versions;
  var _failed = false;
  var _busy = false;

  WhiteboardController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final versions = await c.repository.listVersions(c.boardId);
      if (mounted) {
        setState(() {
          _versions = versions;
          _failed = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  Future<void> _saveNow() async {
    setState(() => _busy = true);
    try {
      await c.flushNow();
      await c.repository.createVersion(c.boardId);
      await _load();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Could not save a version.'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _open(WhiteboardVersionSummary version) async {
    final restored = await showDialog<bool>(
      context: context,
      builder: (context) => _VersionPreview(controller: c, version: version),
    );
    if (restored == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens.colors;
    final versions = _versions;
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(
          tr(
            'WeCord keeps the latest versions of this whiteboard. Going back to one first saves the board as it is now.',
          ),
          style: TextStyle(fontSize: 14, height: 1.4, color: t.muted),
        ),
        if (c.canEdit) ...[
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: WeCordButton(
              key: const ValueKey('whiteboard-save-version'),
              label: tr('Save a version now'),
              icon: Icons.bookmark_add_outlined,
              variant: WeCordButtonVariant.secondary,
              size: WeCordButtonSize.small,
              loading: _busy,
              onPressed: () => unawaited(_saveNow()),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (_failed)
          Text(
            tr("That couldn't load. Try again."),
            style: TextStyle(fontSize: 15, color: t.muted),
          )
        else if (versions == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (versions.isEmpty)
          Text(
            tr('No earlier versions yet.'),
            style: TextStyle(fontSize: 15, color: t.muted),
          )
        else
          SettingsGroup(
            color: t.well,
            separatorIndent: 14,
            children: [
              for (final version in versions)
                SettingsRow(
                  key: ValueKey('whiteboard-version-${version.id}'),
                  title: formatWhiteboardTime(context, version.createdAt),
                  subtitle: [
                    whiteboardVersionKindLabel(version.kind),
                    if (version.label != null && version.label!.isNotEmpty)
                      version.label!,
                    tr('{count} items', {'count': version.elementCount}),
                  ].join(' · '),
                  onTap: () => unawaited(_open(version)),
                ),
            ],
          ),
      ],
    );
  }
}

class _VersionPreview extends StatefulWidget {
  const _VersionPreview({required this.controller, required this.version});

  final WhiteboardController controller;
  final WhiteboardVersionSummary version;

  @override
  State<_VersionPreview> createState() => _VersionPreviewState();
}

class _VersionPreviewState extends State<_VersionPreview> {
  Uint8List? _png;
  var _loaded = false;
  var _failed = false;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final c = widget.controller;
    try {
      final elements = await c.repository.getVersionElements(widget.version.id);
      final png = await renderWhiteboardPng(elements, c.images);
      if (mounted) {
        setState(() {
          _png = png;
          _loaded = true;
        });
      }
    } on Object {
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  Future<void> _restore() async {
    final c = widget.controller;
    setState(() => _busy = true);
    try {
      await c.flushNow();
      await c.repository.restoreVersion(widget.version.id);
      await c.reload();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Object {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Could not go back to this version.'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens.colors;
    return AlertDialog(
      title: Text(formatWhiteboardTime(context, widget.version.createdAt)),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_failed)
                Text(tr("That couldn't load. Try again."))
              else if (!_loaded)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_png == null)
                Text(
                  tr('This version was empty.'),
                  style: TextStyle(color: t.muted),
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _png!,
                    fit: BoxFit.contain,
                    semanticLabel: tr('Preview of this version'),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(tr('Close')),
        ),
        if (widget.controller.canManage)
          TextButton(
            key: const ValueKey('whiteboard-restore-version'),
            onPressed: _busy || !_loaded ? null : () => unawaited(_restore()),
            child: Text(tr('Go back to this version')),
          ),
      ],
    );
  }
}
