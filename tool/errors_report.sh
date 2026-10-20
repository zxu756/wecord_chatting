#!/bin/sh
# Prints the most frequent crash and error groups of the last 24 hours from
# the linked Supabase project (the client_errors table that the apps fill
# through report_client_errors; clients cannot read it, you can). It runs
# read-only SELECTs with `supabase db query`.
#
#   sh tool/errors_report.sh                       # last 24 hours, top 20
#   sh tool/errors_report.sh 72 50                 # last 72 hours, top 50
#   sh tool/errors_report.sh --local               # the local database instead
#   sh tool/errors_report.sh --symbolize           # name the frames of release
#   sh tool/errors_report.sh --symbolize 72 30     #   builds, then regroup
#
# Groups (migration 202610260130): the kind of report, the type of the error
# and the first frame that is WeCord's own code, without line numbers, so one
# bug with several lines or callers is one row. A report from a release build
# made with --split-debug-info has no frame names (only addresses), so it is
# grouped by its message until it is symbolized.
#
# Columns: how many times it happened (the devices dedupe, so this is the sum
# of their counts), how many reports and people, when first and last seen, the
# newest app version and platform, and the group's name. To see one group's
# stack and context:
#
#   supabase db query --linked "select stack, context from public.client_errors \
#     where group_key = '<group_key>' order by created_at desc limit 1"
#
# Symbolizing needs the symbols of the release that crashed. Release builds
# are made with --split-debug-info=build/symbols/<version>/<platform> (see
# docs/WECORD_FEATURES.md, "Build and release"); keep that folder (it is in
# build/, never in git, and each build needs its own: the build id in the
# stack picks the file). --symbolize takes the newest stack of each top group,
# finds the .symbols file under build/symbols/<version>/ whose build matches,
# runs `flutter symbolize`, and prints the first package:wecord frame. Web
# reports are minified JavaScript and cannot be symbolized this way.
#
# Reports older than 30 days are purged daily (migration
# 202610190030_client_errors.sql).
set -eu
cd "$(dirname "$0")/.."

target="--linked"
symbolize=0
while [ $# -gt 0 ]; do
  case "$1" in
    --local) target="--local"; shift ;;
    --symbolize) symbolize=1; shift ;;
    *) break ;;
  esac
done
hours="${1:-24}"
limit="${2:-20}"
case "$hours$limit" in
  *[!0-9]*|"") echo "usage: sh tool/errors_report.sh [--local] [--symbolize] [hours] [limit]" >&2; exit 2 ;;
esac

if [ "$symbolize" = 0 ]; then
  supabase db query "$target" "
select
  e.group_key,
  e.kind,
  sum(e.count) as occurrences,
  count(*) as reports,
  count(distinct e.user_id) as people,
  min(e.created_at)::timestamp(0) as first_seen,
  max(e.created_at)::timestamp(0) as last_seen,
  (array_agg(e.app_version order by e.created_at desc))[1] as version,
  (array_agg(e.platform order by e.created_at desc))[1] as platform,
  left(coalesce(g.label, e.group_key), 110) as name
from public.client_errors e
left join public.ops_error_groups g on g.group_key = e.group_key
where e.created_at > now() - interval '$hours hours'
group by e.group_key, e.kind, g.label
order by occurrences desc, last_seen desc
limit $limit
"
  exit 0
fi

# --symbolize: the newest stack of each of the top groups, as JSON.
rows=$(mktemp)
trap 'rm -f "$rows"' EXIT
supabase db query "$target" --output-format json "
select * from (
  select distinct on (e.group_key)
    e.group_key,
    e.kind,
    e.app_version,
    lower(e.platform) as platform,
    e.stack,
    left(coalesce(g.label, e.group_key), 110) as name,
    (select sum(x.count) from public.client_errors x
       where x.group_key = e.group_key
         and x.created_at > now() - interval '$hours hours') as occurrences
  from public.client_errors e
  left join public.ops_error_groups g on g.group_key = e.group_key
  where e.created_at > now() - interval '$hours hours'
  order by e.group_key, e.created_at desc
) t
order by occurrences desc
limit $limit
" > "$rows"

python3 -I tool/symbolize_errors.py "$rows" build/symbols
