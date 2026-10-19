import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/accessibility/video_captions/video_captions_service.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/image_text/image_text_cache.dart';
import 'package:wecord/features/storage/disk_cache.dart';
import 'package:wecord/features/storage/local_storage_service.dart';
import 'package:wecord/features/transcribe/transcript_cache.dart';
import 'package:wecord/features/wallpapers/wallpaper_store.dart';

/// How long downloaded media and recognised text may sit unused before the
/// app removes them by itself.
enum AutoCleanPeriod {
  off(null),
  days7(7),
  days30(30),
  days90(90);

  const AutoCleanPeriod(this.days);

  final int? days;

  Duration? get duration => days == null ? null : Duration(days: days!);
}

/// Where the auto-clean choice (and when it last ran) is kept; tests swap in
/// memory.
abstract interface class StorageSettingsStore {
  Future<AutoCleanPeriod?> loadPeriod();

  Future<void> savePeriod(AutoCleanPeriod period);

  Future<DateTime?> loadLastRun();

  Future<void> saveLastRun(DateTime time);
}

const _periodKey = 'wecord.storage.auto_clean';
const _lastRunKey = 'wecord.storage.auto_clean_last_run';

class SharedPreferencesStorageSettingsStore implements StorageSettingsStore {
  const SharedPreferencesStorageSettingsStore();

  @override
  Future<AutoCleanPeriod?> loadPeriod() async {
    final preferences = await SharedPreferences.getInstance();
    final name = preferences.getString(_periodKey);
    return AutoCleanPeriod.values.where((p) => p.name == name).firstOrNull;
  }

  @override
  Future<void> savePeriod(AutoCleanPeriod period) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_periodKey, period.name);
  }

  @override
  Future<DateTime?> loadLastRun() async {
    final preferences = await SharedPreferences.getInstance();
    final millis = preferences.getInt(_lastRunKey);
    return millis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  @override
  Future<void> saveLastRun(DateTime time) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_lastRunKey, time.millisecondsSinceEpoch);
  }
}

class InMemoryStorageSettingsStore implements StorageSettingsStore {
  InMemoryStorageSettingsStore([this.period, this.lastRun]);

  AutoCleanPeriod? period;
  DateTime? lastRun;

  @override
  Future<AutoCleanPeriod?> loadPeriod() async => period;

  @override
  Future<void> savePeriod(AutoCleanPeriod period) async => this.period = period;

  @override
  Future<DateTime?> loadLastRun() async => lastRun;

  @override
  Future<void> saveLastRun(DateTime time) async => lastRun = time;
}

final storageSettingsStoreProvider = Provider<StorageSettingsStore>(
  (ref) => const SharedPreferencesStorageSettingsStore(),
);

/// Remembered on this device. Off until the saved choice has loaded.
final autoCleanPeriodProvider =
    NotifierProvider<AutoCleanPeriodController, AutoCleanPeriod>(
      AutoCleanPeriodController.new,
    );

class AutoCleanPeriodController extends Notifier<AutoCleanPeriod> {
  var _changed = false;

  @override
  AutoCleanPeriod build() {
    ref.read(storageSettingsStoreProvider).loadPeriod().then((period) {
      // A choice made while loading wins over the saved one.
      if (period != null && !_changed) {
        state = period;
      }
    }, onError: (Object _) {});
    return AutoCleanPeriod.off;
  }

  Future<void> set(AutoCleanPeriod period) async {
    _changed = true;
    state = period;
    try {
      await ref.read(storageSettingsStoreProvider).savePeriod(period);
    } on Object {
      // Still applies for this session.
    }
  }
}

final diskCacheProvider = Provider<DiskCache>((ref) => createDiskCache());

/// What the browser says about its storage (the web only); tests swap it.
final browserEstimateProvider = Provider<Future<BrowserEstimate?> Function()>(
  (ref) => browserStorageEstimate,
);

/// Measures and empties this device's copies (see [LocalStorageService]).
final localStorageServiceProvider = Provider<LocalStorageService>((ref) {
  String? userId() {
    try {
      return ref.read(authRepositoryProvider).currentUser?.id;
    } on Object {
      return null;
    }
  }

  return LocalStorageService(
    userId: userId,
    chatCache: ref.watch(chatCacheProvider),
    disk: ref.watch(diskCacheProvider),
    transcripts: ref.watch(transcriptCacheProvider),
    imageTexts: ref.watch(imageTextCacheProvider),
    videoCaptions: ref.watch(videoCaptionCacheProvider),
    wallpapers: ref.watch(wallpaperPhotoStoreProvider),
    browserEstimate: ref.watch(browserEstimateProvider),
  );
});

/// Housekeeping that runs once the app is up: forgets cached messages that
/// have expired, and, when the person chose a period, removes media and
/// recognised text not used for that long (at most once every 12 hours).
/// Watched by the app for as long as it runs.
final storageJanitorProvider = Provider<void>((ref) {
  var disposed = false;
  ref.onDispose(() => disposed = true);

  Future<void> run() async {
    if (disposed) {
      return;
    }
    try {
      final service = ref.read(localStorageServiceProvider);
      await service.sweepExpired();
      final store = ref.read(storageSettingsStoreProvider);
      final period = (await store.loadPeriod())?.duration;
      if (period == null) {
        return;
      }
      final now = DateTime.now().toUtc();
      final last = await store.loadLastRun();
      if (last != null && now.difference(last) < const Duration(hours: 12)) {
        return;
      }
      await service.cleanOlderThan(period);
      await store.saveLastRun(now);
    } on Object {
      // Housekeeping: tried again at the next start.
    }
  }

  // After the first frame, so it never competes with the app starting.
  WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(run()));
});
