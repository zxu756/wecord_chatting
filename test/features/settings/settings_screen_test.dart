import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';
import 'package:wecord/features/notifications/notification_preferences_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/profile/profile_extras_repository.dart';
import 'package:wecord/features/profile/profile_repository.dart';
import 'package:wecord/features/profile/profile_social_repository.dart';
import 'package:wecord/features/settings/account_deletion.dart';
import 'package:wecord/features/settings/custom_status_sheet.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/theme/glass_effects_controller.dart';
import 'package:wecord/shared/theme/theme_mode_controller.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../presence/presence_repository_test.dart' as presence_fakes;
import '../profile/profile_extras_repository_test.dart';

void main() {
  testWidgets('edits and saves the current profile', (tester) async {
    final settingsRepository = FakeSettingsRepository();

    await tester.pumpWidget(_app(settingsRepository: settingsRepository));
    await tester.pump();
    await openProfileEditor(tester);

    expect(find.text('@ada'), findsOneWidget);
    expect(displayNameField, findsOneWidget);
    expect(bioField, findsOneWidget);

    await tester.enterText(displayNameField, 'Ada Byron');
    await tester.enterText(bioField, 'First programmer');
    await tapSave(tester);
    await tester.pump();

    expect(settingsRepository.updateCalls, [
      const UpdateProfileCall(
        displayName: 'Ada Byron',
        bio: 'First programmer',
        avatarUrl: 'avatars/existing.png',
      ),
    ]);
  });

  testWidgets('picks a status and hides online status', (tester) async {
    final presence = presence_fakes.FakePresenceRepository();
    await tester.pumpWidget(
      _app(
        settingsRepository: FakeSettingsRepository(),
        presenceRepository: presence,
      ),
    );
    await tester.pump();

    final tile = find.byKey(const ValueKey('presence-status-tile'));
    expect(
      find.descendant(of: tile, matching: find.text('Online')),
      findsOneWidget,
    );

    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('presence-option-dnd')));
    await tester.pumpAndSettle();

    expect(presence.savedStatuses, [PresenceStatus.doNotDisturb]);
    expect(
      find.descendant(of: tile, matching: find.text('Do Not Disturb')),
      findsOneWidget,
    );

    final showOnline = find.byKey(const ValueKey('show-online-status'));
    await tester.scrollUntilVisible(
      showOnline,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(showOnline);
    await tester.pumpAndSettle();
    expect(switchValue(tester, showOnline), isTrue);
    await tester.tap(showOnline);
    await tester.pump();

    expect(presence.savedShowOnline, [false]);
    expect(switchValue(tester, showOnline), isFalse);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: tile, matching: find.text('Invisible')),
      findsOneWidget,
    );
  });

  testWidgets('Privacy & Safety has the crash report switch, on', (
    tester,
  ) async {
    await tester.pumpWidget(_app(settingsRepository: FakeSettingsRepository()));
    await tester.pump();

    final toggle = find.byKey(const ValueKey('error-reports-toggle'));
    await tester.scrollUntilVisible(
      toggle,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Send crash and error reports'), findsOneWidget);
    expect(switchValue(tester, toggle), isTrue);
    expect(find.textContaining('never sends your messages'), findsOneWidget);
  });

  testWidgets('switches between system, light and dark', (tester) async {
    final store = InMemoryThemeModeStore();
    await tester.pumpWidget(
      _app(settingsRepository: FakeSettingsRepository(), themeModeStore: store),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Dark'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    bool selected(ThemeMode mode) => tester
        .widget<WeCordPressable>(
          find
              .descendant(
                of: find.byKey(ValueKey('theme-mode-${mode.name}')),
                matching: find.byType(WeCordPressable),
              )
              .first,
        )
        .selected;
    expect(selected(ThemeMode.system), isTrue);

    await tester.ensureVisible(find.text('Dark'));
    await tester.pump();
    await tester.tap(find.text('Dark'));
    await tester.pump();

    expect(selected(ThemeMode.dark), isTrue);
    expect(selected(ThemeMode.system), isFalse);
    expect(await store.load(), ThemeMode.dark);
  });

  testWidgets('turns glass effects off and remembers it', (tester) async {
    final store = InMemoryGlassEffectsStore();
    await tester.pumpWidget(
      _app(settingsRepository: FakeSettingsRepository(), glassStore: store),
    );
    await tester.pump();

    final toggle = find.byKey(const ValueKey('glass-effects'));
    await tester.scrollUntilVisible(
      toggle,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(toggle);
    await tester.pump();
    expect(switchValue(tester, toggle), isTrue);

    await tester.tap(toggle);
    await tester.pump();

    expect(switchValue(tester, toggle), isFalse);
    expect(await store.load(), isFalse);
  });

  group('delete account', () {
    Future<void> openDialog(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('delete-account')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('delete-account')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-account')));
      await tester.pumpAndSettle();
    }

    testWidgets('needs the username typed, then deletes and signs out', (
      tester,
    ) async {
      final service = FakeAccountDeletionService();
      final authRepository = FakeAuthRepository();
      await tester.pumpWidget(
        _app(
          settingsRepository: FakeSettingsRepository(),
          authRepository: authRepository,
          accountDeletionService: service,
        ),
      );
      await tester.pump();
      await openDialog(tester);

      WeCordButton confirm() =>
          tester.widget(find.byKey(const ValueKey('delete-account-confirm')));
      expect(confirm().onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('delete-account-username')),
        'adx',
      );
      await tester.pump();
      expect(confirm().onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('delete-account-username')),
        'ada',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('delete-account-confirm')));
      await tester.pumpAndSettle();

      expect(service.calls, 1);
      expect(authRepository.signOutCalls, 1);
    });

    testWidgets('explains when owned circles block it', (tester) async {
      final service = FakeAccountDeletionService()
        ..error = const AccountOwnsCirclesException();
      final authRepository = FakeAuthRepository();
      await tester.pumpWidget(
        _app(
          settingsRepository: FakeSettingsRepository(),
          authRepository: authRepository,
          accountDeletionService: service,
        ),
      );
      await tester.pump();
      await openDialog(tester);
      await tester.enterText(
        find.byKey(const ValueKey('delete-account-username')),
        'ada',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('delete-account-confirm')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Transfer ownership of your circles to another member first.',
        ),
        findsOneWidget,
      );
      expect(authRepository.signOutCalls, 0);
    });
  });

  testWidgets('sets a custom status from the Me screen', (tester) async {
    final settingsRepository = FakeSettingsRepository();

    await tester.pumpWidget(_app(settingsRepository: settingsRepository));
    await tester.pump();

    await tester.tap(find.text('Set status'));
    await tester.pumpAndSettle();
    expect(find.text('Set a status'), findsOneWidget);
    // Nothing to save yet.
    final saveStatus = find.descendant(
      of: find.byType(CustomStatusSheet),
      matching: find.widgetWithText(WeCordButton, 'Save'),
    );
    expect(tester.widget<WeCordButton>(saveStatus).onPressed, isNull);

    await tester.tap(find.byTooltip('Choose emoji'));
    await tester.pumpAndSettle();
    expect(find.text('Status emoji'), findsOneWidget);
    await tester.tap(find.text('😎'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, "What's happening?"),
      '  Focusing  ',
    );
    await tester.tap(find.text("Don't clear"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4 hours').last);
    await tester.pumpAndSettle();

    final before = DateTime.now().toUtc();
    await tester.tap(saveStatus);
    await tester.pumpAndSettle();

    final call = settingsRepository.statusCalls.single;
    expect(call.emoji, '😎');
    expect(call.text, '  Focusing  ');
    final remaining = call.expiresAt!.difference(before);
    expect(remaining.inMinutes, inInclusiveRange(239, 241));
    expect(find.text('Set a status'), findsNothing);
    expect(find.text('Focusing'), findsOneWidget);
    expect(find.textContaining('Clears '), findsOneWidget);
  });

  testWidgets('chooses who sees the status when saving it', (tester) async {
    final settingsRepository = FakeSettingsRepository();
    final social = _SocialSource();

    await tester.pumpWidget(
      _app(
        settingsRepository: settingsRepository,
        profileSocialDataSource: social,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Set status'));
    await tester.pumpAndSettle();
    expect(find.text('Who can see this'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, "What's happening?"),
      'Reading',
    );
    await tester.tap(find.byKey(const ValueKey('status-visibility-starred')));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(CustomStatusSheet),
        matching: find.widgetWithText(WeCordButton, 'Save'),
      ),
    );
    await tester.pumpAndSettle();

    expect(settingsRepository.statusCalls.single.text, 'Reading');
    final saved = social.calls.where(
      (call) => call.$1 == 'set_status_visibility',
    );
    expect(saved.single.$2, {'visibility': 'starred'});
  });

  testWidgets('does not touch the audience when it was not changed', (
    tester,
  ) async {
    final settingsRepository = FakeSettingsRepository();
    final social = _SocialSource();
    await tester.pumpWidget(
      _app(
        settingsRepository: settingsRepository,
        profileSocialDataSource: social,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Set status'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, "What's happening?"),
      'Reading',
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(CustomStatusSheet),
        matching: find.widgetWithText(WeCordButton, 'Save'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      social.calls.where((call) => call.$1 == 'set_status_visibility'),
      isEmpty,
    );
  });

  testWidgets('settings has the birthday, and support links off iPhone', (
    tester,
  ) async {
    await tester.pumpWidget(_app(settingsRepository: FakeSettingsRepository()));
    await tester.pump();
    expect(find.byKey(const ValueKey('settings-birthday')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-support-links')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(_app(settingsRepository: FakeSettingsRepository()));
    await tester.pump();
    expect(find.byKey(const ValueKey('settings-birthday')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-support-links')), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('clears the current custom status', (tester) async {
    final settingsRepository = FakeSettingsRepository();
    settingsRepository.profile = settingsRepository.profile.copyWith(
      customStatus: const CustomStatus(emoji: '🎧', text: 'Listening'),
    );

    await tester.pumpWidget(_app(settingsRepository: settingsRepository));
    await tester.pump();

    expect(find.text('Listening'), findsOneWidget);
    expect(find.text("Doesn't clear"), findsOneWidget);

    await tester.tap(find.text('Listening'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, "What's happening?"), findsOneWidget);
    expect(find.text('Listening'), findsWidgets);

    await tester.tap(find.text('Clear status'));
    await tester.pumpAndSettle();

    final call = settingsRepository.statusCalls.single;
    expect(call.emoji, isNull);
    expect(call.text, isNull);
    expect(call.expiresAt, isNull);
    expect(find.text('Set status'), findsOneWidget);
  });

  testWidgets('expired statuses are not shown', (tester) async {
    final settingsRepository = FakeSettingsRepository();
    settingsRepository.profile = settingsRepository.profile.copyWith(
      customStatus: CustomStatus(
        text: 'Old news',
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      ),
    );

    await tester.pumpWidget(_app(settingsRepository: settingsRepository));
    await tester.pump();

    expect(find.text('Old news'), findsNothing);
    expect(find.text('Set status'), findsOneWidget);
  });

  testWidgets('signs out through the auth repository', (tester) async {
    final settingsRepository = FakeSettingsRepository();
    final authRepository = FakeAuthRepository();

    await tester.pumpWidget(
      _app(
        settingsRepository: settingsRepository,
        authRepository: authRepository,
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('sign-out')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // Tiles above load as they scroll into view; settle, then bring the
    // target back on screen.
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('sign-out')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sign-out')));
    await tester.pump();

    expect(authRepository.signOutCalls, 1);
  });

  testWidgets('uploads avatar and saves the returned path', (tester) async {
    final settingsRepository = FakeSettingsRepository();
    final imagePickerService = FakeImagePickerService()
      ..nextImage = ChatImageUpload(
        fileName: 'avatar.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

    await tester.pumpWidget(
      _app(
        settingsRepository: settingsRepository,
        imagePickerService: imagePickerService,
      ),
    );
    await tester.pump();
    await openProfileEditor(tester);

    await tester.tap(find.byKey(const ValueKey('change-avatar')));
    await tester.pump();
    await tapSave(tester);
    await tester.pump();

    expect(settingsRepository.uploadCalls, [
      UploadAvatarCall(
        fileName: 'avatar.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
    ]);
    expect(settingsRepository.updateCalls.single.avatarUrl, 'avatars/ada.png');
  });

  testWidgets('saves pronouns and a banner only when they change', (
    tester,
  ) async {
    final extras = FakeProfileExtrasDataSource();
    final imagePickerService = FakeImagePickerService()
      ..nextImage = ChatImageUpload(
        fileName: 'sky.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
    await tester.pumpWidget(
      _app(
        settingsRepository: FakeSettingsRepository(),
        imagePickerService: imagePickerService,
        profileExtrasDataSource: extras,
      ),
    );
    await tester.pump();
    await openProfileEditor(tester);

    await tapSave(tester);
    await tester.pump();
    expect(extras.calls, isEmpty);

    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('change-banner')));
    await tester.pump();
    expect(extras.uploads.single.bucket, 'profile-banners');
    expect(find.byKey(const ValueKey('remove-banner')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('pronouns')), 'she/her');
    await tapSave(tester);
    await tester.pump();

    expect(extras.calls.single.name, 'update_profile_extras');
    expect(extras.calls.single.params, {
      'pronouns': 'she/her',
      'banner_url': 'profile-banners/user-1/7-sky.png',
    });
  });

  testWidgets('renders uploaded private avatar paths with signed URLs', (
    tester,
  ) async {
    final settingsRepository = FakeSettingsRepository();
    final imagePickerService = FakeImagePickerService()
      ..nextImage = ChatImageUpload(
        fileName: 'avatar.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

    await tester.pumpWidget(
      _app(
        settingsRepository: settingsRepository,
        imagePickerService: imagePickerService,
      ),
    );
    await tester.pump();
    await openProfileEditor(tester);
    settingsRepository.createdAvatarUrls.clear();

    await tester.tap(find.byKey(const ValueKey('change-avatar')));
    await tester.pump();
    await tester.pump();

    // (The picture itself can't load in tests, so check what it asks for.)
    final avatar = find.byKey(const ValueKey('profile-editor-avatar'));
    expect(tester.widget<ProfileAvatar>(avatar).avatarUrl, 'avatars/ada.png');
    expect(settingsRepository.createdAvatarUrls, ['avatars/ada.png']);
    expect(
      ProviderScope.containerOf(
        tester.element(avatar),
      ).read(avatarDisplayUrlProvider('avatars/ada.png')).value,
      'https://signed.example.com/ada.png',
    );
  });

  testWidgets('renders public avatar URLs without signing', (tester) async {
    final settingsRepository = FakeSettingsRepository()
      ..profile = Profile(
        id: 'user-1',
        username: 'ada',
        displayName: 'Ada Lovelace',
        avatarUrl: 'https://example.com/ada.png',
        bio: 'Computing pioneer',
        createdAt: DateTime.utc(2026, 5, 18),
        updatedAt: DateTime.utc(2026, 5, 18),
      );

    await tester.pumpWidget(_app(settingsRepository: settingsRepository));
    await tester.pump();
    await tester.pump();

    // (The picture itself can't load in tests, so check what it asks for.)
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const ValueKey('settings-account-avatar'))),
    );
    expect(settingsRepository.createdAvatarUrls, isEmpty);
    expect(
      container
          .read(avatarDisplayUrlProvider('https://example.com/ada.png'))
          .value,
      'https://example.com/ada.png',
    );
  });

  testWidgets('keeps text edits when avatar upload fails', (tester) async {
    final settingsRepository = FakeSettingsRepository()
      ..uploadError = Exception('storage failed');
    final imagePickerService = FakeImagePickerService()
      ..nextImage = ChatImageUpload(
        fileName: 'avatar.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

    await tester.pumpWidget(
      _app(
        settingsRepository: settingsRepository,
        imagePickerService: imagePickerService,
      ),
    );
    await tester.pump();
    await openProfileEditor(tester);

    await tester.enterText(displayNameField, 'Ada Byron');
    await tester.enterText(bioField, 'First programmer');
    await tester.ensureVisible(find.byKey(const ValueKey('change-avatar')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('change-avatar')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Could not upload avatar. Try again.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Could not upload avatar. Try again.'), findsOneWidget);
    expect(
      tester.widget<TextField>(displayNameField).controller!.text,
      'Ada Byron',
    );
    expect(
      tester.widget<TextField>(bioField).controller!.text,
      'First programmer',
    );
    expect(settingsRepository.updateCalls, isEmpty);
  });

  testWidgets('renders notification controls', (tester) async {
    final settingsRepository = FakeSettingsRepository();

    await tester.pumpWidget(_app(settingsRepository: settingsRepository));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Send test notification'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('notifications-enabled')), findsOneWidget);
    expect(find.text('Message previews'), findsOneWidget);
    expect(find.text('Request permission'), findsOneWidget);
    expect(find.text('Send test notification'), findsOneWidget);
  });

  testWidgets('settings opens blocked users sheet', (tester) async {
    final settingsRepository = FakeSettingsRepository()
      ..blockedUsers = [
        Profile(
          id: 'user-2',
          username: 'ada-2',
          displayName: 'Ada',
          avatarUrl: null,
          bio: '',
          createdAt: DateTime.utc(2026, 5, 18),
          updatedAt: DateTime.utc(2026, 5, 18),
        ),
      ];

    await tester.pumpWidget(_app(settingsRepository: settingsRepository));
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Blocked users'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // Tiles above load as they scroll into view; settle, then bring the
    // target back on screen.
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Blocked users'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blocked users'));
    await tester.pumpAndSettle();

    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Unblock'), findsOneWidget);
  });

  testWidgets('settings open two-step verification', (tester) async {
    await tester.pumpWidget(_app(settingsRepository: FakeSettingsRepository()));
    await tester.pump();

    final tile = find.byKey(const ValueKey('two-factor-settings-tile'));
    await tester.scrollUntilVisible(
      tile,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();

    // Without Supabase there is no authenticator, so it offers setup.
    expect(find.text('Protect your account with a code'), findsOneWidget);
  });

  testWidgets('toggles notification preferences', (tester) async {
    final settingsRepository = FakeSettingsRepository();
    final store = InMemoryNotificationPreferencesStore();

    await tester.pumpWidget(
      _app(
        settingsRepository: settingsRepository,
        notificationPreferencesRepository:
            NotificationPreferencesRepository.withStore(store),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Message previews'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('notifications-enabled')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notifications-enabled')));
    await tester.pump();

    expect((await store.load())?.enabled, isFalse);
  });

  testWidgets('sends a test notification from settings', (tester) async {
    final settingsRepository = FakeSettingsRepository();
    final notificationService = FakeLocalNotificationService();

    await tester.pumpWidget(
      _app(
        settingsRepository: settingsRepository,
        localNotificationService: notificationService,
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('notifications-test')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('notifications-test')),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('notifications-test')));
    await tester.pump();

    expect(
      await notificationService.permissionStatus(),
      NotificationPermissionStatus.granted,
    );
    expect(notificationService.shownNotifications.single.title, 'WeCord');
    expect(
      notificationService.shownNotifications.single.body,
      'Notifications are working.',
    );
    expect(
      notificationService.shownNotifications.single.payload,
      'settings-test',
    );
  });
}

/// Opens the profile editor from the account card.
Future<void> openProfileEditor(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('settings-account-card')));
  await tester.pumpAndSettle();
}

final displayNameField = find.byKey(const ValueKey('display-name'));
final bioField = find.byKey(const ValueKey('bio'));

/// The on/off state of the settings row [row].
bool switchValue(WidgetTester tester, Finder row) => tester
    .widget<WeCordSwitch>(
      find.descendant(of: row, matching: find.byType(WeCordSwitch)),
    )
    .value;

/// Taps the profile's Save button, scrolled into view first.
Future<void> tapSave(WidgetTester tester) async {
  final save = find.byKey(const ValueKey('profile-save'));
  await tester.scrollUntilVisible(
    save,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
  await tester.tap(save);
}

Widget _app({
  required FakeSettingsRepository settingsRepository,
  ThemeModeStore? themeModeStore,
  GlassEffectsStore? glassStore,
  AccountDeletionService? accountDeletionService,
  FakeAuthRepository? authRepository,
  FakeImagePickerService? imagePickerService,
  NotificationPreferencesRepository? notificationPreferencesRepository,
  LocalNotificationService? localNotificationService,
  PresenceRepository? presenceRepository,
  ProfileExtrasDataSource? profileExtrasDataSource,
  ProfileDataSource? profileSocialDataSource,
}) {
  return ProviderScope(
    overrides: [
      if (profileSocialDataSource != null)
        profileSocialRepositoryProvider.overrideWithValue(
          ProfileSocialRepository(profileSocialDataSource),
        ),
      profileExtrasRepositoryProvider.overrideWithValue(
        ProfileExtrasRepository(
          profileExtrasDataSource ?? FakeProfileExtrasDataSource(),
          currentUserId: () => 'user-1',
          storagePathSeed: () => '7',
        ),
      ),
      presenceRepositoryProvider.overrideWithValue(
        presenceRepository ?? presence_fakes.FakePresenceRepository(),
      ),
      settingsRepositoryProvider.overrideWithValue(settingsRepository),
      themeModeStoreProvider.overrideWithValue(
        themeModeStore ?? InMemoryThemeModeStore(),
      ),
      glassEffectsStoreProvider.overrideWithValue(
        glassStore ?? InMemoryGlassEffectsStore(),
      ),
      if (accountDeletionService != null)
        accountDeletionServiceProvider.overrideWithValue(
          accountDeletionService,
        ),
      authRepositoryProvider.overrideWithValue(
        authRepository ?? FakeAuthRepository(),
      ),
      if (imagePickerService != null)
        imagePickerServiceProvider.overrideWithValue(imagePickerService),
      notificationPreferencesRepositoryProvider.overrideWithValue(
        notificationPreferencesRepository ??
            NotificationPreferencesRepository.withStore(
              InMemoryNotificationPreferencesStore(),
            ),
      ),
      localNotificationServiceProvider.overrideWithValue(
        localNotificationService ?? FakeLocalNotificationService(),
      ),
    ],
    child: const MaterialApp(home: SettingsScreen()),
  );
}

class _SocialSource implements ProfileDataSource {
  final calls = <(String, Map<String, dynamic>)>[];

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    calls.add((functionName, params));
    return switch (functionName) {
      'get_my_profile_extras' => {
        'birthday': {'visibility': 'friends', 'reminders': true},
        'status_visibility': 'everyone',
        'links': const [],
      },
      _ => null,
    };
  }
}

class FakeSettingsRepository implements SettingsRepository {
  Profile profile = Profile(
    id: 'user-1',
    username: 'ada',
    displayName: 'Ada Lovelace',
    avatarUrl: 'avatars/existing.png',
    bio: 'Computing pioneer',
    createdAt: DateTime.utc(2026, 5, 18),
    updatedAt: DateTime.utc(2026, 5, 18),
  );
  Object? uploadError;
  final updateCalls = <UpdateProfileCall>[];
  final uploadCalls = <UploadAvatarCall>[];
  final createdAvatarUrls = <String>[];
  final unblockedUserIds = <String>[];
  final statusCalls = <({String? emoji, String? text, DateTime? expiresAt})>[];
  List<Profile> blockedUsers = const [];

  @override
  Future<void> setCustomStatus({
    String? emoji,
    String? text,
    DateTime? expiresAt,
  }) async {
    statusCalls.add((emoji: emoji, text: text, expiresAt: expiresAt));
    final cleared =
        (emoji?.trim().isEmpty ?? true) && (text?.trim().isEmpty ?? true);
    profile = profile.copyWith(
      customStatus: cleared
          ? null
          : CustomStatus(
              emoji: emoji?.trim(),
              text: text?.trim(),
              expiresAt: expiresAt,
            ),
    );
  }

  @override
  Future<Profile> currentProfile() async => profile;

  @override
  Future<void> updateProfile({
    required String displayName,
    required String bio,
    required String? avatarUrl,
  }) async {
    updateCalls.add(
      UpdateProfileCall(
        displayName: displayName,
        bio: bio,
        avatarUrl: avatarUrl,
      ),
    );
  }

  @override
  Future<String> uploadAvatar({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    if (uploadError case final error?) {
      throw error;
    }
    uploadCalls.add(
      UploadAvatarCall(fileName: fileName, mimeType: mimeType, bytes: bytes),
    );
    return 'avatars/ada.png';
  }

  @override
  Future<String> createAvatarUrl(String avatarPath) async {
    createdAvatarUrls.add(avatarPath);
    final uri = Uri.tryParse(avatarPath);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return avatarPath;
    }
    return 'https://signed.example.com/ada.png';
  }

  @override
  Future<List<Profile>> listBlockedUsers() async => blockedUsers;

  @override
  Future<void> unblockUser(String userId) async {
    unblockedUserIds.add(userId);
    blockedUsers = [
      for (final user in blockedUsers)
        if (user.id != userId) user,
    ];
  }
}

class FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AuthUser?>.broadcast();
  var signOutCalls = 0;

  @override
  AuthUser? get currentUser =>
      const AuthUser(id: 'user-1', email: 'ada@example.com');

  @override
  Stream<AuthUser?> authStateChanges() => _controller.stream;

  @override
  Future<void> signIn(String email, String password) async {}

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
  }

  @override
  Future<void> ensureCurrentUserProfile() async {}

  @override
  Future<void> signUp(
    String email,
    String password,
    String username,
    String displayName,
  ) async {}
}

class FakeImagePickerService implements ImagePickerService {
  ChatImageUpload? nextImage;

  @override
  Future<ChatImageUpload?> pickImage() async => nextImage;
}

class UpdateProfileCall {
  const UpdateProfileCall({
    required this.displayName,
    required this.bio,
    required this.avatarUrl,
  });

  final String displayName;
  final String bio;
  final String? avatarUrl;

  @override
  bool operator ==(Object other) {
    return other is UpdateProfileCall &&
        other.displayName == displayName &&
        other.bio == bio &&
        other.avatarUrl == avatarUrl;
  }

  @override
  int get hashCode => Object.hash(displayName, bio, avatarUrl);
}

class UploadAvatarCall {
  const UploadAvatarCall({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String fileName;
  final String mimeType;
  final Uint8List bytes;

  @override
  bool operator ==(Object other) {
    return other is UploadAvatarCall &&
        other.fileName == fileName &&
        other.mimeType == mimeType &&
        _listEquals(other.bytes, bytes);
  }

  @override
  int get hashCode => Object.hash(fileName, mimeType, Object.hashAll(bytes));
}

bool _listEquals(Uint8List left, Uint8List right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

class FakeAccountDeletionService implements AccountDeletionService {
  var calls = 0;
  Object? error;

  @override
  Future<void> deleteAccount() async {
    calls++;
    if (error case final error?) {
      throw error;
    }
  }
}
