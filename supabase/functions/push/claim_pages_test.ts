import { assertEquals } from "jsr:@std/assert@1";
import {
  CLAIM_BATCH_PEOPLE,
  claimAllPushRows,
  claimPushBatches,
  forEachLimited,
  REST_ROW_LIMIT,
} from "./claim_pages.ts";

interface Row {
  subscription_id: string;
  recipient_id: string;
}

type Args = Record<string, unknown>;

/// A database with `people` recipients (ids p000, p001, ...) of `devices`
/// devices each, answering like claim_push_delivery with a cursor.
function fakeDatabase(people: number, devices: number, cut = Infinity) {
  const calls: Args[] = [];
  const client = {
    rpc(_name: string, args?: Args) {
      calls.push(args ?? {});
      const after = args?.after_user_id as string | null;
      const size = args?.page_size as number;
      const ids = Array.from(
        { length: people },
        (_, i) => `p${String(i).padStart(4, "0")}`,
      ).filter((id) => after === null || id > after).slice(0, size);
      let rows: Row[] = ids.flatMap((id) =>
        Array.from({ length: devices }, (_, d) => ({
          subscription_id: `${id}-${d}`,
          recipient_id: id,
        }))
      );
      rows = rows.slice(0, cut);
      return Promise.resolve({ data: rows, error: null });
    },
  };
  return { client, calls };
}

Deno.test("a small chat is one batch", async () => {
  const { client, calls } = fakeDatabase(30, 2);
  const seen: number[] = [];
  const result = await claimPushBatches<Row>(client, "m1", "ada", (rows) => {
    seen.push(rows.length);
  });
  assertEquals(result, { error: null, batches: 1 });
  assertEquals(seen, [60]);
  assertEquals(calls[0], {
    target_message_id: "m1",
    caller_id: "ada",
    after_user_id: null,
    page_size: CLAIM_BATCH_PEOPLE,
  });
});

Deno.test("a big chat continues from the last person of each batch", async () => {
  const { client, calls } = fakeDatabase(450, 2);
  const seen: Row[] = [];
  const result = await claimPushBatches<Row>(client, "m1", "ada", (rows) => {
    seen.push(...rows);
  });
  assertEquals(result.error, null);
  assertEquals(result.batches, 3);
  assertEquals(calls.map((call) => call.after_user_id), [
    null,
    "p0199",
    "p0399",
  ]);
  // Every device exactly once.
  assertEquals(seen.length, 900);
  assertEquals(new Set(seen.map((row) => row.subscription_id)).size, 900);
});

Deno.test("a batch of exactly the batch size asks for one more", async () => {
  const { client, calls } = fakeDatabase(400, 1);
  const rows = await claimAllPushRows<Row>(client, "m1", "ada");
  assertEquals(rows.rows.length, 400);
  // 200 + 200 + an empty third answer.
  assertEquals(calls.length, 3);
});

Deno.test("an answer cut at the row limit leaves the last person for the next batch", async () => {
  // 600 people of 3 devices in batches of 400 people would be 1200 rows; the
  // API cuts them at 1000.
  const { client } = fakeDatabase(900, 3, REST_ROW_LIMIT);
  const seen: Row[] = [];
  const result = await claimPushBatches<Row>(
    client,
    "m1",
    "ada",
    (rows) => {
      seen.push(...rows);
    },
    400,
  );
  assertEquals(result.error, null);
  assertEquals(seen.length, 2700);
  assertEquals(new Set(seen.map((row) => row.subscription_id)).size, 2700);
});

Deno.test("rows without a recipient end the walk after one batch", async () => {
  const client = {
    rpc: () =>
      Promise.resolve({ data: [{ subscription_id: "s1" }], error: null }),
  };
  const result = await claimAllPushRows(client, "m1", "ada");
  assertEquals(result.rows.length, 1);
  assertEquals(result.error, null);
});

Deno.test("an error stops the walk and keeps what came before", async () => {
  let call = 0;
  const client = {
    rpc() {
      call++;
      if (call === 2) {
        return Promise.resolve({ data: null, error: { message: "boom" } });
      }
      const rows = Array.from({ length: 200 }, (_, i) => ({
        subscription_id: `s${i}`,
        recipient_id: `p${String(i).padStart(4, "0")}`,
      }));
      return Promise.resolve({ data: rows, error: null });
    },
  };
  const result = await claimAllPushRows<Row>(client, "m1", "ada");
  assertEquals(result.error, "boom");
  assertEquals(result.rows.length, 200);
});

Deno.test("forEachLimited never runs more than the limit at once", async () => {
  let running = 0;
  let peak = 0;
  const done: number[] = [];
  await forEachLimited([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 3, async (n) => {
    running++;
    peak = Math.max(peak, running);
    await new Promise((resolve) => setTimeout(resolve, 2));
    running--;
    done.push(n);
  });
  assertEquals(peak, 3);
  assertEquals(done.length, 10);
});

Deno.test("forEachLimited on nothing does nothing", async () => {
  await forEachLimited([], 5, () => Promise.reject(new Error("never")));
});
