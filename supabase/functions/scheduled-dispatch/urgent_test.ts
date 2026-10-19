import { assertEquals } from "jsr:@std/assert@1";
import { dropQuietPushes, type RpcClient } from "../push/quiet_hours.ts";
import { targetPath } from "./logic.ts";
import { audibleTargets, urgentRowTarget } from "./urgent.ts";

const row = {
  subscription_id: "s1",
  endpoint: "https://push.example.com/x",
  p256dh: "k",
  auth: "a",
  conversation_id: "c1",
  circle_id: null,
  title: "Ada marked a message urgent (Team)",
  body: "Meeting moved to 3 pm",
  tag: "urgent-m1",
  url: null,
};

Deno.test("an urgent push opens its conversation and has one tag per message", () => {
  const target = urgentRowTarget(row);
  assertEquals(target.tag, "urgent-m1");
  assertEquals(target.url, undefined);
  assertEquals(targetPath(target), "/#/chats/c1");
});

Deno.test("an urgent push in a circle channel opens it in the circle", () => {
  const target = urgentRowTarget({ ...row, circle_id: "k1" });
  assertEquals(targetPath(target), "/#/circles/k1?c=c1");
});

Deno.test("a row with a url keeps it", () => {
  const target = urgentRowTarget({ ...row, url: "/#/notifications" });
  assertEquals(targetPath(target), "/#/notifications");
});

// An admin client where every subscription is in its quiet hours, with
// nothing that breaks through: quiet hours hold back everything it is shown.
const everyoneQuiet: RpcClient = {
  rpc: (_name, args) =>
    Promise.resolve({
      error: null,
      data: (args.target_subscription_ids as string[]).map((id) => ({
        subscription_id: id,
        user_id: "u-" + id,
        time_zone: "UTC",
        quiet_days: [1, 2, 3, 4, 5, 6, 7],
        quiet_start: "00:00",
        quiet_end: "23:59",
        breaks_through: false,
      })),
    }),
};

// Midday UTC: inside the all-day window.
const midday = Date.UTC(2026, 9, 24, 12, 0, 0) / 1000;

Deno.test("quiet hours hold back a normal push but never an urgent one", async () => {
  const normal = { ...urgentRowTarget(row), subscription_id: "normal" };
  const urgent = { ...urgentRowTarget(row), subscription_id: "urgent" };
  const sent = await audibleTargets(everyoneQuiet, [normal], [urgent], midday);
  assertEquals(sent.map((target) => target.subscription_id), ["urgent"]);
});

Deno.test("an urgent push is not even shown to the quiet hours lookup", async () => {
  const asked: string[] = [];
  const spy: RpcClient = {
    rpc: (name, args) => {
      asked.push(...(args.target_subscription_ids as string[]));
      return everyoneQuiet.rpc(name, args);
    },
  };
  const normal = { ...urgentRowTarget(row), subscription_id: "normal" };
  const urgent = { ...urgentRowTarget(row), subscription_id: "urgent" };
  await audibleTargets(spy, [normal], [urgent], midday);
  assertEquals(asked, ["normal"]);
});

Deno.test("without quiet hours nothing is lost on the way", async () => {
  const noQuiet: RpcClient = {
    rpc: () => Promise.resolve({ data: [], error: null }),
  };
  const normal = { ...urgentRowTarget(row), subscription_id: "n" };
  const urgent = { ...urgentRowTarget(row), subscription_id: "u" };
  const sent = await audibleTargets(noQuiet, [normal], [urgent], 0);
  assertEquals(sent.map((target) => target.subscription_id), ["n", "u"]);
  // dropQuietPushes itself is still what holds the normal ones back.
  assertEquals(
    (await dropQuietPushes(everyoneQuiet, [normal], midday)).length,
    0,
  );
});

Deno.test("when quiet hours cannot be looked up, everything goes out", async () => {
  const broken: RpcClient = {
    rpc: () => Promise.resolve({ data: null, error: { message: "down" } }),
  };
  const normal = { ...urgentRowTarget(row), subscription_id: "n" };
  const urgent = { ...urgentRowTarget(row), subscription_id: "u" };
  const sent = await audibleTargets(broken, [normal], [urgent], midday);
  assertEquals(sent.length, 2);
});
