-- Message search, part 3: suggestions for the from:, mentions: and in:
-- filters as they are typed.
--
-- search_filter_suggestions(kind, prefix, scope, max_results):
--   kind 'user': people in the conversations of the scope the caller can
--     read (contacts' aliases count), matching the start of their username
--     or any part of their name; the caller and friends first.
--   kind 'conversation': those conversations themselves (direct chats by
--     the other person's name, groups, channels, threads), most recently
--     active first.
-- At most max_results (1..20, default 8) rows as a jsonb array.

create or replace function public.search_filter_suggestions(
  kind text,
  prefix text,
  scope jsonb,
  max_results integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  needle text := lower(btrim(coalesce(prefix, '')));
  page_size integer := least(greatest(coalesce(max_results, 8), 1), 20);
  conversation_ids uuid[];
  starts_with text;
  contains text;
  result jsonb;
begin
  if caller is null then
    raise exception 'Sign in to search messages' using errcode = '42501';
  end if;
  needle := ltrim(needle, '@#');
  contains := public.search_like_pattern(needle);
  starts_with := substr(contains, 2);
  conversation_ids := public.search_scope_conversation_ids(scope);

  if kind = 'user' then
    select coalesce(jsonb_agg(person order by ordinal), '[]'::jsonb)
    into result
    from (
      select
        jsonb_build_object(
          'id', p.id,
          'username', p.username,
          'display_name', coalesce(
            nullif(btrim(coalesce(ca.alias, '')), ''),
            p.display_name
          ),
          'avatar_url', p.avatar_url
        ) as person,
        row_number() over (
          order by
            (p.username like starts_with) desc,
            (p.id = caller) desc,
            (f.user_low_id is not null) desc,
            lower(p.display_name),
            p.id
        ) as ordinal
      from (
        select distinct cm.user_id
        from public.conversation_members cm
        where cm.conversation_id = any(conversation_ids)
      ) people
      join public.profiles p on p.id = people.user_id
      left join public.contact_aliases ca
        on ca.owner_id = caller
        and ca.friend_id = p.id
      left join public.friendships f
        on f.user_low_id = least(caller, p.id)
        and f.user_high_id = greatest(caller, p.id)
      where p.deleted_at is null
        and (
          needle = ''
          or p.username like starts_with
          or lower(p.display_name) like contains
          or lower(coalesce(ca.alias, '')) like contains
        )
      order by ordinal
      limit page_size
    ) ranked;
    return result;
  end if;

  if kind = 'conversation' then
    select coalesce(jsonb_agg(place order by ordinal), '[]'::jsonb)
    into result
    from (
      select
        details as place,
        row_number() over (
          order by
            (lower(coalesce(details->>'title', '')) like starts_with) desc,
            c.last_message_at desc nulls last,
            c.id
        ) as ordinal
      from public.conversations c
      cross join lateral (
        select public.search_conversation_json(c.id, caller) as details
      ) d
      where c.id = any(conversation_ids)
        and (
          needle = ''
          or lower(coalesce(details->>'title', '')) like contains
          or lower(coalesce(details->>'circle_name', '')) like contains
        )
      order by ordinal
      limit page_size
    ) ranked;
    return result;
  end if;

  raise exception 'Unknown suggestion kind %', kind using errcode = '22023';
end;
$$;

revoke execute on function public.search_filter_suggestions(text, text, jsonb, integer) from public;
revoke execute on function public.search_filter_suggestions(text, text, jsonb, integer) from anon;
grant execute on function public.search_filter_suggestions(text, text, jsonb, integer) to authenticated;
