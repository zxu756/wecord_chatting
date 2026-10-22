import 'dart:async';

import 'package:wecord/features/interactions/interactions_repository.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/message_components.dart';

import '../../mobile/phone_test_support.dart';

/// One press as the fake saw it.
typedef SubmittedPress = ({
  String messageId,
  String componentId,
  Object? values,
});

/// A fake server for presses on a bot's components: records every press,
/// answers (or fails) as told, and holds the bot's private replies.
class FakeInteractionsRepository implements InteractionsRepository {
  final presses = <SubmittedPress>[];
  final dismissed = <String>[];

  /// What the next press does: throws it when set.
  InteractionException? failWith;

  /// What each look at the press finds, in order (the last one repeats).
  List<InteractionStatus> statuses = const [
    InteractionStatus(InteractionState.pending),
  ];
  var _looks = 0;
  var statusCalls = 0;

  /// The bot's private replies, by conversation.
  var ephemeral = <EphemeralReply>[];
  final _changes = StreamController<void>.broadcast();

  void changed() => _changes.add(null);

  @override
  Future<InteractionReceipt> submit({
    required String messageId,
    required String componentId,
    Object? values,
  }) async {
    final error = failWith;
    if (error != null) {
      throw error;
    }
    presses.add((
      messageId: messageId,
      componentId: componentId,
      values: values,
    ));
    _looks = 0;
    return InteractionReceipt(
      interactionId: 'interaction-${presses.length}',
      botName: 'Helper',
    );
  }

  @override
  Future<InteractionStatus> status(String interactionId) async {
    statusCalls++;
    final index = _looks < statuses.length ? _looks : statuses.length - 1;
    _looks++;
    return statuses[index];
  }

  @override
  Future<List<EphemeralReply>> listEphemeral(String conversationId) async =>
      List.of(ephemeral);

  @override
  Stream<void> ephemeralChanges(String conversationId) => _changes.stream;

  @override
  Future<void> dismissEphemeral(String id) async {
    dismissed.add(id);
    ephemeral = [
      for (final reply in ephemeral)
        if (reply.id != id) reply,
    ];
  }
}

/// The components of the sample message: a primary and a danger button, a
/// link, a drop-down with a choice of two, and a button that opens a form.
List<List<Map<String, dynamic>>> sampleComponentsJson() => [
  [
    {'type': 'button', 'id': 'approve', 'label': 'Approve', 'style': 'primary'},
    {'type': 'button', 'id': 'reject', 'label': 'Reject', 'style': 'danger'},
    {'type': 'link', 'label': 'Docs', 'url': 'https://example.com/docs'},
  ],
  [
    {
      'type': 'select',
      'id': 'pick',
      'placeholder': 'Pick a trail',
      'options': [
        {'label': 'Ridge', 'value': 'ridge', 'description': 'Hard'},
        {'label': 'Lake', 'value': 'lake'},
        {'label': 'Forest', 'value': 'forest'},
      ],
      'min_values': 1,
      'max_values': 1,
    },
  ],
  [
    {
      'type': 'button',
      'id': 'note',
      'label': 'Add a note',
      'modal': {
        'title': 'Your note',
        'fields': [
          {
            'id': 'text',
            'label': 'Note',
            'style': 'paragraph',
            'max_length': 50,
          },
          {'id': 'name', 'label': 'Name', 'required': false},
        ],
      },
    },
  ],
];

/// A message from the bot Bart with [components] (a list of rows as the
/// server stores them), in the chat `dm-1` of the phone world.
ChatMessage botMessage(
  String id, {
  Object? components,
  String body = 'Pick one',
  int minutesAgo = 5,
}) {
  return phoneMessage(
    id,
    bart,
    body,
    minutesAgo: minutesAgo,
  ).copyWith(components: MessageComponents.maybeFromJson(components));
}
