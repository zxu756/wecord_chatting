import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/actions/extract_actions_sheet.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/chats/offline/outbox.dart' show newClientId;
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/notes2_repository.dart';
import 'package:wecord/features/notes/notes_repository.dart';
import 'package:wecord/features/voice/captions/captions_controller.dart';
import 'package:wecord/features/voice/captions/recap/meeting_recap_repository.dart';
import 'package:wecord/features/voice/captions/recap/recap_note.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the recap of a call: the captions' words go to the AI, which
/// writes the key points, decisions and to-dos; the person then saves them as
/// a note in the chat's shared notes (with a note card posted in the chat)
/// and turns to-dos into tasks. Nothing leaves the device until they open
/// this, and the words are not kept afterwards.
Future<void> showMeetingRecapSheet(
  BuildContext context, {
  required CaptionTranscript transcript,
  bool useRootNavigator = false,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Call recap'),
    detents: const [0.6, 0.92],
    initialDetent: 0.85,
    useRootNavigator: useRootNavigator,
    builder: (sheetContext, scrollController) => MeetingRecapSheet(
      transcript: transcript,
      scrollController: scrollController,
    ),
  );
}

class MeetingRecapSheet extends ConsumerStatefulWidget {
  const MeetingRecapSheet({
    required this.transcript,
    this.scrollController,
    super.key,
  });

  final CaptionTranscript transcript;
  final ScrollController? scrollController;

  @override
  ConsumerState<MeetingRecapSheet> createState() => _MeetingRecapSheetState();
}

class _MeetingRecapSheetState extends ConsumerState<MeetingRecapSheet> {
  MeetingRecap? _recap;
  Object? _error;
  var _loading = true;
  var _saving = false;
  var _shared = false;
  String? _noteId;
  late final String _newNoteId = newClientId();
  final _title = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final recap = await ref
          .read(meetingRecapRepositoryProvider)
          .recap(
            conversationId: widget.transcript.conversationId,
            entries: widget.transcript.toRequestEntries(),
          );
      if (!mounted) {
        return;
      }
      _title.text = recapNoteTitle(recap.title, widget.transcript.startedAt);
      setState(() {
        _recap = recap;
        _loading = false;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  String? _nameOf(String userId) => widget.transcript.names[userId];

  Future<void> _save() async {
    final recap = _recap;
    if (recap == null || _saving) {
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      // The same id every time, so a lost answer can not make two notes.
      final noteId =
          _noteId ??
          (await ref
                  .read(notes2RepositoryProvider)
                  .createNoteFromBlocks(
                    widget.transcript.conversationId,
                    title: _title.text.trim().isEmpty
                        ? recapNoteTitle('', widget.transcript.startedAt)
                        : _title.text.trim(),
                    icon: NoteMeta.defaultIcon,
                    blocks: buildRecapNoteBlocks(
                      recap,
                      when: widget.transcript.startedAt,
                      speakers: widget.transcript.speakerCount,
                      nameOf: _nameOf,
                    ),
                    id: _newNoteId,
                  ))
              .id;
      _noteId = noteId;
      await ref
          .read(notesRepositoryProvider)
          .shareNote(noteId, widget.transcript.conversationId);
      ref.invalidate(
        conversationWorkspaceProvider(widget.transcript.conversationId),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _shared = true;
        _saving = false;
      });
      messenger?.showSnackBar(
        SnackBar(
          content: Text(tr('Recap saved as a note and shared in the chat.')),
        ),
      );
    } on Object {
      if (mounted) {
        setState(() => _saving = false);
      }
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            _noteId == null
                ? tr('Could not save the recap. Try again.')
                : tr(
                    'The note is saved, but it could not be shared in the chat. Try again.',
                  ),
          ),
        ),
      );
    }
  }

  Future<void> _makeTasks() async {
    final recap = _recap;
    if (recap == null) {
      return;
    }
    await showExtractActionsSheet(
      context,
      conversationId: widget.transcript.conversationId,
      preset: recap.actionItems,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final recap = _recap;
    final Widget body;
    if (_loading) {
      body = _RecapStatus(
        key: const ValueKey('recap-loading'),
        icon: Icons.auto_awesome_rounded,
        text: tr('Writing the recap…'),
        progress: true,
      );
    } else if (_error != null) {
      body = _RecapStatus(
        key: const ValueKey('recap-error'),
        icon: Icons.error_outline_rounded,
        text: aiErrorMessage(_error!),
        action:
            _error is AiNotConfiguredException ||
                _error is AiDisabledInCircleException ||
                _error is AiTurnedOffException
            ? null
            : WeCordButton(
                key: const ValueKey('recap-retry'),
                label: tr('Try again'),
                variant: WeCordButtonVariant.secondary,
                onPressed: () => unawaited(_load()),
              ),
      );
    } else if (recap == null || recap.isEmpty) {
      body = _RecapStatus(
        key: const ValueKey('recap-empty'),
        icon: Icons.notes_rounded,
        text: tr('There was not enough in the call to write a recap.'),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              tr(
                'WeCord AI wrote this from the captions people shared. Speech recognition can mishear, so check it before you share it. Nothing is saved until you save it.',
              ),
              style: TextStyle(fontSize: 13, height: 1.35, color: c.muted),
            ),
          ),
          WeCordTextField(
            fieldKey: const ValueKey('recap-title'),
            controller: _title,
            label: tr('Title'),
            maxLength: 80,
            enabled: !_shared,
          ),
          if (recap.summary.isNotEmpty)
            _RecapSection(
              title: tr('Summary'),
              children: [for (final point in recap.summary) _Bullet(point)],
            ),
          if (recap.decisions.isNotEmpty)
            _RecapSection(
              title: tr('Decisions'),
              children: [
                for (final decision in recap.decisions) _Bullet(decision),
              ],
            ),
          if (recap.actionItems.isNotEmpty)
            _RecapSection(
              title: tr('Action items'),
              children: [
                for (final action in recap.actionItems)
                  _Bullet(
                    recapActionLine(action, nameOf: _nameOf),
                    icon: Icons.check_box_outline_blank_rounded,
                  ),
              ],
            ),
          if (recap.truncated)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                tr('The call was long, so part of the middle was not read.'),
                style: TextStyle(fontSize: 12.5, color: c.subtle),
              ),
            ),
          const SizedBox(height: 18),
          WeCordButton(
            key: const ValueKey('recap-save'),
            label: _shared
                ? tr('Saved and shared')
                : tr('Save as a note and share in the chat'),
            icon: _shared ? Icons.check_rounded : Icons.note_add_outlined,
            expand: true,
            size: WeCordButtonSize.large,
            loading: _saving,
            onPressed: _shared ? null : () => unawaited(_save()),
          ),
          if (recap.actionItems.isNotEmpty) ...[
            const SizedBox(height: 10),
            WeCordButton(
              key: const ValueKey('recap-tasks'),
              label: tr('Make tasks from the action items'),
              icon: Icons.add_task_rounded,
              variant: WeCordButtonVariant.secondary,
              expand: true,
              size: WeCordButtonSize.large,
              onPressed: () => unawaited(_makeTasks()),
            ),
          ],
        ],
      );
    }
    return ListView(
      controller: widget.scrollController,
      shrinkWrap: widget.scrollController == null,
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: [body],
    );
  }
}

class _RecapSection extends StatelessWidget {
  const _RecapSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text, {this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 8),
            child: icon == null
                ? Text('•', style: TextStyle(fontSize: 15, color: c.muted))
                : Icon(icon, size: 17, color: c.muted),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14.5, height: 1.4, color: c.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecapStatus extends StatelessWidget {
  const _RecapStatus({
    required this.icon,
    required this.text,
    this.progress = false,
    this.action,
    super.key,
  });

  final IconData icon;
  final String text;
  final bool progress;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          if (progress)
            const SizedBox.square(
              dimension: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else
            Icon(icon, size: 30, color: c.subtle),
          const SizedBox(height: 14),
          Semantics(
            liveRegion: true,
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, height: 1.4, color: c.muted),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
