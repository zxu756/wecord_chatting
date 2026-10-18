import { assertEquals } from "jsr:@std/assert@1";
import {
  type AdminDeps,
  banDuration,
  handleAdminRequest,
  PERMANENT_BAN,
  type RpcResult,
} from "./handler.ts";

const target = "11111111-2222-3333-4444-555555555555";
const report = "99999999-2222-3333-4444-555555555555";
const now = new Date("2026-10-21T10:00:00Z");

interface Calls {
  rpc: { name: string; args?: Record<string, unknown> }[];
  bans: { userId: string; duration: string }[];
  revoked: string[];
  signed: { bucket: string; path: string; seconds: number }[];
}

function setup(
  options: {
    user?: string | null;
    role?: unknown;
    rpc?: (name: string, args?: Record<string, unknown>) => RpcResult;
    banError?: string | null;
    sessionsError?: string | null;
    signed?: string | null;
  } = {},
) {
  const calls: Calls = { rpc: [], bans: [], revoked: [], signed: [] };
  const deps: AdminDeps = {
    authenticate: () =>
      Promise.resolve(options.user === undefined ? "admin-1" : options.user),
    callRpc: (name, args) => {
      calls.rpc.push({ name, args });
      if (name === "admin_my_role") {
        return Promise.resolve({
          data: options.role === undefined ? "moderator" : options.role,
          error: null,
        });
      }
      return Promise.resolve(
        options.rpc?.(name, args) ?? { data: null, error: null },
      );
    },
    setBan: (userId, duration) => {
      calls.bans.push({ userId, duration });
      return Promise.resolve(options.banError ?? null);
    },
    revokeSessions: (userId) => {
      calls.revoked.push(userId);
      return Promise.resolve({
        count: 2,
        error: options.sessionsError ?? null,
      });
    },
    signedUrl: (bucket, path, seconds) => {
      calls.signed.push({ bucket, path, seconds });
      return Promise.resolve(
        options.signed === undefined
          ? "https://signed.example/x"
          : options.signed,
      );
    },
    now: () => now,
  };
  return {
    calls,
    send: (
      body: unknown,
      headers: Record<string, string> = { Authorization: "Bearer good" },
    ) =>
      handleAdminRequest(
        new Request("https://example.test/admin", {
          method: "POST",
          headers,
          body: typeof body === "string" ? body : JSON.stringify(body),
        }),
        deps,
      ),
  };
}

Deno.test("answers the preflight and refuses other methods", async () => {
  const options = await handleAdminRequest(
    new Request("https://example.test/admin", { method: "OPTIONS" }),
    {} as AdminDeps,
  );
  assertEquals(options.status, 200);
  const get = await handleAdminRequest(
    new Request("https://example.test/admin", { method: "GET" }),
    {} as AdminDeps,
  );
  assertEquals(get.status, 405);
});

Deno.test("needs a signed-in user", async () => {
  const noHeader = await setup().send({ action: "suspend_user" }, {});
  assertEquals(noHeader.status, 401);
  const badToken = await setup({ user: null }).send({ action: "suspend_user" });
  assertEquals(badToken.status, 401);
});

Deno.test("a normal user is refused before anything is read or done", async () => {
  for (const role of [null, undefined, "", "admin", false]) {
    const { send, calls } = setup({ role: role === undefined ? "none" : role });
    const response = await send({
      action: "suspend_user",
      user_id: target,
      reason: "spam",
    });
    assertEquals(response.status, 403);
    assertEquals(calls.rpc.map((c) => c.name), ["admin_my_role"]);
    assertEquals(calls.bans.length, 0);
    assertEquals(calls.revoked.length, 0);
  }
});

Deno.test("a failing role lookup is a server error, not a pass", async () => {
  const response = await handleAdminRequest(
    new Request("https://example.test/admin", {
      method: "POST",
      headers: { Authorization: "Bearer good" },
      body: JSON.stringify({ action: "suspend_user" }),
    }),
    {
      authenticate: () => Promise.resolve("admin-1"),
      callRpc: () =>
        Promise.resolve({
          data: null,
          error: { code: "XX000", message: "boom" },
        }),
      setBan: () => Promise.resolve(null),
      revokeSessions: () => Promise.resolve({ count: 0, error: null }),
      signedUrl: () => Promise.resolve(null),
      now: () => now,
    },
  );
  assertEquals(response.status, 500);
});

Deno.test("support staff cannot suspend or unsuspend", async () => {
  const { send, calls } = setup({ role: "support" });
  for (const action of ["suspend_user", "unsuspend_user"]) {
    const response = await send({ action, user_id: target, reason: "x" });
    assertEquals(response.status, 403);
  }
  assertEquals(calls.bans.length, 0);
  assertEquals(calls.rpc.map((c) => c.name), [
    "admin_my_role",
    "admin_my_role",
  ]);
});

Deno.test("validates the request", async () => {
  const cases: [unknown, number][] = [
    ["not json", 400],
    [[], 400],
    [{ action: "nope" }, 400],
    [{ action: "suspend_user", reason: "x" }, 400],
    [{ action: "suspend_user", user_id: "abc", reason: "x" }, 400],
    [{ action: "suspend_user", user_id: target }, 400],
    [{ action: "suspend_user", user_id: target, reason: "   " }, 400],
    [{ action: "suspend_user", user_id: target, reason: "x".repeat(501) }, 400],
    [
      { action: "suspend_user", user_id: target, reason: "x", until: "soon" },
      400,
    ],
    [{ action: "suspend_user", user_id: target, reason: "x", until: 5 }, 400],
    [
      {
        action: "suspend_user",
        user_id: target,
        reason: "x",
        until: "2026-10-01T00:00:00Z",
      },
      400,
    ],
    [
      { action: "suspend_user", user_id: target, reason: "x", report_id: "no" },
      400,
    ],
    [{ action: "suspend_user", user_id: "admin-1", reason: "x" }, 400],
    [{ action: "unsuspend_user", user_id: "nope" }, 400],
    [{ action: "attachment_url", report_id: "nope" }, 400],
  ];
  for (const [body, status] of cases) {
    const { send, calls } = setup();
    const response = await send(body);
    assertEquals(response.status, status, JSON.stringify(body));
    assertEquals(calls.bans.length, 0);
    // Only the admin check ran; nothing was written.
    assertEquals(calls.rpc.map((c) => c.name), ["admin_my_role"]);
  }
});

Deno.test("suspending yourself is refused", async () => {
  const me = "aaaaaaaa-2222-3333-4444-555555555555";
  const { send, calls } = setup({ user: me });
  const response = await send({
    action: "suspend_user",
    user_id: me,
    reason: "x",
  });
  assertEquals(response.status, 403);
  assertEquals(calls.bans.length, 0);
});

Deno.test("a suspension is recorded, the account banned and its sessions ended", async () => {
  const { send, calls } = setup();
  const until = "2026-10-24T10:30:00Z";
  const response = await send({
    action: "suspend_user",
    user_id: target,
    reason: "  harassment ",
    until,
    report_id: report,
  });
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    suspended: true,
    banned: true,
    sessions_revoked: 2,
    until: new Date(until).toISOString(),
  });
  assertEquals(calls.rpc[1], {
    name: "admin_suspend_user",
    args: {
      target_user_id: target,
      until: new Date(until).toISOString(),
      reason: "harassment",
      report_id: report,
    },
  });
  // 72.5 hours rounds up.
  assertEquals(calls.bans, [{ userId: target, duration: "73h" }]);
  assertEquals(calls.revoked, [target]);
});

Deno.test("without an end date the ban is for good", async () => {
  const { send, calls } = setup({ role: "owner" });
  const response = await send({
    action: "suspend_user",
    user_id: target,
    reason: "x",
  });
  assertEquals(response.status, 200);
  assertEquals(calls.bans, [{ userId: target, duration: PERMANENT_BAN }]);
  assertEquals(calls.rpc[1].args?.report_id, null);
  assertEquals(calls.rpc[1].args?.until, null);
});

Deno.test("when the database refuses, nothing is banned", async () => {
  const codes: [string, number][] = [
    ["42501", 403],
    ["22023", 400],
    ["P0002", 404],
    ["XX000", 500],
  ];
  for (const [code, status] of codes) {
    const { send, calls } = setup({
      rpc: () => ({ data: null, error: { code, message: "no" } }),
    });
    const response = await send({
      action: "suspend_user",
      user_id: target,
      reason: "x",
    });
    assertEquals(response.status, status, code);
    assertEquals(calls.bans.length, 0);
    assertEquals(calls.revoked.length, 0);
  }
});

Deno.test("a failed ban is reported and leaves the sessions alone", async () => {
  const { send, calls } = setup({ banError: "auth down" });
  const response = await send({
    action: "suspend_user",
    user_id: target,
    reason: "x",
  });
  assertEquals(response.status, 502);
  assertEquals((await response.json()).error, "ban_failed");
  assertEquals(calls.revoked.length, 0);
});

Deno.test("failing to end sessions is reported, the ban stands", async () => {
  const { send, calls } = setup({ sessionsError: "db down" });
  const response = await send({
    action: "suspend_user",
    user_id: target,
    reason: "x",
  });
  assertEquals(response.status, 502);
  const body = await response.json();
  assertEquals(body.error, "sessions_failed");
  assertEquals(body.banned, true);
  assertEquals(calls.bans.length, 1);
});

Deno.test("lifting a suspension unbans the account", async () => {
  const { send, calls } = setup();
  const response = await send({
    action: "unsuspend_user",
    user_id: target,
    reason: "appeal",
  });
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { suspended: false, banned: false });
  assertEquals(calls.rpc[1], {
    name: "admin_unsuspend_user",
    args: { target_user_id: target, reason: "appeal" },
  });
  assertEquals(calls.bans, [{ userId: target, duration: "none" }]);
  assertEquals(calls.revoked.length, 0);
});

Deno.test("attachment_url signs only what the report's snapshot holds", async () => {
  const snapshot = (attachment: unknown) => ({
    data: { report: { snapshot: { attachment } } },
    error: null,
  });
  const ok = setup({
    rpc: () => snapshot({ bucket: "chat-media", path: "circle-1/a.png" }),
  });
  const response = await ok.send({
    action: "attachment_url",
    report_id: report,
  });
  assertEquals(response.status, 200);
  assertEquals((await response.json()).url, "https://signed.example/x");
  assertEquals(ok.calls.signed, [
    { bucket: "chat-media", path: "circle-1/a.png", seconds: 300 },
  ]);

  for (
    const attachment of [
      null,
      {},
      { bucket: "profile-avatars", path: "x/y.png" },
      { bucket: "chat-media", path: "../other/z.png" },
      { bucket: "chat-media" },
    ]
  ) {
    const { send, calls } = setup({ rpc: () => snapshot(attachment) });
    const refused = await send({ action: "attachment_url", report_id: report });
    assertEquals(refused.status, 404, JSON.stringify(attachment));
    assertEquals(calls.signed.length, 0);
  }

  const denied = setup({
    rpc: () => ({ data: null, error: { code: "42501" } }),
  });
  assertEquals(
    (await denied.send({ action: "attachment_url", report_id: report })).status,
    403,
  );
  const missing = setup({
    rpc: () => snapshot({ bucket: "chat-media", path: "c/a.png" }),
    signed: null,
  });
  assertEquals(
    (await missing.send({ action: "attachment_url", report_id: report }))
      .status,
    404,
  );
});

Deno.test("ban durations", () => {
  assertEquals(banDuration(null, now), PERMANENT_BAN);
  assertEquals(banDuration(new Date("2026-10-21T10:00:01Z"), now), "1h");
  assertEquals(banDuration(new Date("2026-10-21T11:00:00Z"), now), "1h");
  assertEquals(banDuration(new Date("2026-10-21T11:00:01Z"), now), "2h");
  assertEquals(banDuration(new Date("2026-10-28T10:00:00Z"), now), "168h");
});
