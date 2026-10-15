#!/bin/sh
# Builds the web app and deploys it to Cloudflare (wrangler.jsonc: the
# "wecord" Worker serving build/web at https://wecord.jokebear.fyi). Run
# from anywhere:
#
#   sh tool/deploy_web.sh
#
# The build reads SUPABASE_URL and SUPABASE_ANON_KEY (and optionally
# WECORD_SITE_URL) from .env at the project root; its contents are never
# printed. wrangler asks you to log in to Cloudflare the first time.
set -eu
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo "deploy_web: .env is missing at $(pwd)." >&2
  echo "Create it with SUPABASE_URL=... and SUPABASE_ANON_KEY=... lines" >&2
  echo "(the hosted project's URL and anon key), then run this again." >&2
  exit 1
fi

for tool in flutter npx; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "deploy_web: $tool is not installed." >&2
    exit 1
  fi
done

flutter build web --release --dart-define-from-file=.env
npx wrangler deploy
