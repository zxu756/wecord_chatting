#!/bin/sh
# Prints psql \i lines for every migration after the local baseline
# (202610170001), in file-name order. Optional first argument: highest
# migration prefix to include (for example 202610281199 to leave out the
# L6 migrations when measuring "before"). Run from the repository root.
max="${1:-999999999999}"
for f in $(ls supabase/migrations/*.sql | sort); do
  v=$(basename "$f" | cut -c1-12)
  if [ "$v" -gt 202610170001 ] && [ "$v" -le "$max" ]; then
    echo "\\i $f"
  fi
done
