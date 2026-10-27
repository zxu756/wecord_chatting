import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  type Claimed,
  deliverOne,
  eventBody,
  MAX_BODY_BYTES,
  runEvents,
} from "./deliver.ts";
import { signBody } from "../_shared/sign.ts";

const item: Claimed = {
  delivery_id: "11111111-1111-4111-8111-111111111111",
  bot_id: "22222222-2222-4222-8222-222222222222",
  circle_id: "33333333-3333-4333-8333-333333333333",
  event: "message.created",
  attempt: 1,
  occurred_at: "2026-10-28T09:00:00Z",
  url: "https://bots.example.com/events",
  secret: "b".repeat(64),
  data: {
    chat: { id: "c1", kind: "channel", name: "general" },
    message: {
      id: "m1",
      type: "text",
      content: "hello",
      author: { id: "u", username: "ann", name: "Ann", is_bot: false },
    },
  },
};

const publicResolver = () => Promise.resolve(["93.184.216.34"]);

type Sent = { url: string; init: RequestInit };

function recorder(status: number, sent: Sent[]): typeof fetch {
  return ((url: string | URL | Request, init?: RequestInit) => {
    sent.push({ url: String(url), init: init ?? {} });
    return Promise.resolve(new Response(null, { status }));
  }) as typeof fetch;
}

Deno.test("an event is a signed POST with the kind in a header", async () => {
  const sent: Sent[] = [];
  const outcome = await deliverOne(item, {
    resolve: publicResolver,
    fetch: recorder(204, sent),
    now: () => 1700000000_500,
  });
  assertEquals(outcome, { delivered: true, status: 204, error: null });
  assertEquals(sent.length, 1);
  const { url, init } = sent[0];
  assertEquals(url, "https://bots.example.com/events");
  assertEquals(init.method, "POST");
  assertEquals(init.redirect, "manual");
  assertEquals(init.credentials, "omit");
  assert(init.signal instanceof AbortSignal);
  const body = init.body as string;
  assertEquals(body, eventBody(item));
  const parsed = JSON.parse(body);
  assertEquals(parsed.version, 1);
  assertEquals(parsed.type, "event");
  assertEquals(parsed.event, "message.created");
  assertEquals(parsed.event_id, item.delivery_id);
  assertEquals(parsed.bot_id, item.bot_id);
  assertEquals(parsed.circle_id, item.circle_id);
  assertEquals(parsed.attempt, 1);
  assertEquals(parsed.data.message.content, "hello");
  const headers = init.headers as Record<string, string>;
  assertEquals(headers["X-WeCord-Timestamp"], "1700000000");
  assertEquals(headers["X-WeCord-Delivery"], item.delivery_id);
  assertEquals(headers["X-WeCord-Event"], "message.created");
  assertEquals(
    headers["X-WeCord-Signature"],
    await signBody(item.secret, 1700000000, body),
  );
  // The secret itself never travels.
  assertFalse(JSON.stringify(headers).includes(item.secret));
  assertFalse(body.includes(item.secret));
});

Deno.test("a bad status, a redirect or a failure is a failed delivery with a short code", async () => {
  const deps = (status: number) => ({
    resolve: publicResolver,
    fetch: recorder(status, []),
    now: () => 0,
  });
  assertEquals(await deliverOne(item, deps(500)), {
    delivered: false,
    status: 500,
    error: "http_500",
  });
  assertEquals(await deliverOne(item, deps(301)), {
    delivered: false,
    status: 301,
    error: "redirect_not_followed",
  });
  const throwing = (error: unknown) => ({
    resolve: publicResolver,
    fetch: (() => Promise.reject(error)) as typeof fetch,
    now: () => 0,
  });
  assertEquals(
    await deliverOne(item, throwing(new TypeError("refused"))),
    { delivered: false, status: null, error: "network_error" },
  );
  assertEquals(
    await deliverOne(
      item,
      throwing(new DOMException("timed out", "TimeoutError")),
    ),
    { delivered: false, status: null, error: "timeout" },
  );
});

Deno.test("nothing is sent to an inner address, even through a public-looking name", async () => {
  const sent: Sent[] = [];
  for (
    const [url, resolve, error] of [
      ["https://127.0.0.1/hook", publicResolver, "ip_address"],
      ["http://bots.example.com/hook", publicResolver, "not_https"],
      ["https://printer.local/hook", publicResolver, "inner_name"],
      [
        "https://rebind.example.com/hook",
        () => Promise.resolve(["169.254.169.254"]),
        "inner_address",
      ],
      [
        "https://rebind6.example.com/hook",
        () => Promise.resolve(["fd00::1"]),
        "inner_address",
      ],
    ] as const
  ) {
    const outcome = await deliverOne({ ...item, url }, {
      resolve,
      fetch: recorder(200, sent),
      now: () => 0,
    });
    assertEquals(outcome.delivered, false, url);
    assertEquals(outcome.error, error, url);
  }
  assertEquals(sent.length, 0);
});

Deno.test("a body over 16 KB is not sent", async () => {
  const sent: Sent[] = [];
  const big: Claimed = {
    ...item,
    data: { text: "x".repeat(MAX_BODY_BYTES) },
  };
  const outcome = await deliverOne(big, {
    resolve: publicResolver,
    fetch: recorder(200, sent),
    now: () => 0,
  });
  assertEquals(outcome, {
    delivered: false,
    status: null,
    error: "payload_too_big",
  });
  assertEquals(sent.length, 0);
});

Deno.test("a run claims, sends and reports every delivery once", async () => {
  const calls: { name: string; params: Record<string, unknown> }[] = [];
  let claims = 0;
  const rpc = (name: string, params: Record<string, unknown>) => {
    calls.push({ name, params });
    if (name === "claim_bot_events") {
      claims++;
      return Promise.resolve({
        data: claims === 1
          ? [
            item,
            { ...item, delivery_id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd" },
          ]
          : [],
        error: null,
      });
    }
    return Promise.resolve({ data: null, error: null });
  };
  let n = 0;
  const fetcher = (() => {
    n++;
    return Promise.resolve(new Response(null, { status: n === 1 ? 200 : 500 }));
  }) as typeof fetch;
  const summary = await runEvents(rpc, {
    resolve: publicResolver,
    fetch: fetcher,
    now: () => 0,
  });
  assertEquals(summary, { claimed: 2, delivered: 1, failed: 1 });
  const finished = calls.filter((c) => c.name === "finish_bot_event");
  assertEquals(finished.length, 2);
  assertEquals(
    finished.map((c) => c.params["delivered"]).sort(),
    [false, true],
  );
  // A failure reports a short code, not what the other side said.
  assertEquals(
    finished.find((c) => c.params["delivered"] === false)?.params["error_text"],
    "http_500",
  );
});

Deno.test("a failed claim is an error, not an empty run", async () => {
  let thrown = false;
  try {
    await runEvents(
      () => Promise.resolve({ data: null, error: { message: "boom" } }),
      { resolve: publicResolver, fetch: recorder(200, []), now: () => 0 },
    );
  } catch {
    thrown = true;
  }
  assert(thrown);
});
