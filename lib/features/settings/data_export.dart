import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Where an export is: working through its steps, ready to download, or
/// not going to happen.
enum DataExportPhase {
  working,
  ready,
  failed,
  expired;

  static DataExportPhase fromJson(Object? value) {
    return switch (value) {
      'ready' => DataExportPhase.ready,
      'failed' => DataExportPhase.failed,
      'expired' => DataExportPhase.expired,
      _ => DataExportPhase.working,
    };
  }
}

/// An export as the data-export function reports it.
class DataExportStatus {
  const DataExportStatus({
    required this.id,
    required this.phase,
    required this.stage,
    required this.progress,
    this.detail,
    this.byteSize,
    this.createdAt,
    this.expiresAt,
    this.downloadUrl,
  });

  factory DataExportStatus.fromJson(Map<String, dynamic> json) {
    DateTime? time(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;
    return DataExportStatus(
      id: json['id'] as String,
      phase: DataExportPhase.fromJson(json['status']),
      stage: json['stage'] as String? ?? 'queued',
      progress: ((json['progress'] as num?)?.toInt() ?? 0).clamp(0, 100),
      detail: json['detail'] as String?,
      byteSize: (json['byte_size'] as num?)?.toInt(),
      createdAt: time(json['created_at']),
      expiresAt: time(json['expires_at']),
      downloadUrl: json['download_url'] as String?,
    );
  }

  final String id;
  final DataExportPhase phase;

  /// queued, profile, friends, conversations, messages, circles,
  /// attachments, packaging, uploading or ready.
  final String stage;

  /// 0 to 100.
  final int progress;
  final String? detail;
  final int? byteSize;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final String? downloadUrl;
}

/// The last export was less than 24 hours ago.
class DataExportRateLimited implements Exception {
  const DataExportRateLimited(this.retryAfter);

  final Duration retryAfter;
}

/// An export is already being made.
class DataExportInProgress implements Exception {
  const DataExportInProgress(this.id);

  final String id;
}

abstract interface class DataExportRepository {
  /// Starts an export and returns its id. Throws [DataExportRateLimited]
  /// or [DataExportInProgress].
  Future<String> start();

  /// The export with [id], or the latest one; null when there is none.
  Future<DataExportStatus?> status({String? id});
}

final dataExportRepositoryProvider = Provider<DataExportRepository>((ref) {
  try {
    return SupabaseDataExportRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _NoDataExportRepository();
  }
});

class SupabaseDataExportRepository implements DataExportRepository {
  const SupabaseDataExportRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<String> start() async {
    try {
      final response = await _client.functions.invoke(
        'data-export',
        body: const <String, dynamic>{},
      );
      final data = response.data;
      if (data is Map && data['id'] is String) {
        return data['id'] as String;
      }
      throw StateError('The export did not start.');
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map ? details['error'] : null;
      if (error.status == 429 && code == 'rate_limited') {
        final seconds = details is Map
            ? (details['retry_after_seconds'] as num?)?.toInt() ?? 86400
            : 86400;
        throw DataExportRateLimited(Duration(seconds: seconds));
      }
      if (error.status == 409 && code == 'in_progress') {
        throw DataExportInProgress((details as Map)['id'] as String);
      }
      rethrow;
    }
  }

  @override
  Future<DataExportStatus?> status({String? id}) async {
    final response = await _client.functions.invoke(
      'data-export',
      method: HttpMethod.get,
      queryParameters: {'id': ?id},
    );
    final data = response.data;
    final export = data is Map ? data['export'] : null;
    if (export is! Map) {
      return null;
    }
    return DataExportStatus.fromJson(Map<String, dynamic>.from(export));
  }
}

class _NoDataExportRepository implements DataExportRepository {
  const _NoDataExportRepository();

  @override
  Future<String> start() => Future.error(StateError('Sign in to export.'));

  @override
  Future<DataExportStatus?> status({String? id}) async => null;
}

/// The screen's state: what to show now.
sealed class DataExportState {
  const DataExportState();
}

/// Looking up the last export.
final class DataExportLoading extends DataExportState {
  const DataExportLoading();
}

/// Nothing running or ready: the person can ask for their data.
final class DataExportIdle extends DataExportState {
  const DataExportIdle({this.lastFailed = false});

  final bool lastFailed;
}

/// Asked for, not answered yet.
final class DataExportStarting extends DataExportState {
  const DataExportStarting();
}

/// Being made (or ready, or failed): [status] says which.
final class DataExportActive extends DataExportState {
  const DataExportActive(this.status);

  final DataExportStatus status;
}

/// Asked again within 24 hours of the last export.
final class DataExportWait extends DataExportState {
  const DataExportWait(this.retryAfter, {this.last});

  final Duration retryAfter;
  final DataExportStatus? last;
}

final class DataExportError extends DataExportState {
  const DataExportError();
}

/// Starts exports and follows them until they are ready.
class DataExportController extends Notifier<DataExportState> {
  /// How often a running export is asked how far along it is.
  static const pollInterval = Duration(milliseconds: 1500);

  Timer? _timer;
  var _disposed = false;

  @override
  DataExportState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
    });
    Future.microtask(_loadLatest);
    return const DataExportLoading();
  }

  DataExportRepository get _repository =>
      ref.read(dataExportRepositoryProvider);

  Future<void> _loadLatest() async {
    try {
      final latest = await _repository.status();
      if (_disposed) return;
      if (latest == null || latest.phase == DataExportPhase.expired) {
        state = const DataExportIdle();
      } else if (latest.phase == DataExportPhase.failed) {
        state = const DataExportIdle(lastFailed: true);
      } else {
        state = DataExportActive(latest);
        _follow(latest);
      }
    } catch (_) {
      if (!_disposed) state = const DataExportError();
    }
  }

  void _follow(DataExportStatus status) {
    _timer?.cancel();
    if (status.phase != DataExportPhase.working) {
      return;
    }
    _timer = Timer(pollInterval, () async {
      try {
        final next = await _repository.status(id: status.id);
        if (_disposed) return;
        if (next == null) {
          state = const DataExportError();
          return;
        }
        state = DataExportActive(next);
        _follow(next);
      } catch (_) {
        // A dropped connection: keep trying.
        if (!_disposed) _follow(status);
      }
    });
  }

  /// Asks for the person's data.
  Future<void> start() async {
    if (state is DataExportStarting) return;
    state = const DataExportStarting();
    try {
      final id = await _repository.start();
      final status =
          await _repository.status(id: id) ??
          DataExportStatus(
            id: id,
            phase: DataExportPhase.working,
            stage: 'queued',
            progress: 0,
          );
      if (_disposed) return;
      state = DataExportActive(status);
      _follow(status);
    } on DataExportRateLimited catch (error) {
      if (_disposed) return;
      DataExportStatus? last;
      try {
        last = await _repository.status();
      } catch (_) {
        last = null;
      }
      if (_disposed) return;
      state = DataExportWait(error.retryAfter, last: last);
      if (last != null && last.phase == DataExportPhase.working) {
        state = DataExportActive(last);
        _follow(last);
      }
    } on DataExportInProgress catch (error) {
      final status = await _repository.status(id: error.id);
      if (_disposed) return;
      if (status != null) {
        state = DataExportActive(status);
        _follow(status);
      } else {
        state = const DataExportError();
      }
    } catch (_) {
      if (!_disposed) state = const DataExportError();
    }
  }
}

final dataExportControllerProvider =
    NotifierProvider.autoDispose<DataExportController, DataExportState>(
      DataExportController.new,
    );

/// Opens a signed download link; tests swap it out.
final dataExportLauncherProvider = Provider<Future<bool> Function(Uri uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

void openDataExport(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const DataExportScreen()),
  );
}

/// What the stage name says to a person.
String dataExportStageLabel(String stage) {
  return switch (stage) {
    'profile' => tr('Collecting your profile…'),
    'friends' => tr('Collecting your friends…'),
    'conversations' => tr('Collecting your conversations…'),
    'messages' => tr('Collecting your messages…'),
    'circles' => tr('Collecting your circles…'),
    'moments' => tr('Collecting your Moments…'),
    'more' => tr('Collecting your notes, lists and more…'),
    'attachments' => tr('Linking the files you sent…'),
    'packaging' => tr('Packing everything into a ZIP…'),
    'uploading' => tr('Saving your archive…'),
    'ready' => tr('Your data is ready.'),
    _ => tr('Getting ready…'),
  };
}

/// "12 KB", "3.4 MB".
String dataExportSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// "about 5 hours", "about 1 day" until [duration] has passed.
String dataExportWaitText(Duration duration) {
  final hours = (duration.inMinutes / 60).ceil();
  if (hours <= 1) {
    final minutes = duration.inMinutes.clamp(1, 60);
    return minutes == 1
        ? tr('1 minute')
        : tr('{count} minutes', {'count': minutes});
  }
  return hours == 1 ? tr('1 hour') : tr('{count} hours', {'count': hours});
}

/// Settings -> Privacy -> Download my data.
class DataExportScreen extends ConsumerWidget {
  const DataExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final state = ref.watch(dataExportControllerProvider);
    final controller = ref.read(dataExportControllerProvider.notifier);
    return SettingsPage(
      key: const ValueKey('data-export-screen'),
      title: tr('Download my data'),
      children: [
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
          child: Text(
            tr(
              'Get a copy of what WeCord keeps about you, as a ZIP you can open on any computer: readable pages and plain JSON files.',
            ),
            style: TextStyle(fontSize: 14.5, height: 1.45, color: c.muted),
          ),
        ),
        SettingsGroup(
          header: tr('What is included'),
          children: [
            SettingsRow(
              icon: Icons.person_outline_rounded,
              title: tr('Your profile and settings'),
            ),
            SettingsRow(
              icon: Icons.group_outlined,
              title: tr('Friends, requests and people you blocked'),
            ),
            SettingsRow(
              icon: Icons.chat_bubble_outline_rounded,
              title: tr('The names of your conversations'),
            ),
            SettingsRow(
              icon: Icons.attach_file_rounded,
              title: tr('Messages you sent, with links to your files'),
            ),
            SettingsRow(
              icon: Icons.hub_outlined,
              title: tr('Circles you belong to'),
            ),
            SettingsRow(
              icon: Icons.photo_library_outlined,
              title: tr('Your Moments, friend tags and starred friends'),
            ),
            SettingsRow(
              icon: Icons.sticky_note_2_outlined,
              title: tr('Group chains, notes and task lists you wrote'),
            ),
            SettingsRow(
              icon: Icons.bookmark_border_rounded,
              title: tr(
                'Saved messages, reminders, scheduled messages and wallpapers',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        switch (state) {
          DataExportLoading() => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          ),
          DataExportIdle(:final lastFailed) => _RequestCard(
            error: lastFailed
                ? tr('The last attempt did not finish. You can try again.')
                : null,
            onRequest: controller.start,
          ),
          DataExportStarting() => const _ProgressCard(
            progress: 0,
            title: null,
            starting: true,
          ),
          DataExportError() => _RequestCard(
            error: tr('Could not reach the server. Try again.'),
            onRequest: controller.start,
          ),
          DataExportWait(:final retryAfter, :final last) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (last != null && last.phase == DataExportPhase.ready)
                _ReadyCard(status: last),
              if (last != null && last.phase == DataExportPhase.ready)
                const SizedBox(height: 12),
              _Notice(
                key: const ValueKey('data-export-wait'),
                icon: Icons.schedule_rounded,
                text: tr(
                  'You can request your data once a day. Try again in about {time}.',
                  {'time': dataExportWaitText(retryAfter)},
                ),
              ),
            ],
          ),
          DataExportActive(:final status)
              when status.phase == DataExportPhase.working =>
            _ProgressCard(
              progress: status.progress,
              title: dataExportStageLabel(status.stage),
              detail: status.detail,
            ),
          DataExportActive(:final status) =>
            status.phase == DataExportPhase.ready
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ReadyCard(status: status),
                      const SizedBox(height: 12),
                      _Notice(
                        icon: Icons.schedule_rounded,
                        text: tr(
                          'You can request a new copy once a day. This one is deleted after 7 days.',
                        ),
                      ),
                    ],
                  )
                : _RequestCard(
                    error: tr(
                      'The last attempt did not finish. You can try again.',
                    ),
                    onRequest: controller.start,
                  ),
        },
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: c.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13.5, height: 1.45, color: c.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.onRequest, this.error});

  final VoidCallback onRequest;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error!,
                key: const ValueKey('data-export-error'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.dangerText,
                ),
              ),
            ),
          ),
        WeCordButton(
          key: const ValueKey('data-export-request'),
          label: tr('Request my data'),
          icon: Icons.download_rounded,
          size: WeCordButtonSize.large,
          expand: true,
          onPressed: onRequest,
        ),
        const SizedBox(height: 10),
        Text(
          tr(
            'It can take a minute. You can leave this page; the export keeps going.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.4, color: c.subtle),
        ),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.progress,
    required this.title,
    this.detail,
    this.starting = false,
  });

  final int progress;
  final String? title;
  final String? detail;
  final bool starting;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final label = title ?? tr('Getting ready…');
    final spoken = starting
        ? label
        : tr('{stage} {percent} percent', {
            'stage': label,
            'percent': progress,
          });
    return Container(
      key: const ValueKey('data-export-progress'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Semantics(
        container: true,
        liveRegion: true,
        label: spoken,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: c.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                  ),
                  if (!starting)
                    Text(
                      '$progress%',
                      key: const ValueKey('data-export-percent'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: c.muted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(WeCordRadii.pill),
                child: LinearProgressIndicator(
                  value: starting ? null : progress / 100,
                  minHeight: 8,
                  backgroundColor: c.raised,
                  color: c.accent,
                ),
              ),
              if (detail != null && detail!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  tr('{count} messages so far', {'count': detail}),
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                tr('You can leave this page; the export keeps going.'),
                style: TextStyle(fontSize: 12.5, color: c.subtle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadyCard extends ConsumerWidget {
  const _ReadyCard({required this.status});

  final DataExportStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final size = status.byteSize;
    final expires = status.expiresAt;
    final left = expires?.difference(DateTime.now());
    final details = [
      if (size != null) dataExportSize(size),
      if (left != null && !left.isNegative)
        left.inDays >= 1
            ? tr('Deleted in {count} days', {'count': left.inDays})
            : tr('Deleted within a day'),
    ].join(' · ');
    return Container(
      key: const ValueKey('data-export-ready'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SettingsIconTile(
                icon: Icons.folder_zip_outlined,
                tone: SettingsTone.success,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('Your data is ready'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: c.ink,
                      ),
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        style: TextStyle(fontSize: 13, color: c.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          WeCordButton(
            key: const ValueKey('data-export-download'),
            label: tr('Download'),
            icon: Icons.download_rounded,
            variant: WeCordButtonVariant.accent,
            size: WeCordButtonSize.large,
            expand: true,
            onPressed: status.downloadUrl == null
                ? null
                : () async {
                    final uri = Uri.tryParse(status.downloadUrl!);
                    if (uri == null) return;
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    final opened = await ref.read(dataExportLauncherProvider)(
                      uri,
                    );
                    if (!opened) {
                      messenger?.showSnackBar(
                        SnackBar(
                          content: Text(
                            tr('Could not open the download. Try again.'),
                          ),
                        ),
                      );
                    }
                  },
          ),
        ],
      ),
    );
  }
}
