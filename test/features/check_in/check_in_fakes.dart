import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/chats/chats_repository.dart'
    show ChatImageUpload;
import 'package:wecord/features/chats/media_send/album_grid.dart'
    show chatImageProviderFactoryProvider;
import 'package:wecord/features/check_in/check_in_models.dart';
import 'package:wecord/features/check_in/check_in_repository.dart';
import 'package:wecord/features/forms/form_models.dart' show FormImageAnswer;
import 'package:flutter/widgets.dart';
import 'package:wecord/features/chats/image_picker_service.dart';

import '../forms/form_fakes.dart' show FakeImagePicker;
import '../stickers/sticker_fakes.dart' show samplePhotoPng;

/// The date every fake check-in calls today, so tests do not depend on the
/// clock.
final fakeToday = DateTime(2026, 10, 28);

/// A check-in server in memory: one board, its days, and the rules the real
/// server enforces (closed, one per day, a streak that counts consecutive
/// days up to today or yesterday).
class FakeCheckInRepository implements CheckInRepository {
  FakeCheckInRepository({
    this.checkInId = 'ci-1',
    this.conversationId = 'group-1',
    this.title = 'Read 20 pages',
    this.description = '',
    this.me = 'user-1',
    this.creatorId = 'user-2',
    this.canManage = false,
    this.closed = false,
    this.memberTotal = 30,
    this.timeZone = 'Pacific/Auckland',
    this.remindMinute,
  });

  final String checkInId;
  final String conversationId;
  String title;
  String description;
  final String me;
  final String creatorId;
  bool canManage;
  bool closed;
  int memberTotal;
  String timeZone;
  int? remindMinute;

  /// Every check-in: user, day, note, photo.
  final entries =
      <
        ({
          String userId,
          String name,
          DateTime day,
          String note,
          FormImageAnswer? photo,
        })
      >[];

  /// Makes the next call of this kind fail.
  Object? getError;
  Object? submitError;
  Object? createError;
  Object? detailError;

  final created = <(String, CheckInDraft)>[];
  final submitted = <({String note, FormImageAnswer? photo})>[];
  final uploads = <ChatImageUpload>[];
  final calls = <String>[];
  final _changes = StreamController<void>.broadcast();

  /// Somebody else checked in: Realtime tells the clients.
  void touch() => _changes.add(null);

  void addEntry(
    String userId,
    String name,
    DateTime day, {
    String note = '',
    FormImageAnswer? photo,
  }) {
    entries.add((
      userId: userId,
      name: name,
      day: DateTime(day.year, day.month, day.day),
      note: note,
      photo: photo,
    ));
  }

  Iterable<DateTime> _days(String userId) =>
      entries.where((e) => e.userId == userId).map((e) => e.day);

  /// The length of the run that is alive for [userId] (ends today or
  /// yesterday).
  int streakOf(String userId) {
    final days = _days(userId).toSet();
    var cursor = days.contains(fakeToday)
        ? fakeToday
        : fakeToday.subtract(const Duration(days: 1));
    var run = 0;
    while (days.contains(cursor)) {
      run += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return run;
  }

  int _best(String userId) {
    final days = _days(userId).toSet().toList()..sort();
    var best = 0;
    var run = 0;
    DateTime? last;
    for (final day in days) {
      run = last != null && day.difference(last).inDays == 1 ? run + 1 : 1;
      if (run > best) {
        best = run;
      }
      last = day;
    }
    return best;
  }

  CheckInSnapshot get snapshot {
    final mine = entries
        .where((e) => e.userId == me && e.day == fakeToday)
        .firstOrNull;
    return CheckInSnapshot(
      id: checkInId,
      conversationId: conversationId,
      messageId: 'card-1',
      title: title,
      description: description,
      timeZone: timeZone,
      remindMinute: remindMinute,
      today: fakeToday,
      closed: closed,
      createdBy: creatorId,
      canManage: canManage,
      todayCount: entries.where((e) => e.day == fakeToday).length,
      memberTotal: memberTotal,
      myCheckedIn: mine != null,
      myNote: mine?.note ?? '',
      myPhoto: mine?.photo,
      myStreak: streakOf(me),
      myBestStreak: _best(me),
      myTotalDays: _days(me).toSet().length,
    );
  }

  CheckInEntry _entry(int index) {
    final e = entries[index];
    return CheckInEntry(
      id: 'e$index',
      userId: e.userId,
      name: e.name,
      day: e.day,
      note: e.note,
      photo: e.photo,
      streak: streakOf(e.userId),
      createdAt: DateTime(e.day.year, e.day.month, e.day.day, 8, 5 + index),
    );
  }

  @override
  Future<String> create(String conversationId, CheckInDraft draft) async {
    calls.add('create');
    if (createError != null) {
      throw createError!;
    }
    created.add((conversationId, draft));
    return 'card-new';
  }

  @override
  Future<CheckInSnapshot> get(String checkInId) async {
    calls.add('get');
    if (getError != null) {
      throw getError!;
    }
    return snapshot;
  }

  @override
  Future<CheckInDetail> detail(String checkInId) async {
    calls.add('detail');
    if (detailError != null) {
      throw detailError!;
    }
    final today = <CheckInEntry>[
      for (var i = 0; i < entries.length; i++)
        if (entries[i].day == fakeToday) _entry(i),
    ];
    final people = {for (final e in entries) e.userId: e.name};
    final leaders = <CheckInLeader>[
      for (final id in people.keys)
        if (streakOf(id) >= 2)
          CheckInLeader(userId: id, name: people[id]!, streak: streakOf(id)),
    ]..sort((a, b) => b.streak.compareTo(a.streak));
    return CheckInDetail(
      snapshot: snapshot,
      entries: today,
      leaders: leaders,
      myDays: _days(me).toSet(),
    );
  }

  @override
  Future<CheckInDay> day(String checkInId, DateTime day) async {
    calls.add('day');
    final date = DateTime(day.year, day.month, day.day);
    final list = <CheckInEntry>[
      for (var i = 0; i < entries.length; i++)
        if (entries[i].day == date) _entry(i),
    ];
    return CheckInDay(day: date, count: list.length, entries: list);
  }

  @override
  Future<CheckInResult> submit(
    String checkInId, {
    String note = '',
    FormImageAnswer? photo,
  }) async {
    calls.add('submit');
    if (submitError != null) {
      throw submitError!;
    }
    if (closed) {
      throw const CheckInException(CheckInFailureKind.closed);
    }
    submitted.add((note: note.trim(), photo: photo));
    final index = entries.indexWhere(
      (e) => e.userId == me && e.day == fakeToday,
    );
    final updated = index >= 0;
    final entry = (
      userId: me,
      name: 'Ada',
      day: fakeToday,
      note: note.trim(),
      photo: photo,
    );
    if (updated) {
      entries[index] = entry;
    } else {
      entries.add(entry);
    }
    return CheckInResult(
      updated: updated,
      streak: streakOf(me),
      bestStreak: _best(me),
      totalDays: _days(me).toSet().length,
    );
  }

  @override
  Future<void> undo(String checkInId) async {
    calls.add('undo');
    if (closed) {
      throw const CheckInException(CheckInFailureKind.closed);
    }
    entries.removeWhere((e) => e.userId == me && e.day == fakeToday);
  }

  @override
  Future<void> setClosed(String checkInId, {required bool closed}) async {
    calls.add(closed ? 'close' : 'reopen');
    this.closed = closed;
  }

  @override
  Future<FormImageAnswer> uploadPhoto({
    required String conversationId,
    required String checkInId,
    required ChatImageUpload image,
  }) async {
    calls.add('upload');
    uploads.add(image);
    return FormImageAnswer(
      bucket: 'chat-images',
      path: '$conversationId/check-ins/$checkInId/${uploads.length}.jpg',
      mimeType: image.mimeType,
    );
  }

  @override
  Future<String> imageUrl(FormImageAnswer image) async =>
      'https://files.example.com/${image.path}';

  @override
  Stream<void> changes(String checkInId) => _changes.stream;
}

/// The overrides a check-in test needs: the repository, pictures that need no
/// network and a picker that answers a small picture.
List<Override> checkInOverrides(
  FakeCheckInRepository repository, {
  ImagePickerService? picker,
  bool withPicker = true,
}) {
  return [
    checkInRepositoryProvider.overrideWithValue(repository),
    if (withPicker)
      imagePickerServiceProvider.overrideWithValue(picker ?? FakeImagePicker()),
    chatImageProviderFactoryProvider.overrideWithValue(
      (url) => MemoryImage(samplePhotoPng(width: 120, height: 80)),
    ),
  ];
}
