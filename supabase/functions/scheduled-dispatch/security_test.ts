import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { writeTimesForTargets } from "../push/time_tokens.ts";
import { targetPath } from "./logic.ts";
import { securityTarget } from "./security.ts";

const row = {
  subscription_id: "s1",
  endpoint: "https://push.example.com/x",
  p256dh: "k",
  auth: "a",
  title: "New sign-in to your account",
  body:
    "Ada iPhone (iOS), <t:1760000000:f>. Not you? Open Notifications in WeCord.",
  tag: "security-1",
  url: "/#/notifications",
};

Deno.test("a login alert becomes a push that opens Notifications", () => {
  const target = securityTarget(row);
  assertEquals(target.tag, "security-1");
  assertEquals(target.conversation_id, null);
  assertEquals(targetPath(target), "/#/notifications");
  assertEquals(target.title, row.title);
});

// A fake admin client serving the locale of each subscription.
function adminWith(
  locales: { id: string; language: string; time_zone: string | null }[],
) {
  return {
    from: () => ({
      select: () => ({
        in: () => Promise.resolve({ data: locales, error: null }),
      }),
    }),
  };
}

Deno.test("the time in the alert is written in the subscriber's zone", async () => {
  // 1760000000 is 2025-10-09 08:53:20 UTC: 16:53 in Shanghai, 04:53 in New
  // York.
  const shanghai = { ...securityTarget(row), subscription_id: "zh" };
  const newYork = { ...securityTarget(row), subscription_id: "en" };
  const out = await writeTimesForTargets(
    adminWith([
      { id: "zh", language: "zh", time_zone: "Asia/Shanghai" },
      { id: "en", language: "en", time_zone: "America/New_York" },
    ]),
    [shanghai, newYork],
    1760000000,
  );
  assertEquals(out[0].body.includes("<t:"), false);
  assertEquals(out[1].body.includes("<t:"), false);
  assertStringIncludes(out[0].body, "下午4:53");
  assertStringIncludes(out[1].body, "4:53");
  // The surrounding text is untouched.
  assertStringIncludes(out[1].body, "Ada iPhone (iOS)");
  assertStringIncludes(out[1].body, "Not you?");
});

Deno.test("without a stored zone the time is shown in UTC", async () => {
  const out = await writeTimesForTargets(
    adminWith([{ id: "s1", language: "en", time_zone: null }]),
    [securityTarget(row)],
    1760000000,
  );
  assertEquals(out[0].body.includes("<t:"), false);
  assertStringIncludes(out[0].body, "8:53");
  assertStringIncludes(out[0].body, "UTC");
});
