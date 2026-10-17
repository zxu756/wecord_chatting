import 'package:wecord/features/voice/voice_call.dart';

/// Who the mini player shows: someone else who is speaking now; otherwise
/// the last person who did ([previousId], while they are still there); then
/// someone sharing video or a screen; then anyone else; and the current
/// user when they are alone.
VoiceCallParticipant? activeSpeakerOf(
  List<VoiceCallParticipant> participants, {
  String? previousId,
}) {
  if (participants.isEmpty) {
    return null;
  }
  final remotes = [
    for (final participant in participants)
      if (!participant.isLocal) participant,
  ];
  if (remotes.isEmpty) {
    return participants.first;
  }
  for (final participant in remotes) {
    if (participant.isSpeaking) {
      return participant;
    }
  }
  for (final participant in remotes) {
    if (participant.userId == previousId) {
      return participant;
    }
  }
  for (final participant in remotes) {
    if (participant.cameraEnabled || participant.screenShareEnabled) {
      return participant;
    }
  }
  return remotes.first;
}
