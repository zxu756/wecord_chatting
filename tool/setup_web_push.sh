#!/bin/sh
# Generates a VAPID key pair and stores it as Supabase function secrets,
# turning on web push. Run once from the project root:
#
#   sh tool/setup_web_push.sh [contact]
#
# [contact] is a mailto: or https: address push services can reach
# (default: https://wecord.jokebear.fyi). The keys go straight to Supabase
# and are not printed. Running it again replaces the keys, after which
# browsers must turn push notifications on again.
set -eu
cd "$(dirname "$0")/.."
contact="${1:-https://wecord.jokebear.fyi}"

keys=$(deno eval '
const pair = await crypto.subtle.generateKey(
  { name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const raw = new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey));
const jwk = await crypto.subtle.exportKey("jwk", pair.privateKey);
const b64 = (bytes) => btoa(String.fromCharCode(...bytes))
  .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
console.log(b64(raw) + " " + jwk.d);
')
public_key="${keys% *}"
private_key="${keys#* }"

supabase secrets set \
  "VAPID_PUBLIC_KEY=$public_key" \
  "VAPID_PRIVATE_KEY=$private_key" \
  "VAPID_SUBJECT=$contact" >/dev/null
echo "Web push is set up. Turn on push notifications in WeCord's settings."
