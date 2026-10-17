import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/settings/data_export.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

DataExportStatus working(String stage, int progress, {String? detail}) {
  return DataExportStatus(
    id: 'x-1',
    phase: DataExportPhase.working,
    stage: stage,
    progress: progress,
    detail: detail,
  );
}

DataExportStatus ready({String? url = 'https://files.example/export.zip'}) {
  return DataExportStatus(
    id: 'x-1',
    phase: DataExportPhase.ready,
    stage: 'ready',
    progress: 100,
    byteSize: 3 * 1024 * 1024,
    expiresAt: DateTime.now().add(const Duration(days: 6, hours: 23)),
    downloadUrl: url,
  );
}

class FakeDataExportRepository implements DataExportRepository {
  /// What `status` answers, in order; the last one repeats.
  List<DataExportStatus?> statuses = [null];
  Object? startError;
  var starts = 0;
  var statusCalls = 0;

  @override
  Future<String> start() async {
    starts++;
    final error = startError;
    if (error != null) throw error;
    return 'x-1';
  }

  @override
  Future<DataExportStatus?> status({String? id}) async {
    final index = statusCalls < statuses.length
        ? statusCalls
        : statuses.length - 1;
    statusCalls++;
    return statuses[index];
  }
}

void main() {
  group('status', () {
    test('reads the function answer', () {
      final status = DataExportStatus.fromJson({
        'id': 'x-1',
        'status': 'ready',
        'stage': 'ready',
        'progress': 100,
        'detail': null,
        'byte_size': 2048,
        'created_at': '2026-10-17T10:00:00+00:00',
        'expires_at': '2026-10-24T10:00:00+00:00',
        'download_url': 'https://files.example/a.zip',
      });
      expect(status.phase, DataExportPhase.ready);
      expect(status.byteSize, 2048);
      expect(status.downloadUrl, 'https://files.example/a.zip');
      expect(
        DataExportStatus.fromJson({
          'id': 'x',
          'status': 'working',
          'progress': 250,
        }).progress,
        100,
      );
      expect(DataExportPhase.fromJson('weird'), DataExportPhase.working);
    });

    test('words for stages, sizes and waits', () {
      expect(dataExportStageLabel('messages'), 'Collecting your messages…');
      expect(dataExportStageLabel('nonsense'), 'Getting ready…');
      expect(dataExportSize(900), '900 B');
      expect(dataExportSize(2048), '2 KB');
      expect(dataExportSize(3 * 1024 * 1024), '3.0 MB');
      expect(dataExportWaitText(const Duration(hours: 5)), '5 hours');
      expect(
        dataExportWaitText(const Duration(hours: 23, minutes: 1)),
        '24 hours',
      );
      expect(dataExportWaitText(const Duration(minutes: 20)), '20 minutes');
    });
  });

  group('controller', () {
    late FakeDataExportRepository repository;

    ProviderContainer make() {
      final container = ProviderContainer(
        overrides: [dataExportRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('offers a request when there is no export', () async {
      repository = FakeDataExportRepository();
      final container = make();
      container.listen(dataExportControllerProvider, (_, _) {});
      expect(
        container.read(dataExportControllerProvider),
        isA<DataExportLoading>(),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(dataExportControllerProvider),
        isA<DataExportIdle>(),
      );
    });

    test('follows an export until it is ready', () async {
      repository = FakeDataExportRepository()
        ..statuses = [
          null,
          working('queued', 0),
          working('messages', 40, detail: '1000'),
          ready(),
        ];
      final container = make();
      // Keep the provider alive.
      container.listen(dataExportControllerProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      await container.read(dataExportControllerProvider.notifier).start();
      DataExportStatus current() =>
          (container.read(dataExportControllerProvider) as DataExportActive)
              .status;
      expect(current().stage, 'queued');

      await Future<void>.delayed(
        DataExportController.pollInterval + const Duration(milliseconds: 200),
      );
      expect(current().progress, 40);

      await Future<void>.delayed(
        DataExportController.pollInterval + const Duration(milliseconds: 200),
      );
      expect(current().phase, DataExportPhase.ready);
    });

    test('shows the wait when asked twice in a day', () async {
      repository = FakeDataExportRepository()
        ..statuses = [null, ready()]
        ..startError = const DataExportRateLimited(Duration(hours: 5));
      final container = make();
      container.listen(dataExportControllerProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      await container.read(dataExportControllerProvider.notifier).start();
      final state = container.read(dataExportControllerProvider);
      expect(state, isA<DataExportWait>());
      expect((state as DataExportWait).retryAfter, const Duration(hours: 5));
      expect(state.last?.phase, DataExportPhase.ready);
    });

    test('a failed last attempt can be retried', () async {
      repository = FakeDataExportRepository()
        ..statuses = [
          const DataExportStatus(
            id: 'x-0',
            phase: DataExportPhase.failed,
            stage: 'messages',
            progress: 40,
          ),
        ];
      final container = make();
      container.listen(dataExportControllerProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final state = container.read(dataExportControllerProvider);
      expect(state, isA<DataExportIdle>());
      expect((state as DataExportIdle).lastFailed, isTrue);
    });

    test('an error from the server ends in an error state', () async {
      repository = FakeDataExportRepository()..startError = StateError('boom');
      final container = make();
      container.listen(dataExportControllerProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      await container.read(dataExportControllerProvider.notifier).start();
      expect(
        container.read(dataExportControllerProvider),
        isA<DataExportError>(),
      );
    });
  });

  group('screen', () {
    Future<FakeDataExportRepository> openScreen(
      WidgetTester tester, {
      List<DataExportStatus?> statuses = const [null],
      List<Uri>? launched,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = FakeDataExportRepository()..statuses = statuses;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dataExportRepositoryProvider.overrideWithValue(repository),
            dataExportLauncherProvider.overrideWithValue((uri) async {
              launched?.add(uri);
              return true;
            }),
          ],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: const DataExportScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return repository;
    }

    testWidgets('explains what is included and requests', (tester) async {
      final repository = await openScreen(tester);
      expect(find.text('Download my data'), findsWidgets);
      expect(find.text('Your profile and settings'), findsOneWidget);
      expect(
        find.text('Messages you sent, with links to your files'),
        findsOneWidget,
      );
      repository.statuses = [null, working('queued', 0)];
      await tester.tap(find.byKey(const ValueKey('data-export-request')));
      await tester.pump();
      await tester.pump();
      expect(repository.starts, 1);
      expect(
        find.byKey(const ValueKey('data-export-progress')),
        findsOneWidget,
      );
      expect(find.text('Getting ready…'), findsOneWidget);
      // Dispose the poll timer.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('shows the stage and percent of a running export', (
      tester,
    ) async {
      await openScreen(
        tester,
        statuses: [working('messages', 40, detail: '1000')],
      );
      expect(find.text('Collecting your messages…'), findsOneWidget);
      expect(find.byKey(const ValueKey('data-export-percent')), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('1000 messages so far'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a ready export can be downloaded', (tester) async {
      final launched = <Uri>[];
      await openScreen(tester, statuses: [ready()], launched: launched);
      expect(find.byKey(const ValueKey('data-export-ready')), findsOneWidget);
      expect(find.textContaining('3.0 MB'), findsOneWidget);
      expect(find.textContaining('Deleted in 6 days'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('data-export-download')));
      await tester.pump();
      expect(launched.single.toString(), 'https://files.example/export.zip');
      // Another request is not offered while this one is ready.
      expect(find.byKey(const ValueKey('data-export-request')), findsNothing);
    });

    testWidgets('a failed attempt says so and offers another', (tester) async {
      await openScreen(
        tester,
        statuses: [
          const DataExportStatus(
            id: 'x',
            phase: DataExportPhase.failed,
            stage: 'messages',
            progress: 40,
          ),
        ],
      );
      expect(find.byKey(const ValueKey('data-export-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('data-export-request')), findsOneWidget);
    });
  });
}
