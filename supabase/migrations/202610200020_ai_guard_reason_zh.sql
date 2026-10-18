-- The AI guard's reason in the reader's language.
--
-- The model now gives its reason in English and in Simplified Chinese
-- (supabase/functions/ai, guard mode). message_reviews.reason_zh keeps the
-- Chinese one; the Review queue shows it when the app is in Chinese and
-- falls back to the English reason (older rows have none).
--
-- * finish_message_review gets a fifth argument, p_reason_zh (default null,
--   so four-argument callers keep working). The old four-argument function
--   is dropped so the name is not ambiguous for named-argument calls.
-- * list_message_reviews returns reason_zh. A changed result type needs a
--   drop and create.
-- Everything else in both functions is as in 202610170090.

alter table public.message_reviews
  add column if not exists reason_zh text;

drop function if exists public.finish_message_review(uuid, text, text, text);

create or replace function public.finish_message_review(
  p_message_id uuid,
  p_verdict text,
  p_reason text default null,
  p_unchecked_reason text default null,
  p_reason_zh text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  review public.message_reviews%rowtype;
  new_state text;
  flagged boolean;
  clean_reason text := nullif(left(btrim(coalesce(p_reason, '')), 240), '');
  clean_reason_zh text := nullif(left(btrim(coalesce(p_reason_zh, '')), 240), '');
  channel public.circle_channels%rowtype;
begin
  if p_verdict is null
    or p_verdict not in ('allow', 'spam', 'scam', 'harassment', 'sexual', 'other', 'not_checked')
  then
    raise exception 'Unknown verdict' using errcode = '22023';
  end if;

  select r.* into review
  from public.message_reviews r
  where r.message_id = p_message_id and r.state = 'checking'
  for update;
  if review.message_id is null then
    return null;
  end if;

  flagged := p_verdict not in ('allow', 'not_checked');

  if flagged and review.mode = 'hold' then
    update public.messages m set review_state = 'held' where m.id = p_message_id;
    new_state := 'held';
  else
    perform public.ai_guard_release_message(p_message_id);
    new_state := case when flagged then 'flagged' else 'released' end;
  end if;

  update public.message_reviews r
  set
    state = new_state,
    verdict = p_verdict,
    reason = case when flagged then clean_reason end,
    reason_zh = case when flagged then clean_reason_zh end,
    unchecked_reason = case
      when p_verdict = 'not_checked' then coalesce(p_unchecked_reason, 'error')
    end,
    checked_at = now(),
    released_at = case when new_state in ('released', 'flagged') then now() end,
    push_pending = new_state in ('released', 'flagged')
  where r.message_id = p_message_id;

  if flagged then
    select cc.* into channel
    from public.circle_channels cc
    where cc.id = public.conversation_circle_channel_id(review.conversation_id);

    insert into public.circle_audit_log (
      circle_id, actor_id, action, target_type, target_id, target_label, changes
    )
    values (
      review.circle_id,
      null,
      case when new_state = 'held' then 'guard_hold' else 'guard_flag' end,
      'message',
      p_message_id,
      public.circle_member_label(review.circle_id, review.sender_id),
      jsonb_strip_nulls(jsonb_build_object(
        'verdict', p_verdict,
        'reason', clean_reason,
        'author_id', review.sender_id,
        'channel_id', channel.id,
        'channel_name', channel.name
      ))
    );
  end if;

  if new_state in ('released', 'flagged') then
    -- Push it now; the sweep tries again when this call is lost.
    perform public.ai_guard_wake('scheduled-dispatch', '{}'::jsonb);
  end if;

  return new_state;
end;
$$;

revoke execute on function public.finish_message_review(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function public.finish_message_review(uuid, text, text, text, text) to service_role;

drop function if exists public.list_message_reviews(uuid, integer);

create or replace function public.list_message_reviews(
  target_circle_id uuid,
  max_results integer default 50
)
returns table (
  message_id uuid,
  conversation_id uuid,
  channel_id uuid,
  channel_name text,
  sender_id uuid,
  sender_name text,
  sender_avatar_url text,
  body text,
  state text,
  verdict text,
  reason text,
  sent_at timestamptz,
  checked_at timestamptz,
  reason_zh text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  return query
  select
    r.message_id,
    r.conversation_id,
    cc.id,
    cc.name,
    r.sender_id,
    public.circle_member_label(r.circle_id, r.sender_id),
    coalesce(cm.avatar_url, p.avatar_url),
    m.body,
    r.state,
    r.verdict,
    r.reason,
    m.created_at,
    r.checked_at,
    r.reason_zh
  from public.message_reviews r
  join public.messages m on m.id = r.message_id
  join public.profiles p on p.id = r.sender_id
  left join public.circle_members cm
    on cm.circle_id = r.circle_id and cm.user_id = r.sender_id
  left join public.circle_channels cc
    on cc.id = public.conversation_circle_channel_id(r.conversation_id)
  where r.circle_id = target_circle_id
    and r.state in ('held', 'flagged')
    and m.recalled_at is null
    and public.can_current_user_moderate_messages(r.conversation_id)
  order by m.created_at desc, r.message_id desc
  limit least(greatest(coalesce(max_results, 50), 1), 100);
end;
$$;

revoke execute on function public.list_message_reviews(uuid, integer) from public, anon;
grant execute on function public.list_message_reviews(uuid, integer) to authenticated;
