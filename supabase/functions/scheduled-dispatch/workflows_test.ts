import { assertEquals } from "jsr:@std/assert@1";
import { workflowMessageTargets, type WorkflowRpcClient } from "./workflows.ts";

type Call = { name: string; args?: Record<string, unknown> };

function client(
  calls: Call[],
  answers: Record<string, { data: unknown; error: { message: string } | null }>,
): WorkflowRpcClient {
  return {
    rpc(name, args) {
      calls.push({ name, args });
      return Promise.resolve(answers[name] ?? { data: [], error: null });
    },
  };
}

const sub = {
  subscription_id: "s1",
  endpoint: "https://push.example.com/x",
  p256dh: "k",
  auth: "a",
  conversation_id: "c1",
  circle_id: "club",
  title: "艾达",
  body: "欢迎加入",
};

Deno.test("each claimed message is pushed as one the creator just sent", async () => {
  const calls: Call[] = [];
  const targets = await workflowMessageTargets(client(calls, {
    claim_workflow_message_pushes: {
      data: [{ message_id: "m1", sender_id: "ada" }],
      error: null,
    },
    claim_push_delivery: { data: [sub], error: null },
  }));
  assertEquals(calls.map((call) => call.name), [
    "claim_workflow_message_pushes",
    "claim_push_delivery",
  ]);
  // The first batch of people; a small chat is one batch.
  assertEquals(calls[1].args, {
    target_message_id: "m1",
    caller_id: "ada",
    after_user_id: null,
    page_size: 200,
  });
  assertEquals(targets.length, 1);
  // The message id rides along so silent messages and quiet hours can look
  // at it.
  assertEquals(targets[0].message_id, "m1");
  assertEquals(targets[0].body, "欢迎加入");
});

Deno.test("nothing claimed means no push and no further call", async () => {
  const calls: Call[] = [];
  const targets = await workflowMessageTargets(client(calls, {}));
  assertEquals(targets, []);
  assertEquals(calls.length, 1);
});

Deno.test("a failed claim is not fatal", async () => {
  const calls: Call[] = [];
  const targets = await workflowMessageTargets(client(calls, {
    claim_workflow_message_pushes: { data: null, error: { message: "boom" } },
  }));
  assertEquals(targets, []);
});

Deno.test("a message whose push cannot be claimed is skipped, the others go on", async () => {
  let n = 0;
  const admin: WorkflowRpcClient = {
    rpc(name) {
      if (name === "claim_workflow_message_pushes") {
        return Promise.resolve({
          data: [
            { message_id: "m1", sender_id: "ada" },
            { message_id: "m2", sender_id: "ada" },
          ],
          error: null,
        });
      }
      n++;
      return Promise.resolve(
        n === 1
          ? { data: null, error: { message: "nope" } }
          : { data: [sub], error: null },
      );
    },
  };
  const targets = await workflowMessageTargets(admin);
  assertEquals(targets.map((target) => target.message_id), ["m2"]);
});
