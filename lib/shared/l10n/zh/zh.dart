// Simplified Chinese for every tr() string, keyed by the English text.
// Each area keeps its own map; test/shared/l10n/translations_test.dart
// checks that every tr('…') in lib/ has an entry, and that text shared by
// several areas reads the same everywhere.
import 'package:wecord/shared/l10n/zh/zh_a11y.dart';
import 'package:wecord/shared/l10n/zh/zh_ai.dart';
import 'package:wecord/shared/l10n/zh/zh_account.dart';
import 'package:wecord/shared/l10n/zh/zh_albums.dart';
import 'package:wecord/shared/l10n/zh/zh_app.dart';
import 'package:wecord/shared/l10n/zh/zh_app_shell.dart';
import 'package:wecord/shared/l10n/zh/zh_backend_fixes.dart';
import 'package:wecord/shared/l10n/zh/zh_calls_more.dart';
import 'package:wecord/shared/l10n/zh/zh_chat_more.dart';
import 'package:wecord/shared/l10n/zh/zh_chat_thread.dart';
import 'package:wecord/shared/l10n/zh/zh_chats.dart';
import 'package:wecord/shared/l10n/zh/zh_circles_core.dart';
import 'package:wecord/shared/l10n/zh/zh_circles_extra.dart';
import 'package:wecord/shared/l10n/zh/zh_circles_more.dart';
import 'package:wecord/shared/l10n/zh/zh_design.dart';
import 'package:wecord/shared/l10n/zh/zh_discovery.dart';
import 'package:wecord/shared/l10n/zh/zh_file_preview.dart';
import 'package:wecord/shared/l10n/zh/zh_later.dart';
import 'package:wecord/shared/l10n/zh/zh_layout.dart';
import 'package:wecord/shared/l10n/zh/zh_media_send.dart';
import 'package:wecord/shared/l10n/zh/zh_misc_features.dart';
import 'package:wecord/shared/l10n/zh/zh_profile_more.dart';
import 'package:wecord/shared/l10n/zh/zh_leftovers.dart';
import 'package:wecord/shared/l10n/zh/zh_noise.dart';
import 'package:wecord/shared/l10n/zh/zh_leftovers2.dart';
import 'package:wecord/shared/l10n/zh/zh_notes_lists.dart';
import 'package:wecord/shared/l10n/zh/zh_offline.dart';
import 'package:wecord/shared/l10n/zh/zh_phone_home.dart';
import 'package:wecord/shared/l10n/zh/zh_polish.dart';
import 'package:wecord/shared/l10n/zh/zh_push.dart';
import 'package:wecord/shared/l10n/zh/zh_redesign_shell.dart';
import 'package:wecord/shared/l10n/zh/zh_redesign_chat.dart';
import 'package:wecord/shared/l10n/zh/zh_redesign_circles.dart';
import 'package:wecord/shared/l10n/zh/zh_redesign_voice.dart';
import 'package:wecord/shared/l10n/zh/zh_redesign_settings.dart';
import 'package:wecord/shared/l10n/zh/zh_stage.dart';
import 'package:wecord/shared/l10n/zh/zh_safety.dart';
import 'package:wecord/shared/l10n/zh/zh_search.dart';
import 'package:wecord/shared/l10n/zh/zh_voice_more.dart';

/// Every area's map, for checks.
const zhAreas = <Map<String, String>>[
  zhApp,
  zhAppShell,
  zhAccount,
  zhChats,
  zhChatThread,
  zhChatMore,
  zhCirclesCore,
  zhCirclesMore,
  zhPush,
  zhProfileMore,
  zhVoiceMore,
  zhLeftovers,
  zhStage,
  zhSafety,
  zhPhoneHome,
  zhCirclesExtra,
  zhDesign,
  zhRedesignShell,
  zhRedesignChat,
  zhRedesignCircles,
  zhRedesignVoice,
  zhRedesignSettings,
  zhFilePreview,
  zhLayout,
  zhBackendFixes,
  zhDiscovery,
  zhOffline,
  zhPolish,
  zhSearch,
  zhMediaSend,
  zhMiscFeatures,
  zhAlbums,
  zhA11y,
  zhNoise,
  zhLeftovers2,
  zhAi,
  zhLater,
  zhNotesLists,
  zhCallsMore,
];

final zhStrings = <String, String>{for (final area in zhAreas) ...area};
