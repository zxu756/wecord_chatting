import { assert, assertEquals } from "jsr:@std/assert@1";
import { type AiDeps, handleAiRequest } from "./handler.ts";

const conversation = "11111111-2222-3333-4444-555555555555";
const env = {
  AI_BASE_URL: "https://api.deepseek.com/v1",
  AI_API_KEY: "sk-test",
  AI_MODEL: "deepseek-chat",
  AI_DAILY_LIMIT_PER_USER: "2",
} as Record<string, string>;

interface Calls {
  providerBodies: unknown[];
  consumed: number;
  refunded: number;
  loaded: unknown[];
}

function setup(
  overrides: Partial<AiDeps> = {},
  secrets: Record<string, string> = env,
  provider: () => Response = () =>
    new Response(
      JSON.stringify({ choices: [{ message: { content: "- Ana asked." } }] }),
    ),
) {
  const calls: Calls = {
    providerBodies: [],
    consumed: 0,
    refunded: 0,
    loaded: [],
  };
  let used = 0;
  const deps: AiDeps = {
    env: (name) => secrets[name],
    fetch: (_url, init) => {
      calls.providerBodies.push(JSON.parse(init!.body as string));
      return Promise.resolve(provider());
    },
    authenticate: (header) =>
      Promise.resolve(header === "Bearer good" ? "user-1" : null),
    loadMessages: (options) => {
      calls.loaded.push(options);
      return Promise.resolve({
        messages: [
          {
            id: "m1",
            sender: "Ana",
            type: "text",
            body: "hello?",
            createdAt: "2026-01-01T00:00:00Z",
          },
        ],
        total: 1,
        firstMessageId: "m1",
        recent: options.recent,
      });
    },
    circleAllows: () => Promise.resolve(true),
    consume: (_user, limit) => {
      if (used >= limit) {
        return Promise.resolve({ allowed: false, used });
      }
      used++;
      calls.consumed++;
      return Promise.resolve({ allowed: true, used });
    },
    refund: () => {
      used--;
      calls.refunded++;
      return Promise.resolve();
    },
    usedToday: () => Promise.resolve(used),
    guardClaim: () => Promise.resolve(null),
    guardConsume: () => Promise.resolve({ allowed: true, used: 1 }),
    guardRefund: () => Promise.resolve(),
    guardFinish: () => Promise.resolve(null),
    ...overrides,
  };
  return { deps, calls };
}

function post(body: unknown, authorization = "Bearer good") {
  return new Request("https://example.test/ai", {
    method: "POST",
    headers: { Authorization: authorization },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

async function read(response: Response) {
  return { status: response.status, body: await response.json() };
}

Deno.test("signed-out and invalid requests are refused", async () => {
  const { deps } = setup();
  const noAuth = new Request("https://example.test/ai", {
    method: "POST",
    body: "{}",
  });
  assertEquals((await handleAiRequest(noAuth, deps)).status, 401);
  assertEquals(
    (await handleAiRequest(post({ action: "status" }, "Bearer bad"), deps))
      .status,
    401,
  );
  assertEquals((await handleAiRequest(post("nope"), deps)).status, 400);
  assertEquals(
    (await handleAiRequest(post({ action: "fly" }), deps)).status,
    400,
  );
  assertEquals(
    (await handleAiRequest(
      new Request("https://example.test/ai", { method: "GET" }),
      deps,
    )).status,
    405,
  );
});

Deno.test("missing configuration gives 503 ai_not_configured", async () => {
  for (const secrets of [{}, { ...env, AI_API_KEY: "" }]) {
    const { deps, calls } = setup({}, secrets);
    for (
      const body of [
        { action: "status" },
        { action: "translate", text: "hola", target: "en" },
        { action: "summarize", conversation_id: conversation },
      ]
    ) {
      const result = await read(await handleAiRequest(post(body), deps));
      assertEquals(result.status, 503);
      assertEquals(result.body.error, "ai_not_configured");
    }
    assertEquals(calls.providerBodies.length, 0);
    assertEquals(calls.consumed, 0);
  }
});

Deno.test("status reports the limit and today's use without counting", async () => {
  const { deps, calls } = setup();
  const result = await read(
    await handleAiRequest(post({ action: "status" }), deps),
  );
  assertEquals(result.status, 200);
  assertEquals(result.body, { configured: true, daily_limit: 2, used: 0 });
  assertEquals(calls.consumed, 0);
});

Deno.test("summarize reads the chat as the caller and asks the model", async () => {
  const { deps, calls } = setup();
  const result = await read(
    await handleAiRequest(
      post({
        action: "summarize",
        conversation_id: conversation,
        after_message_id: null,
        language: "zh",
      }),
      deps,
    ),
  );
  assertEquals(result.status, 200);
  assertEquals(result.body.summary, "- Ana asked.");
  assertEquals(result.body.message_count, 1);
  assertEquals(result.body.first_message_id, "m1");
  const load = calls.loaded[0] as Record<string, unknown>;
  assertEquals(load.userId, "user-1");
  assertEquals(load.limit, 400);
  const sent = calls.providerBodies[0] as {
    messages: { content: string }[];
    stream: boolean;
  };
  assertEquals(sent.stream, false);
  assert(sent.messages[0].content.includes("Simplified Chinese"));
  assert(sent.messages[1].content.includes("Ana: hello?"));
  assertEquals(calls.consumed, 1);
});

Deno.test("nothing to summarize does not use a request", async () => {
  const { deps, calls } = setup({
    loadMessages: () =>
      Promise.resolve({
        messages: [],
        total: 0,
        firstMessageId: null,
        recent: false,
      }),
  });
  const result = await read(
    await handleAiRequest(
      post({ action: "summarize", conversation_id: conversation }),
      deps,
    ),
  );
  assertEquals(result.body.summary, null);
  assertEquals(result.body.message_count, 0);
  assertEquals(calls.consumed, 0);
  assertEquals(calls.providerBodies.length, 0);
});

Deno.test("a conversation the caller cannot see is 404", async () => {
  const { deps } = setup({ loadMessages: () => Promise.resolve(null) });
  const result = await read(
    await handleAiRequest(
      post({ action: "summarize", conversation_id: conversation }),
      deps,
    ),
  );
  assertEquals(result.status, 404);
});

Deno.test("the daily limit gives 429 ai_limit_reached and stops calling the model", async () => {
  const { deps, calls } = setup();
  const body = { action: "translate", text: "hola", target: "en" };
  assertEquals((await handleAiRequest(post(body), deps)).status, 200);
  assertEquals((await handleAiRequest(post(body), deps)).status, 200);
  const third = await read(await handleAiRequest(post(body), deps));
  assertEquals(third.status, 429);
  assertEquals(third.body, { error: "ai_limit_reached", limit: 2, used: 2 });
  assertEquals(calls.providerBodies.length, 2);
});

Deno.test("provider rate limits are 'busy', not our limit, and the request is given back", async () => {
  for (const status of [429, 402]) {
    const { deps, calls } = setup(
      {},
      env,
      () => new Response("{}", { status }),
    );
    const result = await read(
      await handleAiRequest(
        post({ action: "rewrite", mode: "fix", text: "helo" }),
        deps,
      ),
    );
    assertEquals(result.status, 503);
    assertEquals(result.body.error, "ai_busy");
    assertEquals(calls.refunded, 1);
  }
});

Deno.test("other provider failures are 502 ai_failed", async () => {
  const { deps, calls } = setup(
    {},
    env,
    () => new Response("{}", { status: 401 }),
  );
  const result = await read(
    await handleAiRequest(
      post({ action: "rewrite", mode: "fix", text: "helo" }),
      deps,
    ),
  );
  assertEquals(result.status, 502);
  assertEquals(result.body.error, "ai_failed");
  assertEquals(calls.refunded, 1);
});

Deno.test("a circle that turned AI off gives 403 and counts nothing", async () => {
  const { deps, calls } = setup({ circleAllows: () => Promise.resolve(false) });
  const result = await read(
    await handleAiRequest(
      post({
        action: "rewrite",
        mode: "fix",
        text: "helo",
        conversation_id: conversation,
      }),
      deps,
    ),
  );
  assertEquals(result.status, 403);
  assertEquals(result.body.error, "ai_disabled_in_circle");
  assertEquals(calls.consumed, 0);
});

Deno.test("text longer than the input limit is refused before counting", async () => {
  const { deps, calls } = setup({}, { ...env, AI_MAX_INPUT_CHARS: "2000" });
  const result = await read(
    await handleAiRequest(
      post({ action: "translate", text: "x".repeat(3000), target: "en" }),
      deps,
    ),
  );
  assertEquals(result.status, 413);
  assertEquals(calls.consumed, 0);
});

Deno.test("an error inside is a 500 with no details", async () => {
  const { deps } = setup({
    consume: () => Promise.reject(new Error("db down: secret detail")),
  });
  const result = await read(
    await handleAiRequest(
      post({ action: "translate", text: "hola", target: "en" }),
      deps,
    ),
  );
  assertEquals(result.status, 500);
  assertEquals(result.body, { error: "internal" });
});
