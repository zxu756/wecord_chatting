-- Repeating scheduled messages (D4, part 1 of 2): the columns.
--
-- A scheduled message can repeat: every day, on weekdays, every week on the
-- weekday of the first send, or every month on the day of the month of the
-- first send. It repeats on the sender's wall clock in their time zone, so
-- "Monday 9:00" stays 9:00 across the clock changes of daylight saving.
--
--   recurrence        daily | weekdays | weekly | monthly; null: sent once
--   recurrence_day    weekly: the ISO weekday 1 (Monday) to 7 (Sunday);
--                     monthly: the day of the month, 1 to 31; else null
--   recurrence_time   the time of day on the wall clock, to the minute
--   recurrence_tz     the IANA zone the wall clock is in ('Asia/Shanghai')
--   recurrence_until  the last local date it may be sent on, inclusive; null:
--                     it goes on until stopped
--   recurrence_parent_id  the earlier send this row was made after
--
-- There is only ever one waiting row for a series: the next send. Sending it
-- (or failing to) writes the one after it (202610240450). The parent link has
-- a unique index, so one send can never make two next sends, however often it
-- is retried. The row's own id is the client_id of the message it sends
-- (202610170010), so a retry can never send the same message twice either.

alter table public.scheduled_messages
  add column if not exists recurrence text,
  add column if not exists recurrence_day smallint,
  add column if not exists recurrence_time time,
  add column if not exists recurrence_tz text,
  add column if not exists recurrence_until date,
  add column if not exists recurrence_parent_id uuid
    references public.scheduled_messages(id) on delete set null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'scheduled_messages_recurrence_shape'
      and conrelid = 'public.scheduled_messages'::regclass
  ) then
    alter table public.scheduled_messages
      add constraint scheduled_messages_recurrence_shape check (
        (
          recurrence is null
          and recurrence_day is null
          and recurrence_time is null
          and recurrence_until is null
        )
        or (
          recurrence in ('daily', 'weekdays', 'weekly', 'monthly')
          and recurrence_time is not null
          and recurrence_tz is not null
          and (
            (recurrence in ('daily', 'weekdays') and recurrence_day is null)
            or (recurrence = 'weekly' and recurrence_day between 1 and 7)
            or (recurrence = 'monthly' and recurrence_day between 1 and 31)
          )
        )
      );
  end if;
end;
$$;

-- One send makes at most one next send.
create unique index if not exists scheduled_messages_recurrence_parent_key
  on public.scheduled_messages (recurrence_parent_id)
  where recurrence_parent_id is not null;

create index if not exists scheduled_messages_recurring_owner_idx
  on public.scheduled_messages (owner_id)
  where recurrence is not null and status = 'pending';
