import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  buildBlocks,
  handleNotePublicRequest,
  imagePathOf,
  imagePathsOf,
  isSafeLink,
  type LookupResult,
  type NotePublicDeps,
  tokenFromPath,
  WindowLimiter,
} from "./page.ts";

const token = "0123456789abcdef0123456789abcdef0123456789abcdef";
const noteId = "11111111-2222-4333-8444-555555555555";
const blockId = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";

function ok(
  blocks: unknown[],
  extra: Record<string, unknown> = {},
): LookupResult {
  return {
    status: "ok",
    note_id: noteId,
    title: "Trip plan",
    icon: "\u{1F5FA}",
    updated_at: "2026-10-24T09:00:00Z",
    allow_indexing: false,
    blocks,
    ...extra,
  } as LookupResult;
}

function deps(
  result: LookupResult | Error,
  extra: Partial<NotePublicDeps> = {},
): NotePublicDeps & { lookups: string[]; signed: string[][] } {
  const lookups: string[] = [];
  const signed: string[][] = [];
  return {
    lookups,
    signed,
    now: () => new Date("2026-10-24T09:00:00Z"),
    badTokens: new WindowLimiter(3, 60_000),
    lookup: (value) => {
      lookups.push(value);
      return result instanceof Error
        ? Promise.reject(result)
        : Promise.resolve(result);
    },
    sign: (paths) => {
      signed.push(paths);
      return Promise.resolve(
        Object.fromEntries(
          paths.map((path) => [path, `https://files.test/${path}?sig=1`]),
        ),
      );
    },
    ...extra,
  };
}

function get(path: string, init: RequestInit = {}): Request {
  return new Request(`https://x.supabase.co/functions/v1${path}`, init);
}

Deno.test("tokenFromPath reads only a 48 digit lowercase hex token", () => {
  assertEquals(tokenFromPath(`/note-public/${token}`), token);
  assertEquals(tokenFromPath(`/functions/v1/note-public/${token}/`), token);
  assertEquals(tokenFromPath("/note-public"), null);
  assertEquals(tokenFromPath(`/note-public/${token.toUpperCase()}`), null);
  assertEquals(tokenFromPath(`/note-public/${token}0`), null);
  assertEquals(tokenFromPath(`/note-public/${token.slice(1)}`), null);
  assertEquals(tokenFromPath(`/note-public/${token}.json`), null);
  assertEquals(tokenFromPath("/note-public/../../etc/passwd"), null);
});

Deno.test("isSafeLink lets only web links through", () => {
  assert(isSafeLink("https://example.com/a?b=c"));
  assert(isSafeLink("http://example.com"));
  assertFalse(isSafeLink("javascript:alert(1)"));
  assertFalse(isSafeLink("JaVaScRiPt:alert(1)"));
  assertFalse(isSafeLink("data:text/html,<script>alert(1)</script>"));
  assertFalse(isSafeLink("vbscript:x"));
  assertFalse(isSafeLink("file:///etc/passwd"));
  assertFalse(isSafeLink("mailto:a@b.c"));
  assertFalse(isSafeLink("//example.com"));
  assertFalse(isSafeLink(""));
  assertFalse(isSafeLink("https://" + "a".repeat(2100)));
});

Deno.test("imagePathOf accepts only a file of this very note", () => {
  assertEquals(
    imagePathOf(noteId, { path: `${noteId}/abc.png` }),
    `${noteId}/abc.png`,
  );
  assertEquals(imagePathOf(noteId, { path: `${noteId}/../other/x.png` }), null);
  assertEquals(imagePathOf(noteId, { path: `${noteId}/a/b.png` }), null);
  assertEquals(
    imagePathOf(noteId, { path: "99999999-2222-4333-8444-555555555555/a.png" }),
    null,
  );
  assertEquals(imagePathOf(noteId, { path: "../secret.png" }), null);
  assertEquals(imagePathOf(noteId, { path: 5 }), null);
  assertEquals(imagePathOf(noteId, {}), null);
  assertEquals(imagePathOf("not-a-uuid", { path: "not-a-uuid/a.png" }), null);
  assertEquals(imagePathOf(noteId, { path: `${noteId}/..` }), null);
});

Deno.test("buildBlocks rebuilds blocks from known parts only", () => {
  const blocks = buildBlocks(noteId, [
    {
      id: blockId,
      kind: "paragraph",
      text: "Hello <script>alert(1)</script> world\u0000",
      marks: [
        [0, 5, "b"],
        [6, 8, "l:javascript:alert(1)"],
        [6, 8, "l:https://example.com"],
        [9, 12, "m:00000000-0000-4000-8000-000000000002"],
        [1, 2, "zz"],
        ["x", 2, "b"],
        [3, 1, "i"],
      ],
      props: { secret: "hunter2" },
      created_by: "someone",
    },
    { kind: "h9", text: "Unknown kind" },
    { kind: "todo", text: "Pack", props: { checked: true, other: 1 } },
    {
      kind: "code",
      text: "let x = 1",
      marks: [[0, 3, "b"]],
      props: { lang: "dart", extra: 1 },
    },
    { kind: "divider", text: "ignored", props: { a: 1 } },
    null,
    "text",
  ], {});
  assertEquals(blocks.length, 5);
  assertEquals(blocks[0].id, blockId);
  assertEquals(blocks[0].text, "Hello <script>alert(1)</script> world");
  assertEquals(blocks[0].marks, [[0, 5, "b"], [6, 8, "l:https://example.com"]]);
  assertEquals(blocks[0].props, {});
  assertEquals(blocks[1].kind, "paragraph");
  assertEquals(blocks[1].id, "");
  assertEquals(blocks[2].props, { checked: true });
  assertEquals(blocks[3].marks, []);
  assertEquals(blocks[3].props, { lang: "dart" });
  assertEquals(blocks[4].text, "");
  assertEquals(blocks[4].props, {});
});

Deno.test("buildBlocks cleans tables cell by cell", () => {
  const [table] = buildBlocks(noteId, [
    {
      kind: "table",
      text: "should go",
      props: {
        header: true,
        cols: ["c1", "c2", 3, "", "x".repeat(17)],
        rows: [
          { id: "r1", c: { c1: "Name", c2: "Day", c9: "stray" } },
          { id: "r2", c: { c1: 5, c2: "<img src=x onerror=alert(1)>" } },
          "bad",
          { id: "r3" },
        ],
      },
    },
  ], {});
  assertEquals(table.kind, "table");
  assertEquals(table.text, "");
  assertEquals(table.props, {
    header: true,
    cols: ["c1", "c2"],
    rows: [
      { id: "r1", c: { c1: "Name", c2: "Day" } },
      { id: "r2", c: { c2: "<img src=x onerror=alert(1)>" } },
      { id: "r3", c: {} },
    ],
  });
});

Deno.test("buildBlocks gives a picture only a signed link of its own note", () => {
  const own = `${noteId}/a.png`;
  const alien = "99999999-2222-4333-8444-555555555555/b.png";
  const raw = [
    {
      kind: "image",
      props: { path: own, name: "a.png", width: 100.4, height: -3, secret: 1 },
    },
    { kind: "image", props: { path: alien, name: "b.png" } },
    { kind: "image", props: { name: "c.png" } },
  ];
  assertEquals(imagePathsOf(noteId, raw), [own]);
  const blocks = buildBlocks(noteId, raw, {
    [own]: "https://files.test/a",
    [alien]: "https://files.test/b",
  });
  assertEquals(blocks[0].props, {
    name: "a.png",
    url: "https://files.test/a",
    width: 100,
    height: 0,
  });
  assertEquals(blocks[1].props, { name: "b.png" });
  assertEquals(blocks[2].props, { name: "c.png" });
});

Deno.test("a live token answers the note, cleaned, with safe headers", async () => {
  const d = deps(ok([
    { id: blockId, kind: "paragraph", text: "Hi", marks: [], props: {} },
    { kind: "image", props: { path: `${noteId}/a.png`, name: "a.png" } },
  ]));
  const response = await handleNotePublicRequest(
    get(`/note-public/${token}`),
    d,
  );
  assertEquals(response.status, 200);
  assertEquals(d.lookups, [token]);
  assertEquals(d.signed, [[`${noteId}/a.png`]]);
  const body = await response.json();
  assertEquals(body.title, "Trip plan");
  assertEquals(body.allow_indexing, false);
  assertEquals(body.blocks.length, 2);
  assertEquals(
    body.blocks[1].props.url,
    `https://files.test/${noteId}/a.png?sig=1`,
  );
  assertFalse("note_id" in body);
  assertEquals(
    response.headers.get("content-type"),
    "application/json; charset=utf-8",
  );
  assertEquals(response.headers.get("x-content-type-options"), "nosniff");
  assertEquals(response.headers.get("x-robots-tag"), "noindex, nofollow");
  assertEquals(response.headers.get("referrer-policy"), "no-referrer");
  assertEquals(response.headers.get("cache-control"), "private, no-store");
  assert(
    response.headers.get("content-security-policy")!.startsWith(
      "default-src 'none'",
    ),
  );
  assertEquals(response.headers.get("access-control-allow-origin"), "*");
});

Deno.test("the author's choice about search engines is passed on", async () => {
  const response = await handleNotePublicRequest(
    get(`/note-public/${token}`),
    deps(ok([], { allow_indexing: true })),
  );
  assertEquals((await response.json()).allow_indexing, true);
});

Deno.test("every dead link answers the same 404", async () => {
  const bodies = new Set<string>();
  for (const result of [{ status: "invalid" }, null, "x", { status: "ok" }]) {
    const response = await handleNotePublicRequest(
      get(`/note-public/${token}`),
      deps(result as unknown as LookupResult),
    );
    assertEquals(response.status, 404);
    bodies.add(await response.text());
  }
  assertEquals(bodies.size, 1);
});

Deno.test("a wrong shape of token never reaches the database", async () => {
  const d = deps(ok([]));
  for (
    const path of [
      "/note-public",
      "/note-public/short",
      `/note-public/${token}x`,
    ]
  ) {
    const response = await handleNotePublicRequest(get(path), d);
    assertEquals(response.status, 404);
  }
  assertEquals(d.lookups, []);
});

Deno.test("an address with too many wrong tokens is turned away", async () => {
  const d = deps({ status: "invalid" });
  const headers = { "x-forwarded-for": "203.0.113.9" };
  for (let i = 0; i < 3; i++) {
    const response = await handleNotePublicRequest(
      get(`/note-public/${token}`, { headers }),
      d,
    );
    assertEquals(response.status, 404);
  }
  const blocked = await handleNotePublicRequest(
    get(`/note-public/${token}`, { headers }),
    d,
  );
  assertEquals(blocked.status, 429);
  assert(Number(blocked.headers.get("retry-after")) >= 1);
  assertEquals(d.lookups.length, 3);
  // Another address is unaffected.
  const other = await handleNotePublicRequest(
    get(`/note-public/${token}`, {
      headers: { "x-forwarded-for": "203.0.113.10" },
    }),
    d,
  );
  assertEquals(other.status, 404);
});

Deno.test("a database error is a 503, not a leak", async () => {
  const response = await handleNotePublicRequest(
    get(`/note-public/${token}`),
    deps(new Error("relation note_publications does not exist")),
  );
  assertEquals(response.status, 503);
  assertFalse((await response.text()).includes("note_publications"));
});

Deno.test("failing to sign pictures still answers the text", async () => {
  const d = deps(
    ok([
      { kind: "paragraph", text: "Words" },
      { kind: "image", props: { path: `${noteId}/a.png`, name: "a.png" } },
    ]),
    { sign: () => Promise.reject(new Error("storage down")) },
  );
  const response = await handleNotePublicRequest(
    get(`/note-public/${token}`),
    d,
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.blocks[0].text, "Words");
  assertFalse("url" in body.blocks[1].props);
});

Deno.test("only GET and HEAD read, OPTIONS answers CORS", async () => {
  const d = deps(ok([]));
  const post = await handleNotePublicRequest(
    get(`/note-public/${token}`, { method: "POST" }),
    d,
  );
  assertEquals(post.status, 405);
  await post.body?.cancel();
  const options = await handleNotePublicRequest(
    get(`/note-public/${token}`, { method: "OPTIONS" }),
    d,
  );
  assertEquals(options.status, 200);
  assert(
    options.headers.get("access-control-allow-headers")!.includes(
      "authorization",
    ),
  );
  await options.body?.cancel();
  const head = await handleNotePublicRequest(
    get(`/note-public/${token}`, { method: "HEAD" }),
    d,
  );
  assertEquals(head.status, 200);
  assertEquals(await head.text(), "");
  assertEquals(d.lookups.length, 1);
});

Deno.test("WindowLimiter counts per key and forgets old windows", () => {
  const limiter = new WindowLimiter(2, 1000);
  assert(limiter.hit("a", 0));
  assert(limiter.hit("a", 10));
  assertFalse(limiter.hit("a", 20));
  assert(limiter.isBlocked("a", 30));
  assertFalse(limiter.isBlocked("b", 30));
  assert(limiter.hit("a", 1500));
  assertFalse(limiter.isBlocked("a", 1500));
  assertEquals(limiter.retryAfterSeconds("missing", 0), 1);
});
