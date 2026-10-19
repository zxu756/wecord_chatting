part of '../chat_thread_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Small chat touches: sending without a push (A9).
extension _ThreadChatPolishState on _ChatThreadScreenState {
  /// "Send silently" is offered where the server can do it and someone else
  /// is there to be left in peace.
  bool get _canSendSilently =>
      !_isNoteToSelf &&
      ref.read(chatsRepositoryProvider) is SilentMessageSender;

  /// Sends the text in the composer like [_sendMessage], but nobody's device
  /// is told about it. Slash commands are not messages and are not sent this
  /// way; the send does not go through the outbox, so it needs the
  /// connection (the text stays in the box when it fails).
  Future<void> _sendSilently() async {
    final body = _composerController.text.trim();
    if (body.isEmpty) {
      _showSnackBar(tr('Write a message to send silently.'));
      return;
    }
    if (_editingMessage != null || _isSending || _isSlowedDown) {
      return;
    }
    final sender = ref.read(chatsRepositoryProvider);
    if (sender is! SilentMessageSender) {
      return;
    }
    final command = parseSlashCommand(
      body,
      context: _slashContext,
      random: ref.read(slashCommandRandomProvider),
    );
    final String messageBody;
    switch (command) {
      case SlashSendText(body: final commandBody):
        messageBody = commandBody;
      case null when parseBotSlashCommand(body, _slashContext) == null:
        messageBody = body;
      default:
        _showSnackBar(tr("Commands can't be sent silently."));
        return;
    }

    final replyingTo = _replyingTo;
    setState(() {
      _isSending = true;
      _sendError = null;
    });
    try {
      final replyPreview = replyingTo == null
          ? null
          : replyPreviewForMessage(replyingTo, quote: _activeReplyQuote);
      // Mentions point into the body as sent, after emoji become tokens.
      final encodedBody = _encodeCustomEmoji(messageBody);
      await (sender as SilentMessageSender).sendSilentTextMessage(
        conversationId: widget.conversationId,
        clientId: newClientId(),
        body: encodedBody,
        replyToMessageId: replyingTo?.id,
        replyPreview: replyPreview,
        mentions: _mentionsForBody(encodedBody),
      );
      await _setTyping(false);
      _composerController.clear();
      _mentionDraft.clear();
      _emojiDraft.clear();
      _emojiQuery = null;
      _isMentioning = false;
      _mentionQuery = '';
      _slashQuery = null;
      _replyingTo = null;
      _replyQuoteFor = null;
      _pendingDraftReplyId = null;
      if (mounted) {
        _saveDraft();
      }
      _refreshThread();
      if (mounted) {
        _showSnackBar(tr('Sent silently. Nobody was notified.'));
      }
    } on SlowmodeException catch (error) {
      _waitOutSlowmode(error);
    } on SendRefusedException catch (error) {
      _showSendRefusal(error);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = tr('Could not send message. Try again.');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  // ---- voice recordings (A10) ----

  /// How long the sound of the recording has run: wall time minus pauses.
  Duration _voiceActiveElapsed() {
    final startedAt = _voiceStartedAt;
    if (startedAt == null) {
      return Duration.zero;
    }
    final now = DateTime.now();
    final pausedAt = _voicePausedAt;
    final paused =
        _voicePausedTotal +
        (pausedAt == null ? Duration.zero : now.difference(pausedAt));
    return now.difference(startedAt) - paused;
  }

  /// Pauses the recording, or carries on with it.
  Future<void> _toggleVoicePause() async {
    final Object recorder = _voiceRecorder;
    if (recorder is! PausableVoiceRecorder ||
        !_isRecordingVoice ||
        _isSendingVoice) {
      return;
    }
    if (_isVoicePaused) {
      await recorder.resume();
      final pausedAt = _voicePausedAt;
      if (pausedAt != null) {
        _voicePausedTotal += DateTime.now().difference(pausedAt);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isVoicePaused = false;
        _voicePausedAt = null;
        // New sound after the cut would be cut off by it.
        _voiceTrim = null;
      });
      return;
    }
    await recorder.pause();
    if (!mounted) {
      return;
    }
    setState(() {
      _isVoicePaused = true;
      _voicePausedAt = DateTime.now();
    });
  }

  /// Opens the trim sheet for what has been recorded so far.
  Future<void> _trimVoiceRecording() async {
    final Object recorder = _voiceRecorder;
    if (recorder is! PausableVoiceRecorder || !recorder.isPaused) {
      return;
    }
    final snapshot = recorder.snapshot();
    if (snapshot == null || snapshot.durationMs < minVoiceTrimMs) {
      _showSnackBar(tr('Record a little more to trim it.'));
      return;
    }
    final range = await showVoiceTrimSheet(
      context,
      wav: snapshot.bytes,
      initial: _voiceTrim,
    );
    if (range == null || !mounted) {
      return;
    }
    setState(() {
      _voiceTrim = range.keepsAll(snapshot.durationMs) ? null : range;
    });
  }

  /// [recording] cut to the range chosen in the trim sheet, if any.
  RecordedVoiceMessage _applyVoiceTrim(RecordedVoiceMessage recording) {
    final range = _voiceTrim;
    if (range == null || range.keepsAll(recording.durationMs)) {
      return recording;
    }
    final cut = trimWav(
      recording.bytes,
      startMs: range.startMs,
      endMs: range.endMs,
    );
    if (cut == null) {
      return recording;
    }
    return RecordedVoiceMessage(
      bytes: cut,
      mimeType: recording.mimeType,
      durationMs: math.min(range.lengthMs, recording.durationMs),
    );
  }
}
