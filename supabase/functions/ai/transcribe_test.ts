import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { type AiDeps, handleAiRequest, type VoiceMessage } from "./handler.ts";
import { ProviderError } from "./provider.ts";
import {
  audioFileName,
  extractTranscript,
  MAX_AUDIO_BYTES,
  readTranscribeConfig,
  transcribeAudio,
  transcriptionsUrl,
} from "./transcribe.ts";

const message = "11111111-2222-3333-4444-555555555555";
const conversation = "66666666-7777-8888-9999-000000000000";

const env = {
  AI_BASE_URL: "https://api.deepseek.com/v1",
  AI_API_KEY: "sk-test",
  AI_MODEL: "deepseek-chat",
  AI_DAILY_LIMIT_PER_USER: "2",
  AI_TRANSCRIBE_BASE_URL: "https://api.openai.com/v1/",
  AI_TRANSCRIBE_API_KEY: " sk-speech ",
  AI_TRANSCRIBE_MODEL: "whisper-1",
} as Record<string, string>;

const get = (values: Record<string, string>) => (name: string) => values[name];

Deno.test("the three optional secrets configure transcription", () => {
  assertEquals(readTranscribeConfig(get(env)), {
    baseUrl: "https://api.openai.com/v1",
    apiKey: "sk-speech",
    model: "whisper-1",
  });
});

Deno.test("a missing, blank or unsafe transcribe secret means not configured", () => {
  for (
    const name of [
      "AI_TRANSCRIBE_BASE_URL",
      "AI_TRANSCRIBE_API_KEY",
      "AI_TRANSCRIBE_MODEL",
    ]
  ) {
    const without = { ...env };
    delete without[name];
    assertEquals(readTranscribeConfig(get(without)), null, `${name} missing`);
    assertEquals(
      readTranscribeConfig(get({ ...env, [name]: "  " })),
      null,
      `${name} blank`,
    );
  }
  assertEquals(
    readTranscribeConfig(
      get({ ...env, AI_TRANSCRIBE_BASE_URL: "http://example.com/v1" }),
    ),
    null,
  );
});

Deno.test("the URL, file name and answer are read the OpenAI way", () => {
  assertEquals(
    transcriptionsUrl("https://api.openai.com/v1"),
    "https://api.openai.com/v1/audio/transcriptions",
  );
  assertEquals(audioFileName("audio/wav", "c/x.bin"), "voice.wav");
  assertEquals(audioFileName("audio/mp4; codecs=mp4a", "c/x"), "voice.m4a");
  assertEquals(
    audioFileName("application/octet-stream", "c/x.OGG"),
    "voice.ogg",
  );
  assertEquals(audioFileName("", "c/x"), "voice.wav");
  assertEquals(extractTranscript({ text: "  hello " }), "hello");
  assertEquals(extractTranscript({ text: "" }), "");
  assertEquals(extractTranscript({}), null);
  assertEquals(extractTranscript(null), null);
});

Deno.test("transcribeAudio posts a multipart file with the key and model", async () => {
  let seen: { url: string; init: RequestInit } | null = null;
  const text = await transcribeAudio(
    { baseUrl: "https://api.openai.com/v1", apiKey: "sk", model: "whisper-1" },
    {
      bytes: new Uint8Array([1, 2, 3]),
      mimeType: "audio/wav",
      fileName: "voice.wav",
    },
    (url, init) => {
      seen = { url, init: init! };
      return Promise.resolve(
        new Response(JSON.stringify({ text: "hi there" })),
      );
    },
  );
  assertEquals(text, "hi there");
  assertEquals(seen!.url, "https://api.openai.com/v1/audio/transcriptions");
  const headers = seen!.init.headers as Record<string, string>;
  assertEquals(headers["Authorization"], "Bearer sk");
  assert(!("Content-Type" in headers));
  const form = seen!.init.body as FormData;
  assertEquals(form.get("model"), "whisper-1");
  const file = form.get("file") as File;
  assertEquals(file.name, "voice.wav");
  assertEquals(file.size, 3);
});

Deno.test("transcribeAudio maps provider failures", async () => {
  const config = { baseUrl: "https://x.test/v1", apiKey: "k", model: "m" };
  const audio = {
    bytes: new Uint8Array(1),
    mimeType: "audio/wav",
    fileName: "v.wav",
  };
  const failWith = (status: number) =>
    assertRejects(
      () =>
        transcribeAudio(
          config,
          audio,
          () => Promise.resolve(new Response("{}", { status })),
        ),
      ProviderError,
    ).then((error) => error.kind);
  assertEquals(await failWith(429), "busy");
  assertEquals(await failWith(402), "busy");
  assertEquals(await failWith(401), "failed");
  const network = await assertRejects(
    () => transcribeAudio(config, audio, () => Promise.reject(new Error("x"))),
    ProviderError,
  );
  assertEquals(network.kind, "failed");
});

interface Calls {
  consumed: number;
  refunded: number;
  providerCalls: number;
  downloads: string[];
}

function setup(
  overrides: Partial<AiDeps> = {},
  secrets: Record<string, string> = env,
  provider: () => Response = () =>
    new Response(JSON.stringify({ text: "hello" })),
) {
  const calls: Calls = {
    consumed: 0,
    refunded: 0,
    providerCalls: 0,
    downloads: [],
  };
  let used = 0;
  const voice: VoiceMessage = {
    conversationId: conversation,
    bucket: "voice-messages",
    path: `${conversation}/a.wav`,
    mimeType: "audio/wav",
    size: 1000,
  };
  const deps: AiDeps = {
    env: (name) => secrets[name],
    fetch: () => {
      calls.providerCalls++;
      return Promise.resolve(provider());
    },
    authenticate: (header) =>
      Promise.resolve(header === "Bearer good" ? "user-1" : null),
    loadMessages: () => Promise.resolve(null),
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
    loadVoiceMessage: () => Promise.resolve(voice),
    downloadAudio: (bucket, path) => {
      calls.downloads.push(`${bucket}/${path}`);
      return Promise.resolve(new Uint8Array(10));
    },
    ...overrides,
  };
  return { deps, calls };
}

function post(body: unknown) {
  return new Request("https://example.test/ai", {
    method: "POST",
    headers: { Authorization: "Bearer good" },
    body: JSON.stringify(body),
  });
}

async function read(response: Response) {
  return { status: response.status, body: await response.json() };
}

const request = { action: "transcribe", message_id: message };

Deno.test("transcribe reads the audio as the caller and returns the text", async () => {
  const { deps, calls } = setup();
  const result = await read(await handleAiRequest(post(request), deps));
  assertEquals(result.status, 200);
  assertEquals(result.body, { text: "hello" });
  assertEquals(calls.downloads, [`voice-messages/${conversation}/a.wav`]);
  assertEquals(calls.consumed, 1);
  assertEquals(calls.providerCalls, 1);
});

Deno.test("status says whether transcription is set up", async () => {
  for (
    const [secrets, expected] of [[env, true], [{
      ...env,
      AI_TRANSCRIBE_MODEL: "",
    }, false]] as const
  ) {
    const { deps } = setup({}, secrets);
    const result = await read(
      await handleAiRequest(post({ action: "status" }), deps),
    );
    assertEquals(result.body.transcribe_configured, expected);
  }
});

Deno.test("without the transcribe secrets: 503 transcribe_not_configured, nothing counted", async () => {
  const { AI_TRANSCRIBE_API_KEY: _key, ...without } = env;
  const { deps, calls } = setup({}, without);
  const result = await read(await handleAiRequest(post(request), deps));
  assertEquals(result.status, 503);
  assertEquals(result.body.error, "transcribe_not_configured");
  assertEquals(calls.consumed, 0);
  assertEquals(calls.downloads.length, 0);
});

Deno.test("without the main AI secrets it is still ai_not_configured", async () => {
  const { AI_API_KEY: _key, ...without } = env;
  const { deps } = setup({}, without);
  const result = await read(await handleAiRequest(post(request), deps));
  assertEquals(result.status, 503);
  assertEquals(result.body.error, "ai_not_configured");
});

Deno.test("a message the caller cannot see, or that is not a voice message, is 404", async () => {
  const { deps, calls } = setup({
    loadVoiceMessage: () => Promise.resolve(null),
  });
  const result = await read(await handleAiRequest(post(request), deps));
  assertEquals(result.status, 404);
  assertEquals(result.body.error, "message_not_found");
  assertEquals(calls.consumed, 0);
});

Deno.test("a bad message id is an invalid request", async () => {
  const { deps } = setup();
  for (const id of [undefined, null, "nope", 5]) {
    const result = await read(
      await handleAiRequest(
        post({ action: "transcribe", message_id: id }),
        deps,
      ),
    );
    assertEquals(result.status, 400);
  }
});

Deno.test("a circle that turned AI off is 403, from the message's own conversation", async () => {
  const asked: string[] = [];
  const { deps, calls } = setup({
    circleAllows: (_user, conversationId) => {
      asked.push(conversationId);
      return Promise.resolve(false);
    },
  });
  const result = await read(await handleAiRequest(post(request), deps));
  assertEquals(result.status, 403);
  assertEquals(result.body.error, "ai_disabled_in_circle");
  assertEquals(asked, [conversation]);
  assertEquals(calls.consumed, 0);
  assertEquals(calls.downloads.length, 0);
});

Deno.test("the daily limit applies to transcription too", async () => {
  const { deps, calls } = setup();
  assertEquals((await handleAiRequest(post(request), deps)).status, 200);
  assertEquals((await handleAiRequest(post(request), deps)).status, 200);
  const third = await read(await handleAiRequest(post(request), deps));
  assertEquals(third.status, 429);
  assertEquals(third.body.error, "ai_limit_reached");
  assertEquals(calls.providerCalls, 2);
});

Deno.test("provider failures give the request back", async () => {
  const busy = setup({}, env, () => new Response("{}", { status: 429 }));
  const busyResult = await read(
    await handleAiRequest(post(request), busy.deps),
  );
  assertEquals(busyResult.status, 503);
  assertEquals(busyResult.body.error, "ai_busy");
  assertEquals(busy.calls.refunded, 1);

  const broken = setup({}, env, () => new Response("{}", { status: 500 }));
  const brokenResult = await read(
    await handleAiRequest(post(request), broken.deps),
  );
  assertEquals(brokenResult.status, 502);
  assertEquals(brokenResult.body.error, "ai_failed");
  assertEquals(broken.calls.refunded, 1);

  const gone = setup({ downloadAudio: () => Promise.resolve(null) });
  const goneResult = await read(
    await handleAiRequest(post(request), gone.deps),
  );
  assertEquals(goneResult.status, 502);
  assertEquals(gone.calls.refunded, 1);
  assertEquals(gone.calls.providerCalls, 0);
});

Deno.test("audio over the provider's size limit is refused", async () => {
  const declared = setup({
    loadVoiceMessage: () =>
      Promise.resolve({
        conversationId: conversation,
        bucket: "b",
        path: "p",
        mimeType: "audio/wav",
        size: MAX_AUDIO_BYTES + 1,
      }),
  });
  const first = await read(await handleAiRequest(post(request), declared.deps));
  assertEquals(first.status, 413);
  assertEquals(first.body.error, "audio_too_long");
  assertEquals(declared.calls.consumed, 0);

  // A recorded size that lies is caught after the download.
  const lying = setup({
    downloadAudio: () => Promise.resolve(new Uint8Array(MAX_AUDIO_BYTES + 1)),
  });
  const second = await read(await handleAiRequest(post(request), lying.deps));
  assertEquals(second.status, 413);
  assertEquals(lying.calls.refunded, 1);
  assertEquals(lying.calls.providerCalls, 0);
});

Deno.test("silence comes back as empty text, not an error", async () => {
  const { deps } = setup(
    {},
    env,
    () => new Response(JSON.stringify({ text: "" })),
  );
  const result = await read(await handleAiRequest(post(request), deps));
  assertEquals(result.status, 200);
  assertEquals(result.body, { text: "" });
});
