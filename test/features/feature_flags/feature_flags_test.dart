import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/feature_flags/feature_flags_models.dart';
import 'package:wecord/features/feature_flags/feature_flags_providers.dart';
import 'package:wecord/features/feature_flags/feature_flags_repository.dart';
import 'package:wecord/features/feature_flags/update_required_screen.dart';
import 'package:wecord/features/pwa/pwa_gateway.dart';
import 'package:wecord/features/pwa/pwa_providers.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

/// Answers `get_my_flags` from a queue and records what it was asked.
class FakeFlagsRepository implements FeatureFlagsRepository {
  final answers = <Object>[];
  final asked = <({String platform, String version})>[];

  @override
  Future<FeatureFlagSnapshot> fetch({
    required String platform,
    required String version,
  }) async {
    asked.add((platform: platform, version: version));
    if (answers.isEmpty) {
      throw StateError('offline');
    }
    final answer = answers.length > 1 ? answers.removeAt(0) : answers.first;
    if (answer is Future<FeatureFlagSnapshot>) {
      return answer;
    }
    if (answer is Exception) {
      throw answer;
    }
    return answer as FeatureFlagSnapshot;
  }
}

class _FakePwaGateway implements PwaGateway {
  var updates = 0;

  @override
  PwaState get state => const PwaState();

  @override
  Stream<PwaState> get changes => const Stream.empty();

  @override
  Future<PwaInstallOutcome> promptInstall() async =>
      PwaInstallOutcome.unavailable;

  @override
  Future<void> applyUpdate() async => updates++;

  @override
  void setBadge(int count) {}
}

/// Lets the controller's start (cache, then the server) finish.
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ProviderContainer containerWith({
  required FakeFlagsRepository repository,
  FeatureFlagCache? cache,
  String version = '1.0.0',
  Stream<AuthUser?>? auth,
  List<Override> more = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      featureFlagsRepositoryProvider.overrideWithValue(repository),
      featureFlagCacheProvider.overrideWithValue(
        cache ?? InMemoryFeatureFlagCache(),
      ),
      appVersionProvider.overrideWithValue(version),
      appPlatformProvider.overrideWithValue('web'),
      authStateProvider.overrideWith(
        (ref) => auth ?? Stream.value(const AuthUser(id: 'u-1')),
      ),
      ...more,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('versions', () {
    // The same cases as the database's version_at_least
    // (test/supabase/admin_ops_behaviour.sql).
    test('compare the way the database does', () {
      expect(appVersionAtLeast('1.2.3', '1.2.3'), isTrue);
      expect(appVersionAtLeast('1.2.2', '1.2.3'), isFalse);
      expect(appVersionAtLeast('1.10.0', '1.9.0'), isTrue);
      expect(appVersionAtLeast('v1.2', '1.2.0'), isTrue);
      expect(appVersionAtLeast('1.2.3+45', '1.2.3'), isTrue);
      expect(appVersionAtLeast('0.9.9', '1.0.0'), isFalse);
      expect(appVersionAtLeast('dev', '1.0.0'), isTrue);
      expect(appVersionAtLeast('1.0.0', 'garbage'), isTrue);
      expect(appVersionAtLeast('0.0.1', ''), isTrue);
    });

    test('parse', () {
      expect(parseAppVersion('1.2'), [1, 2, 0]);
      expect(parseAppVersion(' V2.0.1-beta '), [2, 0, 1]);
      expect(parseAppVersion('1.2.3.4'), isNull);
      expect(parseAppVersion('x'), isNull);
      expect(parseAppVersion(null), isNull);
    });
  });

  group('the snapshot', () {
    test('keeps only booleans and strings, and survives junk', () {
      final snapshot = FeatureFlagSnapshot.fromJson({
        'flags': {'a': true, 'b': false, 'c': 'yes', 3: true},
        'min_version': ' 1.2.0 ',
      });
      expect(snapshot.flags, {'a': true, 'b': false});
      expect(snapshot.minVersion, '1.2.0');
      expect(FeatureFlagSnapshot.fromJson(null), const FeatureFlagSnapshot());
      expect(FeatureFlagSnapshot.fromJson('x').flags, isEmpty);
    });

    test('goes to JSON and back', () {
      const snapshot = FeatureFlagSnapshot(
        flags: {'a': true},
        minVersion: '2.0.0',
      );
      expect(FeatureFlagSnapshot.fromJson(snapshot.toJson()), snapshot);
    });
  });

  group('the flags at start', () {
    test(
      'the server\'s answer is used, kept, and asked for with the build',
      () async {
        final repository = FakeFlagsRepository()
          ..answers.add(
            const FeatureFlagSnapshot(
              flags: {'new_chat': true},
              minVersion: '',
            ),
          );
        final cache = InMemoryFeatureFlagCache();
        final container = containerWith(
          repository: repository,
          cache: cache,
          version: '1.4.0',
        );
        // Before anything has loaded a flag is off: the app never waits.
        expect(container.read(featureFlagProvider('new_chat')), isFalse);
        container.listen(featureFlagsProvider, (_, _) {});
        await settle();
        expect(container.read(featureFlagProvider('new_chat')), isTrue);
        expect(container.read(featureFlagProvider('other')), isFalse);
        expect(repository.asked.first, (platform: 'web', version: '1.4.0'));
        expect(cache.cached?.userId, 'u-1');
        expect(cache.cached?.snapshot.flags, {'new_chat': true});
      },
    );

    test('with no connection the cache is used', () async {
      final repository = FakeFlagsRepository(); // always fails
      final cache = InMemoryFeatureFlagCache(
        const CachedFeatureFlags(
          snapshot: FeatureFlagSnapshot(
            flags: {'new_chat': true},
            minVersion: '3.0.0',
          ),
          userId: 'u-1',
        ),
      );
      final container = containerWith(repository: repository, cache: cache);
      container.listen(featureFlagsProvider, (_, _) {});
      await settle();
      expect(container.read(featureFlagProvider('new_chat')), isTrue);
      expect(container.read(updateRequiredProvider), isTrue);
      expect(container.read(featureFlagsProvider).fromServer, isFalse);
    });

    test(
      'the flags of somebody else are not used, the minimum version is',
      () async {
        final repository = FakeFlagsRepository();
        final cache = InMemoryFeatureFlagCache(
          const CachedFeatureFlags(
            snapshot: FeatureFlagSnapshot(
              flags: {'new_chat': true},
              minVersion: '3.0.0',
            ),
            userId: 'somebody-else',
          ),
        );
        final container = containerWith(repository: repository, cache: cache);
        container.listen(featureFlagsProvider, (_, _) {});
        await settle();
        expect(container.read(featureFlagProvider('new_chat')), isFalse);
        expect(container.read(minimumVersionProvider), '3.0.0');
      },
    );

    test('a request that never answers does not hold anything up', () async {
      final repository = FakeFlagsRepository()
        ..answers.add(Completer<FeatureFlagSnapshot>().future);
      final container = containerWith(repository: repository);
      container.listen(featureFlagsProvider, (_, _) {});
      await settle();
      expect(container.read(featureFlagProvider('new_chat')), isFalse);
      expect(container.read(updateRequiredProvider), isFalse);
    });

    test('a failing cache does not matter', () async {
      final repository = FakeFlagsRepository()
        ..answers.add(const FeatureFlagSnapshot(flags: {'a': true}));
      final container = containerWith(
        repository: repository,
        cache: _BrokenCache(),
      );
      container.listen(featureFlagsProvider, (_, _) {});
      await settle();
      expect(container.read(featureFlagProvider('a')), isTrue);
    });

    test('another person signing in asks again', () async {
      final auth = StreamController<AuthUser?>();
      addTearDown(auth.close);
      final repository = FakeFlagsRepository()
        ..answers.addAll([
          const FeatureFlagSnapshot(flags: {'a': false}),
          const FeatureFlagSnapshot(flags: {'a': true}),
        ]);
      final container = containerWith(
        repository: repository,
        auth: auth.stream,
      );
      container.listen(authStateProvider, (_, _) {});
      container.listen(featureFlagsProvider, (_, _) {});
      auth.add(null);
      await settle();
      expect(container.read(featureFlagProvider('a')), isFalse);
      auth.add(const AuthUser(id: 'u-9'));
      await settle();
      expect(repository.asked, hasLength(2));
      expect(container.read(featureFlagProvider('a')), isTrue);
    });
  });

  group('the "Please update" page', () {
    Future<void> show(
      WidgetTester tester, {
      required FakeFlagsRepository repository,
      required String version,
      bool web = false,
      _FakePwaGateway? pwa,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            featureFlagsRepositoryProvider.overrideWithValue(repository),
            featureFlagCacheProvider.overrideWithValue(
              InMemoryFeatureFlagCache(),
            ),
            appVersionProvider.overrideWithValue(version),
            appPlatformProvider.overrideWithValue(web ? 'web' : 'ios'),
            authStateProvider.overrideWith(
              (ref) => Stream.value(const AuthUser(id: 'u-1')),
            ),
            pwaGatewayProvider.overrideWithValue(pwa ?? _FakePwaGateway()),
          ],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: const Scaffold(
              body: AppUpdateGate(child: Center(child: Text('the app'))),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an app that is new enough just runs', (tester) async {
      final repository = FakeFlagsRepository()
        ..answers.add(const FeatureFlagSnapshot(minVersion: '1.0.0'));
      await show(tester, repository: repository, version: '1.0.0');
      expect(find.text('the app'), findsOneWidget);
      expect(find.byType(UpdateRequiredScreen), findsNothing);
    });

    testWidgets('an app that is too old shows the page instead', (
      tester,
    ) async {
      final repository = FakeFlagsRepository()
        ..answers.add(const FeatureFlagSnapshot(minVersion: '1.2.0'));
      await show(tester, repository: repository, version: '1.1.9');
      expect(find.text('the app'), findsNothing);
      expect(find.text('Please update WeCord'), findsOneWidget);
      expect(
        find.text('You have 1.1.9. You need 1.2.0 or newer.'),
        findsOneWidget,
      );
    });

    testWidgets('on the web the button refreshes the page', (tester) async {
      final pwa = _FakePwaGateway();
      final repository = FakeFlagsRepository()
        ..answers.add(const FeatureFlagSnapshot(minVersion: '9.0.0'));
      // (The test runs as the web app through the screen's own switch.)
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            featureFlagsRepositoryProvider.overrideWithValue(repository),
            featureFlagCacheProvider.overrideWithValue(
              InMemoryFeatureFlagCache(),
            ),
            appVersionProvider.overrideWithValue('1.0.0'),
            appPlatformProvider.overrideWithValue('web'),
            authStateProvider.overrideWith((ref) => Stream.value(null)),
            pwaGatewayProvider.overrideWithValue(pwa),
          ],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: const UpdateRequiredScreen(onWeb: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Check again'), findsNothing);
      await tester.tap(find.byKey(UpdateRequiredScreen.refreshKey));
      await tester.pumpAndSettle();
      expect(pwa.updates, 1);
    });

    testWidgets('elsewhere it asks the server again, and lets go when fixed', (
      tester,
    ) async {
      final repository = FakeFlagsRepository()
        ..answers.addAll([
          const FeatureFlagSnapshot(minVersion: '2.0.0'),
          const FeatureFlagSnapshot(minVersion: ''),
        ]);
      await show(tester, repository: repository, version: '1.0.0');
      expect(find.text('Please update WeCord'), findsOneWidget);
      expect(find.text('Refresh'), findsNothing);
      await tester.tap(find.byKey(UpdateRequiredScreen.checkKey));
      await tester.pumpAndSettle();
      expect(repository.asked, hasLength(greaterThanOrEqualTo(2)));
      expect(find.text('the app'), findsOneWidget);
    });
  });
}

class _BrokenCache implements FeatureFlagCache {
  @override
  Future<CachedFeatureFlags?> load() async => null;

  @override
  Future<void> save(CachedFeatureFlags cached) async =>
      throw StateError('disk full');
}
