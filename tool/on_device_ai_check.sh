#!/bin/sh
# Compiles the on-device AI core (the Swift that the iOS and macOS apps use to
# call Apple's Foundation Models) with a small test program and runs it on
# this Mac. Exit 0: the model answered a translation, a rewrite and a summary;
# 2: the model is not usable here (Apple Intelligence off, model still
# downloading, ...) but the checks that need no model passed; 1: a check
# failed. Needs Xcode 26 or later. Nothing is installed and no app is started.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
swiftc -O -o "$out/check" \
  "$root/macos/Runner/OnDeviceAiCore.swift" "$here/on_device_ai/main.swift" 2>&1 \
  | grep -v "^$" || true
"$out/check"
