import 'package:supabase_flutter/supabase_flutter.dart';

/// The Realtime channels that carry broadcast or presence, and their topics.
///
/// Every one of them is a PRIVATE channel: the server asks the policies on
/// `realtime.messages` (supabase/migrations/202610190050_realtime_private.sql,
/// 202610180050_location.sql and 202610190020_moments_realtime.sql) before it
/// lets anyone listen or send, so a topic name alone is not enough. That is
/// also what lets the project turn "Allow public access" off.
///
/// The topic formats here are matched by the SQL helpers
/// (`chat_activity_topic_conversation`, `note_presence_topic_note`) and
/// policies; change them together.
///
/// What a person is told about other people's online status changing: ids
/// only, never a status (202610190070_presence_visibility.sql). Replaces the
/// global `online-users` presence channel, which showed every online user to
/// every signed-in account.
String presenceUpdatesTopic(String userId) => 'presence-updates:$userId';

/// Typing and who-is-here in one conversation.
String chatActivityTopic(String conversationId) {
  return 'chat-activity-$conversationId';
}

/// Who is in a note, and where their cursor is.
String notePresenceTopic(String noteId) => 'note-presence-$noteId';

/// Who is on a whiteboard, where their pointers are and the stroke they are
/// drawing right now (migration 202610281430_whiteboard_files_realtime.sql).
String whiteboardLiveTopic(String boardId) => 'whiteboard-live-$boardId';

/// A live location share's positions.
String liveLocationTopic(String shareId) => 'live-location:$shareId';

/// What a person is told about Moments changing.
String momentsTopic(String userId) => 'moments:$userId';

/// What a person is told about dailies changing (migration
/// 202610240240_stories_signals_cleanup.sql).
String storiesTopic(String userId) => 'stories:$userId';

/// The options of a broadcast or presence channel. [presenceKey] identifies
/// this client in the channel's presence state (its user id).
RealtimeChannelConfig privateChannelConfig({String? presenceKey}) {
  return RealtimeChannelConfig(private: true, key: presenceKey ?? '');
}
