import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/qr/qr_camera.dart';
import 'package:wecord/features/qr/qr_image_export.dart';
import 'package:wecord/features/qr/qr_link_handler.dart';
import 'package:wecord/features/qr/qr_repository.dart';
import 'package:wecord/features/qr/qr_scanner_sheet.dart';

const sampleUserCode = 'abcd2345efgh6789';
const sampleGroupCode = 'wxyz2345mnpq6789';

/// QR codes without a server: a code that can be reset, people to resolve,
/// and groups to preview and join.
class FakeQrRepository implements QrRepository {
  String code = sampleUserCode;
  var resets = 0;
  Object? failMyCode;
  Object? failReset;

  /// Who each code leads to; missing codes lead nowhere.
  final users = <String, QrProfile>{};
  Object? failResolve;
  final resolved = <String>[];

  GroupQrCode groupQr = GroupQrCode(
    code: sampleGroupCode,
    createdAt: DateTime.now().toUtc(),
    expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
  );
  final groupRequests = <({String conversationId, bool refresh})>[];
  Object? failGroup;

  GroupQrPreview preview = const GroupQrPreview(
    state: GroupQrState.ok,
    conversationId: 'group-1',
    title: 'Weekend climbers',
    memberCount: 12,
  );
  Object? failPreview;
  GroupQrJoin join = const GroupQrJoin(
    state: GroupQrJoinState.joined,
    conversationId: 'group-1',
  );
  Object? failJoin;
  final joined = <String>[];

  @override
  Future<String> myCode() async {
    if (failMyCode case final error?) {
      throw error;
    }
    return code;
  }

  @override
  Future<String> resetMyCode() async {
    if (failReset case final error?) {
      throw error;
    }
    resets++;
    code = 'reset${resets}5678abcdefg'.substring(0, 16);
    return code;
  }

  @override
  Future<QrProfile?> resolveUser(String code) async {
    resolved.add(code);
    if (failResolve case final error?) {
      throw error;
    }
    return users[code];
  }

  @override
  Future<GroupQrCode> groupCode(
    String conversationId, {
    bool refresh = false,
  }) async {
    groupRequests.add((conversationId: conversationId, refresh: refresh));
    if (failGroup case final error?) {
      throw error;
    }
    if (refresh) {
      groupQr = GroupQrCode(
        code: 'new${groupRequests.length}2345mnpq6789'.substring(0, 16),
        createdAt: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
      );
    }
    return groupQr;
  }

  @override
  Future<GroupQrPreview> previewGroup(String code) async {
    if (failPreview case final error?) {
      throw error;
    }
    return preview;
  }

  @override
  Future<GroupQrJoin> joinGroup(String code) async {
    joined.add(code);
    if (failJoin case final error?) {
      throw error;
    }
    return join;
  }
}

/// Saving and sharing without a platform: remembers the pictures.
class FakeQrImageExporter implements QrImageExporter {
  final saved = <({Uint8List png, String name})>[];
  final shared = <({Uint8List png, String name, String? text})>[];
  QrExportOutcome saveOutcome = QrExportOutcome.saved;
  QrExportOutcome shareOutcome = QrExportOutcome.shared;

  @override
  Future<QrExportOutcome> save(Uint8List png, {required String name}) async {
    saved.add((png: png, name: name));
    return saveOutcome;
  }

  @override
  Future<QrExportOutcome> share(
    Uint8List png, {
    required String name,
    String? text,
    Rect? origin,
  }) async {
    shared.add((png: png, name: name, text: text));
    return shareOutcome;
  }
}

/// A camera that shows a dark box and lets the test "read" codes.
class FakeQrCamera {
  ValueChanged<String>? onCode;
  ValueChanged<QrCameraProblem>? onProblem;

  /// Set before the scanner opens to make the camera fail on start.
  QrCameraProblem? failWith;

  Widget build(
    BuildContext context, {
    required ValueChanged<String> onCode,
    required ValueChanged<QrCameraProblem> onProblem,
  }) {
    this.onCode = onCode;
    this.onProblem = onProblem;
    final problem = failWith;
    if (problem != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onProblem(problem));
    }
    return const ColoredBox(
      key: ValueKey('fake-camera'),
      color: Color(0xFF202024),
    );
  }
}

/// Opens links without a browser.
class FakeUrlLauncher {
  final opened = <Uri>[];
  var succeeds = true;

  Future<bool> call(Uri url) async {
    opened.add(url);
    return succeeds;
  }
}

/// The overrides that put the QR fakes in place.
List<Override> qrOverrides({
  required FakeQrRepository repository,
  FakeQrImageExporter? exporter,
  FakeQrCamera? camera,
  QrImageDecoder? decoder,
  FakeUrlLauncher? launcher,
}) {
  return [
    qrRepositoryProvider.overrideWithValue(repository),
    if (exporter != null) qrImageExporterProvider.overrideWithValue(exporter),
    if (camera != null) qrCameraBuilderProvider.overrideWithValue(camera.build),
    if (decoder != null) qrImageDecoderProvider.overrideWithValue(decoder),
    if (launcher != null)
      qrUrlLauncherProvider.overrideWithValue(launcher.call),
  ];
}
