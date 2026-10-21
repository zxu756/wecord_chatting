import { assertEquals } from "jsr:@std/assert@1";
import type { RpcClient } from "./quiet_hours.ts";
import {
  FALLBACK_BODY,
  FALLBACK_TITLE,
  maskLockedPushes,
} from "./locked_chats.ts";

type Answer = { data: unknown; error: unknown } | "throw";

function client(answer: Answer): {
  admin: RpcClient;
  calls: Record<string, unknown>[];
} {
  const calls: Record<string, unknown>[] = [];
  return {
    calls,
    admin: {
      rpc(name, args) {
        calls.push({ name, ...args });
        if (answer === "throw") {
          throw new Error("down");
        }
        return Promise.resolve(answer);
      },
    },
  };
}

interface TestTarget {
  subscription_id: string;
  conversation_id: string | null;
  title: string;
  body: string;
  [key: string]: unknown;
}

const target = (
  subscription_id: string,
  conversation_id: string | null,
  extra: Record<string, unknown> = {},
): TestTarget => ({
  subscription_id,
  conversation_id,
  title: "Ada",
  body: "the secret plan",
  ...extra,
});

Deno.test("a push about a locked chat carries the words of the database", async () => {
  const { admin, calls } = client({
    data: [
      {
        subscription_id: "s1",
        conversation_id: "c1",
        title: "WeCord",
        body: "你收到一条新消息",
      },
    ],
    error: null,
  });
  const out = await maskLockedPushes(admin, [
    target("s1", "c1", { tag: "c1" }),
    target("s2", "c1"),
    target("s1", "c2"),
  ]);
  assertEquals(out[0], {
    subscription_id: "s1",
    conversation_id: "c1",
    title: "WeCord",
    body: "你收到一条新消息",
    tag: "c1",
  });
  // The same chat on a person's other subscription, and another chat on the
  // same subscription, keep their text.
  assertEquals(out[1].body, "the secret plan");
  assertEquals(out[2].body, "the secret plan");
  assertEquals(calls, [{
    name: "locked_chat_push_text",
    target_pairs: [
      { subscription_id: "s1", conversation_id: "c1" },
      { subscription_id: "s2", conversation_id: "c1" },
      { subscription_id: "s1", conversation_id: "c2" },
    ],
  }]);
});

Deno.test("pushes that are not about a chat are not looked up", async () => {
  const { admin, calls } = client({ data: [], error: null });
  const targets = [target("s1", null), target("s2", null)];
  const out = await maskLockedPushes(admin, targets);
  assertEquals(out, targets);
  assertEquals(calls, []);
});

Deno.test("nothing locked leaves every push as it was", async () => {
  const { admin } = client({ data: [], error: null });
  const targets = [target("s1", "c1"), target("s2", "c2")];
  assertEquals(await maskLockedPushes(admin, targets), targets);
});

Deno.test("a missing answer is nothing locked", async () => {
  const { admin } = client({ data: null, error: null });
  const targets = [target("s1", "c1")];
  assertEquals(await maskLockedPushes(admin, targets), targets);
});

Deno.test("when the lookup fails, chat pushes lose their words", async () => {
  for (const answer of ["throw", { data: null, error: { message: "boom" } }]) {
    const { admin } = client(answer as Answer);
    const out = await maskLockedPushes(admin, [
      target("s1", "c1"),
      target("s2", null, { title: "Ada liked your Moment", body: "Nice" }),
    ]);
    assertEquals(out[0].title, FALLBACK_TITLE);
    assertEquals(out[0].body, FALLBACK_BODY);
    // Not about a chat: nothing to hide, nothing changed.
    assertEquals(out[1].title, "Ada liked your Moment");
  }
});

Deno.test("the other fields of a target survive", async () => {
  const { admin } = client({
    data: [{
      subscription_id: "s1",
      conversation_id: "c1",
      title: "WeCord",
      body: "You have a new message",
    }],
    error: null,
  });
  const [out] = await maskLockedPushes(admin, [
    target("s1", "c1", { endpoint: "https://push.test/1", url: "/#/chats/c1" }),
  ]);
  assertEquals(out.endpoint, "https://push.test/1");
  assertEquals(out.url, "/#/chats/c1");
  assertEquals(out.body, "You have a new message");
});
