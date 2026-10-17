#!/bin/sh
# Turns on the one-minute dispatcher: pushes for scheduled messages,
# message reminders, chat event reminders and task due dates, and the
# removal of expired disappearing messages' files (the database does the
# rest on its own; see supabase/migrations/202610170010_scheduled_messages.sql
# and 202610170070_dispatch_more.sql).
# Run once from the project root after `supabase db push`:
#
#   sh tool/setup_later_dispatch.sh <project-ref>
#
# It makes a random shared secret, stores it as the Edge Function secret
# DISPATCH_SECRET, deploys the scheduled-dispatch function, and prints the
# SQL that stores the function URL and the same secret in Supabase Vault and
# (re)creates the one-minute cron job. Paste that SQL into the dashboard's
# SQL editor. pg_cron and pg_net must be enabled (Database -> Extensions);
# web push itself needs `sh tool/setup_web_push.sh` to have run.
# Messages and reminders are delivered without any of this; it only adds
# the push notifications (and the in-app inbox needs nothing at all).
set -eu
cd "$(dirname "$0")/.."
ref="${1:?usage: sh tool/setup_later_dispatch.sh <project-ref>}"

secret=$(deno eval '
const bytes = crypto.getRandomValues(new Uint8Array(32));
console.log(Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join(""));
')

supabase secrets set "DISPATCH_SECRET=$secret" --project-ref "$ref" >/dev/null
supabase functions deploy scheduled-dispatch --no-verify-jwt --project-ref "$ref"

cat <<SQL

-- Paste into the SQL editor of project $ref:
select vault.create_secret('https://$ref.supabase.co/functions/v1', 'wecord_functions_url');
select vault.create_secret('$secret', 'wecord_dispatch_secret');
create extension if not exists pg_cron;
create extension if not exists pg_net;
select public.install_later_dispatch_schedule();
-- To change a secret later: select vault.update_secret(id, 'new value')
-- from vault.secrets where name = 'wecord_dispatch_secret';
SQL
