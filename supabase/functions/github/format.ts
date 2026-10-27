// Turning a GitHub webhook event into one card (roadmap I6).
//
// Everything in a payload that people wrote - a commit message, an issue
// title, a pull request description, a comment - is untrusted text (anyone
// can open an issue on a public repository). Here it is only ever cut short
// and put into a plain-text card field; the database strips what a card may
// not hold, and the app draws every card text as plain text, never as
// markdown or HTML. Links must be https. Which events a connection sends is
// chosen when it is made (channel_github_hooks.events).

export type Card = {
  title: string;
  url?: string;
  description?: string;
  color?: string;
  author?: { name: string; url?: string };
  fields?: { name: string; value: string; inline?: boolean }[];
  footer?: { text: string };
};

const GREEN = "#2da44e";
const PURPLE = "#8250df";
const RED = "#cf222e";
const BLUE = "#0969da";
const GRAY = "#6e7781";

type Json = Record<string, unknown>;

function object(value: unknown): Json {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Json
    : {};
}

function list(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function text(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function count(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/** One line (or [lines] of text), cut to [max] characters with an ellipsis. */
export function clip(value: unknown, max: number, lines = false): string {
  let source = text(value).replace(/\r\n?/g, "\n");
  source = lines
    ? source.replace(/[ \t]+/g, " ").replace(/\n{3,}/g, "\n\n")
    : source.replace(/\s+/g, " ");
  source = source.trim();
  const chars = [...source];
  return chars.length > max
    ? chars.slice(0, max - 1).join("").trim() + "…"
    : source;
}

function https(value: unknown): string | undefined {
  const link = text(value);
  return link.startsWith("https://") && link.length <= 500 ? link : undefined;
}

function firstLine(value: unknown, max: number): string {
  return clip(text(value).split("\n")[0], max);
}

function header(
  payload: Json,
): { repo: string; repoUrl?: string; sender: string } {
  const repository = object(payload.repository);
  return {
    repo: clip(repository.full_name, 100) || "GitHub",
    repoUrl: https(repository.html_url),
    sender: clip(object(payload.sender).login, 39),
  };
}

function card(
  base: { repo: string; repoUrl?: string; sender: string },
  parts: Omit<Card, "author" | "footer"> & { footer?: string },
): Card {
  const { footer, ...rest } = parts;
  const result: Card = {
    ...rest,
    author: base.repoUrl
      ? { name: base.repo, url: base.repoUrl }
      : { name: base.repo },
  };
  const footerText = footer ?? base.sender;
  if (footerText !== "") {
    result.footer = { text: footerText };
  }
  return result;
}

function push(payload: Json, base: ReturnType<typeof header>): Card | null {
  const ref = text(payload.ref);
  const isTag = ref.startsWith("refs/tags/");
  const name = clip(ref.replace(/^refs\/(heads|tags)\//, ""), 80);
  if (name === "") return null;
  const kind = isTag ? "Tag" : "Branch";
  const commits = list(payload.commits);

  if (payload.deleted === true) {
    return card(base, {
      title: `[${base.repo}] ${kind} ${name} deleted`,
      color: RED,
    });
  }
  if (commits.length === 0) {
    if (payload.created === true) {
      return card(base, {
        title: `[${base.repo}] ${kind} ${name} created`,
        url: https(object(payload.head_commit).url),
        color: GREEN,
      });
    }
    return null;
  }

  const lines = commits.slice(0, 5).map((entry) => {
    const commit = object(entry);
    const who = clip(
      object(commit.author).name || object(commit.author).username,
      30,
    );
    const sha = /^[0-9a-f]{7,64}$/i.test(text(commit.id))
      ? text(commit.id).slice(0, 7)
      : "";
    return `${sha === "" ? "" : `\`${sha}\` `}${firstLine(commit.message, 72)}${
      who === "" ? "" : ` - ${who}`
    }`;
  });
  if (commits.length > 5) {
    lines.push(
      `… and ${commits.length >= 20 ? "more" : commits.length - 5 + " more"}`,
    );
  }
  const amount = commits.length >= 20 ? "20+" : String(commits.length);
  const verb = payload.forced === true ? "force-pushed" : "pushed";
  return card(base, {
    title: `[${base.repo}] ${amount} new commit${
      commits.length === 1 ? "" : "s"
    } ${verb} to ${name}`,
    url: https(payload.compare) ?? https(object(payload.head_commit).url),
    description: lines.join("\n"),
    color: BLUE,
    footer: clip(object(payload.pusher).name, 39) || base.sender,
  });
}

function pullRequest(
  payload: Json,
  base: ReturnType<typeof header>,
): Card | null {
  const action = text(payload.action);
  if (!["opened", "closed", "reopened", "ready_for_review"].includes(action)) {
    return null;
  }
  const pr = object(payload.pull_request);
  const number = count(pr.number) ?? count(payload.number);
  if (number === null) return null;
  const merged = action === "closed" && pr.merged === true;
  const verb = merged
    ? "merged"
    : action === "ready_for_review"
    ? "ready for review"
    : action === "opened" && pr.draft === true
    ? "opened (draft)"
    : action;
  const head = clip(object(pr.head).ref, 40);
  const into = clip(object(pr.base).ref, 40);
  const fields: NonNullable<Card["fields"]> = [];
  if (head !== "" && into !== "") {
    fields.push({ name: "Branches", value: `${head} → ${into}`, inline: true });
  }
  const added = count(pr.additions);
  const removed = count(pr.deletions);
  const files = count(pr.changed_files);
  if (added !== null && removed !== null && files !== null) {
    fields.push({
      name: "Changes",
      value: `+${added} −${removed} in ${files} file${files === 1 ? "" : "s"}`,
      inline: true,
    });
  }
  return card(base, {
    title: clip(
      `[${base.repo}] Pull request ${verb}: #${number} ${clip(pr.title, 80)}`,
      120,
    ),
    url: https(pr.html_url),
    description: action === "closed"
      ? undefined
      : clip(pr.body, 300, true) || undefined,
    color: merged ? PURPLE : action === "closed" ? RED : GREEN,
    fields: fields.length > 0 ? fields : undefined,
  });
}

function issue(payload: Json, base: ReturnType<typeof header>): Card | null {
  const action = text(payload.action);
  if (!["opened", "closed", "reopened"].includes(action)) return null;
  const item = object(payload.issue);
  const number = count(item.number);
  if (number === null) return null;
  const labels = list(item.labels)
    .map((label) => clip(object(label).name, 30))
    .filter((name) => name !== "")
    .slice(0, 6);
  return card(base, {
    title: clip(
      `[${base.repo}] Issue ${action}: #${number} ${clip(item.title, 80)}`,
      120,
    ),
    url: https(item.html_url),
    description: action === "opened"
      ? clip(item.body, 300, true) || undefined
      : undefined,
    color: action === "closed" ? PURPLE : GREEN,
    fields: labels.length > 0
      ? [{ name: "Labels", value: labels.join(", "), inline: true }]
      : undefined,
  });
}

function issueComment(
  payload: Json,
  base: ReturnType<typeof header>,
): Card | null {
  if (text(payload.action) !== "created") return null;
  const item = object(payload.issue);
  const comment = object(payload.comment);
  const number = count(item.number);
  if (number === null) return null;
  const onPull = item.pull_request !== undefined && item.pull_request !== null;
  return card(base, {
    title: clip(
      `[${base.repo}] New comment on ${
        onPull ? "pull request" : "issue"
      } #${number}: ${clip(item.title, 70)}`,
      120,
    ),
    url: https(comment.html_url),
    description: clip(comment.body, 400, true) || undefined,
    color: GRAY,
    footer: clip(object(comment.user).login, 39) || base.sender,
  });
}

function release(payload: Json, base: ReturnType<typeof header>): Card | null {
  if (text(payload.action) !== "published") return null;
  const item = object(payload.release);
  const name = clip(item.name, 80) || clip(item.tag_name, 80);
  if (name === "") return null;
  return card(base, {
    title: clip(
      `[${base.repo}] ${
        item.prerelease === true ? "Pre-release" : "Release"
      } published: ${name}`,
      120,
    ),
    url: https(item.html_url),
    description: clip(item.body, 500, true) || undefined,
    color: GREEN,
    footer: [clip(item.tag_name, 40), clip(object(item.author).login, 39)]
      .filter((part) => part !== "")
      .join(" · "),
  });
}

const WORKFLOW_VERBS: Record<string, [string, string]> = {
  success: ["succeeded", GREEN],
  failure: ["failed", RED],
  cancelled: ["was cancelled", GRAY],
  timed_out: ["timed out", RED],
};

function workflowRun(
  payload: Json,
  base: ReturnType<typeof header>,
): Card | null {
  if (text(payload.action) !== "completed") return null;
  const run = object(payload.workflow_run);
  const verdict = WORKFLOW_VERBS[text(run.conclusion)];
  if (verdict === undefined) return null;
  const fields: NonNullable<Card["fields"]> = [];
  const branch = clip(run.head_branch, 60);
  const event = clip(run.event, 30);
  if (branch !== "") {
    fields.push({ name: "Branch", value: branch, inline: true });
  }
  if (event !== "") fields.push({ name: "Event", value: event, inline: true });
  return card(base, {
    title: clip(
      `[${base.repo}] ${clip(run.name, 60) || "Workflow"} ${verdict[0]}`,
      120,
    ),
    url: https(run.html_url),
    description: clip(run.display_title, 200) || undefined,
    color: verdict[1],
    fields: fields.length > 0 ? fields : undefined,
    footer: clip(object(run.actor).login, 39) || base.sender,
  });
}

/**
 * The card for [event] ("push", "pull_request", ...) with [payload], or null
 * when there is nothing worth showing (an action this connection does not
 * report, a push without commits, an event we do not know).
 */
export function formatEvent(event: string, payload: unknown): Card | null {
  const body = object(payload);
  const base = header(body);
  switch (event) {
    case "push":
      return push(body, base);
    case "pull_request":
      return pullRequest(body, base);
    case "issues":
      return issue(body, base);
    case "issue_comment":
      return issueComment(body, base);
    case "release":
      return release(body, base);
    case "workflow_run":
      return workflowRun(body, base);
    default:
      return null;
  }
}
