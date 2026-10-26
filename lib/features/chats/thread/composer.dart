part of '../chat_thread_screen.dart';

// The composer pill and the buttons in it.

class _Composer extends StatelessWidget {
  const _Composer({
    required this.focusNode,
    required this.desktop,
    required this.bottomGap,
    required this.hint,
    required this.slowmodeSeconds,
    required this.slowmodeRemainingSeconds,
    required this.controller,
    required this.isSending,
    required this.isPickingImage,
    required this.errorText,
    required this.mentionCandidates,
    required this.onSelectMention,
    required this.specialMentionCandidates,
    required this.onSelectSpecialMention,
    required this.emojiCandidates,
    required this.onSelectEmoji,
    required this.slashCommands,
    this.quickReplies = const [],
    this.onSelectQuickReply,
    this.botSlashCommands = const [],
    required this.highlightedSlashIndex,
    required this.onSelectSlashCommand,
    this.onSelectBotSlashCommand,
    required this.onComposerKey,
    required this.replyPreviewText,
    required this.isEditing,
    required this.onChanged,
    required this.onSend,
    required this.onSchedule,
    this.voiceButton,
    this.voicePanel,
    required this.onPickGif,
    required this.menuEntries,
    required this.onInsertEmoji,
    required this.gifAvailable,
    required this.isRecordingVoice,
    required this.voiceSecondsLeft,
    required this.isSendingVoice,
    required this.onStartVoiceRecording,
    required this.onCancelVoiceRecording,
    required this.onSendVoiceRecording,
    required this.onCancelReply,
    required this.onCancelEdit,
    required this.availableHeight,
    this.attachmentTray,
    this.aiButton,
    this.scheduledBanner,
    this.isVoicePaused = false,
    this.onToggleVoicePause,
    this.onTrimVoiceRecording,
    this.voiceTrimLabel,
  });

  /// The AI rewrite button (see [AiComposerButton]); on phones it only
  /// shows once there is a draft.
  final Widget? aiButton;

  /// The tray of files waiting to be sent, above the composer pill.
  final Widget? attachmentTray;

  /// The strip counting this conversation's scheduled messages.
  final Widget? scheduledBanner;

  /// Focus of the text field.
  final FocusNode focusNode;

  /// Desktop sizes: a 22 radius pill, a send button that is always there.
  final bool desktop;

  /// Space under the pill (the home indicator on phones).
  final double bottomGap;
  final String hint;
  final TextEditingController controller;
  final bool isSending;
  final bool isPickingImage;
  final String? errorText;
  final List<GroupMember> mentionCandidates;
  final ValueChanged<GroupMember> onSelectMention;

  /// `@here` and roles offered above the members.
  final List<SpecialMention> specialMentionCandidates;
  final ValueChanged<SpecialMention> onSelectSpecialMention;

  /// Custom emoji offered while `:name` is typed.
  final List<CircleEmoji> emojiCandidates;
  final ValueChanged<CircleEmoji> onSelectEmoji;

  /// The commands offered while one is typed after a leading `/`.
  final List<SlashCommand> slashCommands;

  /// The person's own phrases (A8), offered before the commands.
  final List<QuickReply> quickReplies;
  final ValueChanged<QuickReply>? onSelectQuickReply;

  /// Circle bots' commands, offered after [slashCommands].
  final List<BotSlashCommand> botSlashCommands;
  final int highlightedSlashIndex;
  final ValueChanged<SlashCommand> onSelectSlashCommand;
  final ValueChanged<BotSlashCommand>? onSelectBotSlashCommand;

  /// Sees the text field's key presses first (arrow keys and Enter in the
  /// command list).
  final FocusOnKeyEventCallback onComposerKey;
  final String? replyPreviewText;
  final bool isEditing;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onSend;

  /// Schedules the text in the field for later (long-press or right-click
  /// on the send button).
  final Future<void> Function() onSchedule;

  /// Voice input (speak to type): the button next to the emoji button, and
  /// the panel above the composer while it listens. Null where the platform
  /// can't dictate or the person switched it off.
  final Widget? voiceButton;
  final Widget? voicePanel;

  final Future<void> Function() onPickGif;

  /// The "+" menu's entries (see the composer menu registry).
  final List<GlassMenuEntry> Function(
    BuildContext buttonContext, {
    required bool compact,
    required bool gifAvailable,
  })
  menuEntries;
  final Future<void> Function() onInsertEmoji;

  /// False once the server said GIF search isn't set up.
  final bool gifAvailable;
  final bool isRecordingVoice;

  /// Seconds left of the recording in its last stretch; null before.
  final ValueListenable<int?> voiceSecondsLeft;
  final bool isSendingVoice;

  /// The recording is paused (A10). [onToggleVoicePause] is null when the
  /// recorder cannot pause; [onTrimVoiceRecording] is null unless paused.
  final bool isVoicePaused;
  final Future<void> Function()? onToggleVoicePause;
  final Future<void> Function()? onTrimVoiceRecording;

  /// "Keeps 0:07" once the recording was trimmed.
  final String? voiceTrimLabel;
  final Future<void> Function() onStartVoiceRecording;
  final Future<void> Function() onCancelVoiceRecording;
  final Future<void> Function() onSendVoiceRecording;
  final VoidCallback onCancelReply;
  final VoidCallback onCancelEdit;

  /// Height of the thread above the keyboard, header included.
  final double availableHeight;

  /// The channel's slowmode for the current user (0 when off) and how long
  /// they still wait before their next message.
  final int slowmodeSeconds;
  final int slowmodeRemainingSeconds;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final isBusy = isSending || isSendingVoice;
    // Edits are not new messages, so slowmode leaves them alone.
    final isSlowed = slowmodeRemainingSeconds > 0 && !isEditing;
    final compact = isCompactWidth(MediaQuery.sizeOf(context).width);
    final buttonSize = desktop ? 40.0 : 44.0;
    final canAttach = !isBusy && !isEditing && !isRecordingVoice && !isSlowed;
    final hasSuggestions =
        quickReplies.isNotEmpty ||
        slashCommands.isNotEmpty ||
        botSlashCommands.isNotEmpty ||
        emojiCandidates.isNotEmpty ||
        specialMentionCandidates.isNotEmpty ||
        mentionCandidates.isNotEmpty;

    final attach = Builder(
      builder: (buttonContext) => WeCordIconButton(
        key: const ValueKey('composer-attach-button'),
        tooltip: tr('Attach'),
        icon: Icons.add_rounded,
        size: buttonSize,
        iconSize: 24,
        onPressed: canAttach
            ? () => showGlassMenu(
                buttonContext,
                anchor: globalRectOf(buttonContext),
                width: 232,
                entries: menuEntries(
                  buttonContext,
                  compact: compact,
                  gifAvailable: gifAvailable,
                ),
              )
            : null,
      ),
    );

    final field = isRecordingVoice
        ? Semantics(
            liveRegion: true,
            container: true,
            child: Row(
              children: [
                const ExcludeSemantics(child: _RecordingDot()),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isVoicePaused ? tr('Paused') : tr('Recording...'),
                        key: const ValueKey('voice-recording-state'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                      if (voiceTrimLabel != null)
                        Text(
                          voiceTrimLabel!,
                          key: const ValueKey('voice-trim-label'),
                          style: TextStyle(fontSize: 12.5, color: c.muted),
                        ),
                    ],
                  ),
                ),
                // Not read out every second: it is a quiet visual cue.
                ExcludeSemantics(
                  child: ValueListenableBuilder<int?>(
                    valueListenable: voiceSecondsLeft,
                    builder: (context, left, _) => left == null
                        ? const SizedBox.shrink()
                        : Text(
                            key: const ValueKey('voice-seconds-left'),
                            tr('{seconds}s left', {'seconds': left}),
                            style: TextStyle(
                              fontSize: 13,
                              color: c.muted,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
          )
        : Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: onComposerKey,
            child: TextField(
              key: const ValueKey('chat-composer-field'),
              focusNode: focusNode,
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              style: TextStyle(
                fontSize: desktop ? 15 : 16,
                height: 1.35,
                color: c.ink,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintMaxLines: 1,
                // The composer is glass over scrolling messages: muted keeps
                // 4.5:1 there where subtle would not.
                hintStyle: TextStyle(
                  fontSize: desktop ? 15 : 16,
                  color: c.muted,
                ),
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: onChanged,
              onSubmitted: (_) {
                unawaited(onSend());
              },
            ),
          );

    final gif = _GifButton(
      size: desktop ? 36 : 40,
      tooltip: gifAvailable
          ? tr('Send GIF')
          : tr("GIF search isn't set up on this server yet."),
      onPressed: !gifAvailable || isBusy || isEditing || isSlowed
          ? null
          : () => unawaited(onPickGif()),
    );
    final emoji = WeCordIconButton(
      key: const ValueKey('composer-emoji-button'),
      tooltip: tr('Insert emoji'),
      icon: Icons.sentiment_satisfied_alt_rounded,
      size: desktop ? 36 : 40,
      iconSize: 22,
      variant: WeCordButtonVariant.ghost,
      onPressed: isRecordingVoice ? null : () => unawaited(onInsertEmoji()),
    );
    void schedule() {
      WeCordHaptics.light();
      unawaited(onSchedule());
    }

    // Long-press (touch) or right-click schedules instead of sending;
    // screen readers get the long press as an action, and the attach menu
    // has an entry for keyboards.
    Widget sendButton() => GestureDetector(
      excludeFromSemantics: true,
      onSecondaryTap: isEditing || isBusy ? null : schedule,
      child: WeCordIconButton(
        key: const ValueKey('composer-send-button'),
        tooltip: isEditing ? tr('Save edit') : tr('Send'),
        icon: isEditing ? Icons.check_rounded : Icons.arrow_upward_rounded,
        size: buttonSize,
        iconSize: 22,
        variant: WeCordButtonVariant.accent,
        onLongPress: isEditing || isBusy ? null : schedule,
        onPressed: isBusy || isSlowed
            ? null
            : () {
                WeCordHaptics.light();
                unawaited(onSend());
              },
      ),
    );
    final mic = WeCordIconButton(
      key: const ValueKey('composer-mic-button'),
      tooltip: tr('Record voice message'),
      icon: Icons.mic_none_rounded,
      size: desktop ? 36 : buttonSize,
      iconSize: 22,
      variant: desktop ? WeCordButtonVariant.ghost : WeCordButtonVariant.accent,
      onPressed: isBusy || isEditing || isSlowed
          ? null
          : () {
              WeCordHaptics.medium();
              unawaited(onStartVoiceRecording());
            },
    );
    final sending = isSending
        ? Container(
            width: buttonSize,
            height: buttonSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: c.onAccent,
              ),
            ),
          )
        : null;

    final trailing = isRecordingVoice
        ? <Widget>[
            WeCordIconButton(
              tooltip: tr('Cancel voice message'),
              icon: Icons.close_rounded,
              size: desktop ? 36 : 40,
              variant: WeCordButtonVariant.ghost,
              onPressed: isSendingVoice
                  ? null
                  : () => unawaited(onCancelVoiceRecording()),
            ),
            if (onTrimVoiceRecording != null)
              WeCordIconButton(
                key: const ValueKey('composer-voice-trim'),
                tooltip: tr('Trim'),
                icon: Icons.content_cut_rounded,
                size: desktop ? 36 : 40,
                variant: WeCordButtonVariant.ghost,
                onPressed: isSendingVoice
                    ? null
                    : () => unawaited(onTrimVoiceRecording!()),
              ),
            if (onToggleVoicePause != null)
              WeCordIconButton(
                key: const ValueKey('composer-voice-pause'),
                tooltip: isVoicePaused ? tr('Resume recording') : tr('Pause'),
                icon: isVoicePaused ? Icons.mic_rounded : Icons.pause_rounded,
                size: desktop ? 36 : 40,
                variant: WeCordButtonVariant.ghost,
                onPressed: isSendingVoice
                    ? null
                    : () => unawaited(onToggleVoicePause!()),
              ),
            const SizedBox(width: 2),
            isSendingVoice
                ? Container(
                    width: buttonSize,
                    height: buttonSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.onAccent,
                      ),
                    ),
                  )
                : WeCordIconButton(
                    tooltip: tr('Send voice message'),
                    icon: Icons.arrow_upward_rounded,
                    size: buttonSize,
                    iconSize: 22,
                    variant: WeCordButtonVariant.accent,
                    onPressed: () {
                      WeCordHaptics.light();
                      unawaited(onSendVoiceRecording());
                    },
                  ),
          ]
        : desktop
        ? <Widget>[
            ?aiButton,
            gif,
            emoji,
            ?voiceButton,
            mic,
            const SizedBox(width: 2),
            sending ?? sendButton(),
          ]
        : <Widget>[
            if (aiButton case final ai?)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) =>
                    value.text.trim().isEmpty ? const SizedBox.shrink() : ai,
              ),
            emoji,
            // Voice input takes the GIF button's place on phones (GIFs stay
            // in the Attach menu).
            voiceButton ?? gif,
            const SizedBox(width: 2),
            // Phones show the microphone until there is something to send.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (sending != null) {
                  return sending;
                }
                final hasText = value.text.trim().isNotEmpty;
                return hasText || isEditing ? sendButton() : mic;
              },
            ),
          ];

    final pill = WeCordGlass(
      key: const ValueKey('chat-composer'),
      borderRadius: BorderRadius.circular(desktop ? 22 : WeCordRadii.xxl),
      padding: const EdgeInsets.all(6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          attach,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: buttonSize),
                child: Align(alignment: Alignment.centerLeft, child: field),
              ),
            ),
          ),
          ...trailing,
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        desktop ? 24 : 10,
        0,
        desktop ? 24 : 10,
        bottomGap,
      ),
      // On short screens with the keyboard up, banners and suggestions
      // scroll above the text field instead of pushing the messages out.
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: availableHeight * 0.5),
        child: SingleChildScrollView(
          reverse: true,
          clipBehavior: Clip.none,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (errorText != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
                    decoration: BoxDecoration(
                      color: c.dangerSoft,
                      borderRadius: BorderRadius.circular(WeCordRadii.md),
                    ),
                    // A live region: the error is read out as it appears.
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        errorText!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: c.dangerText,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (hasSuggestions) ...[
                WeCordGlass(
                  key: const ValueKey('composer-suggestions'),
                  elevation: GlassElevation.menu,
                  borderRadius: BorderRadius.circular(WeCordRadii.xl),
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (quickReplies.isNotEmpty ||
                          slashCommands.isNotEmpty ||
                          botSlashCommands.isNotEmpty)
                        SlashCommandList(
                          quickReplies: quickReplies,
                          onSelectQuickReply: onSelectQuickReply,
                          commands: slashCommands,
                          botCommands: botSlashCommands,
                          onSelectBot: onSelectBotSlashCommand,
                          highlightedIndex: highlightedSlashIndex,
                          onSelect: onSelectSlashCommand,
                          maxHeight: math.min(240, availableHeight * 0.3),
                          framed: false,
                        ),
                      if (emojiCandidates.isNotEmpty)
                        CustomEmojiCandidateList(
                          candidates: emojiCandidates,
                          onSelect: onSelectEmoji,
                          maxHeight: math.min(220, availableHeight * 0.3),
                          framed: false,
                        ),
                      if (specialMentionCandidates.isNotEmpty)
                        SpecialMentionCandidateList(
                          candidates: specialMentionCandidates,
                          onSelect: onSelectSpecialMention,
                          maxHeight: math.min(150, availableHeight * 0.2),
                          framed: false,
                        ),
                      if (mentionCandidates.isNotEmpty)
                        MentionCandidateList(
                          candidates: mentionCandidates,
                          onSelect: onSelectMention,
                          maxHeight: math.min(180, availableHeight * 0.25),
                          framed: false,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (replyPreviewText != null) ...[
                _ComposerModeBanner(
                  icon: Icons.reply_rounded,
                  text: tr('Replying to {message}', {
                    'message': replyPreviewText,
                  }),
                  tooltip: tr('Cancel reply'),
                  onPressed: onCancelReply,
                ),
                const SizedBox(height: 6),
              ],
              if (isEditing) ...[
                _ComposerModeBanner(
                  icon: Icons.edit_outlined,
                  text: tr('Editing message'),
                  tooltip: tr('Cancel edit'),
                  onPressed: onCancelEdit,
                ),
                const SizedBox(height: 6),
              ],
              if (slowmodeSeconds > 0) ...[
                _SlowmodeBanner(remainingSeconds: slowmodeRemainingSeconds),
                const SizedBox(height: 6),
              ],
              if (attachmentTray != null) ...[
                attachmentTray!,
                const SizedBox(height: 6),
              ],
              ?scheduledBanner,
              ?voicePanel,
              pill,
            ],
          ),
        ),
      ),
    );
  }
}

/// The GIF button: the word in a round ghost button.
class _GifButton extends StatelessWidget {
  const _GifButton({
    required this.size,
    required this.tooltip,
    required this.onPressed,
  });

  final double size;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      key: const ValueKey('composer-gif-button'),
      onPressed: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      shape: const CircleBorder(),
      pressedScale: 0.92,
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedOpacity(
          duration: WeCordMotion.quick,
          opacity: onPressed == null ? 0.4 : 1,
          child: SizedBox.square(
            dimension: math.max(size, WeCordSizes.touchTarget),
            child: Center(
              child: AnimatedContainer(
                duration: WeCordMotion.quick,
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hovered && onPressed != null
                      ? c.raised
                      : c.raised.withValues(alpha: 0),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  'GIF',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: c.ink,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The red dot while a voice message records.
class _RecordingDot extends StatelessWidget {
  const _RecordingDot();

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: c.danger,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: c.danger.withValues(alpha: 0.35), blurRadius: 6),
        ],
      ),
    );
  }
}
