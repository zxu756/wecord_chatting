import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import type { AiConfig } from "./config.ts";
import {
  buildProviderRequest,
  chatCompletionsUrl,
  complete,
  extractCompletion,
  isBusyStatus,
  isOpenCodeHost,
  ProviderError,
  sessionId,
  USER_AGENT,
} from "./provider.ts";

const config: AiConfig = {
  baseUrl: "https://api.deepseek.com/v1",
  apiKey: "sk-secret",
  model: "deepseek-chat",
  dailyLimit: 50,
  maxInputChars: 24000,
  extraHeaders: {},
};
const options = {
  messages: [{ role: "user" as const, content: "hi" }],
  maxTokens: 100,
  conversationKey: "conv-1",
  feature: "summary",
};

Deno.test("builds a non-streaming chat completions request", async () => {
  const { url, init } = await buildProviderRequest(config, options);
  assertEquals(url, "https://api.deepseek.com/v1/chat/completions");
  const headers = init.headers as Record<string, string>;
  assertEquals(headers["Authorization"], "Bearer sk-secret");
  assertEquals(headers["Content-Type"], "application/json");
  assertEquals(headers["User-Agent"], USER_AGENT);
  assert(USER_AGENT.startsWith("WeCord/1.0"));
  assertEquals("x-opencode-session" in headers, false);
  const body = JSON.parse(init.body as string);
  assertEquals(body.model, "deepseek-chat");
  assertEquals(body.stream, false);
  assertEquals(body.max_tokens, 100);
  assertEquals(body.messages, options.messages);
});

Deno.test("opencode.ai gets a stable session header per conversation and feature", async () => {
  const opencode = {
    ...config,
    baseUrl: "https://opencode.ai/inference/go/openai/v1",
  };
  const first = (await buildProviderRequest(opencode, options)).init
    .headers as Record<string, string>;
  const again = (await buildProviderRequest(opencode, options)).init
    .headers as Record<string, string>;
  const other = (await buildProviderRequest(opencode, {
    ...options,
    feature: "rewrite",
  })).init.headers as Record<string, string>;
  assert(/^[0-9a-f]{32}$/.test(first["x-opencode-session"]));
  assertEquals(first["x-opencode-session"], again["x-opencode-session"]);
  assert(first["x-opencode-session"] !== other["x-opencode-session"]);
  assertEquals(
    first["x-opencode-session"],
    await sessionId("conv-1", "summary"),
  );
  assertEquals(isOpenCodeHost("https://evil-opencode.ai/v1"), false);
  assertEquals(isOpenCodeHost("https://opencode.ai/v1"), true);
});

Deno.test("extra headers are added but never replace ours", async () => {
  const withExtra = { ...config, extraHeaders: { "x-team": "wecord" } };
  const headers = (await buildProviderRequest(withExtra, options)).init
    .headers as Record<string, string>;
  assertEquals(headers["x-team"], "wecord");
  assertEquals(headers["User-Agent"], USER_AGENT);
});

Deno.test("url joins the base and chat/completions", () => {
  assertEquals(
    chatCompletionsUrl("https://x.com/v1/"),
    "https://x.com/v1/chat/completions",
  );
});

Deno.test("rate and spend limit statuses are 'busy'", () => {
  for (const status of [429, 402, 503, 529]) {
    assertEquals(isBusyStatus(status), true, `${status}`);
  }
  for (const status of [400, 401, 404, 500]) {
    assertEquals(isBusyStatus(status), false, `${status}`);
  }
});

Deno.test("reads the answer text and drops reasoning blocks", () => {
  assertEquals(
    extractCompletion({ choices: [{ message: { content: " - a\n- b " } }] }),
    "- a\n- b",
  );
  assertEquals(
    extractCompletion({
      choices: [{ message: { content: "<think>hmm</think>\nanswer" } }],
    }),
    "answer",
  );
  assertEquals(
    extractCompletion({
      choices: [{ message: { content: [{ type: "text", text: "x" }] } }],
    }),
    "x",
  );
  assertEquals(extractCompletion({ choices: [] }), null);
  assertEquals(
    extractCompletion({ choices: [{ message: { content: " " } }] }),
    null,
  );
  assertEquals(extractCompletion(null), null);
});

function replying(status: number, body: unknown) {
  return () =>
    Promise.resolve(
      new Response(typeof body === "string" ? body : JSON.stringify(body), {
        status,
      }),
    );
}

Deno.test("complete returns text or throws a classified error", async () => {
  assertEquals(
    await complete(
      config,
      options,
      replying(200, { choices: [{ message: { content: "ok" } }] }),
    ),
    "ok",
  );
  const busy = await assertRejects(
    () => complete(config, options, replying(429, {})),
    ProviderError,
  );
  assertEquals(busy.kind, "busy");
  const payment = await assertRejects(
    () => complete(config, options, replying(402, {})),
    ProviderError,
  );
  assertEquals(payment.kind, "busy");
  const failed = await assertRejects(
    () => complete(config, options, replying(401, {})),
    ProviderError,
  );
  assertEquals(failed.kind, "failed");
  const empty = await assertRejects(
    () => complete(config, options, replying(200, { choices: [] })),
    ProviderError,
  );
  assertEquals(empty.kind, "empty");
  const network = await assertRejects(
    () => complete(config, options, () => Promise.reject(new Error("down"))),
    ProviderError,
  );
  assertEquals(network.kind, "failed");
});
