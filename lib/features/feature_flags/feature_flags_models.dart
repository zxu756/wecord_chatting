import 'package:flutter/foundation.dart';

/// What `get_my_flags` answers: which flags are on for this person on this
/// app, and the lowest version of the app the server still lets run.
@immutable
class FeatureFlagSnapshot {
  const FeatureFlagSnapshot({this.flags = const {}, this.minVersion = ''});

  factory FeatureFlagSnapshot.fromJson(Object? json) {
    if (json is! Map) {
      return const FeatureFlagSnapshot();
    }
    final flags = json['flags'];
    final minVersion = json['min_version'];
    return FeatureFlagSnapshot(
      flags: {
        if (flags is Map)
          for (final entry in flags.entries)
            if (entry.key is String && entry.value is bool)
              entry.key as String: entry.value as bool,
      },
      minVersion: minVersion is String ? minVersion.trim() : '',
    );
  }

  /// Flag key to on or off. A key that is not here is decided by the
  /// default in the code.
  final Map<String, bool> flags;

  /// The lowest app version allowed, or '' for no requirement.
  final String minVersion;

  Map<String, Object?> toJson() => {'flags': flags, 'min_version': minVersion};

  @override
  bool operator ==(Object other) =>
      other is FeatureFlagSnapshot &&
      other.minVersion == minVersion &&
      mapEquals(other.flags, flags);

  @override
  int get hashCode => Object.hash(minVersion, Object.hashAll(flags.entries));
}

/// "1.2.3", "1.2", "v1.2.3+45" and "1.2.3-beta" as [1, 2, 3]; null when the
/// text is not a version. The same rule as `version_parts` in the database
/// (migration 202610240600).
List<int>? parseAppVersion(String? text) {
  if (text == null) {
    return null;
  }
  var core = text.trim();
  if (core.startsWith('v') || core.startsWith('V')) {
    core = core.substring(1);
  }
  core = core.split('+').first.split('-').first;
  if (!RegExp(r'^[0-9]{1,6}(\.[0-9]{1,6}){0,2}$').hasMatch(core)) {
    return null;
  }
  final parts = [for (final piece in core.split('.')) int.parse(piece)];
  while (parts.length < 3) {
    parts.add(0);
  }
  return parts;
}

/// Whether [version] is at least [minimum]. No minimum, a minimum that is
/// not a version, or a version that is not one (a development build) all
/// count as yes: a mistake in a setting must never lock people out.
bool appVersionAtLeast(String version, String minimum) {
  final need = parseAppVersion(minimum);
  final have = parseAppVersion(version);
  if (need == null || have == null) {
    return true;
  }
  for (var i = 0; i < 3; i++) {
    if (have[i] != need[i]) {
      return have[i] > need[i];
    }
  }
  return true;
}
