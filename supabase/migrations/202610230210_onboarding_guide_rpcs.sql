-- Onboarding 2.0 (C2), part 2 of 3: what members and managers call.
-- Tables and the role rule are in 202610230200.
--
-- Members (any member of the circle)
--   * get_circle_guide(circle): the questions with the member's picks, the
--     tasks with their progress, whether to ask the member now, and whether
--     they joined after the guide began ('new_member': the app shows the
--     guide card on its own only to them; everyone finds it in the menu). A
--     suspended circle (K1) answers "nothing here". Only roles that can
--     still be handed out and channels the member can see are named.
--   * complete_onboarding_prompts(circle, option_ids): saves the picks and
--     makes the member's roles match them. Callable again to change picks.
--       - single-select questions take one option, required ones at least
--         one (errcode 22023, detail 'single_select' / 'required_prompt');
--       - roles come only from the options picked and only when
--         onboarding_role_problem() (202610230200) says the role is still
--         plain NOW, whatever it was when it was attached;
--       - roles the member got this way are marked via_onboarding and are
--         the only ones taken back when they change their mind; a role an
--         admin gave by hand is never touched;
--       - this is a system grant: it skips the "only roles below your own"
--         rule of set_member_roles, and the audit log says so
--         (onboarding_roles, target = the member, source 'onboarding').
--   * complete_guide_task(circle, task): ticks off a "visit a channel"
--     task (the others are worked out from the member's own state).
--   * dismiss_circle_guide(circle, dismissed): puts the guide card away or
--     brings it back.
--
-- Managers
--   * get_circle_guide_config(circle): everything, for the editor
--     (manage_circle).
--   * set_circle_guide_prompts(circle, prompts): replaces the questions
--     (manage_circle). Giving an option a NEW role also needs manage_roles
--     and a role below the caller's own rank, like set_member_roles; the
--     role must pass onboarding_role_problem() (errcode 22023, detail
--     'role_permissions' / 'role_rank' / 'role_default' / 'role_missing',
--     hint the role id). Up to 5 questions, 12 options each, 5 roles and 5
--     channels per option. Items with an id keep it (and the members'
--     picks); the rest are new; whatever is missing is deleted.
--   * set_circle_guide_tasks(circle, tasks): replaces the task list (up to
--     10) the same way (manage_circle).
--   * set_circle_greeting(circle, channel, sticker): where new members are
--     announced, and the sticker for the card's "Say hello" (202610230220).
--   Each manager call is audited as onboarding_update.
--
-- Nothing here changes an earlier function; get_circle_onboarding,
-- accept_circle_rules and set_circle_onboarding (202610160021) are as they
-- were.

-- ---------------------------------------------------------------------------
-- Members
-- ---------------------------------------------------------------------------

create or replace function public.get_circle_guide(target_circle_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  member_row public.circle_members%rowtype;
  progress public.circle_member_onboarding%rowtype;
  rules_row public.circle_onboarding%rowtype;
  settings_row public.circle_guide_settings%rowtype;
  has_avatar boolean;
  prompts_json jsonb;
  tasks_json jsonb;
  prompt_count integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cm.* into member_row
  from public.circle_members cm
  where cm.circle_id = target_circle_id
    and cm.user_id = current_user_id;
  if member_row.user_id is null then
    raise exception 'Circle not found or caller is not a member'
      using errcode = '42501';
  end if;

  if public.circle_is_suspended(target_circle_id) then
    return jsonb_build_object(
      'enabled', false,
      'prompts', '[]'::jsonb,
      'tasks', '[]'::jsonb
    );
  end if;

  select p.* into progress
  from public.circle_member_onboarding p
  where p.circle_id = target_circle_id
    and p.user_id = current_user_id;

  select o.* into rules_row
  from public.circle_onboarding o
  where o.circle_id = target_circle_id;

  select s.* into settings_row
  from public.circle_guide_settings s
  where s.circle_id = target_circle_id;

  select coalesce(btrim(pr.avatar_url), '') <> ''
  into has_avatar
  from public.profiles pr
  where pr.id = current_user_id;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', p.id,
          'title', p.title,
          'required', p.required,
          'single_select', p.single_select,
          'options', (
            select coalesce(
              jsonb_agg(
                jsonb_build_object(
                  'id', o.id,
                  'label', o.label,
                  'emoji', o.emoji,
                  'selected', exists (
                    select 1
                    from public.circle_member_onboarding_answers a
                    where a.circle_id = p.circle_id
                      and a.user_id = current_user_id
                      and a.option_id = o.id
                  ),
                  'roles', (
                    select coalesce(
                      jsonb_agg(
                        jsonb_build_object(
                          'id', r.id,
                          'name', r.name,
                          'color', r.color
                        )
                        order by r.position desc
                      ),
                      '[]'::jsonb
                    )
                    from public.circle_onboarding_option_roles orl
                    join public.circle_roles r on r.id = orl.role_id
                    where orl.option_id = o.id
                      and public.onboarding_role_problem(p.circle_id, r.id) is null
                  ),
                  'channels', (
                    select coalesce(
                      jsonb_agg(
                        jsonb_build_object('id', cc.id, 'name', cc.name)
                        order by cc.position, cc.name
                      ),
                      '[]'::jsonb
                    )
                    from public.circle_onboarding_option_channels oc
                    join public.circle_channels cc on cc.id = oc.channel_id
                    where oc.option_id = o.id
                      and public.circle_channel_permissions(
                        cc.id,
                        current_user_id
                      ) & 1 <> 0
                  )
                )
                order by o.position, o.created_at
              ),
              '[]'::jsonb
            )
            from public.circle_onboarding_options o
            where o.prompt_id = p.id
          )
        )
        order by p.position, p.created_at
      ),
      '[]'::jsonb
    ),
    count(*)
  into prompts_json, prompt_count
  from public.circle_onboarding_prompts p
  where p.circle_id = target_circle_id
    and exists (
      select 1
      from public.circle_onboarding_options o
      where o.prompt_id = p.id
    );

  -- Tasks pointing at a channel the member cannot see are left out.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', t.id,
        'title', t.title,
        'action', t.action,
        'channel_id', t.channel_id,
        'channel_name', cc.name,
        'done', case t.action
          when 'read_rules' then
            not coalesce(rules_row.enabled, false)
            or member_row.rules_accepted_at is not null
          when 'set_avatar' then coalesce(has_avatar, false)
          when 'visit_channel' then exists (
            select 1
            from public.circle_member_guide_tasks d
            where d.task_id = t.id
              and d.user_id = current_user_id
          )
          else exists (
            select 1
            from public.messages m
            where m.sender_id = current_user_id
              and m.type <> 'system'
              and m.recalled_at is null
              and m.webhook_id is null
              and m.review_state is distinct from 'held'
              and m.review_state is distinct from 'removed'
              and (
                (
                  t.channel_id is not null
                  and (
                    m.conversation_id = cc.conversation_id
                    or m.conversation_id in (
                      select ct.conversation_id
                      from public.conversation_threads ct
                      where ct.parent_conversation_id = cc.conversation_id
                    )
                  )
                )
                or (
                  t.channel_id is null
                  and m.conversation_id in (
                    select ch.conversation_id
                    from public.circle_channels ch
                    where ch.circle_id = t.circle_id
                  )
                )
              )
          )
        end
      )
      order by t.position, t.created_at
    ),
    '[]'::jsonb
  )
  into tasks_json
  from public.circle_guide_tasks t
  left join public.circle_channels cc on cc.id = t.channel_id
  where t.circle_id = target_circle_id
    and (
      t.channel_id is null
      or public.circle_channel_permissions(t.channel_id, current_user_id) & 1 <> 0
    );

  return jsonb_build_object(
    'enabled', prompt_count > 0 or jsonb_array_length(tasks_json) > 0,
    'prompts', prompts_json,
    'tasks', tasks_json,
    'answered', progress.answered_at is not null,
    'dismissed', progress.dismissed_at is not null,
    -- The guide came to the circle after this member did not: it is shown
    -- on its own only to those who joined once it was there.
    'new_member', coalesce(
      settings_row.guide_since is not null
      and member_row.created_at >= settings_row.guide_since,
      false
    ),
    'needs_answers', prompt_count > 0
      and progress.answered_at is null
      and settings_row.guide_since is not null
      and member_row.created_at >= settings_row.guide_since
  );
end;
$$;

create or replace function public.complete_onboarding_prompts(
  target_circle_id uuid,
  option_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  chosen uuid[];
  desired_roles uuid[];
  added jsonb;
  removed jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = target_circle_id
      and cm.user_id = current_user_id
  ) then
    raise exception 'Circle not found or caller is not a member'
      using errcode = '42501';
  end if;

  if public.circle_is_suspended(target_circle_id) then
    raise exception 'This circle is not available' using errcode = '42501';
  end if;

  select coalesce(array_agg(distinct x), '{}'::uuid[])
  into chosen
  from unnest(coalesce(option_ids, '{}'::uuid[])) as picked(x)
  where x is not null;

  if cardinality(chosen) > 60 then
    raise exception 'Too many options' using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(chosen) as picked(x)
    where not exists (
      select 1
      from public.circle_onboarding_options o
      where o.id = picked.x
        and o.circle_id = target_circle_id
    )
  ) then
    raise exception 'Unknown option' using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.circle_onboarding_prompts p
    where p.circle_id = target_circle_id
      and p.single_select
      and (
        select count(*)
        from public.circle_onboarding_options o
        where o.prompt_id = p.id
          and o.id = any(chosen)
      ) > 1
  ) then
    raise exception 'Pick one option for this question'
      using errcode = '22023', detail = 'single_select';
  end if;

  if exists (
    select 1
    from public.circle_onboarding_prompts p
    where p.circle_id = target_circle_id
      and p.required
      and exists (
        select 1 from public.circle_onboarding_options o where o.prompt_id = p.id
      )
      and not exists (
        select 1
        from public.circle_onboarding_options o
        where o.prompt_id = p.id
          and o.id = any(chosen)
      )
  ) then
    raise exception 'Answer the required questions'
      using errcode = '22023', detail = 'required_prompt';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'onboarding:' || target_circle_id::text || ':' || current_user_id::text,
      0
    )
  );

  delete from public.circle_member_onboarding_answers a
  where a.circle_id = target_circle_id
    and a.user_id = current_user_id;

  insert into public.circle_member_onboarding_answers (
    circle_id,
    user_id,
    option_id
  )
  select target_circle_id, current_user_id, picked.x
  from unnest(chosen) as picked(x);

  insert into public.circle_member_onboarding (circle_id, user_id, answered_at)
  values (target_circle_id, current_user_id, now())
  on conflict (circle_id, user_id) do update
  set answered_at = excluded.answered_at;

  -- The roles the picks give, asked again now: a role that gained a
  -- management permission since it was attached is not handed out.
  select coalesce(array_agg(distinct orl.role_id), '{}'::uuid[])
  into desired_roles
  from public.circle_onboarding_option_roles orl
  where orl.option_id = any(chosen)
    and orl.circle_id = target_circle_id
    and public.onboarding_role_problem(target_circle_id, orl.role_id) is null;

  with granted as (
    insert into public.circle_member_roles (
      circle_id,
      user_id,
      role_id,
      via_onboarding
    )
    select target_circle_id, current_user_id, r, true
    from unnest(desired_roles) as wanted(r)
    on conflict (circle_id, user_id, role_id) do nothing
    returning role_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object('id', r.id, 'name', r.name)
      order by r.position desc
    ),
    '[]'::jsonb
  )
  into added
  from granted g
  join public.circle_roles r on r.id = g.role_id;

  with taken as (
    delete from public.circle_member_roles mr
    where mr.circle_id = target_circle_id
      and mr.user_id = current_user_id
      and mr.via_onboarding
      and not (mr.role_id = any(desired_roles))
    returning mr.role_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object('id', r.id, 'name', r.name)
      order by r.position desc
    ),
    '[]'::jsonb
  )
  into removed
  from taken t
  join public.circle_roles r on r.id = t.role_id;

  if added <> '[]'::jsonb or removed <> '[]'::jsonb then
    perform public.write_circle_audit(
      target_circle_id,
      'onboarding_roles',
      'member',
      current_user_id,
      public.circle_member_label(target_circle_id, current_user_id),
      jsonb_build_object(
        'source', 'onboarding',
        'added', added,
        'removed', removed
      )
    );
  end if;

  return jsonb_build_object('added', added, 'removed', removed);
end;
$$;

create or replace function public.complete_guide_task(
  target_circle_id uuid,
  target_task_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  task public.circle_guide_tasks%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = target_circle_id
      and cm.user_id = current_user_id
  ) then
    raise exception 'Circle not found or caller is not a member'
      using errcode = '42501';
  end if;

  if public.circle_is_suspended(target_circle_id) then
    raise exception 'This circle is not available' using errcode = '42501';
  end if;

  select t.* into task
  from public.circle_guide_tasks t
  where t.id = target_task_id
    and t.circle_id = target_circle_id;
  if task.id is null then
    raise exception 'Task not found' using errcode = 'P0002';
  end if;

  -- The other kinds are worked out from the member's own state.
  if task.action <> 'visit_channel' then
    raise exception 'This task completes itself' using errcode = '22023';
  end if;

  if task.channel_id is null
    or public.circle_channel_permissions(task.channel_id, current_user_id) & 1 = 0
  then
    raise exception 'Channel not found' using errcode = '42501';
  end if;

  insert into public.circle_member_guide_tasks (circle_id, user_id, task_id)
  values (target_circle_id, current_user_id, task.id)
  on conflict do nothing;
end;
$$;

create or replace function public.dismiss_circle_guide(
  target_circle_id uuid,
  dismissed boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = target_circle_id
      and cm.user_id = current_user_id
  ) then
    raise exception 'Circle not found or caller is not a member'
      using errcode = '42501';
  end if;

  insert into public.circle_member_onboarding (circle_id, user_id, dismissed_at)
  values (
    target_circle_id,
    current_user_id,
    case when coalesce(dismissed, true) then now() end
  )
  on conflict (circle_id, user_id) do update
  set dismissed_at = excluded.dismissed_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- Managers
-- ---------------------------------------------------------------------------

create or replace function public.get_circle_guide_config(target_circle_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'manage_circle'
  ) then
    raise exception 'Only members who can manage the circle can edit the guide'
      using errcode = '42501';
  end if;

  return jsonb_build_object(
    'prompts', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', p.id,
            'title', p.title,
            'required', p.required,
            'single_select', p.single_select,
            'options', (
              select coalesce(
                jsonb_agg(
                  jsonb_build_object(
                    'id', o.id,
                    'label', o.label,
                    'emoji', o.emoji,
                    'role_ids', (
                      select coalesce(jsonb_agg(orl.role_id), '[]'::jsonb)
                      from public.circle_onboarding_option_roles orl
                      where orl.option_id = o.id
                    ),
                    'channel_ids', (
                      select coalesce(jsonb_agg(oc.channel_id), '[]'::jsonb)
                      from public.circle_onboarding_option_channels oc
                      where oc.option_id = o.id
                    )
                  )
                  order by o.position, o.created_at
                ),
                '[]'::jsonb
              )
              from public.circle_onboarding_options o
              where o.prompt_id = p.id
            )
          )
          order by p.position, p.created_at
        ),
        '[]'::jsonb
      )
      from public.circle_onboarding_prompts p
      where p.circle_id = target_circle_id
    ),
    'tasks', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', t.id,
            'title', t.title,
            'action', t.action,
            'channel_id', t.channel_id
          )
          order by t.position, t.created_at
        ),
        '[]'::jsonb
      )
      from public.circle_guide_tasks t
      where t.circle_id = target_circle_id
    ),
    'greeting_channel_id', (
      select s.greeting_channel_id
      from public.circle_guide_settings s
      where s.circle_id = target_circle_id
    ),
    'greeting_sticker_id', (
      select s.greeting_sticker_id
      from public.circle_guide_settings s
      where s.circle_id = target_circle_id
    ),
    -- Roles an answer can give today, so the editor offers only those.
    'assignable_role_ids', (
      select coalesce(jsonb_agg(r.id order by r.position desc), '[]'::jsonb)
      from public.circle_roles r
      where r.circle_id = target_circle_id
        and public.onboarding_role_problem(target_circle_id, r.id) is null
    )
  );
end;
$$;

create or replace function public.set_circle_guide_prompts(
  target_circle_id uuid,
  prompt_list jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  can_give_roles boolean;
  caller_rank integer;
  prompt_item jsonb;
  option_item jsonb;
  prompt_index integer := 0;
  option_index integer;
  v_prompt_id uuid;
  v_option_id uuid;
  v_title text;
  v_label text;
  v_emoji text;
  kept_prompts uuid[] := '{}';
  kept_options uuid[];
  wanted_roles uuid[];
  wanted_channels uuid[];
  v_role_id uuid;
  v_role_position integer;
  option_total integer := 0;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'manage_circle'
  ) then
    raise exception 'Only members who can manage the circle can edit the guide'
      using errcode = '42501';
  end if;

  if public.circle_is_suspended(target_circle_id) then
    raise exception 'This circle is not available' using errcode = '42501';
  end if;

  if jsonb_typeof(prompt_list) is distinct from 'array' then
    raise exception 'Prompts must be a list' using errcode = '22023';
  end if;
  if jsonb_array_length(prompt_list) > 5 then
    raise exception 'Up to 5 questions' using errcode = '22023';
  end if;

  perform 1 from public.circles where id = target_circle_id for no key update;

  can_give_roles := public.current_user_has_circle_permission(
    target_circle_id,
    'manage_roles'
  );
  caller_rank := public.circle_member_rank(target_circle_id, current_user_id);

  for prompt_item in select value from jsonb_array_elements(prompt_list) loop
    prompt_index := prompt_index + 1;
    v_title := btrim(coalesce(prompt_item ->> 'title', ''));
    if char_length(v_title) not between 1 and 100 then
      raise exception 'A question is 1 to 100 characters' using errcode = '22023';
    end if;
    if jsonb_typeof(prompt_item -> 'options') is distinct from 'array'
      or jsonb_array_length(prompt_item -> 'options') not between 1 and 12
    then
      raise exception 'A question has 1 to 12 options' using errcode = '22023';
    end if;

    if nullif(prompt_item ->> 'id', '') is not null then
      select p.id into v_prompt_id
      from public.circle_onboarding_prompts p
      where p.id = (prompt_item ->> 'id')::uuid
        and p.circle_id = target_circle_id;
      if v_prompt_id is null then
        raise exception 'Question not found' using errcode = '22023';
      end if;
      update public.circle_onboarding_prompts p
      set
        position = prompt_index,
        title = v_title,
        required = coalesce((prompt_item ->> 'required')::boolean, false),
        single_select = coalesce((prompt_item ->> 'single_select')::boolean, false)
      where p.id = v_prompt_id;
    else
      insert into public.circle_onboarding_prompts (
        circle_id,
        position,
        title,
        required,
        single_select
      )
      values (
        target_circle_id,
        prompt_index,
        v_title,
        coalesce((prompt_item ->> 'required')::boolean, false),
        coalesce((prompt_item ->> 'single_select')::boolean, false)
      )
      returning id into v_prompt_id;
    end if;
    kept_prompts := kept_prompts || v_prompt_id;
    kept_options := '{}';
    option_index := 0;

    for option_item in
      select value from jsonb_array_elements(prompt_item -> 'options')
    loop
      option_index := option_index + 1;
      option_total := option_total + 1;
      v_label := btrim(coalesce(option_item ->> 'label', ''));
      v_emoji := nullif(btrim(coalesce(option_item ->> 'emoji', '')), '');
      if char_length(v_label) not between 1 and 60 then
        raise exception 'An option is 1 to 60 characters' using errcode = '22023';
      end if;
      if v_emoji is not null and char_length(v_emoji) > 16 then
        raise exception 'An option emoji is up to 16 characters'
          using errcode = '22023';
      end if;

      if nullif(option_item ->> 'id', '') is not null then
        select o.id into v_option_id
        from public.circle_onboarding_options o
        where o.id = (option_item ->> 'id')::uuid
          and o.prompt_id = v_prompt_id;
        if v_option_id is null then
          raise exception 'Option not found' using errcode = '22023';
        end if;
        update public.circle_onboarding_options o
        set position = option_index, label = v_label, emoji = v_emoji
        where o.id = v_option_id;
      else
        insert into public.circle_onboarding_options (
          prompt_id,
          circle_id,
          position,
          label,
          emoji
        )
        values (v_prompt_id, target_circle_id, option_index, v_label, v_emoji)
        returning id into v_option_id;
      end if;
      kept_options := kept_options || v_option_id;

      -- Roles.
      select coalesce(array_agg(distinct (e)::uuid), '{}'::uuid[])
      into wanted_roles
      from jsonb_array_elements_text(
        coalesce(option_item -> 'role_ids', '[]'::jsonb)
      ) as e;
      if cardinality(wanted_roles) > 5 then
        raise exception 'Up to 5 roles per option' using errcode = '22023';
      end if;

      foreach v_role_id in array wanted_roles loop
        -- A role this option already gives needs no new permission to keep.
        if not exists (
          select 1
          from public.circle_onboarding_option_roles orl
          where orl.option_id = v_option_id
            and orl.role_id = v_role_id
        ) then
          if not can_give_roles then
            raise exception 'Only members who can manage roles can attach a role'
              using errcode = '42501';
          end if;
          select r.position into v_role_position
          from public.circle_roles r
          where r.id = v_role_id
            and r.circle_id = target_circle_id;
          if v_role_position is null then
            raise exception 'This role cannot be given by an onboarding answer'
              using errcode = '22023', detail = 'role_missing',
                hint = v_role_id::text;
          end if;
          if v_role_position >= caller_rank then
            raise exception 'Cannot attach a role at or above your highest role'
              using errcode = '42501';
          end if;
        end if;
      end loop;

      delete from public.circle_onboarding_option_roles orl
      where orl.option_id = v_option_id
        and not (orl.role_id = any(wanted_roles));

      -- The trigger refuses a role that is not plain.
      begin
        insert into public.circle_onboarding_option_roles (
          option_id,
          circle_id,
          role_id
        )
        select v_option_id, target_circle_id, w
        from unnest(wanted_roles) as wanted(w)
        on conflict do nothing;
      exception when sqlstate '22023' then
        raise exception 'This role cannot be given by an onboarding answer'
          using errcode = '22023',
            detail = coalesce(
              (select 'role_' || public.onboarding_role_problem(target_circle_id, w)
               from unnest(wanted_roles) as wanted(w)
               where public.onboarding_role_problem(target_circle_id, w) is not null
               limit 1),
              'role_permissions'
            ),
            hint = (
              select w::text
              from unnest(wanted_roles) as wanted(w)
              where public.onboarding_role_problem(target_circle_id, w) is not null
              limit 1
            );
      end;

      -- Channels.
      select coalesce(array_agg(distinct (e)::uuid), '{}'::uuid[])
      into wanted_channels
      from jsonb_array_elements_text(
        coalesce(option_item -> 'channel_ids', '[]'::jsonb)
      ) as e;
      if cardinality(wanted_channels) > 5 then
        raise exception 'Up to 5 channels per option' using errcode = '22023';
      end if;
      if exists (
        select 1
        from unnest(wanted_channels) as wanted(w)
        where not exists (
          select 1
          from public.circle_channels cc
          where cc.id = wanted.w
            and cc.circle_id = target_circle_id
        )
      ) then
        raise exception 'Channel not found' using errcode = '22023';
      end if;
      delete from public.circle_onboarding_option_channels oc
      where oc.option_id = v_option_id
        and not (oc.channel_id = any(wanted_channels));
      insert into public.circle_onboarding_option_channels (
        option_id,
        circle_id,
        channel_id
      )
      select v_option_id, target_circle_id, w
      from unnest(wanted_channels) as wanted(w)
      on conflict do nothing;
    end loop;

    delete from public.circle_onboarding_options o
    where o.prompt_id = v_prompt_id
      and not (o.id = any(kept_options));
  end loop;

  delete from public.circle_onboarding_prompts p
  where p.circle_id = target_circle_id
    and not (p.id = any(kept_prompts));

  insert into public.circle_guide_settings (
    circle_id,
    guide_since,
    updated_by,
    updated_at
  )
  values (
    target_circle_id,
    case
      when cardinality(kept_prompts) > 0
        or exists (select 1 from public.circle_guide_tasks t where t.circle_id = target_circle_id)
        then clock_timestamp()
    end,
    current_user_id,
    now()
  )
  on conflict (circle_id) do update
  set
    guide_since = case
      when cardinality(kept_prompts) = 0
        and not exists (select 1 from public.circle_guide_tasks t where t.circle_id = target_circle_id)
        then null
      else coalesce(circle_guide_settings.guide_since, clock_timestamp())
    end,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at;

  perform public.write_circle_audit(
    target_circle_id,
    'onboarding_update',
    'circle',
    target_circle_id,
    (select c.name from public.circles c where c.id = target_circle_id),
    jsonb_build_object(
      'prompt_count', cardinality(kept_prompts),
      'option_count', option_total
    )
  );
end;
$$;

create or replace function public.set_circle_guide_tasks(
  target_circle_id uuid,
  task_list jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  task_item jsonb;
  task_index integer := 0;
  v_task_id uuid;
  v_title text;
  v_action text;
  v_channel_id uuid;
  kept_tasks uuid[] := '{}';
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'manage_circle'
  ) then
    raise exception 'Only members who can manage the circle can edit the guide'
      using errcode = '42501';
  end if;

  if public.circle_is_suspended(target_circle_id) then
    raise exception 'This circle is not available' using errcode = '42501';
  end if;

  if jsonb_typeof(task_list) is distinct from 'array' then
    raise exception 'Tasks must be a list' using errcode = '22023';
  end if;
  if jsonb_array_length(task_list) > 10 then
    raise exception 'Up to 10 tasks' using errcode = '22023';
  end if;

  perform 1 from public.circles where id = target_circle_id for no key update;

  for task_item in select value from jsonb_array_elements(task_list) loop
    task_index := task_index + 1;
    v_title := btrim(coalesce(task_item ->> 'title', ''));
    v_action := task_item ->> 'action';
    v_channel_id := nullif(task_item ->> 'channel_id', '')::uuid;
    v_task_id := null;

    if char_length(v_title) not between 1 and 80 then
      raise exception 'A task is 1 to 80 characters' using errcode = '22023';
    end if;
    if v_action is null
      or v_action not in ('read_rules', 'visit_channel', 'send_message', 'set_avatar')
    then
      raise exception 'Unknown task kind' using errcode = '22023';
    end if;
    if v_action in ('read_rules', 'set_avatar') then
      v_channel_id := null;
    end if;
    if v_action = 'visit_channel' and v_channel_id is null then
      raise exception 'Pick a channel to visit' using errcode = '22023';
    end if;
    if v_channel_id is not null and not exists (
      select 1
      from public.circle_channels cc
      where cc.id = v_channel_id
        and cc.circle_id = target_circle_id
    ) then
      raise exception 'Channel not found' using errcode = '22023';
    end if;

    if nullif(task_item ->> 'id', '') is not null then
      select t.id into v_task_id
      from public.circle_guide_tasks t
      where t.id = (task_item ->> 'id')::uuid
        and t.circle_id = target_circle_id;
      if v_task_id is null then
        raise exception 'Task not found' using errcode = '22023';
      end if;
      update public.circle_guide_tasks t
      set position = task_index, title = v_title, action = v_action,
        channel_id = v_channel_id
      where t.id = v_task_id;
    else
      insert into public.circle_guide_tasks (
        circle_id,
        position,
        title,
        action,
        channel_id
      )
      values (target_circle_id, task_index, v_title, v_action, v_channel_id)
      returning id into v_task_id;
    end if;
    kept_tasks := kept_tasks || v_task_id;
  end loop;

  delete from public.circle_guide_tasks t
  where t.circle_id = target_circle_id
    and not (t.id = any(kept_tasks));

  insert into public.circle_guide_settings (
    circle_id,
    guide_since,
    updated_by,
    updated_at
  )
  values (
    target_circle_id,
    case
      when cardinality(kept_tasks) > 0
        or exists (select 1 from public.circle_onboarding_prompts p where p.circle_id = target_circle_id)
        then clock_timestamp()
    end,
    current_user_id,
    now()
  )
  on conflict (circle_id) do update
  set
    guide_since = case
      when cardinality(kept_tasks) = 0
        and not exists (select 1 from public.circle_onboarding_prompts p where p.circle_id = target_circle_id)
        then null
      else coalesce(circle_guide_settings.guide_since, clock_timestamp())
    end,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at;

  perform public.write_circle_audit(
    target_circle_id,
    'onboarding_update',
    'circle',
    target_circle_id,
    (select c.name from public.circles c where c.id = target_circle_id),
    jsonb_build_object('task_count', cardinality(kept_tasks))
  );
end;
$$;

create or replace function public.set_circle_greeting(
  target_circle_id uuid,
  target_channel_id uuid,
  target_sticker_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'manage_circle'
  ) then
    raise exception 'Only members who can manage the circle can edit the guide'
      using errcode = '42501';
  end if;

  if public.circle_is_suspended(target_circle_id) then
    raise exception 'This circle is not available' using errcode = '42501';
  end if;

  if target_channel_id is not null and not exists (
    select 1
    from public.circle_channels cc
    where cc.id = target_channel_id
      and cc.circle_id = target_circle_id
      and cc.kind in ('text', 'announcement')
  ) then
    raise exception 'Pick a text channel of this circle' using errcode = '22023';
  end if;

  if target_sticker_id is not null and not exists (
    select 1
    from public.circle_emojis e
    where e.id = target_sticker_id
      and e.circle_id = target_circle_id
      and e.kind = 'sticker'
  ) then
    raise exception 'Pick a sticker of this circle' using errcode = '22023';
  end if;

  insert into public.circle_guide_settings (
    circle_id,
    greeting_channel_id,
    greeting_sticker_id,
    updated_by,
    updated_at
  )
  values (
    target_circle_id,
    target_channel_id,
    case when target_channel_id is null then null else target_sticker_id end,
    current_user_id,
    now()
  )
  on conflict (circle_id) do update
  set
    greeting_channel_id = excluded.greeting_channel_id,
    greeting_sticker_id = excluded.greeting_sticker_id,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at;

  perform public.write_circle_audit(
    target_circle_id,
    'onboarding_update',
    'circle',
    target_circle_id,
    (select c.name from public.circles c where c.id = target_circle_id),
    jsonb_build_object('greeting_enabled', target_channel_id is not null)
  );
end;
$$;

revoke execute on function public.get_circle_guide(uuid) from public, anon;
revoke execute on function public.complete_onboarding_prompts(uuid, uuid[]) from public, anon;
revoke execute on function public.complete_guide_task(uuid, uuid) from public, anon;
revoke execute on function public.dismiss_circle_guide(uuid, boolean) from public, anon;
revoke execute on function public.get_circle_guide_config(uuid) from public, anon;
revoke execute on function public.set_circle_guide_prompts(uuid, jsonb) from public, anon;
revoke execute on function public.set_circle_guide_tasks(uuid, jsonb) from public, anon;
revoke execute on function public.set_circle_greeting(uuid, uuid, uuid) from public, anon;
grant execute on function public.get_circle_guide(uuid) to authenticated;
grant execute on function public.complete_onboarding_prompts(uuid, uuid[]) to authenticated;
grant execute on function public.complete_guide_task(uuid, uuid) to authenticated;
grant execute on function public.dismiss_circle_guide(uuid, boolean) to authenticated;
grant execute on function public.get_circle_guide_config(uuid) to authenticated;
grant execute on function public.set_circle_guide_prompts(uuid, jsonb) to authenticated;
grant execute on function public.set_circle_guide_tasks(uuid, jsonb) to authenticated;
grant execute on function public.set_circle_greeting(uuid, uuid, uuid) to authenticated;
