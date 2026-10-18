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
/// (`chat_activity_topic_conversation`, `note_presence_topic_note`); change
/// them together.
const onlineUsersTopic = 'online-users';

/// Typing and who-is-here in one conversation.
String chatActivityTopic(String conversationId) {
  return 'chat-activity-$conversationId';
}

/// Who is in a note, and where their cursor is.
String notePresenceTopic(String noteId) => 'note-presence-$noteId';

/// A live location share's positions.
String liveLocationTopic(String shareId) => 'live-location:$shareId';

/// What a person is told about Moments changing.
String momentsTopic(String userId) => 'moments:$userId';

/// The options of a broadcast or presence channel. [presenceKey] identifies
/// this client in the channel's presence state (its user id).
RealtimeChannelConfig privateChannelConfig({String? presenceKey}) {
  return RealtimeChannelConfig(private: true, key: presenceKey ?? '');
}
