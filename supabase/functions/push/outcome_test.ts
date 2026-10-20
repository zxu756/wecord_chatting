import { assertEquals } from "jsr:@std/assert@1";
import { newTally, recordPushOutcome, tallyPush } from "./outcome.ts";

Deno.test("each answer of a push service lands in one count", () => {
  const tally = newTally();
  for (const status of [201, 200, 404, 410, 500, 429, 403, null]) {
    tallyPush(tally, status);
  }
  // 201 and 200 are sent; 404 and 410 are dead subscriptions; the rest failed.
  assertEquals(tally, { sent: 2, failed: 4, gone: 2 });
});

Deno.test("a round is reported once, as three numbers", async () => {
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  const tally = { sent: 5, failed: 1, gone: 2 };
  await recordPushOutcome({
    rpc(name, args) {
      calls.push({ name, args });
      return Promise.resolve({ data: null });
    },
  }, tally);
  assertEquals(calls, [{
    name: "ops_record_push",
    args: { sent_count: 5, failed_count: 1, gone_count: 2 },
  }]);
});

Deno.test("an empty round reports nothing", async () => {
  let called = false;
  await recordPushOutcome({
    rpc() {
      called = true;
      return Promise.resolve({});
    },
  }, newTally());
  assertEquals(called, false);
});

Deno.test("reporting never throws", async () => {
  await recordPushOutcome({
    rpc() {
      return Promise.reject(new Error("database down"));
    },
  }, { sent: 1, failed: 0, gone: 0 });
});
