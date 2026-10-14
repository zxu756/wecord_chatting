-- Circles created before new circles started with a voice channel get the
-- same "General" voice channel, after their existing channels. Circles that
-- already have a voice channel are left alone.

do $$
declare
  target record;
  created_conversation_id uuid;
begin
  for target in
    select c.id, c.owner_id
    from public.circles c
    where not exists (
      select 1
      from public.circle_channels cc
      where cc.circle_id = c.id
        and cc.kind = 'voice'
    )
  loop
    insert into public.conversations (type, title)
    values ('channel', 'General')
    returning id into created_conversation_id;

    insert into public.conversation_members (conversation_id, user_id, role)
    select created_conversation_id, cm.user_id, cm.role
    from public.circle_members cm
    where cm.circle_id = target.id
    on conflict do nothing;

    insert into public.circle_channels (
      circle_id,
      conversation_id,
      name,
      position,
      created_by,
      kind
    )
    values (
      target.id,
      created_conversation_id,
      'General',
      coalesce((
        select max(position) + 1
        from public.circle_channels
        where circle_id = target.id
      ), 0),
      target.owner_id,
      'voice'
    );
  end loop;
end;
$$;
