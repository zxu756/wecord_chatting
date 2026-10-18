#!/bin/sh
# Prints the most frequent crash and error fingerprints of the last 24 hours
# from the linked Supabase project (the client_errors table that the apps
# fill through report_client_errors; clients cannot read it, you can).
# It runs one read-only SELECT with `supabase db query`.
#
#   sh tool/errors_report.sh              # last 24 hours, top 20
#   sh tool/errors_report.sh 72 50        # last 72 hours, top 50
#   sh tool/errors_report.sh --local      # the local database instead
#
# Columns: how many times it happened (the devices dedupe, so this is the
# sum of their counts), how many reports and people, when first and last
# seen, the kind, the newest app version and platform, and a sample message
# (already scrubbed on the device). To see one problem's stack and context:
#
#   supabase db query --linked "select stack, context from public.client_errors \
#     where fingerprint = '<fingerprint>' order by created_at desc limit 1"
#
# Reports older than 30 days are purged daily (migration
# 202610190030_client_errors.sql).
set -eu
cd "$(dirname "$0")/.."

target="--linked"
if [ "${1:-}" = "--local" ]; then
  target="--local"
  shift
fi
hours="${1:-24}"
limit="${2:-20}"
case "$hours$limit" in
  *[!0-9]*|"") echo "usage: sh tool/errors_report.sh [--local] [hours] [limit]" >&2; exit 2 ;;
esac

supabase db query "$target" "
select
  fingerprint,
  kind,
  sum(count) as occurrences,
  count(*) as reports,
  count(distinct user_id) as people,
  min(created_at)::timestamp(0) as first_seen,
  max(created_at)::timestamp(0) as last_seen,
  (array_agg(app_version order by created_at desc))[1] as version,
  (array_agg(platform order by created_at desc))[1] as platform,
  left((array_agg(message order by created_at desc))[1], 100) as sample
from public.client_errors
where created_at > now() - interval '$hours hours'
group by fingerprint, kind
order by occurrences desc, last_seen desc
limit $limit
"
