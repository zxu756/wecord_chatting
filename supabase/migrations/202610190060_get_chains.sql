-- Performance: read several chains in one request.
--
-- A chat with chain cards asked get_chain once per card on screen (about 40
-- requests after scrolling a thousand messages). get_chains answers for a
-- list of chains in one call: the same objects get_chain returns (in no
-- particular order; each carries its id), and nothing for a chain the caller
-- cannot see (it does not exist, is not in one of the caller's conversations,
-- or its card is deleted, expired or held for review): the app shows those as
-- "not available" exactly as it does for the P0002 of get_chain.
--
-- It calls get_chain for each id, so it is always the same answer as the
-- single read, whatever get_chain becomes (the latest definition is in
-- 202610190012_security_chains.sql), and every rule of who may read a chain
-- stays in that one place.

create or replace function public.get_chains(target_chain_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  chain_id uuid;
  one jsonb;
  result jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if coalesce(cardinality(target_chain_ids), 0) > 50 then
    raise exception 'Too many chains' using errcode = '22023';
  end if;

  for chain_id in
    select distinct ids.id
    from unnest(target_chain_ids) as ids(id)
    where ids.id is not null
  loop
    begin
      one := public.get_chain(chain_id);
      if one is not null then
        result := result || jsonb_build_array(one);
      end if;
    exception when sqlstate 'P0002' then
      -- Not there for this person.
      null;
    end;
  end loop;

  return result;
end;
$$;

revoke execute on function public.get_chains(uuid[]) from public, anon;
grant execute on function public.get_chains(uuid[]) to authenticated;
