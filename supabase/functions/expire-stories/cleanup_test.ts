// The cleanup of ended dailies (B1): purge, claim, remove, confirm.
import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { cleanUpStories, StoryCleanupError } from "./cleanup.ts";

interface Row {
  bucket_id?: string;
  object_path?: string;
}

interface Fake {
  client: SupabaseClient;
  finished: string[][];
  removed: { bucket: string; paths: string[] }[];
  calls: string[];
}

function fake(options: {
  purge?: number[];
  claims?: Row[][];
  purgeError?: boolean;
  claimError?: boolean;
  removeError?: boolean;
}): Fake {
  const out: Fake = {
    client: undefined as unknown as SupabaseClient,
    finished: [],
    removed: [],
    calls: [],
  };
  const purges = [...(options.purge ?? [0])];
  const claims = [...(options.claims ?? [[]])];
  out.client = {
    rpc(name: string, args: Record<string, unknown>) {
      out.calls.push(name);
      if (name === "purge_expired_stories") {
        return Promise.resolve(
          options.purgeError
            ? { data: null, error: { message: "boom" } }
            : { data: purges.shift() ?? 0, error: null },
        );
      }
      if (name === "claim_story_media") {
        return Promise.resolve(
          options.claimError
            ? { data: null, error: { message: "boom" } }
            : { data: claims.shift() ?? [], error: null },
        );
      }
      if (name === "finish_story_media") {
        out.finished.push(args["paths"] as string[]);
        return Promise.resolve({ data: null, error: null });
      }
      throw new Error(`unexpected rpc ${name}`);
    },
    storage: {
      from(bucket: string) {
        return {
          remove(paths: string[]) {
            out.removed.push({ bucket, paths });
            return Promise.resolve({
              error: options.removeError ? { message: "no" } : null,
            });
          },
        };
      },
    },
  } as unknown as SupabaseClient;
  return out;
}

Deno.test("purges, removes the claimed files and confirms them", async () => {
  const f = fake({
    purge: [3],
    claims: [[
      { bucket_id: "stories", object_path: "u/a.jpg" },
      { bucket_id: "stories", object_path: "u/a-t.jpg" },
    ]],
  });
  const result = await cleanUpStories(f.client);
  assertEquals(result, { purged: 3, removed: 2 });
  assertEquals(f.removed, [{
    bucket: "stories",
    paths: ["u/a.jpg", "u/a-t.jpg"],
  }]);
  assertEquals(f.finished, [["u/a.jpg", "u/a-t.jpg"]]);
});

Deno.test("does nothing when there is nothing to do", async () => {
  const f = fake({});
  assertEquals(await cleanUpStories(f.client), { purged: 0, removed: 0 });
  assertEquals(f.removed, []);
});

Deno.test("files Storage refused stay queued", async () => {
  const f = fake({
    claims: [[{ bucket_id: "stories", object_path: "u/a.jpg" }]],
    removeError: true,
  });
  assertEquals(await cleanUpStories(f.client), { purged: 0, removed: 0 });
  assertEquals(f.finished, []);
  // and the same rows are not claimed again in the same run
  assertEquals(f.calls.filter((c) => c === "claim_story_media").length, 1);
});

Deno.test("a failing purge or claim is reported", async () => {
  await assertRejects(
    () => cleanUpStories(fake({ purgeError: true }).client),
    StoryCleanupError,
    "purge_failed",
  );
  await assertRejects(
    () => cleanUpStories(fake({ claimError: true }).client),
    StoryCleanupError,
    "claim_failed",
  );
});

Deno.test("rows without a bucket or path are skipped", async () => {
  const f = fake({
    claims: [[
      { bucket_id: "stories", object_path: "u/a.jpg" },
      { bucket_id: "stories" },
    ]],
  });
  assertEquals((await cleanUpStories(f.client)).removed, 1);
});
