import 'package:wecord/shared/l10n/l10n.dart';

/// How a user shows up: the status they picked, or [idle] after a while
/// without input. Others never see [invisible]; to them it is offline.
enum PresenceStatus {
  online('online'),
  idle('idle'),
  doNotDisturb('dnd'),
  invisible('invisible');

  const PresenceStatus(this.value);

  /// The stored and broadcast value.
  final String value;

  /// [value]'s status; anything unknown is [online].
  static PresenceStatus fromJson(Object? value) {
    return PresenceStatus.values
            .where((status) => status.value == value)
            .firstOrNull ??
        PresenceStatus.online;
  }

  String get label => switch (this) {
    PresenceStatus.online => tr('Online'),
    PresenceStatus.idle => tr('Idle'),
    PresenceStatus.doNotDisturb => tr('Do Not Disturb'),
    PresenceStatus.invisible => tr('Invisible'),
  };

  /// A line under the label in the status picker.
  String? get description => switch (this) {
    PresenceStatus.online => null,
    PresenceStatus.idle => null,
    PresenceStatus.doNotDisturb => tr(
      'You will not get notifications on any device.',
    ),
    PresenceStatus.invisible => tr(
      'You will appear offline, but still have full access to WeCord.',
    ),
  };
}

/// The current user's own presence choices, kept on the server.
class PresenceSettings {
  const PresenceSettings({
    this.status = PresenceStatus.online,
    this.showOnlineStatus = true,
  });

  factory PresenceSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const PresenceSettings();
    }
    return PresenceSettings(
      status: PresenceStatus.fromJson(json['presence_status']),
      showOnlineStatus: json['show_online_status'] as bool? ?? true,
    );
  }

  final PresenceStatus status;

  /// The Settings switch; off hides the user like [PresenceStatus.invisible].
  final bool showOnlineStatus;

  /// Whether others see the user offline whatever happens.
  bool get hidden => !showOnlineStatus || status == PresenceStatus.invisible;

  PresenceSettings copyWith({PresenceStatus? status, bool? showOnlineStatus}) {
    return PresenceSettings(
      status: status ?? this.status,
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PresenceSettings &&
      other.status == status &&
      other.showOnlineStatus == showOnlineStatus;

  @override
  int get hashCode => Object.hash(status, showOnlineStatus);
}
