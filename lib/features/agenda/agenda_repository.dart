import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/agenda/agenda_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// Reads My agenda: events I answered Going or Maybe to, circle events I am
/// interested in, tasks assigned to me, my reminders and my messages
/// waiting to be sent, from every chat I can still read.
abstract interface class AgendaRepository {
  /// The entries with a time in [from, to), soonest first (at most 500).
  Future<List<AgendaItem>> fetch(DateTime from, DateTime to);
}

final agendaRepositoryProvider = Provider<AgendaRepository>((ref) {
  try {
    return SupabaseAgendaRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedAgendaRepository();
  }
});

class SupabaseAgendaRepository implements AgendaRepository {
  const SupabaseAgendaRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<AgendaItem>> fetch(DateTime from, DateTime to) async {
    final rows = await _client.rpc<List<dynamic>>(
      'get_my_agenda',
      params: {
        'p_from': from.toUtc().toIso8601String(),
        'p_to': to.toUtc().toIso8601String(),
      },
    );
    return [
      for (final row in rows) ?AgendaItem.tryParse(row as Map<String, dynamic>),
    ];
  }
}

class UninitializedAgendaRepository implements AgendaRepository {
  const UninitializedAgendaRepository();

  @override
  Future<List<AgendaItem>> fetch(DateTime from, DateTime to) async => const [];
}

/// How far back the list view looks for overdue tasks and reminders.
const agendaLookBack = Duration(days: 60);

/// How far ahead the list view looks.
const agendaLookAhead = Duration(days: 90);

/// The entries of the list view: overdue ones from the last two months and
/// everything in the next three. Fetched again when the next entry comes
/// due (so it turns red on time), and at least every ten minutes.
final agendaListProvider = FutureProvider.autoDispose<List<AgendaItem>>((
  ref,
) async {
  final now = clock.now();
  final today = dateOnly(now);
  final items = await ref
      .watch(agendaRepositoryProvider)
      .fetch(today.subtract(agendaLookBack), today.add(agendaLookAhead));
  final next = items
      .where((item) => item.startsAt.isAfter(now.toUtc()))
      .map((item) => item.startsAt)
      .fold<DateTime?>(
        null,
        (soonest, at) => soonest == null || at.isBefore(soonest) ? at : soonest,
      );
  if (items.isNotEmpty) {
    final wait = next == null
        ? const Duration(minutes: 10)
        : next.difference(now.toUtc()) + const Duration(seconds: 2);
    final timer = Timer(
      wait > const Duration(minutes: 10) ? const Duration(minutes: 10) : wait,
      ref.invalidateSelf,
    );
    ref.onDispose(timer.cancel);
  }
  return items;
});

/// How many entries need me: the red badge on the Agenda entries.
final agendaOverdueCountProvider = Provider.autoDispose<int>((ref) {
  final items = ref.watch(agendaListProvider).value;
  return items == null ? 0 : agendaOverdueCount(items, clock.now());
});

/// The entries of one month (a local midnight on its first day) and the
/// days of the neighbouring months its grid shows.
final agendaMonthProvider = FutureProvider.autoDispose
    .family<List<AgendaItem>, DateTime>((ref, month) {
      return ref
          .watch(agendaRepositoryProvider)
          .fetch(
            DateTime(month.year, month.month, -6),
            DateTime(month.year, month.month + 1, 8),
          );
    });
