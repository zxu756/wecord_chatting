import { assert, assertEquals } from "jsr:@std/assert@1";
import { type AiDeps, handleAiRequest } from "./handler.ts";
import {
  type Guard2Store,
  type GuardItemClaim,
  type GuardItemResult,
  type GuardMessageInfo,
  itemGuardText,
  pollGuardText,
  resetVisionRefusal,
  resetVisionSync,
  visionReady,
} from "./guard2.ts";
import { parseAiRequest } from "./request.ts";
import {
  guardImagePrompt,
  imageDataUrl,
  isVisionRefusal,
  readGuardImage,
  readVisionConfig,
} from "./vision.ts";
import { readAiConfig } from "./config.ts";
import { itemClaimFromRow, messageInfoFromRow } from "./guard2_store.ts";

const messageId = "11111111-2222-3333-4444-555555555555";
const reviewId = "aaaaaaaa-2222-3333-4444-555555555555";
const circleId = "99999999-2222-3333-4444-555555555555";
const secret = "dispatch-secret";
const baseEnv = {
  AI_BASE_URL: "https://api.example.com/v1",
  AI_API_KEY: "sk-test",
  AI_MODEL: "text-model",
  DISPATCH_SECRET: secret,
} as Record<string, string>;
const visionEnv: Record<string, string> = {
  ...baseEnv,
  AI_VISION_ENABLED: "true",
  AI_VISION_MODEL: "vision-model",
};

const png = new Uint8Array([137, 80, 78, 71, 1, 2, 3]);
const imageAttachment = {
  kind: "image",
  bucket: "chat-media",
  path: "conv/user/pic.png",
  mime_type: "image/png",
  size: 7,
};

interface Calls {
  providerBodies: {
    model: string;
    messages: { content: unknown }[];
  }[];
  finished: { messageId: string; result: unknown }[];
  consumed: string[];
  refunded: string[];
  visionConsumed: { circleId: string; limit: number }[];
  visionRefunded: string[];
  flags: { key: string; enabled: boolean }[];
  downloads: number;
  itemFinished: { reviewId: string; result: GuardItemResult }[];
}

function setup(options: {
  env?: Record<string, string>;
  info?: GuardMessageInfo | null;
  provider?: () => Response;
  visionAllowed?: boolean;
  bytes?: Uint8Array | null;
  itemClaim?: GuardItemClaim | null;
  textAllowed?: boolean;
} = {}) {
  const calls: Calls = {
    providerBodies: [],
    finished: [],
    consumed: [],
    refunded: [],
    visionConsumed: [],
    visionRefunded: [],
    flags: [],
    downloads: 0,
    itemFinished: [],
  };
  const guard2: Guard2Store = {
    messageInfo: () => Promise.resolve(options.info ?? null),
    downloadImage: () => {
      calls.downloads++;
      return Promise.resolve(options.bytes === undefined ? png : options.bytes);
    },
    visionConsume: (circle, limit) => {
      calls.visionConsumed.push({ circleId: circle, limit });
      return Promise.resolve({
        allowed: options.visionAllowed ?? true,
        used: 1,
      });
    },
    visionRefund: (circle) => {
      calls.visionRefunded.push(circle);
      return Promise.resolve();
    },
    setRuntimeFlag: (key, enabled) => {
      calls.flags.push({ key, enabled });
      return Promise.resolve();
    },
    itemClaim: () =>
      Promise.resolve(
        options.itemClaim === undefined
          ? {
            circleId,
            itemType: "circle_event",
            title: "Free prizes",
            detail: "Claim at http://scam.example/win",
            aiEnabled: true,
          }
          : options.itemClaim,
      ),
    itemFinish: (id, result) => {
      calls.itemFinished.push({ reviewId: id, result });
      return Promise.resolve(
        result.verdict && result.verdict.category !== "allow"
          ? "flagged"
          : "released",
      );
    },
  };
  const deps: AiDeps = {
    env: (name) => (options.env ?? baseEnv)[name],
    fetch: (_url, init) => {
      calls.providerBodies.push(JSON.parse(init!.body as string));
      return Promise.resolve(
        (options.provider ?? (() =>
          new Response(
            JSON.stringify({
              choices: [{
                message: {
                  content:
                    '{"category":"sexual","reason":"Nudity","reason_zh":"裸露"}',
                },
              }],
            }),
          )))(),
      );
    },
    authenticate: () => Promise.resolve(null),
    loadMessages: () => Promise.resolve(null),
    circleAllows: () => Promise.resolve(true),
    consume: () => Promise.resolve({ allowed: true, used: 1 }),
    refund: () => Promise.resolve(),
    usedToday: () => Promise.resolve(0),
    loadVoiceMessage: () => Promise.resolve(null),
    downloadAudio: () => Promise.resolve(null),
    guardClaim: () => Promise.resolve({ circleId, body: "", aiEnabled: true }),
    guardConsume: (circle) => {
      calls.consumed.push(circle);
      return Promise.resolve({ allowed: options.textAllowed ?? true, used: 1 });
    },
    guardRefund: (circle) => {
      calls.refunded.push(circle);
      return Promise.resolve();
    },
    guardFinish: (id, result) => {
      calls.finished.push({ messageId: id, result });
      return Promise.resolve(
        result.verdict && result.verdict.category !== "allow"
          ? "held"
          : "released",
      );
    },
    guard2,
  };
  return { deps, calls };
}

function dispatch(body: unknown) {
  return new Request("https://example.test/ai", {
    method: "POST",
    headers: { Authorization: `Bearer ${secret}` },
    body: JSON.stringify(body),
  });
}

async function run(deps: AiDeps, body: unknown) {
  const response = await handleAiRequest(dispatch(body), deps);
  return { status: response.status, body: await response.json() };
}

const guardMessage = { action: "guard", message_id: messageId };

function reset() {
  resetVisionRefusal();
  resetVisionSync();
}

// ------------------------------------------------------------------ polls

Deno.test("a poll is read as its question and its options", async () => {
  reset();
  const info: GuardMessageInfo = {
    type: "poll",
    body: "Best prize?",
    attachment: {
      kind: "poll",
      question: "Best prize?",
      options: [{ id: "a", text: "Cash" }, { id: "b", text: "Pills" }],
    },
  };
  assertEquals(
    pollGuardText(info),
    "Poll question and options:\nBest prize?\n- Cash\n- Pills",
  );
  const { deps, calls } = setup({
    info,
    provider: () =>
      new Response(
        JSON.stringify({
          choices: [{ message: { content: '{"category":"allow"}' } }],
        }),
      ),
  });
  const result = await run(deps, guardMessage);
  assertEquals(result.status, 200);
  assertEquals(result.body.state, "released");
  assertEquals(calls.consumed, [circleId]);
  const user = calls.providerBodies[0].messages[1].content as string;
  assert(user.includes("- Pills"));
  assertEquals(calls.providerBodies[0].model, "text-model");
  assertEquals(calls.visionConsumed, []);
});

// --------------------------------------------------------------- pictures

Deno.test("vision off: the picture is skipped and released, nothing is sent or counted", async () => {
  reset();
  const { deps, calls } = setup({
    info: { type: "image", body: "", attachment: imageAttachment },
  });
  const result = await run(deps, guardMessage);
  assertEquals(result.body, {
    ok: true,
    state: "released",
    unchecked: "vision_off",
  });
  assertEquals(calls.providerBodies, []);
  assertEquals(calls.consumed, []);
  assertEquals(calls.visionConsumed, []);
  assertEquals(calls.downloads, 0);
  assertEquals(calls.flags, [{ key: "vision", enabled: false }]);
});

Deno.test("vision on: the picture goes to the vision model as a data URL", async () => {
  reset();
  const { deps, calls } = setup({
    env: visionEnv,
    info: { type: "image", body: "", attachment: imageAttachment },
  });
  const result = await run(deps, guardMessage);
  assertEquals(result.body, { ok: true, state: "held", category: "sexual" });
  assertEquals(calls.finished[0].result, {
    verdict: { category: "sexual", reason: "Nudity", reasonZh: "裸露" },
  });
  assertEquals(calls.flags, [{ key: "vision", enabled: true }]);
  assertEquals(calls.visionConsumed, [{ circleId, limit: 100 }]);
  // The picture is charged apart from the circle's text checks.
  assertEquals(calls.consumed, []);
  const [request] = calls.providerBodies;
  assertEquals(request.model, "vision-model");
  const parts = request.messages[1].content as {
    type: string;
    image_url?: { url: string };
  }[];
  assertEquals(parts[1].type, "image_url");
  assert(parts[1].image_url!.url.startsWith("data:image/png;base64,"));
  assertEquals(
    parts[1].image_url!.url,
    imageDataUrl(png, "image/png"),
  );
  // No names, ids or captions with it.
  assert(!JSON.stringify(request).includes(circleId));
  assert(!JSON.stringify(request).includes(messageId));
});

Deno.test("an allowed picture is released", async () => {
  reset();
  const { deps } = setup({
    env: visionEnv,
    info: { type: "image", body: "", attachment: imageAttachment },
    provider: () =>
      new Response(
        JSON.stringify({
          choices: [{ message: { content: '{"category":"allow"}' } }],
        }),
      ),
  });
  const result = await run(deps, guardMessage);
  assertEquals(result.body.state, "released");
});

Deno.test("the vision model's own limit releases the picture unchecked", async () => {
  reset();
  const { deps, calls } = setup({
    env: { ...visionEnv, AI_VISION_DAILY_LIMIT_PER_CIRCLE: "7" },
    info: { type: "image", body: "", attachment: imageAttachment },
    visionAllowed: false,
  });
  const result = await run(deps, guardMessage);
  assertEquals(result.body.unchecked, "limit");
  assertEquals(calls.visionConsumed, [{ circleId, limit: 7 }]);
  assertEquals(calls.providerBodies, []);
});

Deno.test("a picture models do not read, or that cannot be read, is skipped and not counted", async () => {
  reset();
  const heic = setup({
    env: visionEnv,
    info: {
      type: "image",
      body: "",
      attachment: { ...imageAttachment, mime_type: "image/heic" },
    },
  });
  assertEquals(
    (await run(heic.deps, guardMessage)).body.unchecked,
    "image_unreadable",
  );
  assertEquals(heic.calls.visionConsumed, []);

  const missing = setup({
    env: visionEnv,
    info: { type: "image", body: "", attachment: imageAttachment },
    bytes: null,
  });
  assertEquals(
    (await run(missing.deps, guardMessage)).body.unchecked,
    "image_unreadable",
  );
  assertEquals(missing.calls.visionRefunded, [circleId]);
  assertEquals(missing.calls.providerBodies, []);

  const huge = setup({
    env: visionEnv,
    info: { type: "image", body: "", attachment: imageAttachment },
    bytes: new Uint8Array(4 * 1024 * 1024),
  });
  assertEquals(
    (await run(huge.deps, guardMessage)).body.unchecked,
    "image_unreadable",
  );
});

Deno.test("a model that refuses pictures releases the picture and turns vision off", async () => {
  reset();
  const { deps, calls } = setup({
    env: visionEnv,
    info: { type: "image", body: "", attachment: imageAttachment },
    provider: () => new Response("{}", { status: 400 }),
  });
  const first = await run(deps, guardMessage);
  assertEquals(first.body.unchecked, "vision_unsupported");
  assertEquals(calls.visionRefunded, [circleId]);
  assertEquals(calls.flags.at(-1), { key: "vision", enabled: false });
  assert(!visionReady(readAiConfig((n) => visionEnv[n])!, (n) => visionEnv[n]));

  // The next picture does not even ask the provider.
  const second = await run(deps, guardMessage);
  assertEquals(second.body.unchecked, "vision_off");
  assertEquals(calls.providerBodies.length, 1);
});

Deno.test("a busy or slow provider releases the picture unchecked and gives the count back", async () => {
  reset();
  const busy = setup({
    env: visionEnv,
    info: { type: "image", body: "", attachment: imageAttachment },
    provider: () => new Response("{}", { status: 429 }),
  });
  const result = await run(busy.deps, guardMessage);
  assertEquals(result.body.unchecked, "limit");
  assertEquals(busy.calls.visionRefunded, [circleId]);

  const broken = setup({
    env: visionEnv,
    info: { type: "image", body: "", attachment: imageAttachment },
    provider: () => new Response("{}", { status: 500 }),
  });
  assertEquals(
    (await run(broken.deps, guardMessage)).body.unchecked,
    "error",
  );
  // A server error is not a refusal of pictures.
  assert(visionReady(readAiConfig((n) => visionEnv[n])!, (n) => visionEnv[n]));

  const garbled = setup({
    env: visionEnv,
    info: { type: "image", body: "", attachment: imageAttachment },
    provider: () =>
      new Response(
        JSON.stringify({ choices: [{ message: { content: "no idea" } }] }),
      ),
  });
  assertEquals(
    (await run(garbled.deps, guardMessage)).body.unchecked,
    "error",
  );
  assertEquals(garbled.calls.visionRefunded, [circleId]);
});

Deno.test("text messages are not changed by any of this", async () => {
  reset();
  const { deps, calls } = setup({
    env: visionEnv,
    info: { type: "text", body: "hi", attachment: null },
    provider: () =>
      new Response(
        JSON.stringify({
          choices: [{ message: { content: '{"category":"allow"}' } }],
        }),
      ),
  });
  const result = await run(deps, guardMessage);
  assertEquals(result.body.state, "released");
  assertEquals(calls.consumed, [circleId]);
  assertEquals(calls.visionConsumed, []);
  assertEquals(calls.providerBodies[0].model, "text-model");
});

Deno.test("the vision settings: off by default, own model, own limit", () => {
  const config = readAiConfig((n) => baseEnv[n])!;
  assertEquals(readVisionConfig(config, (n) => baseEnv[n]), {
    enabled: false,
    model: "text-model",
    dailyLimit: 100,
  });
  for (const flag of ["true", "1", "YES", " on "]) {
    assert(
      readVisionConfig(
        config,
        (n) => ({ ...baseEnv, AI_VISION_ENABLED: flag })[n],
      )
        .enabled,
      flag,
    );
  }
  for (const flag of ["false", "0", "", "maybe"]) {
    assert(
      !readVisionConfig(
        config,
        (n) => ({ ...baseEnv, AI_VISION_ENABLED: flag })[n],
      ).enabled,
      flag,
    );
  }
  assertEquals(
    readVisionConfig(config, (n) => visionEnv[n]).model,
    "vision-model",
  );
});

Deno.test("only reads pictures it can send", () => {
  assertEquals(readGuardImage(imageAttachment)?.mimeType, "image/png");
  assertEquals(
    readGuardImage({ ...imageAttachment, mime_type: "IMAGE/JPEG; q=1" })
      ?.mimeType,
    "image/jpeg",
  );
  assertEquals(readGuardImage({ ...imageAttachment, kind: "file" }), null);
  assertEquals(readGuardImage({ ...imageAttachment, path: "" }), null);
  assertEquals(readGuardImage(null), null);
  assertEquals(readGuardImage([]), null);
  assert(isVisionRefusal(400) && isVisionRefusal(422));
  assert(!isVisionRefusal(500) && !isVisionRefusal(null));
});

Deno.test("the picture prompt treats the picture as untrusted data", () => {
  const messages = guardImagePrompt("data:image/png;base64,AAAA");
  const system = messages[0].content as string;
  assert(system.includes("untrusted DATA"));
  assert(system.includes("any text written in it"));
  assert(system.includes('"allow"'));
});

// ------------------------------------------------------------------ items

Deno.test("an event is classified like a message and handed in as the item's result", async () => {
  reset();
  const { deps, calls } = setup({
    provider: () =>
      new Response(
        JSON.stringify({
          choices: [{
            message: {
              content:
                '{"category":"scam","reason":"Fake prize","reason_zh":"虚假奖品"}',
            },
          }],
        }),
      ),
  });
  const result = await run(deps, { action: "guard_item", review_id: reviewId });
  assertEquals(result.body, { ok: true, state: "flagged", category: "scam" });
  assertEquals(calls.itemFinished, [{
    reviewId,
    result: {
      verdict: { category: "scam", reason: "Fake prize", reasonZh: "虚假奖品" },
    },
  }]);
  // Charged to the circle, like the guard of messages.
  assertEquals(calls.consumed, [circleId]);
  const user = calls.providerBodies[0].messages[1].content as string;
  assert(user.includes("Event: Free prizes"));
  assert(user.includes("scam.example"));
  assert(!user.includes(reviewId));
});

Deno.test("an item is released unchecked when AI is off, not configured, over the limit or failing", async () => {
  reset();
  const aiOff = setup({
    itemClaim: {
      circleId,
      itemType: "note",
      title: "x",
      detail: "",
      aiEnabled: false,
    },
  });
  assertEquals(
    (await run(aiOff.deps, { action: "guard_item", review_id: reviewId })).body
      .unchecked,
    "ai_off",
  );
  assertEquals(aiOff.calls.providerBodies, []);

  const notConfigured = setup({ env: { DISPATCH_SECRET: secret } });
  assertEquals(
    (await run(notConfigured.deps, {
      action: "guard_item",
      review_id: reviewId,
    })).body.unchecked,
    "not_configured",
  );

  const limited = setup({ textAllowed: false });
  assertEquals(
    (await run(limited.deps, { action: "guard_item", review_id: reviewId }))
      .body.unchecked,
    "limit",
  );

  const failing = setup({
    provider: () => new Response("{}", { status: 500 }),
  });
  const failed = await run(failing.deps, {
    action: "guard_item",
    review_id: reviewId,
  });
  assertEquals(failed.body.unchecked, "error");
  assertEquals(failing.calls.refunded, [circleId]);
});

Deno.test("an item that is gone or already taken is skipped", async () => {
  reset();
  const { deps, calls } = setup({ itemClaim: null });
  const result = await run(deps, { action: "guard_item", review_id: reviewId });
  assertEquals(result.body, { ok: true, skipped: true });
  assertEquals(calls.providerBodies, []);
});

Deno.test("a signed-in person cannot ask for an item check, and a bad id is refused", async () => {
  reset();
  const { deps } = setup();
  const signedIn = new Request("https://example.test/ai", {
    method: "POST",
    headers: { Authorization: "Bearer user-token" },
    body: JSON.stringify({ action: "guard_item", review_id: reviewId }),
  });
  deps.authenticate = () => Promise.resolve("user-1");
  assertEquals((await handleAiRequest(signedIn, deps)).status, 403);
  assertEquals(
    (await run(deps, { action: "guard_item", review_id: "nope" })).status,
    400,
  );
});

Deno.test("item text keeps the title and the details", () => {
  assertEquals(
    itemGuardText({
      circleId,
      itemType: "task_item",
      title: " Buy ",
      detail: "",
      aiEnabled: true,
    }),
    "Task: Buy",
  );
  assertEquals(
    itemGuardText({
      circleId,
      itemType: "note",
      title: "Plan",
      detail: "more",
      aiEnabled: true,
    }),
    "Note title: Plan\nDetails: more",
  );
});

Deno.test("the store reads the database's rows", () => {
  assertEquals(
    messageInfoFromRow([{ type: "poll", body: "Q", attachment: { a: 1 } }]),
    { type: "poll", body: "Q", attachment: { a: 1 } },
  );
  assertEquals(messageInfoFromRow([]), null);
  assertEquals(messageInfoFromRow(null), null);
  assertEquals(
    itemClaimFromRow([{
      circle_id: circleId,
      item_type: "note",
      title: "T",
      detail: null,
      ai_enabled: true,
    }]),
    { circleId, itemType: "note", title: "T", detail: "", aiEnabled: true },
  );
  assertEquals(itemClaimFromRow([]), null);
});

Deno.test("the new requests are read", () => {
  assertEquals(parseAiRequest({ action: "guard_item", review_id: reviewId }), {
    action: "guard_item",
    reviewId,
  });
  assertEquals(parseAiRequest({ action: "guard_item" }), null);
});

Deno.test("status tells the database whether pictures can be read", async () => {
  reset();
  const { deps, calls } = setup({ env: visionEnv });
  deps.authenticate = () => Promise.resolve("user-1");
  const status = new Request("https://example.test/ai", {
    method: "POST",
    headers: { Authorization: "Bearer user-token" },
    body: JSON.stringify({ action: "status" }),
  });
  assertEquals((await handleAiRequest(status, deps)).status, 200);
  assertEquals(calls.flags, [{ key: "vision", enabled: true }]);
  // And not again for every status call.
  const again = new Request("https://example.test/ai", {
    method: "POST",
    headers: { Authorization: "Bearer user-token" },
    body: JSON.stringify({ action: "status" }),
  });
  await handleAiRequest(again, deps);
  assertEquals(calls.flags.length, 1);
});
