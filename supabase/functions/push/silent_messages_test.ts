import { assertEquals } from "jsr:@std/assert@1";
import type { RpcClient } from "./quiet_hours.ts";
import { dropSilentPushes } from "./silent_messages.ts";

function client(silent: string[] | "error" | "throw"): {
  admin: RpcClient;
  calls: Record<string, unknown>[];
} {
  const calls: Record<string, unknown>[] = [];
  return {
    calls,
    admin: {
      rpc(name, args) {
        calls.push({ name, ...args });
        if (silent === "throw") {
          throw new Error("down");
        }
        return Promise.resolve(
          silent === "error"
            ? { data: null, error: { message: "boom" } }
            : { data: silent, error: null },
        );
      },
    },
  };
}

const target = (subscription_id: string, message_id?: string) => ({
  subscription_id,
  message_id,
});

Deno.test("a silent message sends no push to anyone", async () => {
  const { admin, calls } = client(["m1"]);
  const kept = await dropSilentPushes(admin, [
    target("s1"),
    target("s2"),
  ], "m1");
  assertEquals(kept, []);
  assertEquals(calls, [{ name: "silent_message_ids", message_ids: ["m1"] }]);
});

Deno.test("a message that is not silent is pushed as before", async () => {
  const { admin } = client([]);
  const targets = [target("s1"), target("s2")];
  assertEquals(await dropSilentPushes(admin, targets, "m1"), targets);
});

Deno.test("the dispatcher's targets name their own message", async () => {
  const { admin, calls } = client(["quiet"]);
  const kept = await dropSilentPushes(admin, [
    target("s1", "quiet"),
    target("s2", "loud"),
    target("s3", "quiet"),
    target("s4", "loud"),
  ]);
  assertEquals(kept.map((t) => t.subscription_id), ["s2", "s4"]);
  // One question for all of them.
  assertEquals(calls.length, 1);
  assertEquals(
    new Set(calls[0].message_ids as string[]),
    new Set(["quiet", "loud"]),
  );
});

Deno.test("pushes that are not about a message are never dropped", async () => {
  const { admin, calls } = client(["m1"]);
  const targets = [target("s1"), target("s2")];
  assertEquals(await dropSilentPushes(admin, targets, null), targets);
  assertEquals(calls, [], "nothing to ask");
});

Deno.test("an empty list asks nothing", async () => {
  const { admin, calls } = client(["m1"]);
  assertEquals(await dropSilentPushes(admin, [], "m1"), []);
  assertEquals(calls, []);
});

Deno.test("when the lookup fails every push goes out", async () => {
  const targets = [target("s1")];
  assertEquals(
    await dropSilentPushes(client("error").admin, targets, "m1"),
    targets,
  );
  assertEquals(
    await dropSilentPushes(client("throw").admin, targets, "m1"),
    targets,
  );
});
