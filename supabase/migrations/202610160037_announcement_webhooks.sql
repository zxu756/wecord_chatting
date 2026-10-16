-- Webhooks can post into announcement channels too.
--
-- create_channel_webhook accepted only plain text channels; an
-- announcement channel (202610160027) is a text channel whose messages can
-- be published, so it takes webhooks as well. post_webhook_message never
-- checked the kind. Publishing stays manual: a webhook's message is
-- published like any other, by someone with manage_messages
-- (publish_message), never automatically.

-- Same as 202610130024_channel_webhooks, but announcement channels are
-- allowed.
create or replace function public.create_channel_webhook(
  target_channel_id uuid,
  webhook_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
  trimmed_name text := btrim(coalesce(webhook_name, ''));
  token text := public.new_webhook_token();
  created public.circle_webhooks%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cc.*
  into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel.id is null
    or not public.current_user_has_channel_permission(
      channel.id,
      'manage_webhooks'
    )
  then
    raise exception 'Channel not found or caller cannot manage its webhooks'
      using errcode = '42501';
  end if;

  if channel.kind not in ('text', 'announcement') then
    raise exception 'Webhooks post only into text and announcement channels'
      using errcode = '22023';
  end if;

  if char_length(trimmed_name) not between 1 and 80 then
    raise exception 'Webhook name must be 1 to 80 characters'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('webhooks:' || channel.id::text, 0));

  if (
    select count(*)
    from public.circle_webhooks w
    where w.channel_id = channel.id
  ) >= 10 then
    raise exception 'A channel can have at most 10 webhooks'
      using errcode = '54000';
  end if;

  insert into public.circle_webhooks (
    circle_id,
    channel_id,
    name,
    token_hash,
    created_by
  )
  values (
    channel.circle_id,
    channel.id,
    trimmed_name,
    public.webhook_token_hash(token),
    auth.uid()
  )
  returning * into created;

  perform public.write_circle_audit(
    channel.circle_id,
    'webhook_create',
    'webhook',
    created.id,
    created.name,
    jsonb_build_object('channel_name', channel.name)
  );

  return public.channel_webhook_payload(created)
    || jsonb_build_object('token', token);
end;
$$;

grant execute on function public.create_channel_webhook(uuid, text) to authenticated;
