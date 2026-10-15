-- AutoMod: per-circle rules that check messages as they are sent in the
-- circle's channels and threads, and act on the ones that break them.
--
-- * A new permission, manage_circle (1 << 20), for circle-wide settings
--   (AutoMod, and member onboarding in 202610160021). Roles that could
--   manage both channels and roles get it, so existing managers keep
--   managing. Members with it (the owner and administrators always) are
--   never checked by AutoMod.
-- * circle_automod_rules holds the rules. Kinds:
--     keyword       keywords and regex patterns. A keyword matches as a
--                   whole word ("cat" matches "cat" but not "category");
--                   *cat matches words ending in it, cat* words starting
--                   with it, *cat* anywhere. Matching ignores case.
--                   Patterns are PostgreSQL regular expressions, checked
--                   when saved, up to 10 of 260 characters each.
--     mention_spam  more than mention_limit unique user and role mentions
--                   in one message.
--     spam          more than message_limit messages from one member in
--                   window_seconds, across the circle.
--   Each rule has actions: block_message (with an optional block_reason
--   shown to the sender), alert_channel_id (a system message with who,
--   where, what and which rule, in that channel) and timeout_seconds
--   (times the member out, like timeout_circle_member). Rules skip their
--   exempt roles and channels (a thread counts as its channel). Up to six
--   keyword rules and one rule of each other kind per circle.
-- * Enforcement: the messages_circle_automod trigger runs after
--   messages_check_channel_send (triggers fire in name order), so only
--   messages that could be sent are checked. When a rule blocks a message,
--   its actions must outlive the refusal, which an exception would roll
--   back. So when the caller can take a quiet refusal (a direct insert
--   through the REST API, or send_text_message), the trigger acts, notes
--   the refusal in circle_automod_notices and drops the row: the insert
--   returns no row (send_text_message returns null), and the client reads
--   the reason with take_automod_notice. Other paths (stickers, polls,
--   forwards, forum posts) get an exception instead (SQLSTATE P0001,
--   detail 'automod_block', hint the custom reason), so the message is
--   still blocked but alerts and timeouts are not kept there. Rules that
--   do not block act and let the message through.
--   Edits are checked too: an edit that a blocking rule matches is
--   refused with the same exception.
-- * Audit: automod_rule_create, automod_rule_update, automod_rule_delete
--   by the editor; automod_block, automod_alert and automod_timeout with
--   the member as actor and target, for actions taken.

-- Same as 202610160004_voice_moderation, plus manage_circle.
create or replace function public.circle_permission_bit(permission_name text)
returns bigint
language plpgsql
immutable
set search_path = public
as $$
begin
  return case permission_name
    when 'view_channel' then 1::bigint
    when 'send_messages' then 2::bigint
    when 'manage_messages' then 4::bigint
    when 'manage_channels' then 8::bigint
    when 'manage_roles' then 16::bigint
    when 'kick_members' then 32::bigint
    when 'create_invites' then 64::bigint
    when 'manage_nicknames' then 128::bigint
    when 'mention_everyone' then 256::bigint
    when 'manage_events' then 512::bigint
    when 'manage_emojis' then 1024::bigint
    when 'manage_webhooks' then 2048::bigint
    when 'view_audit_log' then 4096::bigint
    when 'connect_voice' then 8192::bigint
    when 'administrator' then 16384::bigint
    when 'ban_members' then 32768::bigint
    when 'moderate_members' then 65536::bigint
    when 'mute_members' then 131072::bigint
    when 'deafen_members' then 262144::bigint
    when 'move_members' then 524288::bigint
    when 'manage_circle' then 1048576::bigint
    else null
  end;
end;
$$;

create or replace function public.circle_all_permissions()
returns bigint
language sql
immutable
set search_path = public
as $$
  select 2097151::bigint;
$$;

alter table public.circle_roles
  drop constraint if exists circle_roles_permissions_range;

alter table public.circle_roles
  add constraint circle_roles_permissions_range check (
    permissions >= 0 and permissions <= 2097151
  );

update public.circle_roles
set permissions = permissions | 1048576
where permissions & 8 <> 0
  and permissions & 16 <> 0;

create table if not exists public.circle_automod_rules (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  name text not null,
  kind text not null,
  enabled boolean not null default true,
  keywords text[] not null default '{}',
  regex_patterns text[] not null default '{}',
  mention_limit integer,
  message_limit integer,
  window_seconds integer,
  block_message boolean not null default true,
  block_reason text,
  alert_channel_id uuid,
  timeout_seconds integer,
  exempt_role_ids uuid[] not null default '{}',
  exempt_channel_ids uuid[] not null default '{}',
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint circle_automod_rules_kind_check check (
    kind in ('keyword', 'mention_spam', 'spam')
  ),
  constraint circle_automod_rules_name_length check (
    char_length(btrim(name)) between 1 and 100
  ),
  constraint circle_automod_rules_keywords_count check (
    cardinality(keywords) <= 1000
  ),
  constraint circle_automod_rules_patterns_count check (
    cardinality(regex_patterns) <= 10
  ),
  constraint circle_automod_rules_mention_limit_range check (
    mention_limit is null or mention_limit between 1 and 50
  ),
  constraint circle_automod_rules_message_limit_range check (
    message_limit is null or message_limit between 1 and 50
  ),
  constraint circle_automod_rules_window_range check (
    window_seconds is null or window_seconds between 1 and 300
  ),
  constraint circle_automod_rules_block_reason_length check (
    block_reason is null or char_length(block_reason) between 1 and 150
  ),
  constraint circle_automod_rules_timeout_range check (
    timeout_seconds is null or timeout_seconds between 60 and 2419200
  ),
  constraint circle_automod_rules_exempt_count check (
    cardinality(exempt_role_ids) <= 20 and cardinality(exempt_channel_ids) <= 50
  ),
  constraint circle_automod_rules_alert_channel_fkey
    foreign key (alert_channel_id, circle_id)
    references public.circle_channels(id, circle_id)
    on delete set null (alert_channel_id)
);

create index if not exists circle_automod_rules_circle_idx
  on public.circle_automod_rules (circle_id, created_at);

drop trigger if exists circle_automod_rules_set_updated_at
  on public.circle_automod_rules;
create trigger circle_automod_rules_set_updated_at
  before update on public.circle_automod_rules
  for each row execute function public.set_updated_at();

alter table public.circle_automod_rules enable row level security;

revoke insert, update, delete, truncate on public.circle_automod_rules from anon, authenticated;

drop policy if exists circle_automod_rules_select_manager on public.circle_automod_rules;
create policy circle_automod_rules_select_manager
  on public.circle_automod_rules for select
  to authenticated
  using (public.current_user_has_circle_permission(circle_id, 'manage_circle'));

-- The last message AutoMod quietly refused per member and conversation,
-- for the sender's client to explain (see take_automod_notice).
create table if not exists public.circle_automod_notices (
  user_id uuid not null references public.profiles(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  rule_name text not null,
  reason text,
  created_at timestamptz not null default now(),
  primary key (user_id, conversation_id)
);

alter table public.circle_automod_notices enable row level security;

revoke all on public.circle_automod_notices from anon, authenticated;

-- The spam rule counts a member's recent messages.
create index if not exists messages_sender_created_idx
  on public.messages (sender_id, created_at desc);

-- The regular expression a keyword matches with: whole words unless it
-- starts or ends with *. Null for a keyword with nothing but *.
create or replace function public.circle_automod_keyword_pattern(keyword text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  core text := lower(btrim(coalesce(keyword, '')));
  any_start boolean := false;
  any_end boolean := false;
begin
  if left(core, 1) = '*' then
    any_start := true;
    core := substr(core, 2);
  end if;
  if right(core, 1) = '*' then
    any_end := true;
    core := left(core, -1);
  end if;
  if core = '' then
    return null;
  end if;

  core := regexp_replace(core, '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g');
  return case when any_start then '' else '(^|[^[:alnum:]_])' end
    || core
    || case when any_end then '' else '([^[:alnum:]_]|$)' end;
end;
$$;

-- Whether the message being inserted may be refused quietly (see the
-- header): send_text_message sets wecord.automod_soft, and PostgREST sets
-- request.path for direct inserts into messages.
create or replace function public.circle_automod_soft_block()
returns boolean
language sql
stable
set search_path = public
as $$
  select coalesce(current_setting('wecord.automod_soft', true), '') = 'on'
    or coalesce(current_setting('request.path', true), '') ~ '/messages$';
$$;

-- What AutoMod makes of a message from target_sender_id in
-- target_conversation_id: null when no rule matches, otherwise the circle
-- and channel, whether to block (and the first blocking rule's name and
-- reason) and every matching rule with its actions. The spam rule needs
-- include_rate_rules (not for edits).
create or replace function public.circle_automod_verdict(
  target_conversation_id uuid,
  target_sender_id uuid,
  message_body text,
  message_mentions jsonb,
  include_rate_rules boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
  rule public.circle_automod_rules%rowtype;
  sender_role_ids uuid[];
  body_text text := coalesce(message_body, '');
  matched text;
  mention_count integer;
  recent_count integer;
  triggered jsonb := '[]'::jsonb;
  blocked boolean := false;
  blocking_rule_name text;
  blocking_reason text;
begin
  select cc.*
  into channel
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(target_conversation_id);

  if channel.id is null
    or target_sender_id is null
    or not exists (
      select 1
      from public.circle_automod_rules r
      where r.circle_id = channel.circle_id
        and r.enabled
    )
    or not exists (
      select 1
      from public.circle_members cm
      where cm.circle_id = channel.circle_id
        and cm.user_id = target_sender_id
    )
    -- The owner, administrators and circle managers are exempt.
    or public.circle_member_has_permission(
      channel.circle_id,
      target_sender_id,
      'manage_circle'
    )
  then
    return null;
  end if;

  select coalesce(array_agg(r.id), '{}')
  into sender_role_ids
  from public.circle_roles r
  where r.circle_id = channel.circle_id
    and (
      r.is_default
      or exists (
        select 1
        from public.circle_member_roles mr
        where mr.circle_id = channel.circle_id
          and mr.user_id = target_sender_id
          and mr.role_id = r.id
      )
    );

  for rule in
    select r.*
    from public.circle_automod_rules r
    where r.circle_id = channel.circle_id
      and r.enabled
    order by r.created_at, r.id
  loop
    continue when channel.id = any(rule.exempt_channel_ids);
    continue when rule.exempt_role_ids && sender_role_ids;

    matched := null;
    if rule.kind = 'keyword' and body_text <> '' then
      select k
      into matched
      from unnest(rule.keywords) k
      where body_text ~* public.circle_automod_keyword_pattern(k)
      limit 1;

      if matched is null then
        select p
        into matched
        from unnest(rule.regex_patterns) p
        where body_text ~* p
        limit 1;
      end if;
    elsif rule.kind = 'mention_spam' then
      select count(distinct
        case
          when m->>'kind' = 'role' then 'role:' || (m->>'role_id')
          else 'user:' || (m->>'user_id')
        end
      )
      into mention_count
      from jsonb_array_elements(
        case
          when jsonb_typeof(message_mentions) = 'array' then message_mentions
          else '[]'::jsonb
        end
      ) m
      where coalesce(nullif(m->>'kind', ''), 'user') in ('user', 'role')
        and coalesce(m->>'role_id', m->>'user_id') is not null;

      if mention_count > rule.mention_limit then
        matched := format('%s mentions', mention_count);
      end if;
    elsif rule.kind = 'spam' and include_rate_rules then
      -- One count per member and circle at a time, so quick sends cannot
      -- all slip under the limit.
      perform pg_advisory_xact_lock(
        hashtextextended(
          'automod:' || channel.circle_id::text || ':' || target_sender_id::text,
          0
        )
      );

      select count(*)
      into recent_count
      from public.messages m
      where m.sender_id = target_sender_id
        and m.created_at > now() - make_interval(secs => rule.window_seconds)
        and m.type <> 'system'
        and m.webhook_name is null
        and (
          m.conversation_id in (
            select cc.conversation_id
            from public.circle_channels cc
            where cc.circle_id = channel.circle_id
          )
          or m.conversation_id in (
            select ct.conversation_id
            from public.conversation_threads ct
            join public.circle_channels cc
              on cc.conversation_id = ct.parent_conversation_id
            where cc.circle_id = channel.circle_id
          )
        );

      if recent_count >= rule.message_limit then
        matched := format(
          '%s messages in %s seconds',
          recent_count + 1,
          rule.window_seconds
        );
      end if;
    end if;

    if matched is not null then
      triggered := triggered || jsonb_build_array(jsonb_build_object(
        'rule_id', rule.id,
        'rule_name', rule.name,
        'kind', rule.kind,
        'matched', matched,
        'block', rule.block_message,
        'alert_channel_id', rule.alert_channel_id,
        'timeout_seconds', rule.timeout_seconds
      ));
      if rule.block_message and not blocked then
        blocked := true;
        blocking_rule_name := rule.name;
        blocking_reason := rule.block_reason;
      end if;
    end if;
  end loop;

  if jsonb_array_length(triggered) = 0 then
    return null;
  end if;

  return jsonb_build_object(
    'circle_id', channel.circle_id,
    'channel_id', channel.id,
    'channel_name', channel.name,
    'block', blocked,
    'rule_name', blocking_rule_name,
    'reason', blocking_reason,
    'rules', triggered
  );
end;
$$;

-- Carries out a verdict's actions for a message from target_sender_id:
-- alerts, the longest timeout, audit entries, and the sender's notice
-- when the message is blocked.
create or replace function public.circle_automod_act(
  verdict jsonb,
  target_sender_id uuid,
  target_conversation_id uuid,
  message_body text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  verdict_circle_id uuid := (verdict->>'circle_id')::uuid;
  blocked boolean := coalesce((verdict->>'block')::boolean, false);
  item jsonb;
  sender_label text;
  content text := left(coalesce(message_body, ''), 300);
  alert_channel public.circle_channels%rowtype;
  longest_timeout integer := 0;
  timeout_rule_name text;
  ends_at timestamptz;
begin
  sender_label := coalesce(
    public.circle_member_label(verdict_circle_id, target_sender_id),
    'Someone'
  );

  for item in select value from jsonb_array_elements(verdict->'rules')
  loop
    if (item->>'alert_channel_id') is not null then
      select cc.*
      into alert_channel
      from public.circle_channels cc
      where cc.id = (item->>'alert_channel_id')::uuid
        and cc.circle_id = verdict_circle_id
        and cc.kind <> 'forum';

      if alert_channel.id is not null then
        insert into public.messages (
          conversation_id,
          sender_id,
          type,
          body,
          attachment
        )
        values (
          alert_channel.conversation_id,
          target_sender_id,
          'system',
          format(
            'AutoMod %s a message from %s in #%s (rule: %s).',
            case when blocked then 'blocked' else 'flagged' end,
            sender_label,
            verdict->>'channel_name',
            item->>'rule_name'
          ),
          jsonb_build_object(
            'kind', 'automod_alert',
            'rule_name', item->>'rule_name',
            'rule_kind', item->>'kind',
            'matched', item->>'matched',
            'user_id', target_sender_id,
            'user_label', sender_label,
            'channel_id', verdict->>'channel_id',
            'channel_name', verdict->>'channel_name',
            'content', content,
            'blocked', blocked,
            'timeout_seconds', item->'timeout_seconds'
          )
        );

        perform public.write_circle_audit(
          verdict_circle_id,
          'automod_alert',
          'member',
          target_sender_id,
          sender_label,
          jsonb_build_object(
            'rule_name', item->>'rule_name',
            'channel_name', verdict->>'channel_name',
            'alert_channel_name', alert_channel.name
          )
        );
      end if;
    end if;

    if coalesce((item->>'timeout_seconds')::integer, 0) > longest_timeout then
      longest_timeout := (item->>'timeout_seconds')::integer;
      timeout_rule_name := item->>'rule_name';
    end if;
  end loop;

  if blocked then
    perform public.write_circle_audit(
      verdict_circle_id,
      'automod_block',
      'member',
      target_sender_id,
      sender_label,
      jsonb_strip_nulls(jsonb_build_object(
        'rule_name', verdict->>'rule_name',
        'channel_name', verdict->>'channel_name',
        'content', nullif(content, '')
      ))
    );

    insert into public.circle_automod_notices (
      user_id,
      conversation_id,
      rule_name,
      reason
    )
    values (
      target_sender_id,
      target_conversation_id,
      verdict->>'rule_name',
      verdict->>'reason'
    )
    on conflict (user_id, conversation_id) do update
    set
      rule_name = excluded.rule_name,
      reason = excluded.reason,
      created_at = now();

    delete from public.circle_automod_notices n
    where n.user_id = target_sender_id
      and n.created_at < now() - interval '1 hour';
  end if;

  -- Like timeout_circle_member (202610140004_bans_and_timeouts), without
  -- its caller checks: AutoMod never checks the owner or administrators.
  if longest_timeout > 0 then
    ends_at := now() + make_interval(secs => longest_timeout);

    update public.circle_members cm
    set timed_out_until = greatest(coalesce(cm.timed_out_until, ends_at), ends_at)
    where cm.circle_id = verdict_circle_id
      and cm.user_id = target_sender_id
      and not exists (
        select 1
        from public.circles c
        where c.id = cm.circle_id
          and c.owner_id = cm.user_id
      );

    if found then
      delete from public.voice_states vs
      where vs.circle_id = verdict_circle_id
        and vs.user_id = target_sender_id;

      perform public.write_circle_audit(
        verdict_circle_id,
        'automod_timeout',
        'member',
        target_sender_id,
        sender_label,
        jsonb_build_object(
          'rule_name', timeout_rule_name,
          'until', ends_at,
          'seconds', longest_timeout
        )
      );
    end if;
  end if;
end;
$$;

-- BEFORE INSERT on messages, after messages_check_channel_send.
create or replace function public.enforce_circle_automod()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  verdict jsonb;
begin
  if new.type = 'system'
    or new.webhook_id is not null
    or new.webhook_name is not null
  then
    return new;
  end if;

  -- Someone posing as another sender is refused by the insert policy,
  -- which runs after the triggers; don't act on their behalf.
  if auth.uid() is not null and new.sender_id is distinct from auth.uid() then
    return new;
  end if;

  verdict := public.circle_automod_verdict(
    new.conversation_id,
    new.sender_id,
    new.body,
    new.mentions,
    true
  );

  if verdict is null then
    return new;
  end if;

  if not (verdict->>'block')::boolean then
    perform public.circle_automod_act(
      verdict,
      new.sender_id,
      new.conversation_id,
      new.body
    );
    return new;
  end if;

  if public.circle_automod_soft_block() then
    perform public.circle_automod_act(
      verdict,
      new.sender_id,
      new.conversation_id,
      new.body
    );
    return null;
  end if;

  raise exception 'AutoMod blocked this message'
    using errcode = 'P0001',
      detail = 'automod_block',
      hint = coalesce(verdict->>'reason', '');
end;
$$;

-- BEFORE UPDATE OF body on messages: a blocking rule refuses an edit too.
create or replace function public.enforce_circle_automod_on_edit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  verdict jsonb;
begin
  if new.body is not distinct from old.body
    or new.recalled_at is not null
    or new.type = 'system'
    or new.webhook_id is not null
    or new.webhook_name is not null
    or (auth.uid() is not null and new.sender_id is distinct from auth.uid())
  then
    return new;
  end if;

  verdict := public.circle_automod_verdict(
    new.conversation_id,
    new.sender_id,
    new.body,
    new.mentions,
    false
  );

  if verdict is not null and (verdict->>'block')::boolean then
    raise exception 'AutoMod blocked this message'
      using errcode = 'P0001',
        detail = 'automod_block',
        hint = coalesce(verdict->>'reason', '');
  end if;

  return new;
end;
$$;

revoke execute on function public.circle_automod_keyword_pattern(text) from public, anon, authenticated;
revoke execute on function public.circle_automod_soft_block() from public, anon, authenticated;
revoke execute on function public.circle_automod_verdict(uuid, uuid, text, jsonb, boolean) from public, anon, authenticated;
revoke execute on function public.circle_automod_act(jsonb, uuid, uuid, text) from public, anon, authenticated;
revoke execute on function public.enforce_circle_automod() from public, anon, authenticated;
revoke execute on function public.enforce_circle_automod_on_edit() from public, anon, authenticated;

drop trigger if exists messages_circle_automod on public.messages;
create trigger messages_circle_automod
  before insert on public.messages
  for each row execute function public.enforce_circle_automod();

drop trigger if exists messages_circle_automod_edit on public.messages;
create trigger messages_circle_automod_edit
  before update of body on public.messages
  for each row execute function public.enforce_circle_automod_on_edit();

-- A rule as the settings screen reads it.
create or replace function public.circle_automod_rule_json(
  rule public.circle_automod_rules
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', rule.id,
    'circle_id', rule.circle_id,
    'name', rule.name,
    'kind', rule.kind,
    'enabled', rule.enabled,
    'keywords', to_jsonb(rule.keywords),
    'regex_patterns', to_jsonb(rule.regex_patterns),
    'mention_limit', rule.mention_limit,
    'message_limit', rule.message_limit,
    'window_seconds', rule.window_seconds,
    'block_message', rule.block_message,
    'block_reason', rule.block_reason,
    'alert_channel_id', rule.alert_channel_id,
    'timeout_seconds', rule.timeout_seconds,
    'exempt_role_ids', to_jsonb(rule.exempt_role_ids),
    'exempt_channel_ids', to_jsonb(rule.exempt_channel_ids),
    'created_at', rule.created_at,
    'updated_at', rule.updated_at
  );
$$;

-- What the audit log shows of a rule (lists as counts).
create or replace function public.circle_automod_rule_audit_summary(
  rule public.circle_automod_rules
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'kind', rule.kind,
    'enabled', rule.enabled,
    'keyword_count', case
      when rule.kind = 'keyword' then cardinality(rule.keywords)
    end,
    'pattern_count', case
      when rule.kind = 'keyword' then cardinality(rule.regex_patterns)
    end,
    'mention_limit', rule.mention_limit,
    'message_limit', rule.message_limit,
    'window_seconds', rule.window_seconds,
    'block_message', rule.block_message,
    'block_reason', rule.block_reason,
    'alert_channel_name', (
      select cc.name
      from public.circle_channels cc
      where cc.id = rule.alert_channel_id
    ),
    'timeout_seconds', rule.timeout_seconds,
    'exempt_role_count', cardinality(rule.exempt_role_ids),
    'exempt_channel_count', cardinality(rule.exempt_channel_ids)
  );
$$;

revoke execute on function public.circle_automod_rule_json(public.circle_automod_rules) from public, anon, authenticated;
revoke execute on function public.circle_automod_rule_audit_summary(public.circle_automod_rules) from public, anon, authenticated;

create or replace function public.list_circle_automod_rules(target_circle_id uuid)
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
    raise exception 'Only members who can manage the circle can see AutoMod rules'
      using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(
      public.circle_automod_rule_json(r)
      order by r.created_at, r.id
    )
    from public.circle_automod_rules r
    where r.circle_id = target_circle_id
  ), '[]'::jsonb);
end;
$$;

-- Creates (no "id") or updates a rule from a JSON object with the fields
-- circle_automod_rule_json returns. Returns the rule's id.
create or replace function public.save_circle_automod_rule(
  target_circle_id uuid,
  rule jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  existing public.circle_automod_rules%rowtype;
  saved public.circle_automod_rules%rowtype;
  rule_id uuid := nullif(rule->>'id', '')::uuid;
  rule_name text := btrim(coalesce(rule->>'name', ''));
  rule_kind text := coalesce(rule->>'kind', '');
  rule_enabled boolean := coalesce((rule->>'enabled')::boolean, true);
  rule_keywords text[];
  rule_patterns text[];
  rule_mention_limit integer;
  rule_message_limit integer;
  rule_window_seconds integer;
  rule_block boolean := coalesce((rule->>'block_message')::boolean, false);
  rule_reason text := nullif(btrim(coalesce(rule->>'block_reason', '')), '');
  rule_alert_channel_id uuid := nullif(rule->>'alert_channel_id', '')::uuid;
  rule_timeout integer := nullif(rule->>'timeout_seconds', '')::integer;
  rule_exempt_roles uuid[];
  rule_exempt_channels uuid[];
  pattern text;
  old_summary jsonb;
  new_summary jsonb;
  changes jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'manage_circle'
  ) then
    raise exception 'Only members who can manage the circle can change AutoMod'
      using errcode = '42501';
  end if;

  if jsonb_typeof(rule) is distinct from 'object' then
    raise exception 'rule must be an object' using errcode = '22023';
  end if;

  -- Serialises rule changes per circle, so the limits below hold.
  perform 1 from public.circles where id = target_circle_id for no key update;

  if rule_id is not null then
    select r.*
    into existing
    from public.circle_automod_rules r
    where r.id = rule_id
      and r.circle_id = target_circle_id
    for update;

    if existing.id is null then
      raise exception 'AutoMod rule not found' using errcode = 'P0002';
    end if;

    if rule_kind <> '' and rule_kind <> existing.kind then
      raise exception 'A rule keeps its kind' using errcode = '22023';
    end if;
    rule_kind := existing.kind;
  end if;

  if rule_kind not in ('keyword', 'mention_spam', 'spam') then
    raise exception 'Unknown AutoMod rule kind' using errcode = '22023';
  end if;

  if char_length(rule_name) not between 1 and 100 then
    raise exception 'Rule names are 1 to 100 characters' using errcode = '22023';
  end if;

  if rule_id is null and (
    select count(*)
    from public.circle_automod_rules r
    where r.circle_id = target_circle_id
      and r.kind = rule_kind
  ) >= (case when rule_kind = 'keyword' then 6 else 1 end) then
    raise exception 'This circle has as many rules of this kind as it can'
      using errcode = '54000';
  end if;

  -- Keywords: trimmed, lower case, without duplicates.
  if rule_kind = 'keyword' then
    if jsonb_typeof(coalesce(rule->'keywords', '[]'::jsonb)) <> 'array'
      or jsonb_typeof(coalesce(rule->'regex_patterns', '[]'::jsonb)) <> 'array'
    then
      raise exception 'keywords and regex_patterns must be arrays'
        using errcode = '22023';
    end if;

    select coalesce(array_agg(k order by first_seen), '{}')
    into rule_keywords
    from (
      select lower(btrim(value)) as k, min(ordinality) as first_seen
      from jsonb_array_elements_text(coalesce(rule->'keywords', '[]'::jsonb))
        with ordinality
      where btrim(value) <> ''
      group by lower(btrim(value))
    ) keywords;

    select coalesce(array_agg(p order by first_seen), '{}')
    into rule_patterns
    from (
      select value as p, min(ordinality) as first_seen
      from jsonb_array_elements_text(coalesce(rule->'regex_patterns', '[]'::jsonb))
        with ordinality
      where btrim(value) <> ''
      group by value
    ) patterns;

    if cardinality(rule_keywords) > 1000 then
      raise exception 'A rule holds up to 1000 keywords' using errcode = '22023';
    end if;

    if exists (
      select 1
      from unnest(rule_keywords) k
      where char_length(k) > 60
        or public.circle_automod_keyword_pattern(k) is null
    ) then
      raise exception 'Keywords are 1 to 60 characters besides *'
        using errcode = '22023';
    end if;

    if cardinality(rule_patterns) > 10 then
      raise exception 'A rule holds up to 10 patterns' using errcode = '22023';
    end if;

    foreach pattern in array rule_patterns loop
      if char_length(pattern) > 260 then
        raise exception 'Patterns are up to 260 characters' using errcode = '22023';
      end if;
      begin
        perform '' ~ pattern;
      exception when invalid_regular_expression then
        raise exception 'Invalid pattern: %', pattern using errcode = '22023';
      end;
    end loop;

    if cardinality(rule_keywords) + cardinality(rule_patterns) = 0 then
      raise exception 'Add a keyword or a pattern' using errcode = '22023';
    end if;
  else
    rule_keywords := '{}';
    rule_patterns := '{}';
  end if;

  if rule_kind = 'mention_spam' then
    rule_mention_limit := nullif(rule->>'mention_limit', '')::integer;
    if rule_mention_limit is null or rule_mention_limit not between 1 and 50 then
      raise exception 'The mention limit is 1 to 50' using errcode = '22023';
    end if;
  end if;

  if rule_kind = 'spam' then
    rule_message_limit := nullif(rule->>'message_limit', '')::integer;
    rule_window_seconds := nullif(rule->>'window_seconds', '')::integer;
    if rule_message_limit is null or rule_message_limit not between 1 and 50 then
      raise exception 'The message limit is 1 to 50' using errcode = '22023';
    end if;
    if rule_window_seconds is null or rule_window_seconds not between 1 and 300 then
      raise exception 'The window is 1 to 300 seconds' using errcode = '22023';
    end if;
  end if;

  if rule_reason is not null and char_length(rule_reason) > 150 then
    raise exception 'Block reasons are up to 150 characters' using errcode = '22023';
  end if;
  if not rule_block then
    rule_reason := null;
  end if;

  if rule_alert_channel_id is not null and not exists (
    select 1
    from public.circle_channels cc
    where cc.id = rule_alert_channel_id
      and cc.circle_id = target_circle_id
      and cc.kind <> 'forum'
  ) then
    raise exception 'Alerts go to a text or voice channel of this circle'
      using errcode = '22023';
  end if;

  if rule_timeout is not null and rule_timeout not between 60 and 2419200 then
    raise exception 'Timeouts last 60 seconds to 28 days' using errcode = '22023';
  end if;

  if not rule_block and rule_alert_channel_id is null and rule_timeout is null then
    raise exception 'Choose at least one action' using errcode = '22023';
  end if;

  if jsonb_typeof(coalesce(rule->'exempt_role_ids', '[]'::jsonb)) <> 'array'
    or jsonb_typeof(coalesce(rule->'exempt_channel_ids', '[]'::jsonb)) <> 'array'
  then
    raise exception 'exempt_role_ids and exempt_channel_ids must be arrays'
      using errcode = '22023';
  end if;

  -- Only this circle's roles and channels; others are dropped.
  select coalesce(array_agg(r.id order by r.position desc), '{}')
  into rule_exempt_roles
  from public.circle_roles r
  where r.circle_id = target_circle_id
    and r.id::text in (
      select jsonb_array_elements_text(coalesce(rule->'exempt_role_ids', '[]'::jsonb))
    );

  select coalesce(array_agg(cc.id order by cc.position, cc.created_at), '{}')
  into rule_exempt_channels
  from public.circle_channels cc
  where cc.circle_id = target_circle_id
    and cc.id::text in (
      select jsonb_array_elements_text(coalesce(rule->'exempt_channel_ids', '[]'::jsonb))
    );

  if cardinality(rule_exempt_roles) > 20 or cardinality(rule_exempt_channels) > 50 then
    raise exception 'A rule exempts up to 20 roles and 50 channels'
      using errcode = '22023';
  end if;

  if existing.id is null then
    insert into public.circle_automod_rules (
      circle_id,
      name,
      kind,
      enabled,
      keywords,
      regex_patterns,
      mention_limit,
      message_limit,
      window_seconds,
      block_message,
      block_reason,
      alert_channel_id,
      timeout_seconds,
      exempt_role_ids,
      exempt_channel_ids,
      created_by
    )
    values (
      target_circle_id,
      rule_name,
      rule_kind,
      rule_enabled,
      rule_keywords,
      rule_patterns,
      rule_mention_limit,
      rule_message_limit,
      rule_window_seconds,
      rule_block,
      rule_reason,
      rule_alert_channel_id,
      rule_timeout,
      rule_exempt_roles,
      rule_exempt_channels,
      current_user_id
    )
    returning * into saved;

    perform public.write_circle_audit(
      target_circle_id,
      'automod_rule_create',
      'rule',
      saved.id,
      saved.name,
      jsonb_strip_nulls(public.circle_automod_rule_audit_summary(saved))
    );
  else
    old_summary := public.circle_automod_rule_audit_summary(existing)
      || jsonb_build_object('name', existing.name);

    update public.circle_automod_rules r
    set
      name = rule_name,
      enabled = rule_enabled,
      keywords = rule_keywords,
      regex_patterns = rule_patterns,
      mention_limit = rule_mention_limit,
      message_limit = rule_message_limit,
      window_seconds = rule_window_seconds,
      block_message = rule_block,
      block_reason = rule_reason,
      alert_channel_id = rule_alert_channel_id,
      timeout_seconds = rule_timeout,
      exempt_role_ids = rule_exempt_roles,
      exempt_channel_ids = rule_exempt_channels
    where r.id = existing.id
    returning * into saved;

    new_summary := public.circle_automod_rule_audit_summary(saved)
      || jsonb_build_object('name', saved.name);

    select coalesce(
      jsonb_object_agg(
        key,
        jsonb_build_object('old', old_summary->key, 'new', value)
      ),
      '{}'::jsonb
    )
    into changes
    from jsonb_each(new_summary)
    where old_summary->key is distinct from value;

    -- Lists that changed but kept their size still count as changes.
    if existing.keywords is distinct from saved.keywords
      and not changes ? 'keyword_count'
    then
      changes := changes || jsonb_build_object('keywords_changed', true);
    end if;
    if existing.regex_patterns is distinct from saved.regex_patterns
      and not changes ? 'pattern_count'
    then
      changes := changes || jsonb_build_object('patterns_changed', true);
    end if;
    if (
      existing.exempt_role_ids is distinct from saved.exempt_role_ids
      and not changes ? 'exempt_role_count'
    ) or (
      existing.exempt_channel_ids is distinct from saved.exempt_channel_ids
      and not changes ? 'exempt_channel_count'
    ) then
      changes := changes || jsonb_build_object('exemptions_changed', true);
    end if;

    if changes <> '{}'::jsonb then
      perform public.write_circle_audit(
        target_circle_id,
        'automod_rule_update',
        'rule',
        saved.id,
        saved.name,
        changes
      );
    end if;
  end if;

  return saved.id;
end;
$$;

create or replace function public.delete_circle_automod_rule(target_rule_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted public.circle_automod_rules%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select r.*
  into deleted
  from public.circle_automod_rules r
  where r.id = target_rule_id;

  if deleted.id is null
    or not public.current_user_has_circle_permission(
      deleted.circle_id,
      'manage_circle'
    )
  then
    raise exception 'AutoMod rule not found' using errcode = 'P0002';
  end if;

  delete from public.circle_automod_rules r where r.id = deleted.id;

  perform public.write_circle_audit(
    deleted.circle_id,
    'automod_rule_delete',
    'rule',
    deleted.id,
    deleted.name,
    jsonb_build_object('kind', deleted.kind)
  );
end;
$$;

-- Why AutoMod just refused the caller's message in a conversation:
-- {rule_name, reason}, or null. Each notice is read once.
create or replace function public.take_automod_notice(target_conversation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  notice public.circle_automod_notices%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  delete from public.circle_automod_notices n
  where n.user_id = auth.uid()
    and n.conversation_id = target_conversation_id
  returning n.* into notice;

  if notice.user_id is null or notice.created_at < now() - interval '5 minutes' then
    return null;
  end if;

  return jsonb_build_object(
    'rule_name', notice.rule_name,
    'reason', notice.reason
  );
end;
$$;

revoke execute on function public.list_circle_automod_rules(uuid) from public, anon;
revoke execute on function public.save_circle_automod_rule(uuid, jsonb) from public, anon;
revoke execute on function public.delete_circle_automod_rule(uuid) from public, anon;
revoke execute on function public.take_automod_notice(uuid) from public, anon;
grant execute on function public.list_circle_automod_rules(uuid) to authenticated;
grant execute on function public.save_circle_automod_rule(uuid, jsonb) to authenticated;
grant execute on function public.delete_circle_automod_rule(uuid) to authenticated;
grant execute on function public.take_automod_notice(uuid) to authenticated;

-- Same as 202610160003_role_and_here_mentions, but AutoMod may refuse
-- the message quietly (see the header): then nothing is inserted and this
-- returns null.
create or replace function public.send_text_message(
  target_conversation_id uuid,
  body text,
  reply_to_message_id uuid default null,
  reply_preview jsonb default null,
  mentions jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_body text := trim(coalesce(body, ''));
  visible_mentions jsonb;
  created_message_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_body) = 0 then
    raise exception 'Message body is required' using errcode = '22023';
  end if;

  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Cannot send messages in this conversation'
      using errcode = '42501';
  end if;

  if send_text_message.reply_to_message_id is not null and not exists (
    select 1
    from public.messages m
    where m.id = send_text_message.reply_to_message_id
      and m.conversation_id = target_conversation_id
  ) then
    raise exception 'Reply message does not belong to conversation'
      using errcode = '22023';
  end if;

  if jsonb_typeof(coalesce(mentions, '[]'::jsonb)) <> 'array' then
    raise exception 'mentions must be an array' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(mentions, '[]'::jsonb)) mention
    where coalesce(nullif(mention->>'kind', ''), 'user') in ('user', 'all')
      and (mention->>'user_id') is not null
      and not exists (
        select 1
        from public.conversation_members cm
        where cm.conversation_id = target_conversation_id
          and cm.user_id = (mention->>'user_id')::uuid
      )
  ) then
    raise exception 'mentioned users must be conversation members'
      using errcode = '42501';
  end if;

  visible_mentions := public.resolve_message_mentions(
    target_conversation_id,
    current_user_id,
    mentions
  );

  -- AutoMod (202610160020): a blocked message is dropped, not raised.
  perform set_config('wecord.automod_soft', 'on', true);

  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    reply_to_message_id,
    reply_preview,
    mentions
  )
  values (
    target_conversation_id,
    current_user_id,
    'text',
    trimmed_body,
    send_text_message.reply_to_message_id,
    send_text_message.reply_preview,
    visible_mentions
  )
  returning id into created_message_id;

  perform set_config('wecord.automod_soft', 'off', true);

  if created_message_id is null then
    return null;
  end if;

  perform public.record_message_mentions(
    created_message_id,
    target_conversation_id,
    current_user_id,
    mentions,
    visible_mentions
  );

  return created_message_id;
end;
$$;
