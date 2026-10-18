// Forms and collection sheets, for the accessibility guard
// (guidelines_test.dart) and the accessibility screenshot tool: a chat with
// form cards, the builder, the fill-in page, and the results (the summary
// with its charts, and the table).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/forms/form_models.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../features/forms/form_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// "Weekend hike sign-up", made by Bart: 8 questions of every kind, 12
/// answers so far out of at most 30, closing in a day.
FakeFormRepository sampleForm({
  bool mine = false,
  bool answered = false,
  bool closed = false,
  bool anonymous = false,
  FormResultsVisibility results = FormResultsVisibility.creator,
}) {
  final repository = FakeFormRepository(
    conversationId: 'group-1',
    title: 'Weekend hike sign-up',
    description: 'Meet at the north gate at 8. Bring water and layers.',
    me: mine ? 'user-2' : 'user-1',
    creatorId: 'user-2',
    closed: closed,
    memberTotal: 18,
    settings: FormSettings(
      anonymous: anonymous,
      results: results,
      maxResponses: 30,
      deadline: DateTime.now().add(const Duration(days: 1, hours: 3)),
    ),
  );
  const names = [
    'Grace',
    'Linus',
    'Ada',
    'Mei',
    'Tomás',
    'Priya',
    'Jonas',
    'Aiko',
    'Sam',
    'Noor',
    'Lea',
    'Omar',
  ];
  const sizes = ['s', 'm', 'm', 'l', 'm', 's', 'l', 'm', 'm', 'l', 's', 'm'];
  const foods = [
    ['veg'],
    ['fish', 'meat'],
    ['meat'],
    ['veg', 'fish'],
    ['veg'],
    ['veg'],
    ['meat'],
    ['fish'],
    ['veg', 'meat'],
    ['veg'],
    ['fish'],
    ['meat'],
  ];
  for (var i = 0; i < names.length; i++) {
    repository.addSheet('user-${i + 10}', names[i], {
      'name': names[i],
      if (i.isEven) 'story': 'No peanuts, please. I can drive 3 people.',
      'age': 24 + i * 3,
      'size': sizes[i],
      'food': foods[i],
      'day': '2026-11-${(6 + i % 3).toString().padLeft(2, '0')}',
      if (i == 1)
        'photo': const FormImageAnswer(
          bucket: 'chat-images',
          path: 'group-1/forms/form-1/pic.jpg',
        ),
      if (i % 4 == 0) 'buddy': 'user-3',
    });
  }
  repository.people['user-3'] = const FormPerson(id: 'user-3', name: 'Grace');
  if (answered) {
    repository.addSheet('user-1', 'Ada', {
      'name': 'Ada',
      'size': 'm',
      'food': ['veg'],
      'age': 31,
    });
  }
  repository.unfilled = [
    for (final profile in extraMembers.take(6))
      FormPerson(id: profile.id, name: profile.displayName),
  ];
  return repository;
}

Future<void> _openGroupWithForm(
  WidgetTester tester,
  PhoneWorld world,
  FakeFormRepository repository,
) async {
  world.extraOverrides = formOverrides(
    repository,
    exporter: FakeFormFileExporter(),
    withImagePicker: false,
    members: [bart, grace, linus, ...extraMembers.take(5)],
  );
  world.chats.messages = [
    ...richMessages().take(3),
    phoneMessage(
      'form-card',
      bart,
      '\u{1F4DD} Weekend hike sign-up',
      minutesAgo: 6,
      conversationId: 'group-1',
      attachment: const {
        'kind': 'form',
        'form_id': 'form-1',
        'title': 'Weekend hike sign-up',
      },
    ),
  ];
  await world.open(
    tester,
    '${ChatsScreen.path}/group-1',
    extra: ChatThreadRouteExtra(
      title: groupDetail.title,
      type: ConversationType.group,
    ),
  );
  await settle(tester);
}

Future<void> _openFill(
  WidgetTester tester,
  PhoneWorld world,
  FakeFormRepository repository,
) async {
  await _openGroupWithForm(tester, world, repository);
  final button = find.byKey(const ValueKey('form-fill-form-1'));
  final edit = find.byKey(const ValueKey('form-edit-form-1'));
  // A closed form has no button: the card itself opens it.
  await tester.tap(
    button.evaluate().isNotEmpty
        ? button
        : edit.evaluate().isNotEmpty
        ? edit
        : find.byKey(const ValueKey('form-card-form-1')),
  );
  await settle(tester);
}

Future<void> _openResults(
  WidgetTester tester,
  PhoneWorld world,
  FakeFormRepository repository,
) async {
  await _openGroupWithForm(tester, world, repository);
  await tester.tap(find.byKey(const ValueKey('form-results-form-1')));
  await settle(tester);
}

Future<void> _openBuilder(WidgetTester tester, PhoneWorld world) async {
  await _openGroupWithForm(tester, world, sampleForm());
  await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('composer-form-entry')));
  await settle(tester);
}

Future<void> _fillBuilder(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('form-title-field')),
    'Weekend hike sign-up',
  );
  await tester.enterText(
    find.byKey(const ValueKey('form-description-field')),
    'Meet at the north gate at 8. Bring water and layers.',
  );
  await tester.enterText(
    find.byKey(const ValueKey('form-label-q1')),
    'Your name',
  );
  Future<void> add(FormFieldType type, String label) async {
    final add = find.byKey(const ValueKey('form-add-question'));
    await tester.scrollUntilVisible(
      add,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    await tester.tap(add);
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('form-type-${type.wire}')));
    await settle(tester);
  }

  await add(FormFieldType.singleChoice, 'T-shirt size');
  await tester.enterText(
    find.byKey(const ValueKey('form-label-q2')),
    'T-shirt size',
  );
  for (final (id, label) in [('o1', 'S'), ('o2', 'M')]) {
    await tester.enterText(find.byKey(ValueKey('form-option-q2-$id')), label);
  }
  await add(FormFieldType.image, 'A photo');
  await tester.enterText(
    find.byKey(const ValueKey('form-label-q3')),
    'A photo of your gear',
  );
  await settle(tester);
}

final formsA11yScreens = <A11yScreen>[
  A11yScreen('form-card', (tester, world) async {
    await _openGroupWithForm(tester, world, sampleForm());
  }),
  A11yScreen('form-card-answered', (tester, world) async {
    await _openGroupWithForm(tester, world, sampleForm(answered: true));
  }),
  A11yScreen('form-card-closed', (tester, world) async {
    await _openGroupWithForm(tester, world, sampleForm(closed: true));
  }),
  A11yScreen('form-card-creator', (tester, world) async {
    await _openGroupWithForm(
      tester,
      world,
      sampleForm(mine: true, anonymous: true),
    );
  }),
  A11yScreen('form-builder', (tester, world) async {
    await _openBuilder(tester, world);
  }),
  A11yScreen('form-builder-filled', (tester, world) async {
    await _openBuilder(tester, world);
    await _fillBuilder(tester);
  }),
  A11yScreen('form-builder-settings', (tester, world) async {
    await _openBuilder(tester, world);
    await _fillBuilder(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('form-setting-results')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
  }),
  A11yScreen('form-fill', (tester, world) async {
    await _openFill(tester, world, sampleForm());
  }),
  A11yScreen('form-fill-bottom', (tester, world) async {
    await _openFill(tester, world, sampleForm(answered: true));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('form-field-buddy')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
  }),
  A11yScreen('form-fill-anonymous', (tester, world) async {
    await _openFill(tester, world, sampleForm(anonymous: true));
  }),
  A11yScreen('form-fill-errors', (tester, world) async {
    await _openFill(tester, world, sampleForm());
    await tester.tap(find.byKey(const ValueKey('form-submit')));
    await settle(tester);
  }),
  A11yScreen('form-member-picker', (tester, world) async {
    await _openFill(tester, world, sampleForm());
    final buddy = find.byKey(const ValueKey('form-input-buddy'));
    await tester.scrollUntilVisible(
      buddy,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(buddy);
    await settle(tester);
  }),
  A11yScreen('form-fill-closed', (tester, world) async {
    await _openFill(tester, world, sampleForm(answered: true, closed: true));
  }),
  A11yScreen('form-results', (tester, world) async {
    await _openResults(tester, world, sampleForm(mine: true));
  }),
  A11yScreen('form-results-charts', (tester, world) async {
    await _openResults(tester, world, sampleForm(mine: true));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('form-stats-size')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
  }),
  A11yScreen('form-results-table', (tester, world) async {
    await _openResults(tester, world, sampleForm(mine: true));
    await tester.tap(find.byKey(const ValueKey('form-tab-table')));
    await settle(tester);
  }),
  A11yScreen('form-results-anonymous', (tester, world) async {
    await _openResults(tester, world, sampleForm(mine: true, anonymous: true));
  }),
  A11yScreen('form-results-unfilled', (tester, world) async {
    await _openResults(tester, world, sampleForm(mine: true));
    await tester.scrollUntilVisible(
      find.textContaining('Not answered yet'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
  }),
  A11yScreen(
    'desktop-form-card',
    (tester, world) async {
      await _openGroupWithForm(tester, world, sampleForm(answered: true));
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-form-fill',
    (tester, world) async {
      await _openFill(tester, world, sampleForm());
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-form-results',
    (tester, world) async {
      await _openResults(tester, world, sampleForm(mine: true));
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-form-table',
    (tester, world) async {
      await _openResults(tester, world, sampleForm(mine: true));
      await tester.tap(find.byKey(const ValueKey('form-tab-table')));
      await settle(tester);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-form-builder',
    (tester, world) async {
      await _openBuilder(tester, world);
      await _fillBuilder(tester);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
];
