#!/bin/sh
# Builds the web app and deploys it to Cloudflare (wrangler.jsonc: the
# "wecord" Worker serving build/web at https://wecord.jokebear.fyi, and the
# public circle pages in worker/src, deployed together). Run
# from anywhere:
#
#   sh tool/deploy_web.sh
#
# Optional, off by default: a WebAssembly build (L5, docs/wasm-report.md).
#
#   WECORD_WEB_WASM=1 sh tool/deploy_web.sh
#
# builds with `flutter build web --wasm`, which ships main.dart.wasm next to
# the usual main.dart.js. Browsers that can run it (Chromium-based ones, by
# Flutter's default) use it; every other browser gets main.dart.js as before.
# Read the risks in docs/wasm-report.md first; without the variable nothing
# here changes.
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

# The app version (feature-flag minimum versions, "What's new") comes from
# pubspec.yaml, without the build number.
app_version=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)

if [ "${WECORD_WEB_WASM:-0}" = "1" ]; then
  echo "deploy_web: WebAssembly build (WECORD_WEB_WASM=1); main.dart.js stays as the fallback."
  flutter build web --release --wasm --dart-define-from-file=.env \
    --dart-define=APP_VERSION="$app_version"
  if [ ! -f build/web/main.dart.wasm ]; then
    echo "deploy_web: the wasm build produced no build/web/main.dart.wasm." >&2
    exit 1
  fi
else
  flutter build web --release --dart-define-from-file=.env \
    --dart-define=APP_VERSION="$app_version"
fi

# Stamp the build's version into the service worker (web/wecord_sw.js). It is
# a hash of every built file except the worker itself, so it only changes when
# the app does; the new worker then downloads the new shell and open tabs show
# "Update available". Without the stamp the worker does no caching at all.
# Done after the build and before wrangler hashes and uploads the assets.
version=$(find build/web -type f ! -name wecord_sw.js ! -name .last_build_id \
  -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -c1-12)
if ! grep -q "__WECORD_VERSION__" build/web/wecord_sw.js; then
  echo "deploy_web: build/web/wecord_sw.js has no version placeholder." >&2
  exit 1
fi
sed "s/__WECORD_VERSION__/$version/" build/web/wecord_sw.js \
  > build/web/wecord_sw.js.stamped
mv build/web/wecord_sw.js.stamped build/web/wecord_sw.js
echo "deploy_web: service worker version $version"

# The Worker (worker/src, wrangler.jsonc "main") draws /c/<slug> and
# /invite/<code> from two anon-callable database functions, so it needs the
# project's anon key (public: the web build contains it too). It is read from
# .env here, never printed, and passed as a plain Worker variable. When .env
# has none, the Worker hands those two paths to the web app.
anon_key=$(sed -n 's/^SUPABASE_ANON_KEY=//p' .env | head -n 1 | tr -d "\"' \r")
if [ -n "$anon_key" ]; then
  npx wrangler deploy --var "SUPABASE_ANON_KEY:$anon_key"
else
  echo "deploy_web: no SUPABASE_ANON_KEY in .env; public circle pages stay off." >&2
  npx wrangler deploy
fi
