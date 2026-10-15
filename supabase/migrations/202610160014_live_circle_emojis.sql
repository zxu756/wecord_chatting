-- Custom emoji and stickers refresh live.
--
-- circle_emojis joins the realtime publication, so open clients reload a
-- circle's emoji page and their emoji pickers when someone in one of
-- their circles adds, renames or deletes an emoji or sticker. The select
-- policy (members of the circle) decides who hears about inserts and
-- updates. Realtime cannot check policies for deletes, so those reach
-- every subscriber with only the row's id, which clients take as a hint
-- to reload; replica identity full keeps circle_id in the old row where
-- realtime can use it.

alter table public.circle_emojis replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'circle_emojis'
  ) then
    alter publication supabase_realtime add table public.circle_emojis;
  end if;
end $$;
