-- L6 scale test: keeps a copy of the functions the L6 migrations rewrite, as
-- they were before, in the schema l6old, so scale_equiv.sql can ask old and
-- new the same question. Run by run_scale.sh (phase equiv) after seeding and
-- before the L6 migrations.
\set ON_ERROR_STOP on
\o /dev/null
create schema l6old;
grant usage on schema l6old to public;
do $do$
declare
  r record;
  def text;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in (
        'list_conversation_summaries', 'get_conversation_summary',
        'list_circle_summaries', 'search_messages',
        'is_current_user_blocked_in_conversation', 'get_circle_detail',
        'claim_push_delivery'
      )
  loop
    def := replace(
      pg_get_functiondef(r.sig),
      'CREATE OR REPLACE FUNCTION public.',
      'CREATE OR REPLACE FUNCTION l6old.'
    );
    execute def;
  end loop;
end $do$;
grant execute on all functions in schema l6old to public;
\o
