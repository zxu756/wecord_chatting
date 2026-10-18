import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/chats/chats_repository.dart'
    show ChatImageUpload;
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/chats/media_send/album_grid.dart'
    show chatImageProviderFactoryProvider;
import 'package:wecord/features/forms/form_export.dart';
import 'package:wecord/features/forms/form_models.dart';
import 'package:wecord/features/forms/form_repository.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/profile.dart';

import '../stickers/sticker_fakes.dart' show samplePhotoPng;

/// One question of each of the 8 kinds.
List<FormFieldDef> sampleFormFields() => const [
  FormFieldDef(
    id: 'name',
    type: FormFieldType.shortText,
    label: 'Your name',
    required: true,
  ),
  FormFieldDef(
    id: 'story',
    type: FormFieldType.longText,
    label: 'Anything to add?',
    help: 'Allergies, rides, anything.',
  ),
  FormFieldDef(
    id: 'age',
    type: FormFieldType.number,
    label: 'Age',
    min: 1,
    max: 120,
    integerOnly: true,
  ),
  FormFieldDef(
    id: 'size',
    type: FormFieldType.singleChoice,
    label: 'T-shirt size',
    required: true,
    options: [
      FormOption(id: 's', label: 'S'),
      FormOption(id: 'm', label: 'M'),
      FormOption(id: 'l', label: 'L'),
    ],
  ),
  FormFieldDef(
    id: 'food',
    type: FormFieldType.multipleChoice,
    label: 'Food',
    options: [
      FormOption(id: 'veg', label: 'Veg'),
      FormOption(id: 'fish', label: 'Fish'),
      FormOption(id: 'meat', label: 'Meat'),
    ],
  ),
  FormFieldDef(id: 'day', type: FormFieldType.date, label: 'Arrival day'),
  FormFieldDef(id: 'photo', type: FormFieldType.image, label: 'A photo'),
  FormFieldDef(id: 'buddy', type: FormFieldType.member, label: 'Buddy'),
];

/// A form server in memory: one form, its sheets, and the rules the real
/// server enforces (closed, full, one per person and editing).
class FakeFormRepository implements FormRepository {
  FakeFormRepository({
    this.formId = 'form-1',
    this.conversationId = 'group-1',
    this.title = 'Hike sign-up',
    this.description = '',
    List<FormFieldDef>? fields,
    this.settings = const FormSettings(),
    this.me = 'user-1',
    this.creatorId = 'user-2',
    this.closed = false,
    this.memberTotal = 6,
  }) : fields = fields ?? sampleFormFields();

  final String formId;
  final String conversationId;
  String title;
  String description;
  final List<FormFieldDef> fields;
  FormSettings settings;
  final String me;
  final String creatorId;
  bool closed;
  int memberTotal;

  /// Every sheet, with the person who gave it.
  final sheets = <({String userId, FormAnswers answers})>[];

  /// People by user id (for names in the results).
  final people = <String, FormPerson>{};

  /// Members who have not answered, as the creator sees them.
  List<FormPerson>? unfilled;

  /// What the server drops for the caller (the AI guard of new members).
  bool holdText = false;

  /// Makes the next call of this kind fail.
  Object? getError;
  Object? submitError;
  Object? resultsError;
  Object? uploadError;
  Object? createError;

  final created = <(String, FormDraft)>[];
  final submitted = <FormAnswers>[];
  final uploads = <ChatImageUpload>[];
  final calls = <String>[];
  final _changes = StreamController<void>.broadcast();
  var _next = 1;

  /// Somebody else changed the form: Realtime tells the clients.
  void touch() => _changes.add(null);

  void addSheet(String userId, String name, FormAnswers answers) {
    sheets.add((userId: userId, answers: answers));
    people[userId] = FormPerson(id: userId, name: name);
  }

  bool get _isClosed =>
      closed ||
      (settings.deadline != null &&
          !settings.deadline!.isAfter(DateTime.now()));

  FormResponseRow? get _mine {
    final found = sheets.where((s) => s.userId == me).toList();
    if (found.isEmpty) {
      return null;
    }
    return FormResponseRow(id: 'mine', userId: me, answers: found.last.answers);
  }

  @override
  Future<String> create(String conversationId, FormDraft draft) async {
    if (createError case final error?) {
      createError = null;
      throw error;
    }
    created.add((conversationId, draft));
    return 'message-1';
  }

  @override
  Future<FormSnapshot> get(String formId) async {
    calls.add('get');
    if (getError case final error?) {
      getError = null;
      throw error;
    }
    final isCreator = me == creatorId;
    final mine = _mine;
    return FormSnapshot(
      id: this.formId,
      conversationId: conversationId,
      messageId: 'message-1',
      title: title,
      description: description,
      fields: fields,
      settings: settings,
      responseCount: sheets.length,
      closedByServer: closed,
      createdBy: creatorId,
      creatorName: 'Ada',
      canManage: isCreator,
      canViewResults:
          isCreator ||
          settings.results == FormResultsVisibility.everyone ||
          (settings.results == FormResultsVisibility.afterSubmit &&
              mine != null),
      myResponse: mine,
      myResponseCount: sheets.where((s) => s.userId == me).length,
    );
  }

  @override
  Future<FormSubmitResult> submit(String formId, FormAnswers answers) async {
    calls.add('submit');
    if (submitError case final error?) {
      submitError = null;
      throw error;
    }
    if (_isClosed) {
      throw const FormException(FormFailureKind.closed);
    }
    final existing = sheets.indexWhere((s) => s.userId == me);
    if (settings.onePerPerson && existing >= 0) {
      if (!settings.editable) {
        throw const FormException(FormFailureKind.alreadySubmitted);
      }
    } else if (settings.maxResponses != null &&
        sheets.length >= settings.maxResponses!) {
      throw const FormException(FormFailureKind.full);
    }
    for (final field in fields) {
      if (field.required && answers[field.id] == null) {
        throw FormException(FormFailureKind.answerRequired, fieldId: field.id);
      }
    }
    final kept = <String, Object?>{
      for (final MapEntry(:key, :value) in answers.entries)
        if (!(holdText && fields.firstWhere((f) => f.id == key).type.isText))
          key: value,
    };
    submitted.add(answers);
    final held = holdText && kept.length < answers.length;
    if (settings.onePerPerson && existing >= 0) {
      sheets[existing] = (userId: me, answers: kept);
      return FormSubmitResult(updated: true, textHeld: held);
    }
    sheets.add((userId: me, answers: kept));
    people[me] = FormPerson(id: me, name: 'Me');
    return FormSubmitResult(textHeld: held);
  }

  @override
  Future<FormResults> results(String formId) async {
    calls.add('results');
    if (resultsError case final error?) {
      resultsError = null;
      throw error;
    }
    final snapshot = await get(formId);
    if (!snapshot.canViewResults) {
      throw const FormException(FormFailureKind.resultsHidden);
    }
    final anonymous = settings.anonymous;
    return FormResults(
      formId: this.formId,
      anonymous: anonymous,
      responses: [
        for (final (index, sheet) in sheets.indexed)
          FormResponseRow(
            id: 'sheet-$index',
            userId: anonymous ? null : sheet.userId,
            answers: sheet.answers,
            submittedAt: anonymous ? null : DateTime(2026, 10, 20, 9, index),
          ),
      ],
      people: {
        for (final MapEntry(:key, :value) in people.entries)
          if (!anonymous || sheets.any((s) => s.answers.containsValue(key)))
            key: value,
      },
      unfilled: anonymous || me != creatorId ? null : unfilled,
      memberTotal: memberTotal,
    );
  }

  @override
  Future<void> setClosed(String formId, {required bool closed}) async {
    calls.add('close:$closed');
    this.closed = closed;
    touch();
  }

  Object? remindError;

  @override
  Future<int> remind(FormSnapshot form) async {
    calls.add('remind');
    if (remindError case final error?) {
      remindError = null;
      throw error;
    }
    return unfilled?.length ?? 0;
  }

  @override
  Future<FormImageAnswer> uploadImage({
    required String conversationId,
    required String formId,
    required ChatImageUpload image,
  }) async {
    if (uploadError case final error?) {
      uploadError = null;
      throw error;
    }
    uploads.add(image);
    return FormImageAnswer(
      bucket: 'chat-images',
      path: '$conversationId/forms/$formId/pic-${_next++}.jpg',
      mimeType: image.mimeType,
    );
  }

  @override
  Future<String> imageUrl(FormImageAnswer image) async =>
      'https://img.test/${image.path}';

  @override
  Stream<void> changes(String formId) => _changes.stream;
}

/// Picks the same picture every time.
class FakeImagePicker implements ImagePickerService {
  FakeImagePicker({this.size = 1024});

  final int size;
  int picks = 0;

  @override
  Future<ChatImageUpload?> pickImage() async {
    picks++;
    return ChatImageUpload(
      bytes: size <= 4096
          ? samplePhotoPng(width: 60, height: 40)
          : Uint8List(size),
      fileName: 'photo.jpg',
      mimeType: 'image/jpeg',
    );
  }
}

/// Keeps what the export would have handed to the person.
class FakeFormFileExporter implements FormFileExporter {
  final files = <(String, String)>[];
  FormExportOutcome outcome = FormExportOutcome.shared;

  @override
  Future<FormExportOutcome> exportCsv({
    required String fileName,
    required String contents,
    Rect? origin,
  }) async {
    files.add((fileName, contents));
    return outcome;
  }
}

Profile formProfile(String id, String name) {
  return Profile(
    id: id,
    username: name.toLowerCase(),
    displayName: name,
    bio: '',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

/// The providers a form screen needs.
List<Override> formOverrides(
  FakeFormRepository repository, {
  FakeFormFileExporter? exporter,
  FakeImagePicker? picker,
  List<Profile>? members,
  String conversationId = 'group-1',
}) {
  final list =
      members ?? [formProfile('user-3', 'Bob'), formProfile('user-4', 'Cy')];
  return [
    formRepositoryProvider.overrideWithValue(repository),
    if (exporter != null) formFileExporterProvider.overrideWithValue(exporter),
    imagePickerServiceProvider.overrideWithValue(picker ?? FakeImagePicker()),
    chatImageProviderFactoryProvider.overrideWithValue(
      (url) => MemoryImage(samplePhotoPng(width: 120, height: 80)),
    ),
    conversationMembersProvider(conversationId).overrideWith(
      (ref) async => [
        for (final profile in list)
          GroupMember(profile: profile, role: 'member'),
      ],
    ),
  ];
}
