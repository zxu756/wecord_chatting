import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/feature_flags/feature_flags_models.dart';
import 'package:wecord/features/feature_flags/feature_flags_repository.dart';
import 'package:wecord/features/privacy/device_info.dart' show appVersion;

/// What a flag is when the server has not said (it was never created, the
/// request failed and nothing is cached): off unless it is listed here. A
/// feature that must keep working without a connection gets `true` here.
const featureFlagDefaults = <String, bool>{};

/// How long the start waits for the server before it goes on with what it
/// has. The app never waits for this: it only decides how long a request
/// may take.
const featureFlagsTimeout = Duration(seconds: 8);

/// The app's version, from the build (`--dart-define=APP_VERSION=1.2.3`).
final appVersionProvider = Provider<String>((ref) => appVersion);

/// 'web', 'ios', 'android', 'macos', 'windows' or 'linux': the name the
/// minimum version is kept under.
final appPlatformProvider = Provider<String>((ref) {
  if (kIsWeb) {
    return 'web';
  }
  return defaultTargetPlatform.name.toLowerCase();
});

/// Where the flags stand.
@immutable
class FeatureFlagsState {
  const FeatureFlagsState({
    this.snapshot = const FeatureFlagSnapshot(),
    this.fromServer = false,
  });

  final FeatureFlagSnapshot snapshot;

  /// Whether the server has answered in this run (else this is the cache or
  /// the defaults).
  final bool fromServer;
}

final featureFlagsProvider =
    NotifierProvider<FeatureFlagsController, FeatureFlagsState>(
      FeatureFlagsController.new,
    );

/// Loads the cached flags at once, asks the server, and asks again when
/// another person signs in. A failed request leaves what there is: nothing
/// here throws or holds the app up.
class FeatureFlagsController extends Notifier<FeatureFlagsState> {
  var _generation = 0;
  String? _askedFor;
  var _asked = false;

  @override
  FeatureFlagsState build() {
    ref.listen<String?>(authStateProvider.select((auth) => auth.value?.id), (
      previous,
      next,
    ) {
      if (_asked && next != _askedFor) {
        unawaited(refresh());
      }
    });
    unawaited(Future<void>.microtask(_start));
    return const FeatureFlagsState();
  }

  String? get _userId => ref.read(authStateProvider).value?.id;

  Future<void> _start() async {
    final cached = await ref.read(featureFlagCacheProvider).load();
    if (cached != null && !state.fromServer && ref.mounted) {
      // The lowest version applies whoever it was cached for; flags only for
      // the same person.
      state = FeatureFlagsState(
        snapshot: FeatureFlagSnapshot(
          flags: cached.userId == _userId ? cached.snapshot.flags : const {},
          minVersion: cached.snapshot.minVersion,
        ),
      );
    }
    await refresh();
  }

  /// Asks the server again (also after the update page's "Check again").
  Future<void> refresh() async {
    final generation = ++_generation;
    final userId = _userId;
    _asked = true;
    _askedFor = userId;
    try {
      final snapshot = await ref
          .read(featureFlagsRepositoryProvider)
          .fetch(
            platform: ref.read(appPlatformProvider),
            version: ref.read(appVersionProvider),
          )
          .timeout(featureFlagsTimeout);
      if (!ref.mounted || generation != _generation) {
        return;
      }
      state = FeatureFlagsState(snapshot: snapshot, fromServer: true);
      await ref
          .read(featureFlagCacheProvider)
          .save(CachedFeatureFlags(snapshot: snapshot, userId: userId));
    } catch (_) {
      // Offline, the function is missing, the server is slow: go on with
      // the cache or the defaults.
    }
  }
}

/// Whether the flag [key] is on for this person: the server's answer, else
/// the cached one, else [featureFlagDefaults], else off.
///
/// A flag only decides what the app shows. A rule that has to hold is a
/// policy or a check in the database, never a flag.
final featureFlagProvider = Provider.family<bool, String>((ref, key) {
  final value = ref.watch(
    featureFlagsProvider.select((state) => state.snapshot.flags[key]),
  );
  return value ?? featureFlagDefaults[key] ?? false;
});

/// Whether this version of the app is older than the server allows.
final updateRequiredProvider = Provider<bool>((ref) {
  final minimum = ref.watch(
    featureFlagsProvider.select((state) => state.snapshot.minVersion),
  );
  return !appVersionAtLeast(ref.watch(appVersionProvider), minimum);
});

/// The lowest version allowed ('' when there is none), for the update page.
final minimumVersionProvider = Provider<String>((ref) {
  return ref.watch(
    featureFlagsProvider.select((state) => state.snapshot.minVersion),
  );
});
