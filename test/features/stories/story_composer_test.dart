import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/friend_tags/friend_tags_repository.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moment_photos.dart';
import 'package:wecord/features/photo_editor/editor_model.dart';
import 'package:wecord/features/photo_editor/photo_editor_screen.dart';
import 'package:wecord/features/stories/stories_providers.dart';
import 'package:wecord/features/stories/story_composer_screen.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../moments/moments_fakes.dart'
    show FakeFriendTagsRepository, sampleVideo;
import 'stories_fakes.dart';

Profile _friend(String id, String name) {
  final now = DateTime.utc(2026, 5, 18);
  return Profile(
    id: id,
    username: name.toLowerCase().replaceAll(' ', ''),
    displayName: name,
    bio: '',
    createdAt: now,
    updatedAt: now,
  );
}

final _friends = [
  _friend('user-2', 'Ada Lovelace'),
  _friend('user-3', 'Grace Hopper'),
];

Widget _app(
  FakeStoriesRepository repository, {
  FakeStoryMediaPicker? picker,
  Widget? screen,
}) {
  return ProviderScope(
    overrides: [
      ...storiesOverrides(repository: repository, picker: picker),
      friendTagsRepositoryProvider.overrideWithValue(
        FakeFriendTagsRepository(),
      ),
      friendsProvider.overrideWith((ref) async => _friends),
      authStateProvider.overrideWith(
        (ref) => Stream.value(const AuthUser(id: 'user-1')),
      ),
    ],
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: screen != null
          ? Scaffold(
              body: Center(
                child: Consumer(
                  builder: (context, ref, _) => TextButton(
                    key: const ValueKey('open'),
                    onPressed: () => Navigator.of(
                      context,
                    ).push<void>(MaterialPageRoute(builder: (_) => screen)),
                    child: const Text('Open'),
                  ),
                ),
              ),
            )
          : Scaffold(
              body: Center(
                child: Consumer(
                  builder: (context, ref, _) => TextButton(
                    key: const ValueKey('open'),
                    onPressed: () => openStoryComposer(context, ref),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
    ),
  );
}

Future<void> _tapOpen(WidgetTester tester) async {
  // Tall, so the whole form is built.
  tester.view.physicalSize = const Size(800, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
}

Future<void> _post(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('story-post')));
  // The picture is scaled in an isolate: give it real time, a little at a
  // time, until the post is done or has failed.
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final posting = find.byKey(const ValueKey('story-post'));
    if (posting.evaluate().isEmpty) {
      break;
    }
    final button = tester.widget<WeCordButton>(posting);
    if (!button.loading) {
      break;
    }
  }
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  late FakeStoriesRepository repository;

  setUp(() => repository = FakeStoriesRepository());

  group('choosing a video', () {
    testWidgets('a video goes to the composer, with its length and no editor', (
      tester,
    ) async {
      final picker = FakeStoryMediaPicker()..video = sampleVideo(seconds: 9);
      await tester.pumpWidget(_app(repository, picker: picker));
      await _tapOpen(tester);

      await tester.tap(find.byKey(const ValueKey('story-source-video')));
      await tester.pumpAndSettle();

      expect(picker.picks, ['video']);
      expect(find.byType(PhotoEditorScreen), findsNothing);
      expect(find.byKey(const ValueKey('story-preview')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-edit-photo')), findsNothing);
      expect(find.text('Post'), findsOneWidget);
    });

    testWidgets('posting sends the video with its caption and audience', (
      tester,
    ) async {
      final video = sampleVideo(seconds: 9);
      final picker = FakeStoryMediaPicker()..video = video;
      await tester.pumpWidget(_app(repository, picker: picker));
      await _tapOpen(tester);
      await tester.tap(find.byKey(const ValueKey('story-source-video')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('story-caption-field')),
        'On the ridge',
      );
      await _post(tester);

      expect(repository.created, hasLength(1));
      final created = repository.created.single;
      expect(created.caption, 'On the ridge');
      expect(created.video, same(video));
      expect(created.photo, isNull);
      expect(created.audience, MomentAudience.everyone);
      // Back on the page it came from, with the news.
      expect(find.byKey(const ValueKey('story-post')), findsNothing);
      expect(find.text('Your daily is up.'), findsOneWidget);
    });

    testWidgets('a video over the limit is said in words, not opened', (
      tester,
    ) async {
      final picker = FakeStoryMediaPicker()
        ..videoProblem = MomentVideoProblem.tooLong;
      await tester.pumpWidget(_app(repository, picker: picker));
      await _tapOpen(tester);
      await tester.tap(find.byKey(const ValueKey('story-source-video')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'That video is longer than 15 seconds. Choose a shorter one.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('story-post')), findsNothing);

      picker.videoProblem = MomentVideoProblem.tooBig;
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('story-source-video')));
      await tester.pumpAndSettle();
      expect(
        find.text('That video is bigger than 20 MB. Choose a smaller one.'),
        findsOneWidget,
      );
    });

    testWidgets('cancelling the picker does nothing', (tester) async {
      final picker = FakeStoryMediaPicker();
      await tester.pumpWidget(_app(repository, picker: picker));
      await _tapOpen(tester);
      await tester.tap(find.byKey(const ValueKey('story-source-video')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('story-post')), findsNothing);
      expect(repository.created, isEmpty);
    });
  });

  group('choosing a photo', () {
    testWidgets('a photo opens the photo editor first', (tester) async {
      final picker = FakeStoryMediaPicker()..photo = samplePickedPhoto();
      await tester.pumpWidget(_app(repository, picker: picker));
      await _tapOpen(tester);
      await tester.tap(find.byKey(const ValueKey('story-source-photo')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(picker.picks, ['photo']);
      expect(find.byType(PhotoEditorScreen), findsOneWidget);
    });
  });

  group('the composer with a photo', () {
    StoryComposerScreen photoScreen() => StoryComposerScreen(
      photo: samplePickedPhoto(),
      edit: const PhotoEditResult(document: EditorDocument()),
    );

    testWidgets('shows the photo and an Edit button', (tester) async {
      await tester.pumpWidget(_app(repository, screen: photoScreen()));
      await _tapOpen(tester);
      expect(find.byKey(const ValueKey('story-preview')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-edit-photo')), findsOneWidget);
      expect(find.text('Who can see this'), findsOneWidget);
      expect(find.text('Friends'), findsOneWidget);
    });

    testWidgets('posting scales the photo and sends it', (tester) async {
      await tester.pumpWidget(_app(repository, screen: photoScreen()));
      await _tapOpen(tester);
      await _post(tester);

      expect(repository.created, hasLength(1));
      final photo = repository.created.single.photo!;
      expect(photo.full, isNotEmpty);
      expect(photo.thumb, isNotEmpty);
      expect(photo.width, greaterThan(0));
      expect(repository.created.single.video, isNull);
    });

    testWidgets('a failed post says so, and trying again keeps the id', (
      tester,
    ) async {
      repository.failNext = Exception('offline');
      await tester.pumpWidget(_app(repository, screen: photoScreen()));
      await _tapOpen(tester);
      await _post(tester);

      expect(find.byKey(const ValueKey('story-error')), findsOneWidget);
      expect(repository.created, isEmpty);

      await _post(tester);
      expect(repository.created, hasLength(1));
      expect(find.byKey(const ValueKey('story-post')), findsNothing);
    });

    testWidgets('the caption stops at 200 characters', (tester) async {
      await tester.pumpWidget(_app(repository, screen: photoScreen()));
      await _tapOpen(tester);
      await tester.enterText(
        find.byKey(const ValueKey('story-caption-field')),
        'x' * 260,
      );
      await tester.pump();
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('story-caption-field')),
      );
      expect(field.controller!.text.length, 200);
    });
  });

  group('who can see it', () {
    StoryComposerScreen photoScreen() => StoryComposerScreen(
      photo: samplePickedPhoto(),
      edit: const PhotoEditResult(document: EditorDocument()),
    );

    Future<void> openAudience(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('story-audience')));
      await tester.pumpAndSettle();
    }

    testWidgets('the sheet offers Close friends, unlike Moments', (
      tester,
    ) async {
      await tester.pumpWidget(_app(repository, screen: photoScreen()));
      await _tapOpen(tester);
      await openAudience(tester);
      expect(find.byKey(const ValueKey('audience-close')), findsOneWidget);
      expect(find.byKey(const ValueKey('audience-private')), findsOneWidget);
      expect(find.byKey(const ValueKey('audience-only')), findsOneWidget);
      expect(find.byKey(const ValueKey('audience-except')), findsOneWidget);
    });

    testWidgets('Close friends with nobody on the list asks for them first', (
      tester,
    ) async {
      await tester.pumpWidget(_app(repository, screen: photoScreen()));
      await _tapOpen(tester);
      await openAudience(tester);
      await tester.tap(find.byKey(const ValueKey('audience-close')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('audience-done')));
      await tester.pumpAndSettle();
      expect(find.text('Close friends'), findsOneWidget);

      await _post(tester);
      expect(find.text('Choose your close friends first.'), findsOneWidget);
      expect(repository.created, isEmpty);
    });

    testWidgets('editing the list saves it, and then the daily goes out', (
      tester,
    ) async {
      await tester.pumpWidget(_app(repository, screen: photoScreen()));
      await _tapOpen(tester);
      await openAudience(tester);
      await tester.tap(find.byKey(const ValueKey('audience-close')));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('audience-edit-close-friends')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ada Lovelace'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('close-friend-user-2')));
      await tester.pump();
      expect(find.text('Save (1)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('close-friends-save')));
      await tester.pumpAndSettle();

      expect(repository.savedCloseFriends, [
        {'user-2'},
      ]);
      await tester.tap(find.byKey(const ValueKey('audience-done')));
      await tester.pumpAndSettle();
      await _post(tester);

      expect(repository.created, hasLength(1));
      expect(
        repository.created.single.audience.visibility,
        MomentVisibility.close,
      );
    });

    testWidgets('only me and a chosen few are posted as chosen', (
      tester,
    ) async {
      await tester.pumpWidget(_app(repository, screen: photoScreen()));
      await _tapOpen(tester);
      await openAudience(tester);
      await tester.tap(find.byKey(const ValueKey('audience-private')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('audience-done')));
      await tester.pumpAndSettle();
      expect(find.text('Only me'), findsOneWidget);
      await _post(tester);
      expect(
        repository.created.single.audience.visibility,
        MomentVisibility.private,
      );
    });
  });

  group('close friends', () {
    testWidgets('the list starts with who is on it and can be emptied', (
      tester,
    ) async {
      repository.closeFriendIds = {'user-2', 'user-3'};
      await tester.pumpWidget(
        _app(
          repository,
          screen: StoryComposerScreen(
            photo: samplePickedPhoto(),
            edit: const PhotoEditResult(document: EditorDocument()),
          ),
        ),
      );
      await _tapOpen(tester);
      await tester.tap(find.byKey(const ValueKey('story-audience')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('audience-close')));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('audience-edit-close-friends')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Save (2)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('close-friend-user-2')));
      await tester.tap(find.byKey(const ValueKey('close-friend-user-3')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('close-friends-save')));
      await tester.pumpAndSettle();
      expect(repository.closeFriendIds, isEmpty);
    });

    testWidgets('a list that cannot be saved says so', (tester) async {
      await tester.pumpWidget(
        _app(
          repository,
          screen: StoryComposerScreen(
            photo: samplePickedPhoto(),
            edit: const PhotoEditResult(document: EditorDocument()),
          ),
        ),
      );
      await _tapOpen(tester);
      await tester.tap(find.byKey(const ValueKey('story-audience')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('audience-close')));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('audience-edit-close-friends')),
      );
      await tester.pumpAndSettle();
      repository.failNext = Exception('offline');
      await tester.tap(find.byKey(const ValueKey('close-friends-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('close-friends-error')), findsOneWidget);
    });
  });

  testWidgets('posting refreshes the row of dailies', (tester) async {
    final picker = FakeStoryMediaPicker()..video = sampleVideo(seconds: 5);
    await tester.pumpWidget(_app(repository, picker: picker));
    await _tapOpen(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const ValueKey('open'))),
    );
    container.listen(storiesTrayProvider, (previous, next) {});
    await tester.pump();
    final before = repository.trayCalls;
    await tester.tap(find.byKey(const ValueKey('story-source-video')));
    await tester.pumpAndSettle();
    await _post(tester);
    expect(repository.trayCalls, greaterThan(before));
  });
}
