import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// What was noticed while a view-once photo or video was open (roadmap G7).
enum ViewOnceCaptureKind { screenshot, recording }

/// One report the other phone sent: a screenshot, or a screen recording.
class ViewOnceCaptureReport {
  const ViewOnceCaptureReport({
    required this.userId,
    required this.kind,
    required this.reportedAt,
  });

  final String userId;
  final ViewOnceCaptureKind kind;
  final DateTime reportedAt;
}

/// Reports, and reads, screenshots of view-once messages. Best effort on both
/// ends: only an iPhone or iPad can notice, the report comes after the fact,
/// and a person who is offline sends none.
abstract interface class ViewOnceScreenshotRepository {
  /// Tells the sender (and the chat) that [kind] happened to [messageId].
  /// Returns whether it was new; the server keeps one report per kind and
  /// person.
  Future<bool> report(String messageId, ViewOnceCaptureKind kind);

  /// The reports of [messageId] the caller may see: all of them for its
  /// sender, their own for anyone else.
  Stream<List<ViewOnceCaptureReport>> watch(String messageId);
}

class SupabaseViewOnceScreenshotRepository
    implements ViewOnceScreenshotRepository {
  const SupabaseViewOnceScreenshotRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<bool> report(String messageId, ViewOnceCaptureKind kind) async {
    final result = await _client.rpc<Object?>(
      'report_view_once_screenshot',
      params: {
        'target_message_id': messageId,
        'event_kind': switch (kind) {
          ViewOnceCaptureKind.screenshot => 'screenshot',
          ViewOnceCaptureKind.recording => 'recording',
        },
      },
    );
    return result == true;
  }

  @override
  Stream<List<ViewOnceCaptureReport>> watch(String messageId) {
    return _client
        .from('message_view_once_screenshots')
        .stream(primaryKey: ['message_id', 'user_id', 'event'])
        .eq('message_id', messageId)
        .map(
          (rows) => [
            for (final row in rows)
              ViewOnceCaptureReport(
                userId: row['user_id'] as String,
                kind: row['event'] == 'recording'
                    ? ViewOnceCaptureKind.recording
                    : ViewOnceCaptureKind.screenshot,
                reportedAt: DateTime.parse(row['created_at'] as String).toUtc(),
              ),
          ],
        );
  }
}

class _UninitializedViewOnceScreenshotRepository
    implements ViewOnceScreenshotRepository {
  const _UninitializedViewOnceScreenshotRepository();

  @override
  Future<bool> report(String messageId, ViewOnceCaptureKind kind) async =>
      false;

  @override
  Stream<List<ViewOnceCaptureReport>> watch(String messageId) =>
      Stream.value(const <ViewOnceCaptureReport>[]);
}

final viewOnceScreenshotRepositoryProvider =
    Provider<ViewOnceScreenshotRepository>((ref) {
      try {
        return SupabaseViewOnceScreenshotRepository(
          ref.watch(supabaseClientProvider),
        );
      } on ProviderException {
        return const _UninitializedViewOnceScreenshotRepository();
      }
    });

/// The reports of a view-once message; empty when they cannot be read.
final viewOnceCaptureReportsProvider = StreamProvider.autoDispose
    .family<List<ViewOnceCaptureReport>, String>((ref, messageId) {
      return ref
          .watch(viewOnceScreenshotRepositoryProvider)
          .watch(messageId)
          .handleError((Object _) {});
    });

/// What the sender's bubble adds to its status once the other phone reported:
/// null when nothing was reported.
String? viewOnceCaptureNote(List<ViewOnceCaptureReport> reports) {
  if (reports.isEmpty) {
    return null;
  }
  final screenshots = reports
      .where((r) => r.kind == ViewOnceCaptureKind.screenshot)
      .length;
  if (screenshots > 0) {
    return screenshots == 1 ? tr('Screenshot taken') : tr('Screenshots taken');
  }
  return tr('Screen recorded');
}
