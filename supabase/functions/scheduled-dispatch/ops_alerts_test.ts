import { assertEquals } from "jsr:@std/assert@1";
import { targetPath } from "./logic.ts";
import { opsAlertTarget } from "./ops_alerts.ts";

const row = {
  subscription_id: "s1",
  endpoint: "https://push.example.com/x",
  p256dh: "k",
  auth: "a",
  title: "定时任务停了",
  body: "每分钟的调度任务已有 13 分钟没有成功运行。",
  tag: "ops-alert-a1",
  url: "/#/admin",
};

Deno.test("an alert opens the admin console, one tag per alert", () => {
  const target = opsAlertTarget(row);
  assertEquals(targetPath(target), "/#/admin");
  assertEquals(target.tag, "ops-alert-a1");
  assertEquals(target.conversation_id, null);
  assertEquals(target.circle_id, null);
  assertEquals(target.title, "定时任务停了");
  assertEquals(target.message_id, undefined);
});

Deno.test("the push carries the subscription it was claimed for", () => {
  const target = opsAlertTarget(row);
  assertEquals(target.subscription_id, "s1");
  assertEquals(target.endpoint, "https://push.example.com/x");
  assertEquals(target.p256dh, "k");
  assertEquals(target.auth, "a");
});
