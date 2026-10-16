import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  checkClip,
  maxSoundBytes,
  readUploadFields,
  refusalForRpcError,
} from "./request.ts";

const circle = "5BC6E021-F4F7-47D5-9A7B-9CB7529015E0";

/// A mono 8-bit PCM WAV of [seconds] at 8 kHz.
function wav(seconds: number): Uint8Array {
  const samples = Math.round(seconds * 8000);
  const bytes = new Uint8Array(44 + samples);
  const data = new DataView(bytes.buffer);
  const ascii = (offset: number, text: string) => {
    for (let i = 0; i < text.length; i++) {
      bytes[offset + i] = text.charCodeAt(i);
    }
  };
  ascii(0, "RIFF");
  data.setUint32(4, 36 + samples, true);
  ascii(8, "WAVE");
  ascii(12, "fmt ");
  data.setUint32(16, 16, true);
  data.setUint16(20, 1, true);
  data.setUint16(22, 1, true);
  data.setUint32(24, 8000, true);
  data.setUint32(28, 8000, true);
  data.setUint16(32, 1, true);
  data.setUint16(34, 8, true);
  ascii(36, "data");
  data.setUint32(40, samples, true);
  return bytes;
}

Deno.test("reads the form fields", () => {
  assertEquals(
    readUploadFields({ circle_id: circle, name: " Airhorn ", emoji: " 📯 " }),
    {
      ok: true,
      circleId: circle.toLowerCase(),
      name: "Airhorn",
      emoji: "📯",
    },
  );
  assertEquals(
    readUploadFields({ circle_id: circle, name: "Ding", emoji: "" }),
    { ok: true, circleId: circle.toLowerCase(), name: "Ding", emoji: null },
  );
  for (
    const fields of [
      { circle_id: "x", name: "Ding" },
      { circle_id: circle, name: " " },
      { circle_id: circle, name: "x".repeat(33) },
      { circle_id: circle, name: "Ding", emoji: "x".repeat(17) },
    ]
  ) {
    assertEquals(readUploadFields(fields), {
      ok: false,
      status: 400,
      error: "invalid_request",
    });
  }
});

Deno.test("accepts clips up to 5.2 seconds, storing at most 5000 ms", () => {
  const short = checkClip(wav(1.5));
  assert(short.ok);
  assertEquals(short.mimeType, "audio/wav");
  assertEquals(short.extension, "wav");
  assertEquals(short.durationMs, 1500);

  const edge = checkClip(wav(5.15));
  assert(edge.ok);
  assertEquals(edge.durationMs, 5000);
});

Deno.test("refuses long, big, empty and unverifiable clips", () => {
  assertEquals(checkClip(wav(5.3)), {
    ok: false,
    status: 400,
    error: "too_long",
  });
  assertEquals(checkClip(new Uint8Array(maxSoundBytes + 1)), {
    ok: false,
    status: 413,
    error: "too_large",
  });
  assertEquals(checkClip(new Uint8Array()), {
    ok: false,
    status: 400,
    error: "missing_file",
  });
  assertEquals(checkClip(new TextEncoder().encode("hello")), {
    ok: false,
    status: 415,
    error: "unsupported_format",
  });
  assertEquals(checkClip(wav(0)), {
    ok: false,
    status: 400,
    error: "malformed",
  });
});

Deno.test("maps create_circle_sound refusals", () => {
  assertEquals(refusalForRpcError("42501").status, 403);
  assertEquals(refusalForRpcError("23505").error, "name_taken");
  assertEquals(refusalForRpcError("54000").error, "no_room");
  assertEquals(refusalForRpcError("22023").status, 400);
  assertEquals(refusalForRpcError(undefined).status, 500);
});
