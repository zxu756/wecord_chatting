// Forms (D1): my own answers in the archive, nobody else's.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  buildExportFiles,
  type ExportData,
  formFilesToSign,
} from "./export_builder.ts";

const base: ExportData = {
  generatedAt: "2026-10-23T14:03:00.000Z",
  user: {
    id: "u-1",
    email: "ada@example.com",
    createdAt: null,
    lastSignInAt: null,
  },
  profile: { id: "u-1", username: "ada", display_name: "Ada" },
  settings: {},
  friends: [],
  friendRequests: [],
  blocked: [],
  conversations: [
    {
      id: "c-2",
      kind: "group",
      name: "Climbing crew",
      circleName: null,
      joinedAt: null,
      role: "owner",
      createdAt: null,
    },
  ],
  messages: [],
  circles: [],
  moments: null,
  extras: null,
  files: [],
  attachmentLinks: {},
  linksExpireAt: "2026-10-30T14:03:00.000Z",
  skipped: [],
};

const questions = [
  { id: "name", type: "short_text", label: "Your name", options: null },
  {
    id: "size",
    type: "single_choice",
    label: "T-shirt size",
    options: [{ id: "m", label: "Medium" }, { id: "l", label: "Large" }],
  },
  {
    id: "food",
    type: "multiple_choice",
    label: "Food",
    options: [{ id: "veg", label: "Vegetarian" }, { id: "fish", label: "Fish" }],
  },
  { id: "photo", type: "image", label: "A photo", options: null },
];

const answered = {
  id: "f-1",
  conversation_id: "c-2",
  title: "Hike sign-up",
  created_by_me: false,
  creator: { id: "u-2", username: "bart", display_name: "Bart" },
  description: null,
  settings: null,
  response_count: null,
  questions,
  created_at: "2026-10-20T08:00:00Z",
  my_responses: [{
    answers: {
      name: "Ada <script>",
      size: "m",
      food: ["veg", "fish"],
      photo: { bucket: "chat-images", path: "c-2/forms/f-1/pic.jpg" },
    },
    submitted_at: "2026-10-20T09:00:00Z",
    updated_at: "2026-10-20T09:00:00Z",
  }],
};

const made = {
  id: "f-2",
  conversation_id: "c-2",
  title: "Feedback",
  created_by_me: true,
  creator: { id: "u-1", username: "ada", display_name: "Ada" },
  description: "What went well?",
  settings: { anonymous: true },
  response_count: 7,
  questions: [{ id: "say", type: "long_text", label: "Say", options: null }],
  created_at: "2026-10-21T08:00:00Z",
  my_responses: [],
};

function texts(input: ExportData): Record<string, string> {
  return Object.fromEntries(
    buildExportFiles(input).map((f) => [f.path, f.content]),
  );
}

Deno.test("forms add a page and a JSON file with my own answers", () => {
  const files = texts({
    ...base,
    forms: [answered, made],
    attachmentLinks: {
      "chat-images/c-2/forms/f-1/pic.jpg": "https://files.example/pic?t=1",
    },
  });
  assert("pages/forms.html" in files);
  assert("data/forms.json" in files);
  assertStringIncludes(files["index.html"], 'href="pages/forms.html"');
  assertStringIncludes(files["README.txt"], "data/forms.json");

  const page = files["pages/forms.html"];
  assertStringIncludes(page, "Hike sign-up");
  assertStringIncludes(page, "made by Bart");
  assertStringIncludes(page, "Climbing crew");
  // Choices are in words, text is escaped, the picture is a link.
  assertStringIncludes(page, "Medium");
  assertStringIncludes(page, "Vegetarian, Fish");
  assertStringIncludes(page, "Ada &lt;script&gt;");
  assert(!page.includes("<script>"));
  assertStringIncludes(page, "https://files.example/pic?t=1");
  // My own form: its text and the number of answers, not the answers.
  assertStringIncludes(page, "you made it");
  assertStringIncludes(page, "What went well?");
  assertStringIncludes(page, "7 answers in all (not included)");
  assertStringIncludes(page, "You did not answer this form.");

  const json = JSON.parse(files["data/forms.json"]);
  assertEquals(json.length, 2);
  assertEquals(json[0].my_responses[0].readable[1], {
    question: "T-shirt size",
    answer: "Medium",
    picture: null,
  });
  assertEquals(json[0].my_responses[0].readable[3].picture.download_url,
    "https://files.example/pic?t=1");
});

Deno.test("no forms say so; an export without the part has no page", () => {
  const empty = texts({ ...base, forms: [] });
  assertStringIncludes(empty["pages/forms.html"], "No forms.");
  const absent = texts(base);
  assert(!("pages/forms.html" in absent));
  assert(!("data/forms.json" in absent));
  const failed = texts({ ...base, forms: null });
  assert(!("pages/forms.html" in failed));
});

Deno.test("the pictures I attached are linked, once", () => {
  assertEquals(formFilesToSign([answered, answered, made]), [
    { bucket: "chat-images", path: "c-2/forms/f-1/pic.jpg" },
  ]);
});
