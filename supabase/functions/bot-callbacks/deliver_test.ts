import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  callbackBody,
  type Claimed,
  deliverOne,
  runCallbacks,
} from "./deliver.ts";
import { signBody } from "../_shared/sign.ts";
import { dohResolver, systemResolver } from "../_shared/dns.ts";

const item: Claimed = {
  interaction_id: "11111111-1111-4111-8111-111111111111",
  bot_id: "22222222-2222-4222-8222-222222222222",
  circle_id: "33333333-3333-4333-8333-333333333333",
  attempt: 1,
  url: "https://bots.example.com/hook",
  secret: "a".repeat(64),
  payload: {
    id: "11111111-1111-4111-8111-111111111111",
    type: "component",
    component: { id: "approve", type: "button", label: "Approve" },
    values: null,
    user: { id: "u", username: "ann", name: "Ann" },
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

Deno.test("a delivery is a signed POST of the interaction", async () => {
  const sent: Sent[] = [];
  const outcome = await deliverOne(item, {
    resolve: publicResolver,
    fetch: recorder(200, sent),
    now: () => 1700000000_500,
  });
  assertEquals(outcome, { delivered: true, status: 200, error: null });
  assertEquals(sent.length, 1);
  const { url, init } = sent[0];
  assertEquals(url, "https://bots.example.com/hook");
  assertEquals(init.method, "POST");
  assertEquals(init.redirect, "manual");
  assertEquals(init.credentials, "omit");
  assert(init.signal instanceof AbortSignal);
  const body = init.body as string;
  assertEquals(body, callbackBody(item));
  const parsed = JSON.parse(body);
  assertEquals(parsed.version, 1);
  assertEquals(parsed.type, "interaction");
  assertEquals(parsed.bot_id, item.bot_id);
  assertEquals(parsed.attempt, 1);
  assertEquals(parsed.interaction.component.id, "approve");
  const headers = init.headers as Record<string, string>;
  assertEquals(headers["X-WeCord-Timestamp"], "1700000000");
  assertEquals(headers["X-WeCord-Delivery"], item.interaction_id);
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
  assertEquals(await deliverOne(item, deps(404)), {
    delivered: false,
    status: 404,
    error: "http_404",
  });
  assertEquals(await deliverOne(item, deps(302)), {
    delivered: false,
    status: 302,
    error: "redirect_not_followed",
  });
  const throwing = (error: unknown) => ({
    resolve: publicResolver,
    fetch: (() => Promise.reject(error)) as typeof fetch,
    now: () => 0,
  });
  assertEquals(
    await deliverOne(item, throwing(new TypeError("connection refused"))),
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
      [
        "https://bots.example.com:8443/hook",
        publicResolver,
        "port_not_allowed",
      ],
      ["https://printer.local/hook", publicResolver, "inner_name"],
      [
        "https://rebind.example.com/hook",
        () => Promise.resolve(["169.254.169.254"]),
        "inner_address",
      ],
      [
        "https://rebind6.example.com/hook",
        () => Promise.resolve(["::ffff:10.0.0.1"]),
        "inner_address",
      ],
      [
        "https://nx.example.com/hook",
        () => Promise.reject(new Error("NotFound")),
        "dns_failed",
      ],
    ] as const
  ) {
    const outcome = await deliverOne({ ...item, url }, {
      resolve,
      fetch: recorder(200, sent),
      now: () => 0,
    });
    assertEquals(outcome, { delivered: false, status: null, error }, url);
  }
  assertEquals(sent.length, 0);
});

Deno.test("a payload over 16 KB is not sent", async () => {
  const sent: Sent[] = [];
  const outcome = await deliverOne(
    { ...item, payload: { values: { text: "x".repeat(20 * 1024) } } },
    { resolve: publicResolver, fetch: recorder(200, sent), now: () => 0 },
  );
  assertEquals(outcome.error, "payload_too_big");
  assertEquals(sent.length, 0);
});

Deno.test("claimed interactions are sent and each result is reported", async () => {
  const calls: { name: string; params: Record<string, unknown> }[] = [];
  const queue: Claimed[][] = [
    [
      item,
      { ...item, interaction_id: "i2", url: "https://down.example.com/hook" },
      { ...item, interaction_id: "i3", url: "https://127.0.0.1/hook" },
    ],
  ];
  const rpc = (name: string, params: Record<string, unknown>) => {
    calls.push({ name, params });
    return Promise.resolve({
      data: name === "claim_bot_callbacks" ? queue.shift() ?? [] : null,
      error: null,
    });
  };
  const fetcher = ((url: string | URL | Request) =>
    Promise.resolve(
      new Response(null, {
        status: String(url).includes("down.example.com") ? 503 : 204,
      }),
    )) as typeof fetch;
  const summary = await runCallbacks(rpc, {
    resolve: publicResolver,
    fetch: fetcher,
    now: () => 0,
  });
  assertEquals(summary, { claimed: 3, delivered: 1, failed: 2 });
  const finished = calls.filter((c) => c.name === "finish_bot_callback");
  assertEquals(finished.length, 3);
  const byId = Object.fromEntries(
    finished.map((c) => [c.params.target_interaction_id, c.params]),
  );
  assertEquals(byId[item.interaction_id], {
    target_interaction_id: item.interaction_id,
    delivered: true,
    http_status: 204,
    error_text: null,
  });
  assertEquals(byId["i2"].error_text, "http_503");
  assertEquals(byId["i3"].error_text, "ip_address");
  // One claim found fewer than a full batch, so it stopped there.
  assertEquals(calls.filter((c) => c.name === "claim_bot_callbacks").length, 1);
});

Deno.test("nothing due means no work, and a failed claim is an error", async () => {
  const empty = await runCallbacks(
    () => Promise.resolve({ data: [], error: null }),
    { resolve: publicResolver, fetch: recorder(200, []), now: () => 0 },
  );
  assertEquals(empty, { claimed: 0, delivered: 0, failed: 0 });
  let failed = false;
  try {
    await runCallbacks(
      () => Promise.resolve({ data: null, error: { message: "boom" } }),
      { resolve: publicResolver, fetch: recorder(200, []), now: () => 0 },
    );
  } catch {
    failed = true;
  }
  assert(failed);
});

Deno.test("DNS over HTTPS answers are read", async () => {
  const answers: Record<string, unknown> = {
    "good.example.com": {
      Status: 0,
      Answer: [
        { type: 5, data: "alias.example.net." },
        { type: 1, data: "93.184.216.34" },
      ],
    },
    "none.example.com": { Status: 0 },
    "gone.example.com": { Status: 3 },
    "broken.example.com": { Status: 2 },
  };
  const requests: string[] = [];
  const resolver = dohResolver(
    ((url: string | URL | Request) => {
      const parsed = new URL(String(url));
      requests.push(parsed.search);
      const answer = answers[parsed.searchParams.get("name") ?? ""];
      return Promise.resolve(
        answer
          ? new Response(JSON.stringify(answer))
          : new Response("no", { status: 500 }),
      );
    }) as typeof fetch,
  );
  assertEquals(await resolver("good.example.com", "A"), ["93.184.216.34"]);
  assertEquals(await resolver("good.example.com", "AAAA"), []);
  assertEquals(await resolver("none.example.com", "A"), []);
  assertEquals(await resolver("gone.example.com", "A"), []);
  let failed = 0;
  for (const host of ["broken.example.com", "other.example.com"]) {
    try {
      await resolver(host, "A");
    } catch {
      failed++;
    }
  }
  assertEquals(failed, 2);
  assert(requests[0].includes("type=A"));
});

Deno.test("the system resolver is used first and DNS over HTTPS only when it cannot be", async () => {
  const fallback = () => Promise.resolve(["fallback"]);
  const works = systemResolver(
    { resolveDns: () => Promise.resolve(["1.2.3.4"]) },
    fallback,
  );
  assertEquals(await works("a.example.com", "A"), ["1.2.3.4"]);
  const notFound = systemResolver(
    {
      resolveDns: () => {
        const error = new Error("no record");
        error.name = "NotFound";
        return Promise.reject(error);
      },
    },
    fallback,
  );
  assertEquals(await notFound("a.example.com", "AAAA"), []);
  const unsupported = systemResolver(
    { resolveDns: () => Promise.reject(new TypeError("not supported")) },
    fallback,
  );
  assertEquals(await unsupported("a.example.com", "A"), ["fallback"]);
  const missing = systemResolver({}, fallback);
  assertEquals(await missing("a.example.com", "A"), ["fallback"]);
});
