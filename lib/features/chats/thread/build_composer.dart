part of '../chat_thread_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ThreadComposerBuild on _ChatThreadScreenState {
  /// The composer (or the selection bar) with its typing line and notices.
  Widget _buildComposerArea(
    BuildContext context,
    _ThreadFacts f,
    _HeaderActions h,
    _ThreadLayoutFacts l,
  ) {
    final _ThreadFacts(
      :currentUserId,
      :isNoteToSelf,
      :title,
      :conversationType,
      :groupDetail,
      :isDirectOrGroup,
      :canSend,
      :threadLocked,
      :slowmodeSeconds,
      :circleId,
      :canDeleteAsModerator,
      :desktop,
      :typingIds,
      :typingName,
      :composerBottomGap,
    ) = f;
    final _HeaderActions(:openWallpaper) = h;
    final _ThreadLayoutFacts(:constraints, :selecting) = l;
    final composerColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (typingIds.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(desktop ? 34 : 22, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ChatTypingIndicator(name: typingName),
            ),
          ),
        if (canSend)
          TimePhraseSuggestion(
            controller: _composerController,
            horizontalPadding: desktop ? 24 : 16,
            onConverted: () => _handleComposerChanged(_composerController.text),
          ),
        if (!canSend)
          _ReadOnlyComposerNotice(
            timedOutUntil: widget.timedOutUntil,
            threadLocked: threadLocked,
            desktop: desktop,
            bottomGap: composerBottomGap,
          )
        else
          _SlowmodeGate(
            until: _slowmodeUntil,
            builder: (context, slowmodeRemaining) => Actions(
              actions: {
                if (!kIsWeb && ref.read(clipboardFilesProvider).isSupported)
                  PasteTextIntent: _pasteFilesAction,
              },
              child: _Composer(
                focusNode: _composerFocus,
                desktop: desktop,
                bottomGap: composerBottomGap,
                hint: isNoteToSelf
                    ? tr('Send something to your devices')
                    : composerHint(conversationType, title),
                slowmodeSeconds: slowmodeSeconds,
                slowmodeRemainingSeconds: slowmodeRemaining,
                controller: _composerController,
                isSending: _isSending,
                isPickingImage: _isPickingImage,
                errorText: _sendError,
                mentionCandidates: _mentionCandidates(groupDetail),
                onSelectMention: _insertMention,
                specialMentionCandidates: _specialMentionCandidates(),
                onSelectSpecialMention: _insertSpecialMention,
                emojiCandidates: _emojiCandidates(),
                onSelectEmoji: _insertCustomEmoji,
                slashCommands: _slashCandidates(),
                botSlashCommands: _botSlashCandidates(),
                highlightedSlashIndex: _slashIndex,
                onSelectSlashCommand: _selectSlashCommand,
                onSelectBotSlashCommand: _selectBotSlashCommand,
                onComposerKey: _handleComposerKey,
                replyPreviewText: _replyingTo == null
                    ? null
                    : _activeReplyQuote?.text ??
                          replyPreviewBody(_replyingTo!, localized: true),
                isEditing: _editingMessage != null,
                onChanged: _handleComposerChanged,
                onSend: _sendMessage,
                onSchedule: _scheduleMessage,
                scheduledBanner: ScheduledMessagesBanner(
                  conversationId: widget.conversationId,
                  onOpen: _openScheduledMessages,
                ),
                aiButton: AiComposerButton(
                  circleId: circleId,
                  size: desktop ? 36 : 40,
                  onPressed: _isSending || _isSendingVoice
                      ? null
                      : _openAiRewrite,
                ),
                attachmentTray: MediaTray(
                  conversationId: widget.conversationId,
                  desktop: desktop,
                  sendEnabled: slowmodeRemaining <= 0,
                  allowViewOnce: isDirectOrGroup,
                  onSend: _sendTray,
                  onAddMore: _showAddMoreMenu,
                ),
                voiceButton: ref.watch(voiceInputAvailableProvider)
                    ? VoiceInputButton(
                        owner: widget.conversationId,
                        field: _composerController,
                        focus: _composerFocus,
                        size: desktop ? 36 : 40,
                        enabled:
                            !_isSending &&
                            !_isSendingVoice &&
                            !_isRecordingVoice,
                      )
                    : null,
                voicePanel: ref.watch(voiceInputAvailableProvider)
                    ? VoiceInputPanel(owner: widget.conversationId)
                    : null,
                menuEntries:
                    (
                      buttonContext, {
                      required compact,
                      required gifAvailable,
                    }) => ref
                        .read(composerMenuRegistryProvider)
                        .entriesFor(
                          ComposerMenuContext(
                            context: buttonContext,
                            conversationId: widget.conversationId,
                            conversationType: conversationType,
                            compact: compact,
                            gifAvailable: gifAvailable,
                            actions: ComposerMenuActions(
                              pickPhotosAndVideos: _pickPhotosAndVideos,
                              pickFiles: _pickFilesForTray,
                              createPoll: _openPollComposer,
                              createChain: _openChainComposer,
                              sendContactCard: _openContactCardPicker,
                              sendLocation: _sendLocation,
                              shareLiveLocation: _shareLiveLocation,
                              scheduleMessage: _scheduleMessage,
                              insertTime: _insertTime,
                              showEvents: _showEvents,
                              changeWallpaper: openWallpaper,
                              pickSticker: _pickAndSendSticker,
                              pickGif: _pickAndSendGif,
                              sendSilently: _canSendSilently
                                  ? _sendSilently
                                  : null,
                              draftReply: isNoteToSelf
                                  ? null
                                  : () async => _openAiDraftReply(),
                            ),
                          ),
                        ),
                onPickGif: _pickAndSendGif,
                onInsertEmoji: _pickAndInsertEmoji,
                gifAvailable: ref.watch(gifSearchAvailableProvider) != false,
                isRecordingVoice: _isRecordingVoice,
                voiceSecondsLeft: _voiceSecondsLeft,
                isSendingVoice: _isSendingVoice,
                onStartVoiceRecording: _startVoiceRecording,
                onCancelVoiceRecording: _cancelVoiceRecording,
                onSendVoiceRecording: _sendVoiceRecording,
                isVoicePaused: _isVoicePaused,
                onToggleVoicePause: _voiceRecorder is PausableVoiceRecorder
                    ? _toggleVoicePause
                    : null,
                onTrimVoiceRecording:
                    _isVoicePaused && _voiceRecorder is PausableVoiceRecorder
                    ? _trimVoiceRecording
                    : null,
                voiceTrimLabel: _voiceTrim == null
                    ? null
                    : tr('Keeps {time}', {
                        'time': voiceTrimTime(_voiceTrim!.lengthMs),
                      }),
                onCancelReply: _cancelReply,
                onCancelEdit: _cancelEdit,
                // What is left above the keyboard, so a short phone keeps
                // some of the conversation in view while typing.
                availableHeight:
                    constraints.maxHeight -
                    MediaQuery.viewInsetsOf(context).bottom,
              ),
            ),
          ),
      ],
    );
    final composerArea = selecting ? _selectionBar(f) : composerColumn;
    return composerArea;
  }
}
