// Made-up payloads in the shape GitHub sends; nothing here reaches GitHub.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { clip, formatEvent } from "./format.ts";

const repository = {
  full_name: "wecord/app",
  html_url: "https://github.com/wecord/app",
};
const sender = { login: "ada" };

Deno.test("a push lists the commits and links to the comparison", () => {
  const card = formatEvent("push", {
    ref: "refs/heads/main",
    forced: false,
    compare: "https://github.com/wecord/app/compare/a...b",
    pusher: { name: "ada" },
    repository,
    sender,
    commits: [
      {
        id: "abc1234567890",
        message: "Fix the thing\n\nLong body that is not shown",
        author: { name: "Ada" },
      },
      {
        id: "def5678901234",
        message: "Add a test",
        author: { username: "bob" },
      },
    ],
  })!;
  assertEquals(card.title, "[wecord/app] 2 new commits pushed to main");
  assertEquals(card.url, "https://github.com/wecord/app/compare/a...b");
  assertEquals(
    card.description,
    "`abc1234` Fix the thing - Ada\n`def5678` Add a test - bob",
  );
  assertEquals(card.author, {
    name: "wecord/app",
    url: "https://github.com/wecord/app",
  });
  assertEquals(card.footer, { text: "ada" });
  assertEquals(card.color, "#0969da");
});

Deno.test("a push with one commit, a force push, many commits", () => {
  const one = formatEvent("push", {
    ref: "refs/heads/dev",
    repository,
    commits: [{ id: "1234567", message: "m" }],
  })!;
  assertEquals(one.title, "[wecord/app] 1 new commit pushed to dev");
  const forced = formatEvent("push", {
    ref: "refs/heads/dev",
    forced: true,
    repository,
    commits: [{ id: "1234567", message: "m" }],
  })!;
  assertEquals(forced.title, "[wecord/app] 1 new commit force-pushed to dev");
  const many = formatEvent("push", {
    ref: "refs/heads/dev",
    repository,
    commits: Array.from(
      { length: 8 },
      (_, i) => ({ id: `abcdef${i}`, message: `c${i}` }),
    ),
  })!;
  assertEquals(many.description!.split("\n").length, 6);
  assert(many.description!.endsWith("… and 3 more"));
  const lots = formatEvent("push", {
    ref: "refs/heads/dev",
    repository,
    commits: Array.from(
      { length: 20 },
      (_, i) => ({ id: `abcdef${i}`, message: `c${i}` }),
    ),
  })!;
  assertEquals(lots.title, "[wecord/app] 20+ new commits pushed to dev");
});

Deno.test("branches and tags created or deleted; empty pushes are ignored", () => {
  assertEquals(
    formatEvent("push", {
      ref: "refs/heads/old",
      deleted: true,
      repository,
      commits: [],
    })!.title,
    "[wecord/app] Branch old deleted",
  );
  assertEquals(
    formatEvent("push", {
      ref: "refs/tags/v1.0",
      created: true,
      repository,
      commits: [],
    })!.title,
    "[wecord/app] Tag v1.0 created",
  );
  assertEquals(
    formatEvent("push", { ref: "refs/heads/main", repository, commits: [] }),
    null,
  );
  assertEquals(formatEvent("push", { repository }), null);
});

const pull = {
  number: 12,
  title: "Add dark mode",
  html_url: "https://github.com/wecord/app/pull/12",
  body: "Adds a dark theme.\n\n- tokens\n- screenshots",
  head: { ref: "dark" },
  base: { ref: "main" },
  additions: 120,
  deletions: 8,
  changed_files: 5,
  draft: false,
};

Deno.test("pull requests: opened, merged, closed, and the actions we skip", () => {
  const opened = formatEvent("pull_request", {
    action: "opened",
    pull_request: pull,
    repository,
    sender,
  })!;
  assertEquals(
    opened.title,
    "[wecord/app] Pull request opened: #12 Add dark mode",
  );
  assertEquals(opened.url, "https://github.com/wecord/app/pull/12");
  assertEquals(
    opened.description,
    "Adds a dark theme.\n\n- tokens\n- screenshots",
  );
  assertEquals(opened.fields, [
    { name: "Branches", value: "dark → main", inline: true },
    { name: "Changes", value: "+120 −8 in 5 files", inline: true },
  ]);
  assertEquals(opened.color, "#2da44e");

  const merged = formatEvent("pull_request", {
    action: "closed",
    pull_request: { ...pull, merged: true },
    repository,
    sender,
  })!;
  assertEquals(
    merged.title,
    "[wecord/app] Pull request merged: #12 Add dark mode",
  );
  assertEquals(merged.color, "#8250df");
  assertEquals(merged.description, undefined);

  const closed = formatEvent("pull_request", {
    action: "closed",
    pull_request: { ...pull, merged: false },
    repository,
  })!;
  assertEquals(closed.color, "#cf222e");

  const draft = formatEvent("pull_request", {
    action: "opened",
    pull_request: { ...pull, draft: true },
    repository,
  })!;
  assert(draft.title.includes("opened (draft)"));

  for (
    const action of [
      "edited",
      "labeled",
      "synchronize",
      "assigned",
      "review_requested",
    ]
  ) {
    assertEquals(
      formatEvent("pull_request", { action, pull_request: pull, repository }),
      null,
      action,
    );
  }
});

Deno.test("issues and comments", () => {
  const issue = {
    number: 7,
    title: "Crash on start",
    html_url: "https://github.com/wecord/app/issues/7",
    body: "It crashes.",
    labels: [{ name: "bug" }, { name: "ios" }],
  };
  const opened = formatEvent("issues", {
    action: "opened",
    issue,
    repository,
    sender,
  })!;
  assertEquals(opened.title, "[wecord/app] Issue opened: #7 Crash on start");
  assertEquals(opened.fields, [{
    name: "Labels",
    value: "bug, ios",
    inline: true,
  }]);
  assertEquals(
    formatEvent("issues", { action: "closed", issue, repository })!.color,
    "#8250df",
  );
  assertEquals(
    formatEvent("issues", { action: "labeled", issue, repository }),
    null,
  );

  const comment = formatEvent("issue_comment", {
    action: "created",
    issue,
    comment: {
      html_url: "https://github.com/wecord/app/issues/7#issuecomment-1",
      body: "Same here.",
      user: { login: "bob" },
    },
    repository,
  })!;
  assertEquals(
    comment.title,
    "[wecord/app] New comment on issue #7: Crash on start",
  );
  assertEquals(comment.footer, { text: "bob" });
  const onPull = formatEvent("issue_comment", {
    action: "created",
    issue: { ...issue, pull_request: {} },
    comment: { body: "LGTM" },
    repository,
  })!;
  assert(onPull.title.includes("pull request #7"));
  assertEquals(
    formatEvent("issue_comment", {
      action: "edited",
      issue,
      comment: {},
      repository,
    }),
    null,
  );
});

Deno.test("releases and workflow runs", () => {
  const release = formatEvent("release", {
    action: "published",
    release: {
      name: "v2.0",
      tag_name: "v2.0.0",
      html_url: "https://github.com/wecord/app/releases/tag/v2.0.0",
      body: "Big things.",
      prerelease: false,
      author: { login: "ada" },
    },
    repository,
  })!;
  assertEquals(release.title, "[wecord/app] Release published: v2.0");
  assertEquals(release.footer, { text: "v2.0.0 · ada" });
  assertEquals(
    formatEvent("release", {
      action: "created",
      release: { name: "x" },
      repository,
    }),
    null,
  );
  assert(
    formatEvent("release", {
      action: "published",
      release: { tag_name: "v3-rc1", prerelease: true },
      repository,
    })!.title.includes("Pre-release published: v3-rc1"),
  );

  const run = {
    name: "CI",
    conclusion: "failure",
    head_branch: "main",
    event: "push",
    html_url: "https://github.com/wecord/app/actions/runs/1",
    display_title: "Fix the thing",
    actor: { login: "ada" },
  };
  const failed = formatEvent("workflow_run", {
    action: "completed",
    workflow_run: run,
    repository,
  })!;
  assertEquals(failed.title, "[wecord/app] CI failed");
  assertEquals(failed.color, "#cf222e");
  assertEquals(failed.fields, [
    { name: "Branch", value: "main", inline: true },
    { name: "Event", value: "push", inline: true },
  ]);
  assertEquals(
    formatEvent("workflow_run", {
      action: "completed",
      workflow_run: { ...run, conclusion: "skipped" },
      repository,
    }),
    null,
  );
  assertEquals(
    formatEvent("workflow_run", {
      action: "requested",
      workflow_run: run,
      repository,
    }),
    null,
  );
});

Deno.test("people's words are only cut short, and links must be https", () => {
  const card = formatEvent("issues", {
    action: "opened",
    issue: {
      number: 1,
      title: "<img src=x onerror=alert(1)> " + "t".repeat(300),
      html_url: "http://github.com/wecord/app/issues/1",
      body: "b".repeat(5000),
    },
    repository: { full_name: "wecord/app", html_url: "javascript:alert(1)" },
    sender: { login: "x".repeat(100) },
  })!;
  assert([...card.title].length <= 120);
  assert(card.title.endsWith("…"));
  assertEquals(card.url, undefined);
  assertEquals(card.author, { name: "wecord/app" });
  assert([...card.description!].length <= 300);
  assert(
    card.title.includes("<img"),
    "text is kept as text; the app draws it as plain text",
  );
  assertEquals([...card.footer!.text].length <= 39, true);
});

Deno.test("odd payloads give no card instead of an error", () => {
  for (const payload of [null, 5, "x", [], {}, { action: "opened" }]) {
    for (
      const event of [
        "push",
        "pull_request",
        "issues",
        "issue_comment",
        "release",
        "workflow_run",
        "star",
        "",
      ]
    ) {
      const card = formatEvent(event, payload);
      assert(card === null || typeof card.title === "string");
    }
  }
  assertEquals(formatEvent("star", { action: "created", repository }), null);
});

Deno.test("clip tidies and cuts", () => {
  assertEquals(clip("  a\n\n b   c ", 20), "a b c");
  assertEquals(clip("a\n\n\n\nb", 20, true), "a\n\nb");
  assertEquals(clip("abcdef", 4), "abc…");
  assertEquals(clip(5, 4), "");
});
