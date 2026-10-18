import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { writeTimesForTargets } from "../push/time_tokens.ts";
import { targetPath } from "./logic.ts";
import { joinRequestTarget } from "./join_requests.ts";

const approved = {
  subscription_id: "s1",
  endpoint: "https://push.example.com/x",
  p256dh: "k",
  auth: "a",
  title: "Join request approved",
  body:
    "You are in Chess club, <t:1760000000:f>. Open WeCord to read the rules and say hello.",
  tag: "join-request-1",
  url: "/#/circles/c1",
};

Deno.test("an approval opens the circle, a denial opens Notifications", () => {
  const yes = joinRequestTarget(approved);
  assertEquals(targetPath(yes), "/#/circles/c1");
  assertEquals(yes.tag, "join-request-1");
  assertEquals(yes.conversation_id, null);
  const no = joinRequestTarget({ ...approved, url: "/#/notifications" });
  assertEquals(targetPath(no), "/#/notifications");
});

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

Deno.test("the time in the answer is written in the device's zone", async () => {
  // 1760000000 is 2025-10-09 08:53:20 UTC: 16:53 in Shanghai, 04:53 in New
  // York.
  const zh = {
    ...joinRequestTarget({
      ...approved,
      title: "入圈申请已通过",
      body:
        "「Chess club」通过了你的申请，<t:1760000000:f>。打开 WeCord 阅读规则并打个招呼。",
    }),
    subscription_id: "zh",
  };
  const en = { ...joinRequestTarget(approved), subscription_id: "en" };
  const out = await writeTimesForTargets(
    adminWith([
      { id: "zh", language: "zh", time_zone: "Asia/Shanghai" },
      { id: "en", language: "en", time_zone: "America/New_York" },
    ]),
    [zh, en],
    1760000000,
  );
  assertEquals(out[0].body.includes("<t:"), false);
  assertEquals(out[1].body.includes("<t:"), false);
  assertStringIncludes(out[0].body, "下午4:53");
  assertStringIncludes(out[0].body, "通过了你的申请");
  assertStringIncludes(out[1].body, "4:53");
  assertStringIncludes(out[1].body, "You are in Chess club");
});
