part of '../chat_thread_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Attachments: the tray, pickers, paste and drop.
extension _ThreadAttachmentsState on _ChatThreadScreenState {
  MediaTrayController get _tray =>
      ref.read(mediaTrayProvider(widget.conversationId).notifier);

  /// Whether files can be added to the tray now: the composer is there and
  /// not busy with an edit or a slowmode wait.
  bool get _canAttach =>
      mounted &&
      _editingMessage == null &&
      !_isRecordingVoice &&
      !_isSlowedDown;

  /// Puts files (picked, dropped or pasted) in the tray above the
  /// composer.
  Future<void> _addToTray(List<XFile> files) async {
    if (files.isEmpty || !_canAttach) {
      return;
    }
    setState(() => _sendError = null);
    await _tray.add(files);
  }

  void _handlePastedFiles(List<XFile> files) {
    // Only the chat in front takes a paste, and not while a dialog or the
    // file viewer is open.
    if (ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    unawaited(_addToTray(files));
  }

  Future<void> _pickPhotosAndVideos() async {
    if (_isPickingImage || _isSending || !_canAttach) {
      return;
    }
    setState(() {
      _isPickingImage = true;
      _sendError = null;
    });
    try {
      final room = ref.read(mediaTrayProvider(widget.conversationId)).room;
      if (room <= 0) {
        return;
      }
      final files = await ref
          .read(chatMediaPickerProvider)
          .pickPhotosAndVideos(limit: room);
      await _addToTray(files);
    } catch (error) {
      if (mounted) {
        setState(() {
          _sendError = tr('Could not open your photos. Try again. {error}', {
            'error': error,
          });
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingImage = false);
      }
    }
  }

  Future<void> _pickFilesForTray() async {
    if (_isPickingImage || _isSending || !_canAttach) {
      return;
    }
    setState(() {
      _isPickingImage = true;
      _sendError = null;
    });
    try {
      final files = await ref.read(chatMediaPickerProvider).pickFiles();
      await _addToTray(files);
    } catch (error) {
      if (mounted) {
        setState(() {
          _sendError = tr('Could not open the files. Try again. {error}', {
            'error': error,
          });
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingImage = false);
      }
    }
  }

  /// The tray's "add more": the same two choices as the attach menu.
  void _showAddMoreMenu(BuildContext anchorContext) {
    showGlassMenu(
      anchorContext,
      anchor: globalRectOf(anchorContext),
      width: 232,
      entries: [
        GlassMenuEntry(
          icon: Icons.image_outlined,
          label: tr('Photos and videos'),
          onSelected: () => unawaited(_pickPhotosAndVideos()),
        ),
        GlassMenuEntry(
          icon: Icons.attach_file_rounded,
          label: tr('Files'),
          onSelected: () => unawaited(_pickFilesForTray()),
        ),
      ],
    );
  }

  /// Sends what the tray holds: photos are scaled and cleaned, everything
  /// is copied to the pending media store, and the attachments appear in
  /// the chat at once as one album, uploading with progress rings. They go
  /// out through the outbox, so they are tried again after a failure and
  /// survive closing the app (where files are kept on disk).
  Future<void> _sendTray() async {
    final tray = ref.read(mediaTrayProvider(widget.conversationId));
    if (!tray.canSend || _isSlowedDown || _editingMessage != null) {
      return;
    }
    final outbox = ref.read(outboxProvider.notifier);
    if (!outbox.isAvailable) {
      setState(() {
        _sendError = tr('Could not send message. Try again.');
      });
      return;
    }
    final controller = _tray;
    controller.setPreparing((0, tray.items.length));
    setState(() => _sendError = null);
    try {
      final items = await prepareDrafts(
        tray.items,
        original: tray.original,
        onProgress: (done, total) => controller.setPreparing((done, total)),
      );
      if (!mounted) {
        return;
      }
      final replyingTo = _replyingTo;
      final entries = await outbox.enqueueMedia(
        conversationId: widget.conversationId,
        items: items,
        caption: tray.caption.trim(),
        replyToMessageId: replyingTo?.id,
        replyPreview: replyingTo == null
            ? null
            : replyPreviewForMessage(replyingTo),
        viewOnce: tray.sendsViewOnce,
      );
      if (!mounted) {
        return;
      }
      if (entries.isEmpty) {
        controller.setPreparing(null);
        setState(() => _sendError = tr('Could not send message. Try again.'));
        return;
      }
      controller.clear();
      setState(() {
        _replyingTo = null;
        _pendingDraftReplyId = null;
      });
      _saveDraft();
      if (!_isAtBottom || _threadData?.hasNewer == true) {
        _jumpToLatest();
      }
      unawaited(outbox.startSending());
    } catch (error) {
      controller.setPreparing(null);
      if (mounted) {
        setState(() {
          _sendError = tr('Could not prepare the files. Try again. {error}', {
            'error': error,
          });
        });
      }
    }
  }
}
