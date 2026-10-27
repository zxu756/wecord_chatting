#!/bin/sh
# L6: scale test against the LOCAL database only. Everything happens inside a
# transaction that is rolled back at the end, so no data is left behind.
#
#   sh tool/scale/run_scale.sh [small|full] [before|after|equiv] [bench|seed|FILE]
#
#   small   a quick check of the script itself (a few thousand rows)
#   full    the real run (5000-member group, 10000-member circle, ~400k messages)
#   before  leaves out the L6 migrations (202610281200 and later)
#   after   includes them
#   equiv   seeds with the migrations before L6, keeps copies of the old
#           functions in schema l6old, applies the L6 migrations, then runs
#           scale_equiv.sql: old and new must answer the same
#   seed    only seeds (to see that the script works); bench seeds and measures;
#           a file name seeds and then runs that file (your own probes)
#
# Run from the repository root. Takes the advisory lock the behaviour tests
# take, so it waits for (and blocks) other SQL tests while it runs.
# EXTRA="-v plans=1" prints query plans at the end of the bench.
set -e
SIZE="${1:-small}"
PHASE="${2:-after}"
WHAT="${3:-bench}"
DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"

case "$SIZE" in
  full)
    VARS="-v users=10000 -v group_members=5000 -v circle_members=10000 -v circle_channels=8 -v group_msgs=150000 -v channel_msgs=25000 -v dm_count=150 -v small_groups=30" ;;
  *)
    VARS="-v users=1500 -v group_members=800 -v circle_members=1200 -v circle_channels=3 -v group_msgs=8000 -v channel_msgs=2000 -v dm_count=20 -v small_groups=5" ;;
esac

if [ "$PHASE" = "after" ]; then
  MAX=999999999999
else
  MAX=202610281199
fi

OUT="$(mktemp -t l6scale).sql"
{
  echo '\set ON_ERROR_STOP on'
  echo 'begin;'
  echo 'do $$ begin perform pg_advisory_xact_lock(20261017); end $$;'
  echo 'set local client_min_messages = warning;'
  echo '\o /dev/null'
  sh tool/scale/load_migrations.sh "$MAX"
  echo '\o'
  echo '\i tool/scale/scale_seed.sql'
  if [ "$PHASE" = "equiv" ]; then
    echo '\i tool/scale/scale_snapshot_old.sql'
    echo '\o /dev/null'
    for f in $(ls supabase/migrations/*.sql | sort); do
      v=$(basename "$f" | cut -c1-12)
      if [ "$v" -gt 202610281199 ]; then
        echo "\\i $f"
      fi
    done
    echo '\o'
    echo '\i tool/scale/scale_equiv.sql'
  elif [ "$WHAT" = "bench" ]; then
    echo '\i tool/scale/scale_bench.sql'
  elif [ "$WHAT" != "seed" ]; then
    # Any other value is a file of your own measurements to run after seeding.
    echo "\\i $WHAT"
  fi
  echo 'rollback;'
} > "$OUT"

echo "phase=$PHASE size=$SIZE script=$OUT"
# shellcheck disable=SC2086
psql "$DB" -q $VARS ${EXTRA:-} -f "$OUT"
rm -f "$OUT"
