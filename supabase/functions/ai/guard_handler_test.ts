import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  type AiDeps,
  GUARD_TIMEOUT_MS,
  type GuardClaim,
  type GuardResult,
  handleAiRequest,
  isDispatchAuthorized,
} from "./handler.ts";

const messageId = "11111111-2222-3333-4444-555555555555";
const circleId = "99999999-2222-3333-4444-555555555555";
const secret = "dispatch-secret";
const env = {
  AI_BASE_URL: "https://api.deepseek.com/v1",
  AI_API_KEY: "sk-test",
  AI_MODEL: "deepseek-chat",
  AI_DAILY_LIMIT_PER_USER: "1",
  AI_GUARD_DAILY_LIMIT_PER_CIRCLE: "2",
  DISPATCH_SECRET: secret,
} as Record<string, string>;

interface Calls {
  providerBodies: { messages: { content: string }[]; temperature: number }[];
  providerSignals: (AbortSignal | null | undefined)[];
  claimed: string[];
  consumed: { circleId: string; limit: number }[];
  refunded: string[];
  finished: { messageId: string; result: GuardResult }[];
  authenticated: number;
  userConsumed: number;
}

function setup(
  options: {
    claim?: GuardClaim | null;
    secrets?: Record<string, string>;
    provider?: () => Response | Promise<Response>;
    allowed?: boolean;
    finishFails?: boolean;
    overrides?: Partial<AiDeps>;
  } = {},
) {
  const calls: Calls = {
    providerBodies: [],
    providerSignals: [],
    claimed: [],
    consumed: [],
    refunded: [],
    finished: [],
    authenticated: 0,
    userConsumed: 0,
  };
  const claim = options.claim === undefined
    ? { circleId, body: "Win cheap pills https://evil.test", aiEnabled: true }
    : options.claim;
  const deps: AiDeps = {
    env: (name) => (options.secrets ?? env)[name],
    fetch: async (_url, init) => {
      calls.providerBodies.push(JSON.parse(init!.body as string));
      calls.providerSignals.push(init!.signal);
      return await (options.provider ??
        (() =>
          new Response(
            JSON.stringify({
              choices: [{
                message: {
                  content: '{"category":"spam","reason":"Sells pills"}',
                },
              }],
            }),
          )))();
    },
    authenticate: () => {
      calls.authenticated++;
      return Promise.resolve(null);
    },
    loadMessages: () => Promise.resolve(null),
    circleAllows: () => Promise.resolve(true),
    consume: () => {
      calls.userConsumed++;
      return Promise.resolve({ allowed: true, used: 1 });
    },
    refund: () => Promise.resolve(),
    usedToday: () => Promise.resolve(0),
    guardClaim: (id) => {
      calls.claimed.push(id);
      return Promise.resolve(claim);
    },
    guardConsume: (circle, limit) => {
      calls.consumed.push({ circleId: circle, limit });
      return Promise.resolve({
        allowed: options.allowed ?? true,
        used: 1,
      });
    },
    guardRefund: (circle) => {
      calls.refunded.push(circle);
      return Promise.resolve();
    },
    guardFinish: (id, result) => {
      if (options.finishFails) {
        return Promise.reject(new Error("database down"));
      }
      calls.finished.push({ messageId: id, result });
      return Promise.resolve(
        result.verdict && result.verdict.category !== "allow"
          ? "held"
          : "released",
      );
    },
    ...options.overrides,
  };
  return { deps, calls };
}

function guardRequest(
  authorization: string | null = `Bearer ${secret}`,
  body: unknown = { action: "guard", message_id: messageId },
) {
  return new Request("https://example.test/ai", {
    method: "POST",
    headers: authorization === null ? {} : { Authorization: authorization },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

async function read(response: Response) {
  return { status: response.status, body: await response.json() };
}

Deno.test("the shared secret is compared exactly", () => {
  assert(isDispatchAuthorized("Bearer s3", "s3"));
  assert(!isDispatchAuthorized("Bearer s3 ", "s3"));
  assert(!isDispatchAuthorized("Bearer s", "s3"));
  assert(!isDispatchAuthorized("s3", "s3"));
  assert(!isDispatchAuthorized(null, "s3"));
  // Not configured: nothing matches, not even an empty bearer.
  assert(!isDispatchAuthorized("Bearer ", ""));
});

Deno.test("a flagged message is handed in with its category and reason", async () => {
  const { deps, calls } = setup();
  const result = await read(await handleAiRequest(guardRequest(), deps));
  assertEquals(result.status, 200);
  assertEquals(result.body, { ok: true, state: "held", category: "spam" });
  assertEquals(calls.claimed, [messageId]);
  assertEquals(calls.finished, [{
    messageId,
    result: { verdict: { category: "spam", reason: "Sells pills" } },
  }]);
  assertEquals(calls.refunded, []);
});

Deno.test("only the text and the link hosts reach the model, at temperature 0", async () => {
  const { deps, calls } = setup();
  await handleAiRequest(guardRequest(), deps);
  assertEquals(calls.providerBodies.length, 1);
  const [body] = calls.providerBodies;
  assertEquals(body.temperature, 0);
  const user = body.messages[1].content;
  assert(user.includes("Win cheap pills https://evil.test"));
  assert(user.includes("<link_domains>\nevil.test\n</link_domains>"));
  assert(!user.includes(messageId));
  assert(!user.includes(circleId));
});

Deno.test("an allowed message is released", async () => {
  const { deps, calls } = setup({
    provider: () =>
      new Response(
        JSON.stringify({
          choices: [{ message: { content: '{"category":"allow"}' } }],
        }),
      ),
  });
  const result = await read(await handleAiRequest(guardRequest(), deps));
  assertEquals(result.body.state, "released");
  assertEquals(calls.finished[0].result.verdict?.category, "allow");
});

Deno.test("the request is charged to the circle with the circle's limit, not to a user", async () => {
  const { deps, calls } = setup();
  await handleAiRequest(guardRequest(), deps);
  assertEquals(calls.consumed, [{ circleId, limit: 2 }]);
  assertEquals(calls.userConsumed, 0);
  assertEquals(calls.authenticated, 0);
});

Deno.test("the circle's limit releases the message, not checked, without asking the model", async () => {
  const { deps, calls } = setup({ allowed: false });
  const result = await read(await handleAiRequest(guardRequest(), deps));
  assertEquals(result.status, 200);
  assertEquals(calls.providerBodies.length, 0);
  assertEquals(calls.finished[0].result, { unchecked: "limit" });
});

Deno.test("AI not configured releases the message, not checked", async () => {
  const { deps, calls } = setup({
    secrets: { DISPATCH_SECRET: secret, AI_BASE_URL: "https://x.test" },
  });
  const result = await read(await handleAiRequest(guardRequest(), deps));
  assertEquals(result.status, 200);
  assertEquals(calls.consumed.length, 0);
  assertEquals(calls.finished[0].result, { unchecked: "not_configured" });
});

Deno.test("a circle that turned AI off releases the message, not checked", async () => {
  const { deps, calls } = setup({
    claim: { circleId, body: "hello", aiEnabled: false },
  });
  await handleAiRequest(guardRequest(), deps);
  assertEquals(calls.providerBodies.length, 0);
  assertEquals(calls.consumed.length, 0);
  assertEquals(calls.finished[0].result, { unchecked: "ai_off" });
});

Deno.test("provider failures release the message and give the request back", async () => {
  const cases: [() => Response, "error" | "limit"][] = [
    [() => new Response("boom", { status: 500 }), "error"],
    [() => new Response("slow down", { status: 429 }), "limit"],
    [
      () => new Response(JSON.stringify({ choices: [] }), { status: 200 }),
      "error",
    ],
  ];
  for (const [provider, unchecked] of cases) {
    const { deps, calls } = setup({ provider });
    const result = await read(await handleAiRequest(guardRequest(), deps));
    assertEquals(result.status, 200);
    assertEquals(calls.finished[0].result, { unchecked });
    assertEquals(calls.refunded, [circleId]);
  }
});

Deno.test("an answer that is not a verdict releases the message, not checked", async () => {
  const { deps, calls } = setup({
    provider: () =>
      new Response(
        JSON.stringify({
          choices: [{ message: { content: "This looks fine to me." } }],
        }),
      ),
  });
  await handleAiRequest(guardRequest(), deps);
  assertEquals(calls.finished[0].result, { unchecked: "error" });
  assertEquals(calls.refunded, [circleId]);
});

Deno.test("a provider that does not answer in time releases the message", async () => {
  const { deps, calls } = setup({
    provider: () => new Promise<Response>(() => {}),
    overrides: {
      fetch: (_url, init) =>
        new Promise<Response>((_resolve, reject) => {
          calls.providerSignals.push(init!.signal);
          init!.signal!.addEventListener(
            "abort",
            () => reject(new DOMException("aborted", "AbortError")),
          );
        }),
    },
  });
  // Fast-forward the 15 second wait.
  const realSetTimeout = globalThis.setTimeout;
  const waits: number[] = [];
  globalThis.setTimeout = ((fn: () => void, ms?: number) => {
    waits.push(ms ?? 0);
    return realSetTimeout(fn, 0);
  }) as typeof setTimeout;
  try {
    const result = await read(await handleAiRequest(guardRequest(), deps));
    assertEquals(result.status, 200);
  } finally {
    globalThis.setTimeout = realSetTimeout;
  }
  assert(waits.includes(GUARD_TIMEOUT_MS));
  assertEquals(calls.finished[0].result, { unchecked: "timeout" });
  assertEquals(calls.refunded, [circleId]);
});

Deno.test("a message that is not waiting is skipped", async () => {
  const { deps, calls } = setup({ claim: null });
  const result = await read(await handleAiRequest(guardRequest(), deps));
  assertEquals(result.body, { ok: true, skipped: true });
  assertEquals(calls.providerBodies.length, 0);
  assertEquals(calls.finished.length, 0);
});

Deno.test("when the hand-in itself fails the answer is 500 and the sweep releases it", async () => {
  const { deps } = setup({ finishFails: true });
  const result = await read(await handleAiRequest(guardRequest(), deps));
  assertEquals(result.status, 500);
});

Deno.test("only the shared secret may ask for a check", async () => {
  // A wrong secret, no header, and a signed-in user's token all fail.
  const { deps, calls } = setup();
  for (const header of [`Bearer wrong`, null, "Bearer good-user"]) {
    const response = await handleAiRequest(guardRequest(header), deps);
    assert(response.status === 401 || response.status === 403);
  }
  assertEquals(calls.claimed.length, 0);

  // A signed-in user asking for the guard is refused.
  const { deps: userDeps, calls: userCalls } = setup({
    overrides: { authenticate: () => Promise.resolve("user-1") },
  });
  const response = await handleAiRequest(
    guardRequest("Bearer good-user"),
    userDeps,
  );
  assertEquals(response.status, 403);
  assertEquals(userCalls.claimed.length, 0);
  assertEquals(userCalls.providerBodies.length, 0);
});

Deno.test("without DISPATCH_SECRET configured nothing is accepted as the secret", async () => {
  const { deps, calls } = setup({
    secrets: { ...env, DISPATCH_SECRET: "" },
  });
  const response = await handleAiRequest(guardRequest("Bearer "), deps);
  assertEquals(response.status, 401);
  assertEquals(calls.claimed.length, 0);
});

Deno.test("the secret cannot be used for the user features", async () => {
  const { deps, calls } = setup();
  const response = await handleAiRequest(
    guardRequest(`Bearer ${secret}`, {
      action: "translate",
      text: "hola",
      target: "en",
    }),
    deps,
  );
  assertEquals(response.status, 400);
  assertEquals(calls.providerBodies.length, 0);
});

Deno.test("a bad guard body is refused", async () => {
  const { deps } = setup();
  assertEquals(
    (await handleAiRequest(guardRequest(`Bearer ${secret}`, "nope"), deps))
      .status,
    400,
  );
  assertEquals(
    (await handleAiRequest(
      guardRequest(`Bearer ${secret}`, { action: "guard", message_id: "x" }),
      deps,
    )).status,
    400,
  );
});
