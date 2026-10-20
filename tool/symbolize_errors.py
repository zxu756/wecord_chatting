"""Names the frames of release-build crashes (K5), for tool/errors_report.sh.

    python3 -I tool/symbolize_errors.py rows.json build/symbols

rows.json is what `supabase db query --output-format json` printed for the
newest stack of each top error group: group_key, kind, app_version, platform,
stack, name and occurrences. Symbols are looked up in
<symbols>/<app_version>/ (any depth) by trying each *.symbols file with
`flutter symbolize`: the one whose build id matches the stack's header gives
named frames. Stacks that already have names are used as they are. The
output regroups the groups by kind and first package:wecord frame.
"""

import glob
import json
import os
import re
import subprocess
import sys
import tempfile

BUILD_ID = re.compile(r"build_id:\s*'([0-9a-fA-F]+)'")
APP_FRAME = re.compile(r"#\d+\s+(?:abs\s+\S+\s+virt\s+\S+\s+)?(.*?)\s*\((package:wecord/[^:)\s]+)")


def find_rows(data):
    """The list of row dicts in whatever shape the CLI printed."""
    if isinstance(data, list):
        if all(isinstance(item, dict) for item in data):
            if data and not any("group_key" in item for item in data):
                for item in data:
                    found = find_rows(list(item.values()))
                    if found:
                        return found
            return data
        for item in data:
            found = find_rows(item)
            if found:
                return found
    if isinstance(data, dict):
        for value in data.values():
            found = find_rows(value)
            if found:
                return found
    return []


def first_app_frame(text):
    match = APP_FRAME.search(text)
    if not match:
        return None
    return "%s @ %s" % (match.group(1).strip(), match.group(2))


def symbolize(stack, version, symbols_root):
    """The stack with names, or None when no symbols file fits."""
    candidates = sorted(
        glob.glob(os.path.join(symbols_root, version, "**", "*.symbols"), recursive=True)
    )
    if not candidates:
        return None
    with tempfile.NamedTemporaryFile("w", suffix=".err", delete=False) as handle:
        handle.write(stack)
        path = handle.name
    try:
        for candidate in candidates:
            result = subprocess.run(
                ["flutter", "symbolize", "-i", path, "-d", candidate],
                capture_output=True,
                text=True,
            )
            if result.returncode == 0 and "package:" in result.stdout:
                return result.stdout
    finally:
        os.unlink(path)
    return None


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    with open(sys.argv[1]) as handle:
        rows = find_rows(json.load(handle))
    if not rows:
        print("No error reports in that time.")
        return 0

    regrouped = {}
    unnamed = 0
    for row in rows:
        stack = row.get("stack") or ""
        occurrences = int(row.get("occurrences") or 0)
        frame = None
        if BUILD_ID.search(stack):
            named = symbolize(stack, row.get("app_version") or "", sys.argv[2])
            frame = first_app_frame(named) if named else None
            if named is None:
                unnamed += 1
        else:
            frame = first_app_frame(stack)
        where = frame or "(" + (row.get("name") or row.get("group_key")) + ")"
        key = (row.get("kind") or "other", where)
        entry = regrouped.setdefault(key, [0, 0, []])
        entry[0] += occurrences
        entry[1] += 1
        entry[2].append(row.get("app_version") or "?")

    print("%-8s %-6s %-20s %s" % ("times", "groups", "kind", "first WeCord frame"))
    for (kind, where), (times, groups, versions) in sorted(
        regrouped.items(), key=lambda item: -item[1][0]
    ):
        print("%-8d %-6d %-20s %s  [%s]" % (times, groups, kind, where, ", ".join(sorted(set(versions)))))
    if unnamed:
        print(
            "\n%d group(s) have an address-only stack and no matching file under "
            "%s/<version>/. Build releases with --split-debug-info=%s/<version>/<platform> "
            "and keep that folder." % (unnamed, sys.argv[2], sys.argv[2])
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
