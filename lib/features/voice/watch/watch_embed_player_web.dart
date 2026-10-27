import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'package:wecord/features/voice/watch/watch_player.dart';
import 'package:wecord/features/voice/watch/watch_sources.dart';
import 'package:wecord/features/voice/watch/youtube_embed_protocol.dart';

/// The web build shows the embedded players of YouTube and Bilibili in an
/// iframe, the sites' own official way to put a video on another page.
const embedPlayersSupported = true;

var _viewCounter = 0;

/// Opens the embedded player for [source]. Never throws: a player that can
/// not load just stays empty and the call's controls say so.
Future<WatchPlayer?> createEmbedWatchPlayer(WatchEmbedSource source) async {
  return _WebEmbedWatchPlayer(source);
}

class _WebEmbedWatchPlayer extends ChangeNotifier implements WatchPlayer {
  _WebEmbedWatchPlayer(this._source)
    : _viewType = 'wecord-watch-embed-${_viewCounter++}' {
    final youtube = _source.provider == WatchEmbedProvider.youtube;
    final iframe = web.HTMLIFrameElement()
      ..src = _source
          .embedUri(origin: youtube ? web.window.location.origin : null)
          .toString()
      ..allow = 'autoplay; fullscreen; encrypted-media; picture-in-picture'
      ..allowFullscreen = youtube ? false : true
      ..referrerPolicy = 'strict-origin-when-cross-origin'
      ..title = _source.label;
    iframe.style
      ..border = 'none'
      ..width = '100%'
      ..height = '100%'
      // YouTube's picture is not clickable: everything goes through the
      // call's own controls, so the room stays in step.
      ..pointerEvents = youtube ? 'none' : 'auto';
    _iframe = iframe;
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int _) => iframe,
    );
    if (youtube) {
      _listener = ((web.MessageEvent event) => _onMessage(event)).toJS;
      web.window.addEventListener('message', _listener!);
      iframe.addEventListener(
        'load',
        ((web.Event _) => _restartListening()).toJS,
      );
      _restartListening();
    }
  }

  /// The player only starts reporting once it has been told someone is
  /// listening; ask until it answers. The frame loads again whenever the
  /// call's screen takes it back into the page.
  void _restartListening() {
    _gotInfo = false;
    _state = -1;
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_gotInfo || timer.tick > 40) {
        timer.cancel();
        return;
      }
      _listen();
    });
  }

  final WatchEmbedSource _source;
  final String _viewType;
  late final web.HTMLIFrameElement _iframe;
  JSFunction? _listener;
  Timer? _poll;
  var _closed = false;
  var _gotInfo = false;

  // What the player last said, and when we heard it.
  double _time = 0;
  DateTime _timeAt = DateTime.now();
  double? _length;
  int _state = -1;

  bool get _youtube => _source.provider == WatchEmbedProvider.youtube;

  void _post(String message) {
    if (_closed || !_youtube) {
      return;
    }
    try {
      _iframe.contentWindow?.postMessage(message.toJS, youtubeEmbedOrigin.toJS);
    } on Object {
      // The frame is not ready yet; the poll tries again.
    }
  }

  void _listen() => _post(youtubeListeningMessage());

  void _onMessage(web.MessageEvent event) {
    if (_closed || event.origin != youtubeEmbedOrigin) {
      return;
    }
    if (event.source != _iframe.contentWindow) {
      return;
    }
    final data = event.data;
    final info = parseYoutubeMessage(
      data.isA<JSString>() ? (data as JSString).toDart : null,
    );
    if (info == null) {
      return;
    }
    _gotInfo = true;
    final now = DateTime.now();
    if (info.currentTime != null) {
      _time = info.currentTime!;
      _timeAt = now;
    }
    if (info.duration != null) {
      _length = info.duration;
    }
    if (info.playerState != null) {
      // Time is measured at the moment the state changed.
      if (info.currentTime == null) {
        _time = position.inMilliseconds / 1000;
        _timeAt = now;
      }
      _state = info.playerState!;
    }
    notifyListeners();
  }

  @override
  Duration get position {
    if (!_youtube) {
      return Duration.zero;
    }
    var seconds = _time;
    if (_state == YoutubeInfo.statePlaying) {
      seconds += DateTime.now().difference(_timeAt).inMilliseconds / 1000;
    }
    if (_length != null && seconds > _length!) {
      seconds = _length!;
    }
    return Duration(milliseconds: (seconds * 1000).round());
  }

  @override
  Duration? get duration => _length == null
      ? null
      : Duration(milliseconds: (_length! * 1000).round());

  @override
  bool get isPlaying => _state == YoutubeInfo.statePlaying;

  @override
  bool get isBuffering => _state == YoutubeInfo.stateBuffering;

  @override
  bool get hasEnded => _state == YoutubeInfo.stateEnded;

  @override
  bool get hasSurface => true;

  @override
  bool get remoteControl => _youtube;

  @override
  bool get surfaceInteractive => !_youtube;

  @override
  Future<void> play() async {
    _post(youtubeCommandMessage('playVideo'));
  }

  @override
  Future<void> pause() async {
    _post(youtubeCommandMessage('pauseVideo'));
  }

  @override
  Future<void> seek(Duration position) async {
    final seconds = position.inMilliseconds / 1000;
    _post(youtubeCommandMessage('seekTo', [seconds, true]));
    _time = seconds;
    _timeAt = DateTime.now();
  }

  @override
  Future<void> setMuted(bool muted) async {
    _post(youtubeCommandMessage(muted ? 'mute' : 'unMute'));
  }

  @override
  Widget buildSurface(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: HtmlElementView(viewType: _viewType),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _poll?.cancel();
    final listener = _listener;
    if (listener != null) {
      web.window.removeEventListener('message', listener);
    }
    // Emptying the frame stops its sound at once.
    _iframe.src = 'about:blank';
    super.dispose();
  }
}
