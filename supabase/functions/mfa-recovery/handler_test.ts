import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  type FactorList,
  handleRecovery,
  maxCodeLength,
  type RecoveryDeps,
  type RpcResult,
} from "./handler.ts";

const user = "11111111-2222-3333-4444-555555555555";
const codeId = "99999999-2222-3333-4444-555555555555";

interface Calls {
  consumed: { userId: string; code: string }[];
  deleted: string[];
  finished: {
    userId: string;
    codeId: string;
    succeeded: boolean;
    left: number;
  }[];
}

function setup(
  options: {
    user?: string | null;
    factors?: Partial<FactorList>;
    consume?: RpcResult;
    deleteFails?: string[];
    finishError?: string | null;
  } = {},
) {
  const calls: Calls = { consumed: [], deleted: [], finished: [] };
  const deps: RecoveryDeps = {
    authenticate: () =>
      Promise.resolve(options.user === undefined ? user : options.user),
    listFactors: () =>
      Promise.resolve({
        verified: ["f1"],
        unverified: [],
        error: null,
        ...options.factors,
      }),
    consume: (userId, code) => {
      calls.consumed.push({ userId, code });
      return Promise.resolve(
        options.consume ??
          {
            data: { ok: true, code_id: codeId, remaining: 7 },
            error: null,
          },
      );
    },
    deleteFactor: (_userId, factorId) => {
      calls.deleted.push(factorId);
      return Promise.resolve(
        options.deleteFails?.includes(factorId) ? "boom" : null,
      );
    },
    finish: (userId, id, succeeded, left) => {
      calls.finished.push({ userId, codeId: id, succeeded, left });
      return Promise.resolve(options.finishError ?? null);
    },
  };
  return { deps, calls };
}

function post(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request("https://example.test/mfa-recovery", {
    method: "POST",
    headers: { Authorization: "Bearer token", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

Deno.test("a right code removes the authenticator and records it", async () => {
  const { deps, calls } = setup({ factors: { unverified: ["f2"] } });
  const response = await handleRecovery(post({ code: "ABCDE-FGHJK" }), deps);
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { recovered: true, remaining: 7 });
  assertEquals(calls.consumed, [{ userId: user, code: "ABCDE-FGHJK" }]);
  assertEquals(calls.deleted, ["f1", "f2"]);
  assertEquals(calls.finished, [
    { userId: user, codeId, succeeded: true, left: 7 },
  ]);
});

Deno.test("no token, a bad token and the wrong method are refused", async () => {
  const { deps, calls } = setup({ user: null });
  const noHeader = new Request("https://example.test/x", {
    method: "POST",
    body: JSON.stringify({ code: "x" }),
  });
  assertEquals((await handleRecovery(noHeader, deps)).status, 401);
  assertEquals((await handleRecovery(post({ code: "x" }), deps)).status, 401);
  assertEquals(
    (await handleRecovery(
      new Request("https://example.test/x", { method: "GET" }),
      deps,
    )).status,
    405,
  );
  assertEquals(calls.consumed, []);
  assertEquals(calls.deleted, []);
});

Deno.test("OPTIONS answers the browser's check", async () => {
  const { deps } = setup();
  const response = await handleRecovery(
    new Request("https://example.test/x", { method: "OPTIONS" }),
    deps,
  );
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), "*");
  await response.text();
});

Deno.test("a missing, empty, long or odd code is a bad request", async () => {
  for (
    const body of [
      {},
      { code: "" },
      { code: "   " },
      { code: 123456 },
      { code: "A".repeat(maxCodeLength + 1) },
      "not json",
    ]
  ) {
    const { deps, calls } = setup();
    const response = await handleRecovery(post(body), deps);
    assertEquals(response.status, 400);
    assertEquals((await response.json()).error, "bad_request");
    assertEquals(calls.consumed, []);
  }
});

Deno.test("an account without two-step verification tries no code", async () => {
  const { deps, calls } = setup({
    factors: { verified: [], unverified: ["f2"] },
  });
  const response = await handleRecovery(post({ code: "ABCDE-FGHJK" }), deps);
  assertEquals(response.status, 409);
  assertEquals((await response.json()).error, "not_enabled");
  assertEquals(calls.consumed, []);
  assertEquals(calls.deleted, []);
});

Deno.test("a failed factor lookup is a server error, no code tried", async () => {
  const { deps, calls } = setup({ factors: { error: "down" } });
  const response = await handleRecovery(post({ code: "ABCDE-FGHJK" }), deps);
  assertEquals(response.status, 500);
  assertEquals(calls.consumed, []);
});

Deno.test("a wrong code says how many tries are left and removes nothing", async () => {
  const { deps, calls } = setup({
    consume: {
      data: { ok: false, reason: "invalid", attempts_left: 3 },
      error: null,
    },
  });
  const response = await handleRecovery(post({ code: "AAAAA-AAAAA" }), deps);
  assertEquals(response.status, 400);
  assertEquals(await response.json(), {
    error: "invalid_code",
    attempts_left: 3,
  });
  assertEquals(calls.deleted, []);
  assertEquals(calls.finished, []);
});

Deno.test("a locked account is told to wait and nothing is removed", async () => {
  const { deps, calls } = setup({
    consume: {
      data: { ok: false, reason: "locked", retry_after_seconds: 900 },
      error: null,
    },
  });
  const response = await handleRecovery(post({ code: "ABCDE-FGHJK" }), deps);
  assertEquals(response.status, 429);
  assertEquals(await response.json(), {
    error: "locked",
    retry_after_seconds: 900,
  });
  assertEquals(calls.deleted, []);
});

Deno.test("an account with no codes left is told so", async () => {
  const { deps } = setup({
    consume: { data: { ok: false, reason: "no_codes" }, error: null },
  });
  const response = await handleRecovery(post({ code: "ABCDE-FGHJK" }), deps);
  assertEquals(response.status, 400);
  assertEquals((await response.json()).error, "no_codes");
});

Deno.test("a database error or an odd answer removes nothing", async () => {
  for (
    const consume of [
      { data: null, error: { message: "db down" } },
      { data: { ok: false, reason: "surprise" }, error: null },
      { data: { ok: true, code_id: "not-a-uuid", remaining: 1 }, error: null },
      { data: null, error: null },
    ] as RpcResult[]
  ) {
    const { deps, calls } = setup({ consume });
    const response = await handleRecovery(post({ code: "ABCDE-FGHJK" }), deps);
    assertEquals(response.status, 500);
    assertEquals(calls.deleted, []);
  }
});

Deno.test("if the authenticator cannot be removed the code is given back", async () => {
  const { deps, calls } = setup({
    factors: { verified: ["f1", "f3"] },
    deleteFails: ["f3"],
  });
  const response = await handleRecovery(post({ code: "ABCDE-FGHJK" }), deps);
  assertEquals(response.status, 500);
  assertEquals((await response.json()).error, "recovery_failed");
  assertEquals(calls.finished, [
    { userId: user, codeId, succeeded: false, left: 7 },
  ]);
});

Deno.test("an unfinished set-up that cannot be removed does not fail it", async () => {
  const { deps, calls } = setup({
    factors: { unverified: ["f2"] },
    deleteFails: ["f2"],
  });
  const response = await handleRecovery(post({ code: "ABCDE-FGHJK" }), deps);
  assertEquals(response.status, 200);
  assertEquals(calls.finished[0].succeeded, true);
});

Deno.test("a failure to record it still reports the recovery", async () => {
  const { deps } = setup({ finishError: "db down" });
  const response = await handleRecovery(post({ code: "ABCDE-FGHJK" }), deps);
  assertEquals(response.status, 200);
  assert((await response.json()).recovered);
});

Deno.test("the code is not written to the log", async () => {
  const lines: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => lines.push(args.join(" "));
  try {
    const { deps } = setup({
      consume: { data: null, error: { message: "db down" } },
    });
    await handleRecovery(post({ code: "ABCDE-FGHJK" }), deps);
  } finally {
    console.error = original;
  }
  assert(lines.length > 0);
  assert(lines.every((line) => !line.includes("ABCDE")));
});
