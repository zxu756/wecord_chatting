-- Media channels and Q&A channels (roadmap C9), part 4 of 4: taking your data.
--
-- export_my_channel_posts(user) is for the data-export Edge Function (service
-- role only, like export_my_honors): what the person made in media and Q&A
-- channels, and only that:
--   * media_posts: the posts they made in media channels, with the circle,
--     the channel, the title, the time and the picture (a storage path the
--     function signs, and the description they wrote, if any);
--   * questions: the posts they made in Q&A channels, with whether they were
--     solved, when, whether an answer was accepted, and whether they marked
--     it themselves;
--   * accepted_answers: where an answer of theirs was accepted: the circle,
--     the channel and the time. Not the question's title or text: that is
--     somebody else's words.
-- The words of the posts and answers themselves are with their messages in the
-- rest of the export. Deleting an account already erases the waiting pushes
-- and the name of whoever solved a post (profiles_erase_qa, 202610270300).

create or replace function public.export_my_channel_posts(target_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if target_user_id is null then
    raise exception 'A user is required' using errcode = '22023';
  end if;

  return jsonb_build_object(
    'media_posts', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'circle_id', cc.circle_id,
          'circle_name', c.name,
          'channel_name', cc.name,
          'title', ct.title,
          'posted_at', ct.created_at,
          'picture', (
            select jsonb_build_object(
              'bucket', m.attachment ->> 'bucket',
              'path', m.attachment ->> 'path',
              'description', m.attachment ->> 'alt'
            )
            from public.messages m
            where m.conversation_id = ct.conversation_id
              and m.sender_id = target_user_id
              and m.recalled_at is null
              and m.attachment ->> 'kind' = 'image'
            order by m.created_at, m.id
            limit 1
          )
        )
        order by ct.created_at desc, ct.id
      )
      from public.conversation_threads ct
      join public.circle_channels cc
        on cc.conversation_id = ct.parent_conversation_id and cc.kind = 'media'
      join public.circles c on c.id = cc.circle_id
      where ct.created_by = target_user_id
    ), '[]'::jsonb),
    'questions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'circle_id', cc.circle_id,
          'circle_name', c.name,
          'channel_name', cc.name,
          'title', ct.title,
          'asked_at', ct.created_at,
          'solved', ct.solved_at is not null,
          'solved_at', ct.solved_at,
          'answer_accepted', ct.solved_message_id is not null,
          'solved_by_you', ct.solved_by = target_user_id
        )
        order by ct.created_at desc, ct.id
      )
      from public.conversation_threads ct
      join public.circle_channels cc
        on cc.conversation_id = ct.parent_conversation_id and cc.kind = 'qa'
      join public.circles c on c.id = cc.circle_id
      where ct.created_by = target_user_id
    ), '[]'::jsonb),
    'accepted_answers', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'circle_id', cc.circle_id,
          'circle_name', c.name,
          'channel_name', cc.name,
          'accepted_at', ct.solved_at
        )
        order by ct.solved_at desc, ct.id
      )
      from public.conversation_threads ct
      join public.messages m on m.id = ct.solved_message_id
      join public.circle_channels cc
        on cc.conversation_id = ct.parent_conversation_id and cc.kind = 'qa'
      join public.circles c on c.id = cc.circle_id
      where m.sender_id = target_user_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_channel_posts(uuid)
  from public, anon, authenticated;
grant execute on function public.export_my_channel_posts(uuid) to service_role;
