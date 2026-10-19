import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:wecord/features/file_preview/viewers/video_preview.dart';
import 'package:wecord/features/stories/stories_models.dart';
import 'package:wecord/features/stories/story_viewer_screen.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'stories_fakes.dart';

/// A player that plays nothing: the test moves its clock.
class FakeVideoController extends VideoPlayerController {
  FakeVideoController({this.length = const Duration(seconds: 9)})
    : super.networkUrl(Uri.parse('fake://video'));

  final Duration length;
  var failToStart = false;
  var playing = false;
  var disposed = false;

  @override
  Future<void> initialize() async {
    if (failToStart) {
      throw Exception('cannot play');
    }
    value = value.copyWith(
      isInitialized: true,
      duration: length,
      size: const Size(360, 640),
    );
  }

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> play() async {
    playing = true;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    playing = false;
    value = value.copyWith(isPlaying: false);
  }

  /// The player reaches [position].
  void moveTo(Duration position) {
    value = value.copyWith(position: position);
  }

  // The real dispose would talk to a platform player that is not there.
  @override
  // ignore: must_call_super
  Future<void> dispose() async {
    disposed = true;
  }
}

Widget _app(
  FakeStoriesRepository repository,
  FakeVideoController controller, {
  bool reduceMotion = false,
}) {
  final entries = [entry('user-2', stories: 2)];
  return ProviderScope(
    overrides: [
      ...storiesOverrides(repository: repository),
      videoControllerFactoryProvider.overrideWithValue(
        ({url, localPath}) => controller,
      ),
    ],
    child: MaterialApp(
      theme: WeCordTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open'),
            onPressed: () =>
                openStoryViewer(context, entries: entries, start: 'user-2'),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump();
}

double _filled(WidgetTester tester, int segment) {
  final fills = find.descendant(
    of: find.byKey(const ValueKey('story-progress')),
    matching: find.byType(FractionallySizedBox),
  );
  return tester.widget<FractionallySizedBox>(fills.at(segment)).widthFactor!;
}

void main() {
  late FakeStoriesRepository repository;
  late FakeVideoController controller;

  setUp(() {
    repository = FakeStoriesRepository()
      ..stories['user-2'] = [
        story('v1', kind: StoryMediaKind.video, caption: 'A walk'),
        story('p1', caption: 'After the walk'),
      ];
    controller = FakeVideoController();
  });

  testWidgets('a video plays, its progress fills the bar, then the next', (
    tester,
  ) async {
    await tester.pumpWidget(_app(repository, controller));
    await _open(tester);

    expect(find.text('A walk'), findsOneWidget);
    expect(controller.playing, isTrue);
    expect(_filled(tester, 0), 0);

    controller.moveTo(const Duration(milliseconds: 4500));
    await tester.pump();
    expect(_filled(tester, 0), closeTo(0.5, 0.01));

    controller.moveTo(const Duration(seconds: 9));
    await tester.pump();
    await tester.pump();
    expect(find.text('After the walk'), findsOneWidget);
  });

  testWidgets('holding pauses the video and letting go plays it again', (
    tester,
  ) async {
    await tester.pumpWidget(_app(repository, controller));
    await _open(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('story-surface'))),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(controller.playing, isFalse);

    await gesture.up();
    await tester.pump();
    expect(controller.playing, isTrue);
  });

  testWidgets('writing a reply pauses the video', (tester) async {
    await tester.pumpWidget(_app(repository, controller));
    await _open(tester);

    await tester.tap(find.byKey(const ValueKey('story-reply-field')));
    await tester.pump();
    expect(controller.playing, isFalse);
  });

  testWidgets('a video that cannot play is skipped', (tester) async {
    controller.failToStart = true;
    await tester.pumpWidget(_app(repository, controller));
    await _open(tester);
    await tester.pump();
    expect(find.text('After the walk'), findsOneWidget);
  });

  testWidgets('with reduced motion the video waits for the play button', (
    tester,
  ) async {
    await tester.pumpWidget(_app(repository, controller, reduceMotion: true));
    await _open(tester);

    expect(controller.playing, isFalse);
    expect(find.byKey(const ValueKey('story-play')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('story-play')));
    await tester.pump();
    expect(controller.playing, isTrue);
    expect(find.byKey(const ValueKey('story-play')), findsNothing);
  });

  testWidgets('closing the viewer lets the player go', (tester) async {
    await tester.pumpWidget(_app(repository, controller));
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('story-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(controller.disposed, isTrue);
  });
}
