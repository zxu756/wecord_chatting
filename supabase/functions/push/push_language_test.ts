// Every SQL function that hands the push Edge Functions a title and a body
// must write them per subscription language (push_subscriptions.language,
// 202610170005_push_language.sql), or Chinese devices get English text.
//
// The text is built in SQL, so this reads the migrations: it finds the latest
// definition of each function that returns push targets and checks it
// branches on the subscription's language and carries Chinese. A new push
// kind added with English only fails here.
//
//   deno test --allow-read supabase/functions/push/push_language_test.ts
import { assert, assertEquals } from "jsr:@std/assert@1";

const migrationsDir = new URL("../../migrations/", import.meta.url);

/// The latest definition of every `public` function, by name.
function latestFunctions(): Map<string, { file: string; sql: string }> {
  const files = [...Deno.readDirSync(migrationsDir)]
    .filter((entry) => entry.isFile && entry.name.endsWith(".sql"))
    .map((entry) => entry.name)
    .sort();
  const latest = new Map<string, { file: string; sql: string }>();
  const header = /create or replace function public\.([a-z_0-9]+)\(/g;
  for (const file of files) {
    const source = Deno.readTextFileSync(new URL(file, migrationsDir));
    const starts = [...source.matchAll(header)];
    for (const [index, match] of starts.entries()) {
      const end = starts[index + 1]?.index ?? source.length;
      latest.set(match[1], {
        file,
        sql: source.slice(match.index, end),
      });
    }
  }
  return latest;
}

/// Whether the function returns rows for the push senders: one per device
/// (`subscription_id`) with the text to show.
function returnsPushText(sql: string): boolean {
  const returns = /returns table \(([\s\S]*?)\)\s*language/i.exec(sql);
  if (!returns) return false;
  const columns = returns[1];
  return /\bsubscription_id\b/.test(columns) &&
    /\btitle\s+text\b/.test(columns) &&
    /\bbody\s+text\b/.test(columns);
}

// Chinese written in the SQL, or picked from a column that holds it (an
// official notice carries the admin's own `title_zh` / `body_zh`).
const hasChinese = /[一-鿿]|\b\w+_zh\b/;

Deno.test("every push text function writes Chinese for zh subscriptions", () => {
  const functions = latestFunctions();
  const pushFunctions = [...functions.entries()].filter(([, { sql }]) =>
    returnsPushText(sql)
  );

  // The known ones, so a rename or a regex slip does not pass vacuously.
  const names = pushFunctions.map(([name]) => name).sort();
  for (
    const expected of [
      "claim_chat_event_reminder_pushes",
      "claim_moments_pushes",
      "claim_push_delivery",
      "claim_reminder_pushes",
      "claim_task_assignment_push",
      "due_list_item_reminders",
    ]
  ) {
    assert(names.includes(expected), `${expected} not found in ${names}`);
  }

  const english = pushFunctions.filter(([, { sql }]) =>
    !/\.language\s*=\s*'zh'|language\s*=\s*'zh'/.test(sql) ||
    !hasChinese.test(sql)
  ).map(([name, { file }]) => `${name} (${file})`);
  assertEquals(
    english,
    [],
    "These push functions build English only; branch on s.language = 'zh'",
  );
});

Deno.test("the card helper is used wherever message text is pushed", () => {
  const functions = latestFunctions();
  for (const name of ["claim_push_delivery", "claim_reminder_pushes"]) {
    const sql = functions.get(name)?.sql ?? "";
    assert(
      sql.includes("card_body_zh"),
      `${name} should word cards (live location, contact card, ...) in Chinese`,
    );
  }
  const helper = functions.get("card_body_zh")?.sql ?? "";
  for (const kind of ["live_location", "chat_history", "contact_card"]) {
    assert(helper.includes(`'${kind}'`), `card_body_zh lacks ${kind}`);
  }
});
