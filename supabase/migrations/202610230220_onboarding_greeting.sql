-- Onboarding 2.0 (C2), part 3 of 3: the card that greets a new member.
--
-- When a circle has chosen a greeting channel (set_circle_greeting,
-- 202610230210), every new member is announced there with a system message
--   body        '<name> joined the circle'
--   attachment  {kind: 'newcomer', user_id, user_label, circle_id,
--                sticker_id}
-- The app draws it as a card with a "Say hello" button that replies with the
-- circle's greeting sticker (or a waving hand when it has none) through the
-- ordinary send paths, so the reply obeys the rules, slowmode, AutoMod and
-- the channel's permissions like any message.
--
-- It is one AFTER INSERT trigger on circle_members, which every way into a
-- circle ends in: invite links, Discover, a member adding friends, contact
-- cards and an approved request (C1). It does nothing for the owner, bots,
-- circles that took no greeting channel, or a suspended circle (K1), and
-- a member who left and came back within a week is not announced twice.
-- A greeting that cannot be written never stops the person from joining.
--
-- The system message is sent as the new member (like AutoMod's alerts). It
-- is a system message, so it is skipped by unread counts, pushes and the
-- send-permission trigger.

create or replace function public.announce_new_circle_member()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  settings public.circle_guide_settings%rowtype;
  channel_conversation_id uuid;
  member_label text;
begin
  select s.* into settings
  from public.circle_guide_settings s
  where s.circle_id = new.circle_id
    and s.greeting_channel_id is not null;
  if settings.circle_id is null then
    return new;
  end if;

  if exists (
      select 1 from public.circles c
      where c.id = new.circle_id and c.owner_id = new.user_id
    )
    or exists (
      select 1 from public.profiles p
      where p.id = new.user_id and p.is_bot
    )
    or public.circle_is_suspended(new.circle_id)
  then
    return new;
  end if;

  select cc.conversation_id into channel_conversation_id
  from public.circle_channels cc
  where cc.id = settings.greeting_channel_id
    and cc.circle_id = new.circle_id;
  if channel_conversation_id is null then
    return new;
  end if;

  if exists (
    select 1
    from public.messages m
    where m.conversation_id = channel_conversation_id
      and m.type = 'system'
      and m.attachment ->> 'kind' = 'newcomer'
      and m.attachment ->> 'user_id' = new.user_id::text
      and m.created_at > now() - interval '7 days'
  ) then
    return new;
  end if;

  begin
    member_label := coalesce(
      public.circle_member_label(new.circle_id, new.user_id),
      'Someone'
    );
    insert into public.messages (
      conversation_id,
      sender_id,
      type,
      body,
      attachment
    )
    values (
      channel_conversation_id,
      new.user_id,
      'system',
      member_label || ' joined the circle',
      jsonb_build_object(
        'kind', 'newcomer',
        'user_id', new.user_id,
        'user_label', member_label,
        'circle_id', new.circle_id,
        'sticker_id', settings.greeting_sticker_id
      )
    );
  exception when others then
    null;
  end;

  return new;
end;
$$;

revoke execute on function public.announce_new_circle_member()
  from public, anon, authenticated;

drop trigger if exists circle_members_announce_newcomer on public.circle_members;
create trigger circle_members_announce_newcomer
  after insert on public.circle_members
  for each row execute function public.announce_new_circle_member();
