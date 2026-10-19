import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/urgent/urgent_models.dart';
import 'package:wecord/features/urgent/urgent_repository.dart';
import 'package:wecord/shared/models/message.dart';

/// An in-memory urgent messages and confirmations backend.
class FakeUrgentRepository implements UrgentRepository {
  FakeUrgentRepository({
    List<PendingUrgent>? waiting,
    List<UrgentRecipient>? before,
    this.quotaUsed = 0,
    AnnouncementAckState? announcement,
    List<AnnouncementAckMember>? members,
    List<PendingAnnouncementAck>? announcements,
    List<MutedUrgentSender>? muted,
  }) : waiting = [...?waiting],
       before = [...?before],
       announcement = announcement ?? AnnouncementAckState.none,
       members = [...?members],
       announcements = [...?announcements],
       muted = [...?muted];

  final List<PendingUrgent> waiting;
  final List<UrgentRecipient> before;
  int quotaUsed;
  AnnouncementAckState announcement;
  final List<AnnouncementAckMember> members;
  final List<PendingAnnouncementAck> announcements;
  final List<MutedUrgentSender> muted;

  /// What the next call to sendUrgent / remindUnconfirmed throws.
  Object? sendError;
  Object? remindError;

  final sent = <({String messageId, List<String> targets})>[];
  final acknowledged = <String>[];
  final allowedChanges = <({String senderId, bool allowed})>[];
  final announcementAcks = <String>[];
  final requiresAckChanges = <({String conversation, bool required})>[];
  final reminded = <String>[];
  final _changes = StreamController<void>.broadcast();

  /// Pretends an urgent message arrived (Realtime).
  void arrive(PendingUrgent urgent) {
    waiting.insert(0, urgent);
    _changes.add(null);
  }

  @override
  Future<int> sendUrgent(String messageId, List<String> targetIds) async {
    if (sendError case final error?) {
      throw error;
    }
    sent.add((messageId: messageId, targets: targetIds));
    quotaUsed++;
    return targetIds.length;
  }

  @override
  Future<void> acknowledge(String messageId) async {
    acknowledged.add(messageId);
    waiting.removeWhere((urgent) => urgent.messageId == messageId);
  }

  @override
  Future<List<PendingUrgent>> pending({String? conversationId}) async => [
    for (final urgent in waiting)
      if (conversationId == null || urgent.conversationId == conversationId)
        urgent,
  ];

  @override
  Future<List<UrgentRecipient>> recipients(String messageId) async => before;

  @override
  Future<UrgentQuota> quota() async => UrgentQuota(used: quotaUsed, allowed: 5);

  @override
  Future<void> setAllowedFrom(String senderId, {required bool allowed}) async {
    allowedChanges.add((senderId: senderId, allowed: allowed));
    if (allowed) {
      muted.removeWhere((sender) => sender.senderId == senderId);
    } else {
      waiting.removeWhere((urgent) => urgent.senderId == senderId);
    }
  }

  @override
  Future<List<MutedUrgentSender>> mutedSenders() async => [...muted];

  @override
  Stream<void> changes() => _changes.stream;

  @override
  Future<AnnouncementAckState> announcementState(String conversationId) async =>
      announcement;

  @override
  Future<List<AnnouncementAckMember>> announcementMembers(
    String conversationId,
  ) async => members;

  @override
  Future<void> acknowledgeAnnouncement(String conversationId) async {
    announcementAcks.add(conversationId);
    announcements.removeWhere((a) => a.conversationId == conversationId);
    announcement = AnnouncementAckState(
      requiresAck: true,
      total: announcement.total,
      acked: announcement.acked + 1,
      iAcked: true,
      canManage: announcement.canManage,
      nextReminderAt: announcement.nextReminderAt,
    );
  }

  @override
  Future<void> setAnnouncementRequiresAck(
    String conversationId, {
    required bool required,
  }) async {
    requiresAckChanges.add((conversation: conversationId, required: required));
  }

  @override
  Future<int> remindUnconfirmed(String conversationId) async {
    if (remindError case final error?) {
      throw error;
    }
    reminded.add(conversationId);
    return members.where((m) => !m.confirmed).length;
  }

  @override
  Future<List<PendingAnnouncementAck>> pendingAnnouncements() async => [
    ...announcements,
  ];
}

Override urgentOverride(FakeUrgentRepository repository) =>
    urgentRepositoryProvider.overrideWithValue(repository);

PendingUrgent pendingUrgent(
  String messageId, {
  String conversationId = 'c1',
  String senderId = 'ada',
  String senderName = 'Ada',
  String body = 'The meeting moved to 3 pm',
}) => PendingUrgent(
  urgentId: 'u-$messageId',
  messageId: messageId,
  conversationId: conversationId,
  senderId: senderId,
  senderName: senderName,
  body: body,
  type: MessageType.text,
  createdAt: DateTime(2026, 10, 24, 9),
);
