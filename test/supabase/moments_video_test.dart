import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Moments video (migration 202610190022): schema checks plus the behaviour
/// script (limits, names, who may read the files).
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610190022_moments_video.sql',
    ).readAsStringSync();
  });

  test('the video is readable like the audience-free columns, not more', () {
    final grant = RegExp(
      r'grant select \(([^)]*)\) on public\.moments_posts to authenticated;',
    ).firstMatch(sql);
    expect(grant, isNotNull);
    expect(grant!.group(1), contains('video'));
    expect(grant.group(1), isNot(contains('audience')));
  });

  test('videos are in the private bucket, 50 MB at most, mp4 mov webm', () {
    expect(sql, contains('file_size_limit = 52428800'));
    for (final mime in ['video/mp4', 'video/quicktime', 'video/webm']) {
      expect(sql, contains("'$mime'"));
    }
    expect(sql, isNot(contains('public = true')));
  });

  test('the video file is read by the same rule as a photo', () {
    expect(sql, contains('-v\\.(mp4|mov|webm)'));
    expect(sql, contains('public.moments_post_visible_to(auth.uid(), p)'));
  });

  test('a minute and 50 MB are checked on the server', () {
    expect(sql, contains('video_duration > 61000'));
    expect(sql, contains('video_size > 52428800'));
    expect(sql, contains('The video was not uploaded'));
  });

  test('uploads are the owner\'s, with names the rules know', () {
    expect(sql, contains('(storage.foldername(name))[1] = auth.uid()::text'));
    expect(sql, contains('v\\.(mp4|mov|webm)'));
  });

  behaviourTest(
    'moments video: limits, names, and who may read the files',
    'test/supabase/moments_video_behaviour.sql',
  );
}
