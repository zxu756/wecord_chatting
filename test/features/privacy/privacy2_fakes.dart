import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/groups/group_invitations.dart';
import 'package:wecord/features/privacy/privacy_permissions.dart';
import 'package:wecord/features/privacy/security_alerts.dart';

/// The stored choices, and a record of what was saved.
class FakePrivacyPermissionsRepository implements PrivacyPermissionsRepository {
  FakePrivacyPermissionsRepository([this.stored = const PrivacyPermissions()]);

  PrivacyPermissions stored;
  var fail = false;
  final saves = <(PrivacyPermissions, PrivacyPermissions)>[];

  @override
  Future<PrivacyPermissions> load() async => stored;

  @override
  Future<void> save(PrivacyPermissions before, PrivacyPermissions after) async {
    if (fail) {
      throw StateError('offline');
    }
    saves.add((before, after));
    stored = after;
  }
}

/// Alerts the server holds; "Not me" and "It was me" close them.
class FakeSecurityAlertsRepository implements SecurityAlertsRepository {
  FakeSecurityAlertsRepository([List<LoginAlert>? alerts])
    : alerts = alerts ?? sampleLoginAlerts();

  List<LoginAlert> alerts;
  var failResolve = false;
  final resolved = <(String, LoginAlertResolution)>[];

  @override
  Future<List<LoginAlert>> list() async => alerts;

  @override
  Future<void> resolve(String alertId, LoginAlertResolution resolution) async {
    if (failResolve) {
      throw StateError('offline');
    }
    resolved.add((alertId, resolution));
    alerts = [
      for (final alert in alerts)
        if (alert.id == alertId)
          LoginAlert(
            id: alert.id,
            sessionId: alert.sessionId,
            deviceName: alert.deviceName,
            platform: alert.platform,
            createdAt: alert.createdAt,
            resolution: resolution,
          )
        else
          alert,
    ];
  }
}

List<LoginAlert> sampleLoginAlerts() {
  final now = DateTime.now().toUtc();
  return [
    LoginAlert(
      id: 'alert-1',
      sessionId: 'phone',
      deviceName: 'iPhone or iPad',
      platform: 'iOS',
      createdAt: now.subtract(const Duration(minutes: 12)),
    ),
  ];
}

/// Invitations the server holds.
class FakeGroupInvitationsRepository implements GroupInvitationsRepository {
  FakeGroupInvitationsRepository([List<GroupInvitation>? invitations])
    : invitations = invitations ?? sampleGroupInvitations();

  List<GroupInvitation> invitations;
  var fail = false;
  final answers = <(String, bool)>[];

  @override
  Future<List<GroupInvitation>> list() async => invitations;

  @override
  Future<String?> respond(String invitationId, {required bool accept}) async {
    if (fail) {
      throw StateError('expired');
    }
    answers.add((invitationId, accept));
    final answered = invitations.firstWhere((i) => i.id == invitationId);
    invitations = [
      for (final invitation in invitations)
        if (invitation.id != invitationId) invitation,
    ];
    return accept ? answered.conversationId : null;
  }
}

List<GroupInvitation> sampleGroupInvitations() {
  final now = DateTime.now().toUtc();
  return [
    GroupInvitation(
      id: 'invite-1',
      conversationId: 'group-1',
      groupTitle: 'Weekend climbers',
      inviterId: 'user-2',
      inviterName: 'Bart the Bold',
      inviterUsername: 'bart',
      createdAt: now.subtract(const Duration(hours: 3)),
      expiresAt: now.add(const Duration(days: 6, hours: 21)),
    ),
  ];
}

List<Override> privacy2Overrides({
  FakePrivacyPermissionsRepository? permissions,
  FakeSecurityAlertsRepository? alerts,
  FakeGroupInvitationsRepository? invitations,
  String? currentSessionId,
}) => [
  privacyPermissionsRepositoryProvider.overrideWithValue(
    permissions ?? FakePrivacyPermissionsRepository(),
  ),
  securityAlertsRepositoryProvider.overrideWithValue(
    alerts ?? FakeSecurityAlertsRepository(),
  ),
  groupInvitationsRepositoryProvider.overrideWithValue(
    invitations ?? FakeGroupInvitationsRepository(),
  ),
  currentSessionIdProvider.overrideWithValue(currentSessionId ?? 'mac'),
];
