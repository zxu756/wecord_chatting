import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/report_reason.dart';

/// What a circle's moderator can do about a reported message
/// (`resolve_message_report`).
enum MessageReportAction {
  dismiss('dismiss'),
  deleteMessage('delete_message'),
  timeout('timeout'),
  ban('ban');

  const MessageReportAction(this.value);

  final String value;
}

/// How long "Time out" lasts: one hour, a day, a week.
const messageReportTimeoutChoices = <Duration>[
  Duration(hours: 1),
  Duration(days: 1),
  Duration(days: 7),
];

String _string(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

ReportReason _reason(Object? value) => ReportReason.values.firstWhere(
  (reason) => reason.value == value,
  orElse: () => ReportReason.other,
);

/// A short line for an attachment in a copy of a message ("Photo", "File
/// report.pdf"), or null when there is none.
String? attachmentLabel(Object? attachment) {
  if (attachment is! Map) {
    return null;
  }
  if (attachment['view_once'] == true) {
    return tr('View-once photo or video (not kept)');
  }
  final name = _string(attachment['name']);
  final mime = _string(attachment['mime_type']);
  final kind = _string(attachment['kind']);
  final label = kind == 'video' || mime.startsWith('video/')
      ? tr('Video')
      : mime.startsWith('image/')
      ? tr('Photo')
      : mime.startsWith('audio/')
      ? tr('Voice message')
      : tr('File');
  return name.isEmpty ? label : '$label · $name';
}

/// One message near the reported one, as the reporter saw it.
class ReportContextMessage {
  const ReportContextMessage({
    required this.senderName,
    required this.body,
    required this.createdAt,
    required this.isAfter,
    this.attachment,
  });

  factory ReportContextMessage.fromJson(Map<String, dynamic> json) =>
      ReportContextMessage(
        senderName: _string(json['sender_name']),
        body: _string(json['body']),
        createdAt: _time(json['created_at']),
        isAfter: json['position'] == 'after',
        attachment: attachmentLabel(json['attachment']),
      );

  final String senderName;
  final String body;
  final DateTime? createdAt;
  final bool isAfter;
  final String? attachment;
}

/// A report of a message in a circle, as its moderators see it
/// (`list_circle_message_reports`).
class CircleMessageReport {
  const CircleMessageReport({
    required this.id,
    required this.reason,
    required this.details,
    required this.createdAt,
    required this.reporterName,
    required this.reportedName,
    required this.reportedUserId,
    required this.body,
    required this.messageAvailable,
    required this.context,
    required this.repeatCount,
    this.attachment,
    this.channelName,
    this.reportedAvatarUrl,
    this.sentAt,
  });

  factory CircleMessageReport.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> map(Object? value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    final snapshot = map(json['snapshot']);
    final reporter = map(json['reporter']);
    final reported = map(json['reported_user']);
    final context = json['context'];
    final snapshotName = _string(snapshot['sender_display_name']);
    return CircleMessageReport(
      id: _string(json['id']),
      reason: _reason(json['reason']),
      details: _string(json['details']),
      createdAt: _time(json['created_at']) ?? DateTime.now(),
      reporterName: _string(reporter['name'], tr('Someone')),
      reportedName: _string(
        reported['name'],
        snapshotName.isEmpty ? tr('Someone') : snapshotName,
      ),
      reportedUserId: reported['id'] is String
          ? reported['id'] as String
          : null,
      reportedAvatarUrl: reported['avatar_url'] as String?,
      body: _string(snapshot['body']),
      attachment: attachmentLabel(snapshot['attachment']),
      channelName: snapshot['channel_name'] as String?,
      sentAt: _time(snapshot['created_at']),
      messageAvailable: json['message_available'] == true,
      context: [
        if (context is List)
          for (final item in context)
            if (item is Map)
              ReportContextMessage.fromJson(Map<String, dynamic>.from(item)),
      ],
      repeatCount: json['repeat_count'] is int
          ? json['repeat_count'] as int
          : 1,
    );
  }

  final String id;
  final ReportReason reason;
  final String details;
  final DateTime createdAt;
  final String reporterName;
  final String reportedName;
  final String? reportedUserId;
  final String? reportedAvatarUrl;

  /// The text of the message as it was when it was reported.
  final String body;
  final String? attachment;
  final String? channelName;
  final DateTime? sentAt;

  /// The message still exists (not deleted, not expired).
  final bool messageAvailable;
  final List<ReportContextMessage> context;

  /// Open reports of the same message, this one included.
  final int repeatCount;
}

/// The calls for message reports.
class MessageReportsRepository {
  const MessageReportsRepository(this._rpc);

  final CircleRpc _rpc;

  /// Reports a message. [includeContext] shares up to five messages before
  /// and after it that the reporter could see; [alsoBlock] blocks the sender.
  Future<void> report({
    required String messageId,
    required ReportReason reason,
    String details = '',
    bool includeContext = true,
    bool alsoBlock = false,
  }) async {
    await _rpc('report_message', {
      'target_message_id': messageId,
      'report_reason': reason.value,
      'report_details': details.trim(),
      'include_context': includeContext,
      'also_block': alsoBlock,
    });
  }

  /// The open reports of a circle's messages, newest first.
  Future<List<CircleMessageReport>> listForCircle(String circleId) async {
    final rows = await _rpc('list_circle_message_reports', {
      'target_circle_id': circleId,
      'status_filter': 'open',
      'max_results': 100,
    });
    return [for (final row in rpcRows(rows)) CircleMessageReport.fromJson(row)];
  }

  Future<void> resolve(
    String reportId,
    MessageReportAction action, {
    Duration? timeout,
  }) async {
    await _rpc('resolve_message_report', {
      'target_report_id': reportId,
      'action': action.value,
      'duration_seconds': ?timeout?.inSeconds,
    });
  }
}

final messageReportsRepositoryProvider = Provider<MessageReportsRepository>(
  (ref) => MessageReportsRepository(ref.watch(circleRpcProvider)),
);

/// The open message reports of a circle, for its Review queue. Moderators
/// with Manage messages only; anybody else gets an error (the server says
/// no), which the Review page treats as "no reports".
final circleMessageReportsProvider = FutureProvider.autoDispose
    .family<List<CircleMessageReport>, String>((ref, circleId) {
      return ref
          .watch(messageReportsRepositoryProvider)
          .listForCircle(circleId);
    });

/// What to tell the reporter about a refused report.
String reportFailureText(Object error) {
  if (error is PostgrestException) {
    switch (error.code) {
      case '54000':
        return tr('You have sent too many reports today. Try again tomorrow.');
      case 'P0002':
        return tr('This message is no longer available.');
      case '22023':
        return tr('This message cannot be reported.');
    }
  }
  return tr('Could not submit report. Try again.');
}
