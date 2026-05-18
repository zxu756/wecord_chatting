import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';
import 'package:wecord/features/notifications/notification_preferences_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/shared/models/profile.dart';

void main() {
  testWidgets('edits and saves the current profile', (tester) async {
    final settingsRepository = FakeSettingsRepository();

    await tester.pumpWidget(_app(settingsRepository: settingsRepository));
    await tester.pump();

    expect(find.text('@ada'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Display name'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Bio'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Display name'),
      'Ada Byron',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Bio'),
      'First programmer',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(settingsRepository.updateCalls, [
      const UpdateProfileCall(
        displayName: 'Ada Byron',
        bio: 'First programmer',
        avatarUrl: 'avatars/existing.png',
      ),
    ]);
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

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
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

    await tester.tap(find.widgetWithText(OutlinedButton, 'Change avatar'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
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
    settingsRepository.createdAvatarUrls.clear();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Change avatar'));
    await tester.pump();
    await tester.pump();

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    final image = avatar.backgroundImage;
    expect(settingsRepository.createdAvatarUrls, ['avatars/ada.png']);
    expect(image, isA<NetworkImage>());
    expect((image! as NetworkImage).url, 'https://signed.example.com/ada.png');
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

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    final image = avatar.backgroundImage;
    expect(settingsRepository.createdAvatarUrls, isEmpty);
    expect(image, isA<NetworkImage>());
    expect((image! as NetworkImage).url, 'https://example.com/ada.png');
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

    await tester.enterText(
      find.widgetWithText(TextField, 'Display name'),
      'Ada Byron',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Bio'),
      'First programmer',
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Change avatar'));
    await tester.pump();

    expect(find.text('Could not upload avatar. Try again.'), findsOneWidget);
    expect(find.text('Ada Byron'), findsOneWidget);
    expect(find.text('First programmer'), findsOneWidget);
    expect(settingsRepository.updateCalls, isEmpty);
  });

  testWidgets('renders notification controls', (tester) async {
    final settingsRepository = FakeSettingsRepository();

    await tester.pumpWidget(_app(settingsRepository: settingsRepository));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Message previews'), findsOneWidget);
    expect(find.text('Request permission'), findsOneWidget);
    expect(find.text('Send test notification'), findsOneWidget);
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

    await tester.tap(find.widgetWithText(SwitchListTile, 'Notifications'));
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
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Send test notification'),
    );
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

Widget _app({
  required FakeSettingsRepository settingsRepository,
  FakeAuthRepository? authRepository,
  FakeImagePickerService? imagePickerService,
  NotificationPreferencesRepository? notificationPreferencesRepository,
  LocalNotificationService? localNotificationService,
}) {
  return ProviderScope(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(settingsRepository),
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
