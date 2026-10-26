// Account security (G4): the record of recovery codes and passkeys in the
// archive. Names are escaped, and no code, hash or key is ever in it.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { buildExportFiles, type ExportData } from "./export_builder.ts";

const base: ExportData = {
  generatedAt: "2026-10-28T14:03:00.000Z",
  user: {
    id: "u-1",
    email: "ada@example.com",
    createdAt: null,
    lastSignInAt: null,
  },
  profile: { id: "u-1", username: "ada", display_name: "Ada" },
  settings: {},
  friends: [],
  friendRequests: [],
  blocked: [],
  conversations: [],
  messages: [],
  circles: [],
  moments: null,
  extras: null,
  files: [],
  attachmentLinks: {},
  linksExpireAt: "2026-11-04T14:03:00.000Z",
  skipped: [],
};

const security = {
  events: [
    {
      kind: "passkey_added",
      detail: { name: "Work <b>laptop</b>" },
      at: "2026-10-28T09:00:00Z",
      answer: "denied",
      answered_at: "2026-10-28T09:05:00Z",
    },
    {
      kind: "recovery_codes_generated",
      detail: { count: 10 },
      at: "2026-10-27T09:00:00Z",
      answer: null,
      answered_at: null,
    },
  ],
  recovery_codes: { remaining: 9, made_at: "2026-10-27T09:00:00Z" },
  passkeys: [
    {
      name: "iCloud Keychain",
      added_at: "2026-10-26T09:00:00Z",
      last_used_at: null,
    },
  ],
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("the security record adds a page and a JSON file", () => {
  const files = texts({ ...base, accountSecurity: security });
  assert("pages/account_security.html" in files);
  assert("data/account_security.json" in files);
  assertStringIncludes(
    files["index.html"],
    'href="pages/account_security.html"',
  );
  assertStringIncludes(files["index.html"], "2 events · 1 passkey");
  assertStringIncludes(files["README.txt"], "data/account_security.json");

  const page = files["pages/account_security.html"];
  assertStringIncludes(page, "9 unused recovery codes left");
  assertStringIncludes(page, "iCloud Keychain");
  assertStringIncludes(page, "New recovery codes were made");
  assertStringIncludes(page, "A passkey was added");
  assertStringIncludes(page, "You said it was not you");
  // Nothing a passkey's name says becomes markup.
  assertStringIncludes(page, "Work &lt;b&gt;laptop&lt;/b&gt;");
  assert(!page.includes("<b>laptop"));

  const json = JSON.parse(files["data/account_security.json"]);
  assertEquals(json.events.length, 2);
  assertEquals(json.recovery_codes.remaining, 9);
  assertEquals(json.passkeys.length, 1);
});

Deno.test("no code, hash, salt or key is in the archive", () => {
  const files = texts({ ...base, accountSecurity: security });
  const all = files["pages/account_security.html"] +
    files["data/account_security.json"];
  for (const word of ["code_hash", '"salt"', "public_key", "credential_id"]) {
    assert(!all.includes(word), word);
  }
});

Deno.test("an export without the part has no page; an empty one says so", () => {
  const without = texts(base);
  assert(!("pages/account_security.html" in without));
  assert(!("data/account_security.json" in without));

  const empty = texts({
    ...base,
    accountSecurity: {
      events: [],
      recovery_codes: { remaining: null, made_at: null },
      passkeys: [],
    },
  });
  assertStringIncludes(empty["pages/account_security.html"], "No passkeys.");
  assertStringIncludes(
    empty["pages/account_security.html"],
    "Nothing recorded.",
  );
  assertStringIncludes(
    empty["pages/account_security.html"],
    "0 unused recovery codes left",
  );
  assertStringIncludes(empty["index.html"], "0 events · 0 passkeys");
});
