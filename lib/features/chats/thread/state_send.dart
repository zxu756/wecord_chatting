part of '../chat_thread_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Sending: text, edits, the outbox, slowmode and voice messages.
extension _ThreadSendState on _ChatThreadScreenState {
  Future<void> _retryPending(OutboxEntry entry) async {
    final outbox = ref.read(outboxProvider.notifier);
    if (entry.media != null) {
      await outbox.retryMedia(entry);
    } else {
      await outbox.retry(entry.clientId);
    }
  }

  /// Long-pressing a failed message offers to delete it.
  Future<void> _discardPending(OutboxEntry entry) async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(tr('Delete unsent message?')),
        content: Text(tr("It hasn't been sent and will be removed.")),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('pending-discard-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      final outbox = ref.read(outboxProvider.notifier);
      if (entry.media != null) {
        outbox.discardMedia(entry);
      } else {
        outbox.discard(entry.clientId);
      }
    }
  }

  Future<void> _sendMessage() async {
    final body = _composerController.text.trim();
    if (body.isEmpty || _isSending) {
      return;
    }

    final editingMessage = _editingMessage;
    if (editingMessage != null) {
      await _saveEdit(editingMessage, body);
      return;
    }

    final command = parseSlashCommand(
      body,
      context: _slashContext,
      random: ref.read(slashCommandRandomProvider),
    );
    final String messageBody;
    switch (command) {
      case SlashCommandError(:final message):
        setState(() => _sendError = message);
        return;
      case SlashSetNickname(:final nickname):
        await _runSlashAction(() => _setNicknameFromCommand(nickname));
        return;
      case SlashSetStatus():
        await _runSlashAction(() => _setStatusFromCommand(command));
        return;
      case SlashOpenPoll():
        _clearComposerAfterCommand();
        await _openPollComposer();
        return;
      case SlashSendText(body: final commandBody):
        messageBody = commandBody;
      case null:
        if (parseBotSlashCommand(body, _slashContext) case (
          final command,
          final options,
        )) {
          await _runSlashAction(() => _invokeBotCommand(command, options));
          return;
        }
        messageBody = body;
    }

    if (_isSlowedDown) {
      return;
    }

    final outbox = ref.read(outboxProvider.notifier);
    if (outbox.isAvailable) {
      await _sendThroughOutbox(outbox, messageBody, composerText: body);
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
          : replyPreviewForMessage(replyingTo);
      // Mentions point into the body as sent, after emoji become tokens.
      final encodedBody = _encodeCustomEmoji(messageBody);
      await ref
          .read(chatsRepositoryProvider)
          .sendTextMessage(
            conversationId: widget.conversationId,
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
      _pendingDraftReplyId = null;
      if (mounted) {
        _saveDraft();
      }
      _refreshThread();
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

  /// Sends through the outbox: the message shows as sending at once and
  /// the composer is free again; when the network fails it is sent again
  /// later. A refusal (slowmode, AutoMod) puts the text back.
  Future<void> _sendThroughOutbox(
    OutboxNotifier outbox,
    String messageBody, {
    required String composerText,
  }) async {
    final replyingTo = _replyingTo;
    final replyPreview = replyingTo == null
        ? null
        : replyPreviewForMessage(replyingTo);
    // Mentions point into the body as sent, after emoji become tokens.
    final encodedBody = _encodeCustomEmoji(messageBody);
    final entry = outbox.enqueue(
      conversationId: widget.conversationId,
      body: encodedBody,
      replyToMessageId: replyingTo?.id,
      replyPreview: replyPreview,
      mentions: _mentionsForBody(encodedBody),
    );
    if (entry == null) {
      return;
    }
    _composerController.clear();
    _mentionDraft.clear();
    _emojiDraft.clear();
    setState(() {
      _emojiQuery = null;
      _isMentioning = false;
      _mentionQuery = '';
      _slashQuery = null;
      _replyingTo = null;
      _pendingDraftReplyId = null;
      _sendError = null;
    });
    _saveDraft();
    unawaited(_setTyping(false));
    if (!_isAtBottom || _threadData?.hasNewer == true) {
      _jumpToLatest();
    }
    final result = await outbox.sendNow(entry.clientId);
    if (!mounted) {
      return;
    }
    if (result case OutboxRefused(:final error)) {
      outbox.discard(entry.clientId);
      if (_composerController.text.isEmpty) {
        _composerController.value = TextEditingValue(
          text: composerText,
          selection: TextSelection.collapsed(offset: composerText.length),
        );
        if (replyingTo != null && _editingMessage == null) {
          _replyingTo = replyingTo;
        }
        _saveDraft();
      }
      switch (error) {
        case SlowmodeException():
          _waitOutSlowmode(error);
        case SendRefusedException():
          _showSendRefusal(error);
        default:
          setState(() {
            _sendError = tr('Could not send message. Try again.');
          });
      }
    }
  }

  Future<void> _saveEdit(ChatMessage message, String body) async {
    setState(() {
      _isSending = true;
      _sendError = null;
    });

    try {
      await ref
          .read(chatsRepositoryProvider)
          .editMessage(messageId: message.id, body: _encodeCustomEmoji(body));
      await _setTyping(false);
      _composerController.clear();
      _emojiDraft.clear();
      _emojiQuery = null;
      _editingMessage = null;
      unawaited(_restoreDraft());
      _refreshThread(messageId: message.id);
    } on SendRefusedException catch (error) {
      _showSendRefusal(error);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = tr('Could not save edit. Try again.');
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

  /// Slowmode keeps the current user from sending a new message right now.
  bool get _isSlowedDown {
    final until = _slowmodeUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  /// AutoMod or the circle's rules refused the message: says why.
  void _showSendRefusal(SendRefusedException error) {
    if (mounted) {
      setState(() => _sendError = error.toString());
    }
  }

  /// Counts down from the server's answer, which wins over the local
  /// estimate (clocks drift, and other devices may have sent meanwhile).
  void _waitOutSlowmode(SlowmodeException error) {
    if (!mounted) {
      return;
    }
    setState(() {
      _slowmodeRetryAt = DateTime.now().add(
        Duration(seconds: error.remainingSeconds),
      );
      _sendError = null;
    });
  }

  Future<void> _startVoiceRecording() async {
    if (_isRecordingVoice ||
        _isSendingVoice ||
        _isSending ||
        _editingMessage != null ||
        _isSlowedDown) {
      return;
    }

    setState(() {
      _sendError = null;
    });

    try {
      await _voiceRecorder.start();
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecordingVoice = true;
      });
      _startVoiceTimer();
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = tr(
            'Could not start recording. Check microphone access.',
          );
        });
      }
    }
  }

  /// Counts the recording down: the last [voiceCountdownSeconds] show the
  /// seconds left, and at [maxVoiceRecordingSeconds] it stops and sends
  /// what was recorded. Time is the larger of the ticks and the clock, so a
  /// timer that was held up in the background cannot let it run over.
  void _startVoiceTimer() {
    _voiceTimer?.cancel();
    _voiceTicks = 0;
    _voiceStartedAt = DateTime.now();
    _voiceSecondsLeft.value = null;
    _voiceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _voiceTicks += 1;
      final startedAt = _voiceStartedAt;
      final clock = startedAt == null
          ? 0
          : DateTime.now().difference(startedAt).inSeconds;
      final elapsed = clock > _voiceTicks ? clock : _voiceTicks;
      final left = maxVoiceRecordingSeconds - elapsed;
      if (left > voiceCountdownSeconds) {
        return;
      }
      if (left > 0) {
        _voiceSecondsLeft.value = left;
        return;
      }
      timer.cancel();
      unawaited(_sendVoiceRecording(reachedLimit: true));
    });
  }

  void _stopVoiceTimer() {
    _voiceTimer?.cancel();
    _voiceTimer = null;
    _voiceStartedAt = null;
    _voiceSecondsLeft.value = null;
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_isRecordingVoice || _isSendingVoice) {
      return;
    }

    _stopVoiceTimer();
    try {
      await _voiceRecorder.cancel();
    } finally {
      if (mounted) {
        setState(() {
          _isRecordingVoice = false;
        });
      }
    }
  }

  Future<void> _sendVoiceRecording({bool reachedLimit = false}) async {
    if (!_isRecordingVoice || _isSendingVoice) {
      return;
    }

    _stopVoiceTimer();
    setState(() {
      _isSendingVoice = true;
      _sendError = null;
    });

    try {
      final recording = await _voiceRecorder.stop();
      if (recording == null) {
        return;
      }
      await ref
          .read(chatsRepositoryProvider)
          .sendVoiceMessage(
            conversationId: widget.conversationId,
            bytes: recording.bytes,
            mimeType: recording.mimeType,
            durationMs: recording.durationMs,
          );
      _refreshThread();
      if (reachedLimit) {
        _showSnackBar(
          tr('Reached the 9 minute limit. Your voice message was sent.'),
        );
      }
    } on SlowmodeException catch (error) {
      _waitOutSlowmode(error);
    } on SendRefusedException catch (error) {
      _showSendRefusal(error);
    } on VoiceMessageTooLargeException catch (error) {
      if (mounted) {
        setState(() {
          _sendError = error.toString();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = tr('Could not send voice message. Try again.');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRecordingVoice = false;
          _isSendingVoice = false;
        });
      }
    }
  }

  VoiceMessageRecorder get _voiceRecorder =>
      _voiceMessageRecorder ?? ref.read(voiceMessageRecorderProvider);

  /// Queues the text in the composer to be sent later, at a time chosen
  /// in a sheet (quick picks or a date and time).
  Future<void> _scheduleMessage() async {
    final body = _composerController.text.trim();
    if (body.isEmpty) {
      _showSnackBar(tr('Write a message to schedule.'));
      return;
    }
    if (_editingMessage != null || _isSending) {
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
        _showSnackBar(tr("Commands can't be scheduled."));
        return;
    }
    final repeat = ValueNotifier<ScheduleRepeat?>(null);
    final when = await showWhenSheet(
      context,
      title: tr('Schedule message'),
      picks: schedulePicks,
      repeat: repeat,
    );
    final chosenRepeat = repeat.value;
    repeat.dispose();
    if (when == null || !mounted) {
      return;
    }
    final encodedBody = _encodeCustomEmoji(messageBody);
    final ScheduledMessage created;
    try {
      created = await ref
          .read(scheduledMessagesRepositoryProvider)
          .create(
            conversationId: widget.conversationId,
            body: encodedBody,
            sendAt: when,
            mentions: [
              for (final mention in _mentionsForBody(encodedBody))
                mention.toJson(),
            ],
            repeat: chosenRepeat,
          );
    } catch (error) {
      if (mounted) {
        setState(() => _sendError = scheduleErrorText(error));
      }
      return;
    }
    if (!mounted) {
      return;
    }
    // A scheduled message is a plain text message: a reply's quote is not
    // kept.
    _cancelReply();
    _clearComposerAfterCommand();
    ref.invalidate(scheduledMessagesProvider(widget.conversationId));
    // A repeating message may start later than picked (a weekdays message set
    // for a Saturday goes out on Monday): say what the server made of it.
    final firstSend = created.repeat == null ? when : created.sendAt.toLocal();
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final localizations = MaterialLocalizations.of(context);
    final first = describeWhen(
      localizations,
      firstSend,
      DateTime.now(),
      alwaysUse24HourFormat: use24,
    );
    final savedRepeat = created.repeat;
    _showSnackBar(
      savedRepeat == null
          ? tr('Scheduled for {time}', {'time': first})
          : tr('Scheduled: {rule}. Next: {time}', {
              'rule': describeRepeat(
                savedRepeat,
                localizations,
                alwaysUse24HourFormat: use24,
              ),
              'time': first,
            }),
    );
  }

  Future<void> _setTyping(bool isTyping) async {
    // Nobody else is in the note to self to see it.
    if (_isNoteToSelf || _isTypingShared == isTyping) {
      return;
    }
    _isTypingShared = isTyping;
    var repository = _typingRepository;
    if (repository == null) {
      repository = ref.read(chatsRepositoryProvider);
      _typingRepository = repository;
    }
    final activeRepository = repository!;
    await activeRepository
        .setTyping(conversationId: widget.conversationId, isTyping: isTyping)
        .catchError((Object _) {});
  }
}
