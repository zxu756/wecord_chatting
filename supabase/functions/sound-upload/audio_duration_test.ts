import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import {
  measureAudio,
  opusPacketSamples,
  vorbisModeBlockFlags,
} from "./audio_duration.ts";

// ------------------------------------------------------------ fixtures

function text(value: string): number[] {
  return Array.from(value, (char) => char.charCodeAt(0));
}

function u16(value: number): number[] {
  return [value & 0xff, (value >> 8) & 0xff];
}

function u32(value: number): number[] {
  return [
    value & 0xff,
    (value >>> 8) & 0xff,
    (value >>> 16) & 0xff,
    (value >>> 24) & 0xff,
  ];
}

function wav(
  {
    seconds = 1,
    sampleRate = 8000,
    channels = 1,
    bits = 8,
    format = 1,
    byteRate,
    dataSize,
    extraData = 0,
  }: {
    seconds?: number;
    sampleRate?: number;
    channels?: number;
    bits?: number;
    format?: number;
    byteRate?: number;
    dataSize?: number;
    extraData?: number;
  } = {},
): Uint8Array {
  const blockAlign = channels * bits / 8;
  const length = Math.round(seconds * sampleRate) * blockAlign;
  const bytes = [
    ...text("RIFF"),
    ...u32(36 + length),
    ...text("WAVE"),
    ...text("fmt "),
    ...u32(16),
    ...u16(format),
    ...u16(channels),
    ...u32(sampleRate),
    ...u32(byteRate ?? sampleRate * blockAlign),
    ...u16(blockAlign),
    ...u16(bits),
    ...text("data"),
    ...u32(dataSize ?? length),
    ...new Array(length).fill(0x80),
  ];
  if (extraData > 0) {
    bytes.push(...text("data"), ...u32(extraData), ...new Array(extraData));
  }
  return new Uint8Array(bytes);
}

/// MPEG-1 Layer III frames at 128 kbps and 44.1 kHz (417 bytes, 26.1 ms).
function mp3Frames(count: number): number[] {
  const out: number[] = [];
  for (let index = 0; index < count; index++) {
    const frame = new Array(417).fill(0);
    frame[0] = 0xff;
    frame[1] = 0xfb;
    frame[2] = 0x90;
    frame[3] = 0x64;
    out.push(...frame);
  }
  return out;
}

function id3(): number[] {
  return [0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 20, ...new Array(20).fill(0)];
}

/// An Ogg stream holding packets, a page per packet (lacing included),
/// with whatever granule position the test likes.
function ogg(
  packets: number[][],
  { serial = 7, granule = () => 0 }: {
    serial?: number | ((index: number) => number);
    granule?: (index: number) => number;
  } = {},
): Uint8Array {
  const out: number[] = [];
  packets.forEach((packet, index) => {
    const lacing: number[] = [];
    let left = packet.length;
    while (left >= 255) {
      lacing.push(255);
      left -= 255;
    }
    lacing.push(left);
    out.push(
      ...text("OggS"),
      0,
      index === 0 ? 2 : index === packets.length - 1 ? 4 : 0,
      ...u32(granule(index)),
      ...u32(0),
      ...u32(typeof serial === "function" ? serial(index) : serial),
      ...u32(index),
      ...u32(0),
      lacing.length,
      ...lacing,
      ...packet,
    );
  });
  return new Uint8Array(out);
}

function opusHead(preSkip: number): number[] {
  return [...text("OpusHead"), 1, 2, ...u16(preSkip), ...u32(48000), 0, 0, 0];
}

const opusTags = [...text("OpusTags"), ...u32(0), ...u32(0)];

/// A CELT 20 ms packet (config 31, one frame).
const opus20ms = [31 << 3, 1, 2, 3];

/// Writes bits least significant first, like Vorbis.
class BitWriter {
  bytes: number[] = [];
  private bit = 0;
  write(value: number, count: number) {
    for (let index = 0; index < count; index++) {
      if (this.bit === 0) this.bytes.push(0);
      const last = this.bytes.length - 1;
      this.bytes[last] |= ((value >> index) & 1) << this.bit;
      this.bit = (this.bit + 1) % 8;
    }
  }
}

/// A Vorbis setup header whose last section lists modes with these block
/// flags, after some made-up codebook bytes.
function vorbisSetup(blockFlags: boolean[], filler: number[]): number[] {
  const writer = new BitWriter();
  writer.write(blockFlags.length - 1, 6);
  blockFlags.forEach((flag, mode) => {
    writer.write(flag ? 1 : 0, 1);
    writer.write(0, 16);
    writer.write(0, 16);
    writer.write(mode, 8);
  });
  writer.write(1, 1); // framing
  return [5, ...text("vorbis"), ...filler, ...writer.bytes];
}

function vorbisId(sampleRate: number, small = 8, large = 11): number[] {
  return [
    1,
    ...text("vorbis"),
    ...u32(0),
    2,
    ...u32(sampleRate),
    ...u32(0),
    ...u32(128000),
    ...u32(0),
    (large << 4) | small,
    1,
  ];
}

const vorbisComment = [3, ...text("vorbis"), ...u32(0), ...u32(0), 1];

/// A Vorbis audio packet in mode (two modes: one mode bit).
function vorbisAudio(mode: number): number[] {
  return [mode << 1, 0xaa, 0x55];
}

// ---------------------------------------------------------------- WAV

Deno.test("WAV length comes from sample rate and block align", () => {
  const result = measureAudio(wav({ seconds: 2.5 }));
  assert(result.ok);
  assertEquals(result.mimeType, "audio/wav");
  assertEquals(result.extension, "wav");
  assertAlmostEquals(result.seconds, 2.5, 1e-9);

  const stereo = measureAudio(
    wav({ seconds: 1.2, sampleRate: 22050, channels: 2, bits: 16 }),
  );
  assert(stereo.ok);
  assertAlmostEquals(stereo.seconds, 1.2, 1e-9);
});

Deno.test("a lying WAV byte rate or data size doesn't shorten it", () => {
  const result = measureAudio(wav({ seconds: 6, byteRate: 8000 * 100 }));
  assert(result.ok);
  assertAlmostEquals(result.seconds, 6, 1e-9);

  // A data size past the end counts only what is there; a later data
  // chunk counts too.
  const streamed = measureAudio(wav({ seconds: 3, dataSize: 0xffffffff }));
  assert(streamed.ok);
  assertAlmostEquals(streamed.seconds, 3, 1e-9);
  const twoChunks = measureAudio(wav({ seconds: 3, extraData: 24000 }));
  assert(twoChunks.ok);
  assertAlmostEquals(twoChunks.seconds, 6, 1e-9);
});

Deno.test("compressed or broken WAV files are refused", () => {
  assertEquals(measureAudio(wav({ format: 2 })), {
    ok: false,
    error: "unsupported",
  }); // MS ADPCM
  assertEquals(measureAudio(wav({ format: 0x55 })), {
    ok: false,
    error: "unsupported",
  }); // MP3 in WAV
  const noData = wav().subarray(0, 36);
  assertEquals(measureAudio(noData), { ok: false, error: "malformed" });
});

// ---------------------------------------------------------------- MP3

Deno.test("MP3 counts every frame", () => {
  const result = measureAudio(new Uint8Array([...id3(), ...mp3Frames(100)]));
  assert(result.ok);
  assertEquals(result.mimeType, "audio/mpeg");
  assertAlmostEquals(result.seconds, 100 * 1152 / 44100, 1e-9);

  const untagged = measureAudio(new Uint8Array(mp3Frames(10)));
  assert(untagged.ok);
  assertAlmostEquals(untagged.seconds, 10 * 1152 / 44100, 1e-9);
});

Deno.test("MP3 frames hidden after junk still count", () => {
  const junk = new Array(300).fill(0x11);
  const bytes = new Uint8Array([
    ...mp3Frames(50),
    ...junk,
    ...mp3Frames(200),
  ]);
  const result = measureAudio(bytes);
  assert(result.ok);
  assertAlmostEquals(result.seconds, 250 * 1152 / 44100, 1e-9);
  assert(result.seconds > 5.2);
});

Deno.test("anything else is refused", () => {
  assertEquals(measureAudio(new TextEncoder().encode("not audio at all")), {
    ok: false,
    error: "unsupported",
  });
  assertEquals(measureAudio(new Uint8Array([...id3(), 1, 2, 3])), {
    ok: false,
    error: "malformed",
  });
  assertEquals(measureAudio(new Uint8Array([...text("fLaC"), 0, 0, 0, 0])), {
    ok: false,
    error: "unsupported",
  });
});

// ---------------------------------------------------------------- Opus

Deno.test("Opus TOC bytes give each packet's samples", () => {
  assertEquals(opusPacketSamples(new Uint8Array([31 << 3])), 960); // CELT 20
  assertEquals(opusPacketSamples(new Uint8Array([16 << 3])), 120); // CELT 2.5
  assertEquals(opusPacketSamples(new Uint8Array([3 << 3])), 2880); // SILK 60
  assertEquals(opusPacketSamples(new Uint8Array([(13 << 3) | 1])), 1920);
  assertEquals(opusPacketSamples(new Uint8Array([(31 << 3) | 3, 6])), 5760);
  assertEquals(opusPacketSamples(new Uint8Array([(31 << 3) | 3, 7])), null);
  assertEquals(opusPacketSamples(new Uint8Array([])), null);
});

Deno.test("Ogg Opus counts its packets, not its granule positions", () => {
  const packets = [opusHead(312), opusTags];
  for (let index = 0; index < 150; index++) packets.push(opus20ms);
  const honest = measureAudio(
    ogg(packets, { granule: (index) => Math.max(0, index - 1) * 960 }),
  );
  assert(honest.ok);
  assertEquals(honest.mimeType, "audio/ogg");
  assertAlmostEquals(honest.seconds, (150 * 960 - 312) / 48000, 1e-9);

  // 300 packets (6 s) claiming one second: still 6 s.
  const long = [opusHead(0), opusTags];
  for (let index = 0; index < 300; index++) long.push(opus20ms);
  const faked = measureAudio(ogg(long, { granule: () => 48000 }));
  assert(faked.ok);
  assertAlmostEquals(faked.seconds, 6, 1e-9);
});

Deno.test("Ogg pages hidden after junk still count", () => {
  const first = ogg([opusHead(0), opusTags, opus20ms]);
  const rest = ogg(
    Array.from({ length: 260 }, () => opus20ms),
  ).subarray(0);
  const bytes = new Uint8Array([...first, 9, 9, 9, 9, ...rest]);
  const result = measureAudio(bytes);
  assert(result.ok);
  assertAlmostEquals(result.seconds, 261 * 0.02, 1e-9);
});

Deno.test("multiplexed, chained or other Ogg codecs are refused", () => {
  const packets = [opusHead(0), opusTags, opus20ms];
  assertEquals(
    measureAudio(ogg(packets, { serial: (index) => index })),
    { ok: false, error: "unsupported" },
  );
  assertEquals(
    measureAudio(ogg([[0x7f, ...text("FLAC"), 1, 0]])),
    { ok: false, error: "unsupported" },
  );
  assertEquals(
    measureAudio(ogg([opusHead(0), opusTags, []])),
    { ok: false, error: "malformed" },
  );
});

// ---------------------------------------------------------------- Vorbis

Deno.test("Vorbis modes are read from the end of the setup header", () => {
  const filler = Array.from({ length: 200 }, (_, index) => (index * 37) & 0xff);
  assertEquals(
    vorbisModeBlockFlags(new Uint8Array(vorbisSetup([false, true], filler))),
    [false, true],
  );
  assertEquals(
    vorbisModeBlockFlags(
      new Uint8Array(vorbisSetup([true, false, true, true], filler)),
    ),
    [true, false, true, true],
  );
  assertEquals(
    vorbisModeBlockFlags(new Uint8Array([5, ...text("vorbis"), 0, 0])),
    null,
  );
});

Deno.test("Ogg Vorbis counts samples from block sizes", () => {
  const filler = new Array(120).fill(0xff);
  const packets = [
    vorbisId(44100),
    vorbisComment,
    vorbisSetup([false, true], filler),
  ];
  // 100 long blocks (2048): 99 × (512 + 512) samples.
  for (let index = 0; index < 100; index++) packets.push(vorbisAudio(1));
  const long = measureAudio(ogg(packets, { granule: () => 4410 }));
  assert(long.ok);
  assertAlmostEquals(long.seconds, 99 * 1024 / 44100, 1e-9);

  // Short (256) and long blocks mixed: 64 + 512, 512 + 64, 64 + 64.
  const mixed = [
    vorbisId(44100),
    vorbisComment,
    vorbisSetup([false, true], filler),
    vorbisAudio(0),
    vorbisAudio(1),
    vorbisAudio(0),
    vorbisAudio(0),
  ];
  const result = measureAudio(ogg(mixed));
  assert(result.ok);
  assertAlmostEquals(result.seconds, (576 + 576 + 128) / 44100, 1e-9);
});

Deno.test("a Vorbis stream without a readable setup header is refused", () => {
  assertEquals(
    measureAudio(ogg([vorbisId(44100), vorbisComment, [5, 1, 2]])),
    { ok: false, error: "malformed" },
  );
});
