import 'dart:async';
import 'dart:math' as math;

import 'package:wecord/features/error_reports/anomaly_detectors.dart';
import 'package:wecord/features/error_reports/breadcrumbs.dart';
import 'package:wecord/features/error_reports/error_description.dart';
import 'package:wecord/features/error_reports/error_report_io.dart';
import 'package:wecord/features/error_reports/error_scrubber.dart';

/// Where the app runs, sent with every report.
class ReporterEnvironment {
  const ReporterEnvironment({
    this.platform = '',
    this.appVersion = '',
    this.build = '',
  });

  final String platform;
  final String appVersion;
  final String build;
}

/// Collects problems, scrubs and dedupes them, and uploads them in batches
/// to the server.
///
/// Nothing here may crash or loop: [report] and the `note…` methods never
/// throw, a report made while another is being made is dropped, and a
/// failed upload only changes when the next try happens (it is never itself
/// reported).
class ErrorReporter {
  ErrorReporter({
    this.environment = const ReporterEnvironment(),
    DateTime Function()? clock,
    Breadcrumbs? breadcrumbs,
    this.flushInterval = const Duration(seconds: 20),
    this.sameProblemCooldown = const Duration(minutes: 10),
    this.maxBatch = 10,
    this.maxQueue = 30,
    this.maxNewPerWindow = 30,
    this.newWindow = const Duration(minutes: 10),
    this.maxUploadsPerHour = 60,
    this.maxBackoff = const Duration(minutes: 15),
    this.sendTimeout = const Duration(seconds: 15),
    RefreshBurstDetector? refreshBursts,
    RedirectLoopDetector? redirectLoops,
    UnexpectedSignOutDetector? signOuts,
  }) : _clock = clock ?? DateTime.now,
       breadcrumbs = breadcrumbs ?? Breadcrumbs(clock: clock),
       refreshBursts = refreshBursts ?? RefreshBurstDetector(),
       redirectLoops = redirectLoops ?? RedirectLoopDetector(),
       signOuts = signOuts ?? UnexpectedSignOutDetector();

  ErrorReportSink? _sink;
  ErrorReportStore? _store;
  final DateTime Function() _clock;

  ReporterEnvironment environment;
  final Breadcrumbs breadcrumbs;
  final Duration flushInterval;
  final Duration sameProblemCooldown;
  final int maxBatch;
  final int maxQueue;
  final int maxNewPerWindow;
  final Duration newWindow;
  final int maxUploadsPerHour;
  final Duration maxBackoff;
  final Duration sendTimeout;

  final RefreshBurstDetector refreshBursts;
  final RedirectLoopDetector redirectLoops;
  final UnexpectedSignOutDetector signOuts;

  /// The route the app is on now (a pattern, never a real id) and the
  /// language, for the context of a report.
  String Function()? routeProvider;
  String Function()? localeProvider;

  final Map<String, ErrorReport> _pending = {};
  final Map<String, DateTime> _lastSent = {};
  final List<DateTime> _newTimes = [];
  final List<(DateTime, int)> _uploads = [];

  var _enabled = true;
  var _loaded = false;
  var _busy = false;
  var _flushing = false;
  var _failures = 0;
  DateTime? _retryAt;
  Timer? _timer;

  /// Reports lost to the device's limits (queue full or too many new
  /// problems); for tests and debugging.
  int dropped = 0;

  bool get enabled => _enabled;

  int get pendingCount => _pending.length;

  List<ErrorReport> get pending => List.unmodifiable(_pending.values);

  /// Connects the reporter to the server and the device's storage, loads
  /// the saved setting and queue, and starts sending. Until this has run,
  /// reports wait in memory (and are dropped if the setting turns out to be
  /// off).
  Future<void> start({
    ErrorReportSink? sink,
    ErrorReportStore? store,
    ReporterEnvironment? environment,
  }) async {
    _sink = sink ?? _sink;
    _store = store ?? _store;
    this.environment = environment ?? this.environment;
    try {
      _enabled = await _store?.loadEnabled() ?? true;
      if (_enabled) {
        for (final json in await _store?.loadQueue() ?? const []) {
          try {
            final report = ErrorReport.fromJson(json);
            _pending.putIfAbsent(report.fingerprint, () => report);
          } on Object {
            // A damaged entry is skipped.
          }
        }
      }
    } on Object {
      // Storage may be unavailable; reports then live in memory.
    }
    _loaded = true;
    if (!_enabled) {
      _clear();
    }
    _schedule();
  }

  /// The setting: when off, nothing is kept or sent, and what waited is
  /// deleted.
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (!value) {
      _clear();
    }
    try {
      await _store?.saveEnabled(value);
    } on Object {
      // Applies for this run at least.
    }
  }

  void _clear() {
    _pending.clear();
    _timer?.cancel();
    _timer = null;
    _persist();
  }

  // ---- Capturing ----

  /// Reports an error that was thrown.
  void report(
    ErrorKind kind,
    Object error,
    StackTrace? stack, {
    String discriminator = '',
  }) {
    if (!_enabled || _busy) {
      return;
    }
    _busy = true;
    try {
      final description = describeError(error);
      _add(
        kind,
        description.type,
        description.message,
        stack == null ? '' : ErrorScrubber.stack('$stack'),
        discriminator,
      );
    } on Object {
      // Reporting never throws.
    } finally {
      _busy = false;
    }
  }

  /// Reports something that is wrong without an error being thrown (a
  /// refresh burst, a redirect loop). [message] must already be free of user
  /// content.
  void reportAnomaly(
    ErrorKind kind,
    String message, {
    String discriminator = '',
  }) {
    if (!_enabled || _busy) {
      return;
    }
    _busy = true;
    try {
      _add(kind, kind.wire, message, '', discriminator);
    } on Object {
      // Reporting never throws.
    } finally {
      _busy = false;
    }
  }

  void _add(
    ErrorKind kind,
    String type,
    String message,
    String stack,
    String discriminator,
  ) {
    final fingerprint = ErrorScrubber.fingerprint(
      kind: kind.wire,
      type: type,
      message: message,
      stack: stack,
      discriminator: discriminator,
    );
    final existing = _pending[fingerprint];
    if (existing != null) {
      existing.count = math.min(existing.count + 1, 10000);
      return;
    }
    final now = _clock();
    _newTimes.removeWhere((time) => now.difference(time) > newWindow);
    if (_newTimes.length >= maxNewPerWindow || _pending.length >= maxQueue) {
      dropped++;
      return;
    }
    _newTimes.add(now);
    final lastSent = _lastSent[fingerprint];
    _pending[fingerprint] = ErrorReport(
      kind: kind.wire,
      message: message,
      stack: stack,
      fingerprint: fingerprint,
      platform: environment.platform,
      appVersion: environment.appVersion,
      build: environment.build,
      context: _context(),
      notBefore: lastSent?.add(sameProblemCooldown),
    );
    _persist();
    _schedule();
  }

  Map<String, Object?> _context() {
    String? read(String Function()? provider) {
      try {
        return provider?.call();
      } on Object {
        return null;
      }
    }

    return {
      'route': ?read(routeProvider),
      'locale': ?read(localeProvider),
      'crumbs': breadcrumbs.recent(),
    };
  }

  // ---- Breadcrumbs and anomaly detectors ----

  void noteRoute(String template) {
    try {
      breadcrumbs.add('route', ErrorScrubber.route(template));
    } on Object {
      // Breadcrumbs are best effort.
    }
  }

  void noteLifecycle(String state) => breadcrumbs.add('lifecycle', state);

  /// An auth event by name (`signedIn`, `tokenRefreshed`, `signedOut`…).
  void noteAuthEvent(String event) {
    try {
      final now = _clock();
      breadcrumbs.add('auth', event);
      switch (event) {
        case 'tokenRefreshed':
          final count = refreshBursts.record(now);
          if (count != null) {
            reportAnomaly(
              ErrorKind.refreshBurst,
              '$count token refreshes within '
              '${refreshBursts.window.inSeconds} seconds',
            );
          }
        case 'signedIn':
          signOuts.signedIn();
        case 'signedOut':
          if (signOuts.signedOut(now)) {
            reportAnomaly(
              ErrorKind.unexpectedSignOut,
              'Signed out without being asked to',
            );
          }
      }
    } on Object {
      // Never throws.
    }
  }

  /// The app is about to sign this person out on purpose.
  void expectSignOut({Duration? within}) {
    try {
      signOuts.expectSignOut(_clock(), within: within);
    } on Object {
      // Never throws.
    }
  }

  /// A router redirect from one location to another.
  void noteRedirect(String from, String to) {
    try {
      final a = ErrorScrubber.route(from);
      final b = ErrorScrubber.route(to);
      final count = redirectLoops.record(a, b, _clock());
      if (count != null) {
        reportAnomaly(
          ErrorKind.redirectLoop,
          'Redirected $count times within '
          '${redirectLoops.window.inSeconds} seconds from $a to $b',
          discriminator: '$a->$b',
        );
      }
    } on Object {
      // Never throws.
    }
  }

  /// A request that came back with an error status. Only the kind of call,
  /// its name, the status and the server's error code are kept; and only
  /// failures that point at a bug or an outage (not the business rules that
  /// functions refuse on purpose, like a taken username).
  void noteRequestFailure({
    required ErrorKind kind,
    required String name,
    required int status,
    String? code,
  }) {
    try {
      if (!shouldReportFailure(kind, status, code)) {
        return;
      }
      final safeCode =
          code != null && RegExp(r'^[A-Za-z0-9_.\-]{1,40}$').hasMatch(code)
          ? code
          : '-';
      final safeName = RegExp(r'^[A-Za-z0-9_\-]{1,64}$').hasMatch(name)
          ? name
          : '-';
      reportAnomaly(
        kind,
        '${kind == ErrorKind.rpcError ? 'rpc' : 'call'} $safeName failed: '
        'status=$status code=$safeCode',
        discriminator: '$safeName|$status|$safeCode',
      );
    } on Object {
      // Never throws.
    }
  }

  /// Which failed calls are worth a report: server errors, auth trouble and
  /// codes that mean the call itself is wrong (missing function, missing
  /// column, no privilege). Errors raised on purpose (`P0001`), constraint
  /// violations (`23…`), bad input and rate limits are expected.
  static bool shouldReportFailure(ErrorKind kind, int status, String? code) {
    if (status >= 500) {
      return true;
    }
    if (kind == ErrorKind.signInError) {
      // A wrong password is not a problem; the service failing is.
      return status == 429 || status >= 500;
    }
    if (status == 401 || status == 403 || status == 404) {
      return true;
    }
    if (code == null) {
      return false;
    }
    return code.startsWith('PGRST') ||
        code.startsWith('42') ||
        code.startsWith('XX') ||
        code.startsWith('53') ||
        code.startsWith('57');
  }

  // ---- Uploading ----

  void _persist() {
    final store = _store;
    if (store == null || !_loaded) {
      return;
    }
    final queue = [for (final r in _pending.values) r.toJson()];
    unawaited(
      store.saveQueue(queue).then<void>((_) {}, onError: (Object _) {}),
    );
  }

  void _schedule() {
    if (_timer != null || !_loaded || !_enabled || _pending.isEmpty) {
      return;
    }
    if (_sink == null) {
      return;
    }
    final now = _clock();
    var delay = flushInterval;
    final retryAt = _retryAt;
    if (retryAt != null && retryAt.isAfter(now.add(delay))) {
      delay = retryAt.difference(now);
    }
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(flush());
    });
  }

  /// Sends what is ready, at most one batch. Never throws.
  Future<void> flush() async {
    final sink = _sink;
    if (_flushing || !_loaded || !_enabled || sink == null) {
      return;
    }
    _flushing = true;
    try {
      final now = _clock();
      final retryAt = _retryAt;
      if (retryAt != null && now.isBefore(retryAt)) {
        return;
      }
      _uploads.removeWhere(
        (u) => now.difference(u.$1) > const Duration(hours: 1),
      );
      final used = _uploads.fold<int>(0, (sum, u) => sum + u.$2);
      final allowance = maxUploadsPerHour - used;
      final ready = [
        for (final r in _pending.values)
          if (r.notBefore == null || !r.notBefore!.isAfter(now)) r,
      ].take(math.min(maxBatch, math.max(allowance, 0))).toList();
      if (ready.isEmpty) {
        return;
      }
      final sent = {for (final r in ready) r.fingerprint: r.count};
      final batch = [for (final r in ready) r.toJson()];
      var done = true;
      try {
        await sink.send(batch).timeout(sendTimeout);
        _uploads.add((now, ready.length));
        _failures = 0;
        _retryAt = null;
      } on ErrorReportRejected {
        // The server will not take these; dropping them is the only way not
        // to send them forever.
      } on Object {
        done = false;
        _failures++;
        final seconds = math.min(
          maxBackoff.inSeconds,
          flushInterval.inSeconds * math.pow(2, _failures).toInt(),
        );
        _retryAt = _clock().add(Duration(seconds: seconds));
      }
      if (done) {
        final after = _clock();
        sent.forEach((fingerprint, count) {
          _lastSent[fingerprint] = after;
          final report = _pending[fingerprint];
          if (report == null) {
            return;
          }
          // Occurrences while the upload was in flight wait for the next.
          report.count -= count;
          if (report.count <= 0) {
            _pending.remove(fingerprint);
          } else {
            report.notBefore = after.add(sameProblemCooldown);
          }
        });
        if (_lastSent.length > 200) {
          _lastSent.removeWhere(
            (_, time) => after.difference(time) > sameProblemCooldown,
          );
        }
      }
      _persist();
    } on Object {
      // Never throws.
    } finally {
      _flushing = false;
      _schedule();
    }
  }

  /// Stops the timer (for tests and shutdown).
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
