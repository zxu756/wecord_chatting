import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  basicAuthorization,
  conversionFileName,
  errorResponse,
  fileAttachmentOf,
  gotenbergConvertUrl,
  jsonResponse,
  looksLikePdf,
  officeExtension,
  parsePreviewRequest,
  previewObjectPath,
  readGotenbergConfig,
  statusFor,
} from "./preview_helpers.ts";

const ID = "3f6c1d2e-8a4b-4c7d-9e0f-1a2b3c4d5e6f";

Deno.test("reads message_id and refuses anything else", () => {
  assertEquals(parsePreviewRequest({ message_id: ID }), {
    ok: true,
    messageId: ID,
  });
  assertEquals(parsePreviewRequest({ message_id: ` ${ID.toUpperCase()} ` }), {
    ok: true,
    messageId: ID,
  });
  assertEquals(parsePreviewRequest(null), { ok: false, error: "invalid_body" });
  assertEquals(parsePreviewRequest([ID]), { ok: false, error: "invalid_body" });
  assertEquals(parsePreviewRequest({ message_id: "x/../y" }), {
    ok: false,
    error: "invalid_message_id",
  });
  assertEquals(parsePreviewRequest({ message_id: 42 }), {
    ok: false,
    error: "invalid_message_id",
  });
});

Deno.test("previews live under the message id", () => {
  assertEquals(previewObjectPath(ID.toUpperCase()), `${ID}/preview.pdf`);
});

Deno.test("finds the file of file messages only", () => {
  const attachment = {
    kind: "file",
    bucket: "chat-files",
    path: "c/1-plan.docx",
    name: "Plan.docx",
    mime_type: "application/octet-stream",
    size: 1200,
  };
  assertEquals(fileAttachmentOf({ type: "file", attachment }), {
    bucket: "chat-files",
    path: "c/1-plan.docx",
    name: "Plan.docx",
    mimeType: "application/octet-stream",
    size: 1200,
  });
  assertEquals(fileAttachmentOf({ type: "image", attachment }), null);
  assertEquals(
    fileAttachmentOf({ type: "file", attachment, recalled_at: "2026-10-16" }),
    null,
  );
  assertEquals(fileAttachmentOf({ type: "file", attachment: null }), null);
  assertEquals(
    fileAttachmentOf({ type: "file", attachment: { kind: "file", bucket: 1 } }),
    null,
  );
  assertEquals(
    fileAttachmentOf({
      type: "file",
      attachment: { kind: "file", bucket: "chat-files", path: "c/notes.odt" },
    })?.name,
    "notes.odt",
  );
});

Deno.test("knows Office files by extension, then by MIME type", () => {
  assertEquals(
    officeExtension("Q3 Report.DOCX", "application/octet-stream"),
    "docx",
  );
  assertEquals(officeExtension("deck.key", ""), "key");
  assertEquals(officeExtension("budget.numbers", ""), "numbers");
  assertEquals(
    officeExtension(
      "download",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ),
    "xlsx",
  );
  assertEquals(officeExtension("photo.png", "image/png"), null);
  assertEquals(officeExtension("report.pdf", "application/pdf"), null);
});

Deno.test("needs the URL and both credentials", () => {
  const env = (values: Record<string, string>) => (name: string) =>
    values[name];
  assertEquals(readGotenbergConfig(env({})), null);
  assertEquals(
    readGotenbergConfig(env({ GOTENBERG_URL: "https://convert.example.com" })),
    null,
  );
  assertEquals(
    readGotenbergConfig(
      env({
        GOTENBERG_URL: "https://convert.example.com",
        GOTENBERG_USERNAME: "wecord",
      }),
    ),
    null,
  );
  assertEquals(
    readGotenbergConfig(
      env({
        GOTENBERG_URL: "not a url",
        GOTENBERG_USERNAME: "wecord",
        GOTENBERG_PASSWORD: "secret",
      }),
    ),
    null,
  );
  assertEquals(
    readGotenbergConfig(
      env({
        GOTENBERG_URL: "https://convert.example.com/",
        GOTENBERG_USERNAME: "wecord",
        GOTENBERG_PASSWORD: "s3cr3t",
      }),
    ),
    {
      convertUrl: "https://convert.example.com/forms/libreoffice/convert",
      authorization: `Basic ${btoa("wecord:s3cr3t")}`,
    },
  );
});

Deno.test("builds the convert URL and a UTF-8 Basic header", () => {
  assertEquals(
    gotenbergConvertUrl("https://g.example.run.app//"),
    "https://g.example.run.app/forms/libreoffice/convert",
  );
  assertEquals(basicAuthorization("a", "b"), "Basic YTpi");
  assertEquals(basicAuthorization("用户", "pw"), "Basic 55So5oi3OnB3");
});

Deno.test("uploads under a plain name with the extension", () => {
  assertEquals(conversionFileName("docx"), "document.docx");
  assertEquals(conversionFileName("x/../ls"), "document.xls");
});

Deno.test("error responses carry their status, code and CORS", async () => {
  const response = errorResponse("preview_not_configured");
  assertEquals(response.status, 503);
  assertEquals(await response.json(), { error: "preview_not_configured" });
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), "*");
  assertEquals(statusFor("unsupported_type"), 415);
  assertEquals(statusFor("not_found"), 404);
  assertEquals(statusFor("unauthorized"), 401);
  const ok = jsonResponse({ status: "ok", url: "https://x", cached: true });
  assertEquals(ok.status, 200);
  assertEquals(ok.headers.get("Content-Type"), "application/json");
});

Deno.test("recognises PDF bytes", () => {
  assert(looksLikePdf(new TextEncoder().encode("%PDF-1.7\n...")));
  assertFalse(looksLikePdf(new TextEncoder().encode("<html>")));
  assertFalse(looksLikePdf(new Uint8Array()));
});
