-- "Download my data" (202610170053), part two: Moments, friend tags and
-- stars, group chains, notes and task lists, saved messages, reminders,
-- scheduled messages and chat wallpapers.
--
-- Two functions for the data-export Edge Function (service role only, like
-- begin_data_export). Each starts from the person it is asked about and
-- reads only rows that person wrote or owns, so the export cannot be made
-- to carry somebody else's content by a mistake in the function:
--
-- * export_my_moments(user): my Moments settings, my per-friend choices
--   (hide_mine / hide_theirs), the posts I wrote (every column, so columns
--   added later, such as a video, are exported too; the audience resolved to
--   names), the comments I wrote (with the post id and the post author's
--   name; the text of the post only when it is mine), my likes (post ids),
--   my friend tags with who is in them, and my starred friends. Other
--   people's posts, photos, comments, tags, stars and choices are never
--   read.
-- * export_my_extras(user): chains I created or joined (chain entries: only
--   mine), notes (only the blocks I last wrote), task lists (only the items I
--   created), saved messages, reminders (the message text only when I wrote
--   it), scheduled messages and chat wallpapers.
--
-- People are only ever named (id, username, display name): the same names
-- the export already carries for friends and conversations.
--
-- Everything is capped (rows per section), so one export stays small.

-- A person as the export names them. Internal.
create or replace function public.export_person_json(person_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case
    when person_id is null then null
    else coalesce(
      (
        select jsonb_build_object(
          'id', p.id,
          'username', p.username,
          'display_name', p.display_name
        )
        from public.profiles p
        where p.id = person_id
      ),
      jsonb_build_object('id', person_id, 'username', null, 'display_name', null)
    )
  end;
$$;

revoke execute on function public.export_person_json(uuid) from public;
revoke execute on function public.export_person_json(uuid) from anon;
revoke execute on function public.export_person_json(uuid) from authenticated;

create or replace function public.export_my_moments(target_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if target_user_id is null then
    raise exception 'A user is required' using errcode = '22023';
  end if;

  select jsonb_build_object(
    'settings', (
      select to_jsonb(s)
      from public.moments_settings s
      where s.user_id = target_user_id
    ),
    'friend_prefs', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'friend', public.export_person_json(f.friend_id),
          'hide_mine', f.hide_mine,
          'hide_theirs', f.hide_theirs,
          'updated_at', f.updated_at
        )
        order by f.updated_at desc, f.friend_id
      )
      from (
        select *
        from public.moments_friend_prefs
        where owner_id = target_user_id
        order by updated_at desc, friend_id
        limit 5000
      ) f
    ), '[]'::jsonb),
    'posts', coalesce((
      select jsonb_agg(
        to_jsonb(p) || jsonb_build_object(
          'audience_friends', coalesce((
            select jsonb_agg(public.export_person_json(a.id) order by a.id)
            from (select distinct unnest(p.audience_friend_ids) as id) a
          ), '[]'::jsonb),
          'audience_tags', coalesce((
            select jsonb_agg(
              jsonb_build_object('id', t.id, 'name', t.name)
              order by t.name, t.id
            )
            from public.friend_tags t
            where t.owner_id = target_user_id
              and t.id = any (p.audience_tag_ids)
          ), '[]'::jsonb)
        )
        order by p.created_at desc, p.id
      )
      from (
        select *
        from public.moments_posts
        where author_id = target_user_id
        order by created_at desc, id desc
        limit 5000
      ) p
    ), '[]'::jsonb),
    'comments', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'post_id', c.post_id,
          'post_author', public.export_person_json(c.post_author_id),
          'post_text', case when c.post_author_id = target_user_id then c.post_body end,
          'reply_to', public.export_person_json(c.reply_to_user_id),
          'text', c.body,
          'created_at', c.created_at
        )
        order by c.created_at desc, c.id
      )
      from (
        select mc.id, mc.post_id, mc.reply_to_user_id, mc.body, mc.created_at,
               mp.author_id as post_author_id, mp.body as post_body
        from public.moments_comments mc
        join public.moments_posts mp on mp.id = mc.post_id
        where mc.author_id = target_user_id
        order by mc.created_at desc, mc.id desc
        limit 10000
      ) c
    ), '[]'::jsonb),
    'likes', coalesce((
      select jsonb_agg(
        jsonb_build_object('post_id', l.post_id, 'created_at', l.created_at)
        order by l.created_at desc, l.post_id
      )
      from (
        select post_id, created_at
        from public.moments_likes
        where user_id = target_user_id
        order by created_at desc, post_id
        limit 20000
      ) l
    ), '[]'::jsonb),
    'tags', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', t.id,
          'name', t.name,
          'created_at', t.created_at,
          'friends', coalesce((
            select jsonb_agg(public.export_person_json(m.friend_id) order by m.created_at, m.friend_id)
            from public.friend_tag_members m
            where m.tag_id = t.id and m.owner_id = target_user_id
          ), '[]'::jsonb)
        )
        order by t.name, t.id
      )
      from (
        select *
        from public.friend_tags
        where owner_id = target_user_id
        order by name, id
        limit 1000
      ) t
    ), '[]'::jsonb),
    'stars', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'friend', public.export_person_json(s.friend_id),
          'starred_at', s.created_at
        )
        order by s.created_at, s.friend_id
      )
      from (
        select friend_id, created_at
        from public.friend_stars
        where owner_id = target_user_id
        order by created_at, friend_id
        limit 5000
      ) s
    ), '[]'::jsonb)
  )
  into result;

  return result;
end;
$$;

create or replace function public.export_my_extras(target_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if target_user_id is null then
    raise exception 'A user is required' using errcode = '22023';
  end if;

  select jsonb_build_object(
    -- Chains I made or joined. The title and who made it are context; the
    -- description, the example and the line of every other person are not
    -- exported, and neither is the list of who else joined.
    'chains', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'conversation_id', c.conversation_id,
          'title', c.title,
          'created_by_me', c.created_by = target_user_id,
          'creator', public.export_person_json(c.created_by),
          'description', case when c.created_by = target_user_id then c.description end,
          'example', case when c.created_by = target_user_id then c.example end,
          'deadline', c.deadline,
          'max_entries', c.max_entries,
          'entry_count', c.entry_count,
          'closed_at', c.closed_at,
          'created_at', c.created_at,
          'my_entry', (
            select jsonb_build_object(
              'text', e.note,
              'joined_at', e.created_at,
              'updated_at', e.updated_at
            )
            from public.chain_entries e
            where e.chain_id = c.id and e.user_id = target_user_id
          )
        )
        order by c.created_at desc, c.id
      )
      from (
        select *
        from public.chains ch
        where ch.created_by = target_user_id
          or exists (
            select 1
            from public.chain_entries e
            where e.chain_id = ch.id and e.user_id = target_user_id
          )
        order by ch.created_at desc, ch.id desc
        limit 2000
      ) c
    ), '[]'::jsonb),
    -- Notes I made or wrote in. The title and icon are context; of the
    -- text only the blocks whose last editor is me.
    'notes', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', n.id,
          'conversation_id', n.conversation_id,
          'title', n.title,
          'icon', n.icon,
          'created_by_me', n.created_by = target_user_id,
          'pinned', n.pinned,
          'created_at', n.created_at,
          'updated_at', n.updated_at,
          'blocks', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'kind', b.kind,
                'text', b.text,
                'marks', b.marks,
                'props', b.props,
                'updated_at', b.updated_at
              )
              order by b.pos, b.id
            )
            from (
              select *
              from public.note_blocks nb
              where nb.note_id = n.id
                and not nb.deleted
                and nb.updated_by = target_user_id
              order by nb.pos, nb.id
              limit 2000
            ) b
          ), '[]'::jsonb)
        )
        order by n.updated_at desc, n.id
      )
      from (
        select *
        from public.notes nn
        where nn.deleted_at is null
          and (
            nn.created_by = target_user_id
            or exists (
              select 1
              from public.note_blocks nb
              where nb.note_id = nn.id
                and not nb.deleted
                and nb.updated_by = target_user_id
            )
          )
        order by nn.updated_at desc, nn.id desc
        limit 2000
      ) n
    ), '[]'::jsonb),
    -- Task lists I made or added items to. The title is context; of the
    -- items only the ones I created (and who they are assigned to, by name).
    'task_lists', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', l.id,
          'conversation_id', l.conversation_id,
          'title', l.title,
          'icon', l.icon,
          'created_by_me', l.created_by = target_user_id,
          'statuses', case when l.created_by = target_user_id then l.statuses end,
          'created_at', l.created_at,
          'items', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', i.id,
                'title', i.title,
                'details', i.details,
                'status', i.status,
                'priority', i.priority,
                'due_at', i.due_at,
                'created_at', i.created_at,
                'updated_at', i.updated_at,
                'completed_at', i.completed_at,
                'assigned_to', coalesce((
                  select jsonb_agg(public.export_person_json(a.user_id) order by a.assigned_at, a.user_id)
                  from public.task_item_assignees a
                  where a.item_id = i.id
                ), '[]'::jsonb)
              )
              order by i.created_at, i.id
            )
            from (
              select *
              from public.task_items ti
              where ti.list_id = l.id
                and ti.deleted_at is null
                and ti.created_by = target_user_id
              order by ti.created_at, ti.id
              limit 2000
            ) i
          ), '[]'::jsonb)
        )
        order by l.created_at desc, l.id
      )
      from (
        select *
        from public.task_lists tl
        where tl.deleted_at is null
          and (
            tl.created_by = target_user_id
            or exists (
              select 1
              from public.task_items ti
              where ti.list_id = tl.id
                and ti.deleted_at is null
                and ti.created_by = target_user_id
            )
          )
        order by tl.created_at desc, tl.id desc
        limit 1000
      ) l
    ), '[]'::jsonb),
    -- Messages I saved: when and where. The text only when I wrote it.
    'saved_messages', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', s.id,
          'conversation_id', s.conversation_id,
          'message_id', s.message_id,
          'saved_at', s.created_at,
          'done_at', s.done_at,
          'from_you', s.message_sender_id = target_user_id,
          'text', case when s.message_sender_id = target_user_id then s.message_body end,
          'message_sent_at', case when s.message_sender_id = target_user_id then s.message_created_at end
        )
        order by s.created_at desc, s.id
      )
      from (
        select sm.id, sm.conversation_id, sm.message_id, sm.created_at, sm.done_at,
               m.sender_id as message_sender_id, m.body as message_body,
               m.created_at as message_created_at
        from public.saved_messages sm
        left join public.messages m on m.id = sm.message_id
        where sm.user_id = target_user_id
        order by sm.created_at desc, sm.id desc
        limit 5000
      ) s
    ), '[]'::jsonb),
    'reminders', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', r.id,
          'conversation_id', r.conversation_id,
          'message_id', r.message_id,
          'remind_at', r.remind_at,
          'created_at', r.created_at,
          'dismissed_at', r.dismissed_at,
          'from_you', r.message_sender_id = target_user_id,
          'text', case when r.message_sender_id = target_user_id then r.message_body end
        )
        order by r.remind_at desc, r.id
      )
      from (
        select mr.id, mr.conversation_id, mr.message_id, mr.remind_at, mr.created_at,
               mr.dismissed_at, m.sender_id as message_sender_id, m.body as message_body
        from public.message_reminders mr
        left join public.messages m on m.id = mr.message_id
        where mr.user_id = target_user_id
        order by mr.remind_at desc, mr.id desc
        limit 5000
      ) r
    ), '[]'::jsonb),
    'scheduled_messages', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', s.id,
          'conversation_id', s.conversation_id,
          'text', s.body,
          'mentions', s.mentions,
          'send_at', s.send_at,
          'status', s.status,
          'sent_at', s.sent_at,
          'created_at', s.created_at
        )
        order by s.send_at desc, s.id
      )
      from (
        select *
        from public.scheduled_messages
        where owner_id = target_user_id
        order by send_at desc, id desc
        limit 5000
      ) s
    ), '[]'::jsonb),
    'wallpapers', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'conversation_id', w.conversation_id,
          'kind', w.kind,
          'preset_id', w.preset_id,
          'photo_path', w.photo_path,
          'dim', w.dim,
          'blur', w.blur,
          'focus_x', w.focus_x,
          'focus_y', w.focus_y,
          'created_at', w.created_at,
          'updated_at', w.updated_at
        )
        order by w.created_at, w.id
      )
      from (
        select *
        from public.chat_wallpapers
        where user_id = target_user_id
        order by created_at, id
        limit 2000
      ) w
    ), '[]'::jsonb)
  )
  into result;

  return result;
end;
$$;

revoke execute on function public.export_my_moments(uuid) from public;
revoke execute on function public.export_my_moments(uuid) from anon;
revoke execute on function public.export_my_moments(uuid) from authenticated;
revoke execute on function public.export_my_extras(uuid) from public;
revoke execute on function public.export_my_extras(uuid) from anon;
revoke execute on function public.export_my_extras(uuid) from authenticated;
