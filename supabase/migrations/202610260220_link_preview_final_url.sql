-- Link safety (roadmap G5): where a link ended up.
--
-- The link-preview function already follows up to three redirects to read a
-- page's preview. It now also remembers the address it ended at, so the risk
-- it reports for a short link ("bit.ly/...") is the risk of where the link
-- really goes. The risk itself is worked out from the address when the
-- function answers (supabase/functions/link-preview/link_risk.ts), so nothing
-- else is stored.
--
-- Deploy this migration before the new link-preview function: the function
-- reads and writes the column.

alter table public.link_previews
  add column if not exists final_url text
  check (final_url is null or char_length(final_url) between 1 and 2048);
