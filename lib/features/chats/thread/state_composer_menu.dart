part of '../chat_thread_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// What the composer's + menu and buttons do.
extension _ThreadComposerMenuState on _ChatThreadScreenState {
  /// Sends the GIF picked from the picker as a message holding its link,
  /// which chats show as the GIF.
  Future<void> _pickAndSendGif() async {
    if (_isSlowedDown || _isSending || _editingMessage != null) {
      return;
    }
    if (ref.read(gifSearchAvailableProvider) == false) {
      _showSnackBar(tr("GIF search isn't set up on this server yet."));
      return;
    }
    final gif = await showGifPicker(context);
    if (gif == null || !mounted) {
      return;
    }
    setState(() {
      _isSending = true;
      _sendError = null;
    });
    try {
      await ref
          .read(chatsRepositoryProvider)
          .sendTextMessage(
            conversationId: widget.conversationId,
            body: gif.url,
          );
      _refreshThread();
    } on SlowmodeException catch (error) {
      _waitOutSlowmode(error);
    } on SendRefusedException catch (error) {
      _showSendRefusal(error);
    } catch (_) {
      if (mounted) {
        setState(() => _sendError = tr('Could not send GIF. Try again.'));
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _openPollComposer() async {
    if (_isSlowedDown || _isSending || _editingMessage != null) {
      return;
    }
    final posted = await showPollComposerSheet(
      context,
      conversationId: widget.conversationId,
    );
    if (posted == true && mounted) {
      _refreshThread();
    }
  }

  Future<void> _openChainComposer() async {
    if (_isSlowedDown || _isSending || _editingMessage != null) {
      return;
    }
    final posted = await showChainCreateSheet(
      context,
      conversationId: widget.conversationId,
    );
    if (posted == true && mounted) {
      _refreshThread();
    }
  }

  Future<void> _openContactCardPicker() async {
    if (_isSlowedDown || _isSending || _editingMessage != null) {
      return;
    }
    final sent = await showContactCardPicker(
      context,
      conversationId: widget.conversationId,
    );
    if (sent == true && mounted) {
      _refreshThread();
    }
  }

  Future<void> _sendLocation() async {
    if (_isSlowedDown || _isSending || _editingMessage != null) {
      return;
    }
    await sendLocationFlow(context, ref, conversationId: widget.conversationId);
  }

  Future<void> _shareLiveLocation() async {
    if (_isSlowedDown || _isSending || _editingMessage != null) {
      return;
    }
    await shareLiveLocationFlow(
      context,
      ref,
      conversationId: widget.conversationId,
    );
  }

  /// Picks an emoji and puts it in the composer at the cursor.
  Future<void> _pickAndInsertEmoji() async {
    final emoji = await showEmojiReactionPicker(
      context,
      title: tr('Insert emoji'),
    );
    if (emoji == null || !mounted) {
      return;
    }
    final value = _composerController.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final text = value.text.replaceRange(selection.start, selection.end, emoji);
    _composerController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: selection.start + emoji.length,
      ),
    );
    _handleComposerChanged(text);
  }

  /// The chat's events, with a button to plan a new one (which the chat
  /// then announces).
  Future<void> _showEvents() async {
    await showChatEventsList(
      context,
      conversationId: widget.conversationId,
      canCreate: !_isSlowedDown && _editingMessage == null,
    );
    if (mounted) {
      _refreshThread();
    }
  }

  /// Picks a date and time and puts it in the composer at the cursor as a
  /// time token that every reader sees in their own time zone.
  Future<void> _insertTime() async {
    final token = await showInsertTimeSheet(context);
    if (token == null || !mounted) {
      return;
    }
    final markup = token.markup;
    final value = _composerController.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final text = value.text.replaceRange(
      selection.start,
      selection.end,
      markup,
    );
    _composerController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: selection.start + markup.length,
      ),
    );
    _composerFocus.requestFocus();
    _handleComposerChanged(text);
  }

  Future<void> _pickAndSendSticker() async {
    if (_isSlowedDown || _isSending || _editingMessage != null) {
      return;
    }
    final sticker = await showStickerPicker(context, circleId: _circleId);
    if (sticker == null || !mounted) {
      return;
    }
    setState(() {
      _isSending = true;
      _sendError = null;
    });
    try {
      await ref
          .read(chatsRepositoryProvider)
          .sendSticker(
            conversationId: widget.conversationId,
            stickerId: sticker.id,
          );
      _refreshThread();
    } on SlowmodeException catch (error) {
      _waitOutSlowmode(error);
    } on SendRefusedException catch (error) {
      _showSendRefusal(error);
    } catch (_) {
      if (mounted) {
        setState(() => _sendError = tr('Could not send sticker. Try again.'));
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }
}
