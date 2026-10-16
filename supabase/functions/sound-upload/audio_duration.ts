// Measures how long a soundboard clip plays, from its bytes, without
// decoding audio. The client's own measurement can't be trusted, so each
// format is read the way a player reads it and, where a file could say
// one thing and play another, the longer reading wins:
//
// * WAV: PCM, IEEE float, A-law or µ-law only (and their
//   WAVE_FORMAT_EXTENSIBLE forms). Length = bytes in every data chunk /
//   (sample rate × block align), which is what players use; the byte rate
//   field, which a file can set to anything, is ignored. Compressed WAV
//   (ADPCM, MP3 in WAV, …) is refused.
// * MP3: every MPEG audio frame (Layer I, II or III, MPEG 1, 2 or 2.5) is
//   counted, including frames after junk (decoders resync), not the
//   Xing/VBRI header's count. Free-format streams are refused.
// * Ogg: one logical stream of Opus or Vorbis. Opus: the samples of every
//   packet from its TOC byte, minus the pre-skip. Vorbis: the samples of
//   every audio packet from its mode's block size (the modes are read from
//   the end of the setup header, like FFmpeg's vorbis parser does).
//   Granule positions, which a file can fake, are ignored. Other Ogg codecs
//   (FLAC, Speex) and chained or multiplexed streams are refused.

export type AudioFormat = "wav" | "mp3" | "ogg";

export type AudioMeasurement =
  | {
    ok: true;
    format: AudioFormat;
    mimeType: "audio/wav" | "audio/mpeg" | "audio/ogg";
    extension: AudioFormat;
    seconds: number;
  }
  | { ok: false; error: "unsupported" | "malformed" };

const unsupported = { ok: false, error: "unsupported" } as const;
const malformed = { ok: false, error: "malformed" } as const;

function ascii(bytes: Uint8Array, offset: number, text: string): boolean {
  if (offset < 0 || offset + text.length > bytes.length) return false;
  for (let index = 0; index < text.length; index++) {
    if (bytes[offset + index] !== text.charCodeAt(index)) return false;
  }
  return true;
}

function view(bytes: Uint8Array): DataView {
  return new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
}

/// Reads the clip's format and length; refuses what it can't verify.
export function measureAudio(bytes: Uint8Array): AudioMeasurement {
  if (ascii(bytes, 0, "RIFF") && ascii(bytes, 8, "WAVE")) {
    return measureWav(bytes);
  }
  if (ascii(bytes, 0, "OggS")) {
    return measureOgg(bytes);
  }
  if (ascii(bytes, 0, "RIFF") || ascii(bytes, 0, "fLaC")) {
    return unsupported;
  }
  return measureMp3(bytes);
}

// ---------------------------------------------------------------- WAV

const wavFormats = new Set([1, 3, 6, 7]);

export function measureWav(bytes: Uint8Array): AudioMeasurement {
  const data = view(bytes);
  let offset = 12;
  let sampleRate = 0;
  let blockAlign = 0;
  let dataBytes = 0;
  let sawData = false;
  while (offset + 8 <= bytes.length) {
    const size = data.getUint32(offset + 4, true);
    const body = offset + 8;
    const available = Math.max(0, bytes.length - body);
    if (ascii(bytes, offset, "fmt ")) {
      if (size < 16 || available < 16) return malformed;
      let format = data.getUint16(body, true);
      if (format === 0xfffe) {
        // WAVE_FORMAT_EXTENSIBLE: the real format leads the sub-format GUID.
        if (size < 40 || available < 40) return malformed;
        format = data.getUint16(body + 24, true);
      }
      if (!wavFormats.has(format)) return unsupported;
      const channels = data.getUint16(body + 2, true);
      sampleRate = data.getUint32(body + 4, true);
      blockAlign = data.getUint16(body + 12, true);
      const bits = data.getUint16(body + 14, true);
      if (
        channels === 0 || sampleRate === 0 || blockAlign === 0 || bits === 0
      ) {
        return malformed;
      }
    } else if (ascii(bytes, offset, "data")) {
      sawData = true;
      // Streams write an unknown (or too large) size; count what is there.
      dataBytes += Math.min(size, available);
    }
    offset = body + size + (size % 2);
  }
  if (!sawData || sampleRate === 0 || blockAlign === 0) return malformed;
  return {
    ok: true,
    format: "wav",
    mimeType: "audio/wav",
    extension: "wav",
    seconds: dataBytes / (sampleRate * blockAlign),
  };
}

// ---------------------------------------------------------------- MP3

const mpeg1Bitrates = [
  [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
  [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
  [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
];
const mpeg2Bitrates = [
  [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
  [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
  [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
];
const mpegSampleRates: Record<number, number[]> = {
  3: [44100, 48000, 32000], // MPEG 1
  2: [22050, 24000, 16000], // MPEG 2
  0: [11025, 12000, 8000], // MPEG 2.5
};

/// The MPEG audio frame starting at offset: its length in bytes and in
/// seconds, or null when there is none.
export function mpegFrame(
  bytes: Uint8Array,
  offset: number,
): { length: number; seconds: number } | null {
  if (
    offset + 4 > bytes.length || bytes[offset] !== 0xff ||
    (bytes[offset + 1] & 0xe0) !== 0xe0
  ) {
    return null;
  }
  const version = (bytes[offset + 1] >> 3) & 0x3;
  const layerBits = (bytes[offset + 1] >> 1) & 0x3;
  const bitrateIndex = bytes[offset + 2] >> 4;
  const sampleRateIndex = (bytes[offset + 2] >> 2) & 0x3;
  const padding = (bytes[offset + 2] >> 1) & 0x1;
  const rates = mpegSampleRates[version];
  if (
    !rates || layerBits === 0 || bitrateIndex === 0 || bitrateIndex === 15 ||
    sampleRateIndex === 3
  ) {
    return null;
  }
  const layer = 4 - layerBits;
  const mpeg1 = version === 3;
  const bitrate =
    (mpeg1 ? mpeg1Bitrates : mpeg2Bitrates)[layer - 1][bitrateIndex] * 1000;
  const sampleRate = rates[sampleRateIndex];
  let samples: number;
  let length: number;
  if (layer === 1) {
    samples = 384;
    length = (Math.floor(12 * bitrate / sampleRate) + padding) * 4;
  } else if (layer === 3 && !mpeg1) {
    samples = 576;
    length = Math.floor(72 * bitrate / sampleRate) + padding;
  } else {
    samples = 1152;
    length = Math.floor(144 * bitrate / sampleRate) + padding;
  }
  if (length < 4) return null;
  return { length, seconds: samples / sampleRate };
}

function id3v2Length(bytes: Uint8Array, offset: number): number {
  if (!ascii(bytes, offset, "ID3") || offset + 10 > bytes.length) return 0;
  const size = ((bytes[offset + 6] & 0x7f) << 21) |
    ((bytes[offset + 7] & 0x7f) << 14) |
    ((bytes[offset + 8] & 0x7f) << 7) |
    (bytes[offset + 9] & 0x7f);
  const footer = (bytes[offset + 5] & 0x10) !== 0 ? 10 : 0;
  return 10 + size + footer;
}

export function measureMp3(bytes: Uint8Array): AudioMeasurement {
  let offset = id3v2Length(bytes, 0);
  const tagged = offset > 0;
  let seconds = 0;
  let frames = 0;
  let inChain = false;
  while (offset + 4 <= bytes.length) {
    const frame = mpegFrame(bytes, offset);
    // A frame counts when it follows a counted frame, or when another
    // frame (or the end) follows it, so stray sync bytes in junk don't;
    // decoders resync past junk, so frames after it count too.
    if (frame) {
      const next = offset + frame.length;
      if (
        inChain || next >= bytes.length || mpegFrame(bytes, next) !== null
      ) {
        seconds += frame.seconds;
        frames++;
        offset = next;
        inChain = true;
        continue;
      }
    }
    inChain = false;
    offset++;
  }
  if (frames === 0) {
    return tagged ? malformed : unsupported;
  }
  return {
    ok: true,
    format: "mp3",
    mimeType: "audio/mpeg",
    extension: "mp3",
    seconds,
  };
}

// ---------------------------------------------------------------- Ogg

/// The packets of a single logical Ogg stream, in order, read page by page
/// (junk between pages is skipped). Null when it isn't one stream.
export function oggPackets(bytes: Uint8Array): Uint8Array[] | null {
  const data = view(bytes);
  const packets: Uint8Array[] = [];
  let pending: Uint8Array[] = [];
  let serial: number | null = null;
  let offset = 0;
  while (offset + 27 <= bytes.length) {
    if (!ascii(bytes, offset, "OggS") || bytes[offset + 4] !== 0) {
      offset++;
      continue;
    }
    const segments = bytes[offset + 26];
    const header = 27 + segments;
    if (offset + header > bytes.length) break;
    let bodyLength = 0;
    for (let index = 0; index < segments; index++) {
      bodyLength += bytes[offset + 27 + index];
    }
    if (offset + header + bodyLength > bytes.length) {
      // A truncated last page: players drop it.
      break;
    }
    const pageSerial = data.getUint32(offset + 14, true);
    if (serial === null) {
      serial = pageSerial;
    } else if (pageSerial !== serial) {
      return null;
    }
    let cursor = offset + header;
    let segmentStart = cursor;
    for (let index = 0; index < segments; index++) {
      const lace = bytes[offset + 27 + index];
      cursor += lace;
      if (lace < 255) {
        pending.push(bytes.subarray(segmentStart, cursor));
        packets.push(concat(pending));
        pending = [];
        segmentStart = cursor;
      }
    }
    if (segmentStart < cursor) {
      pending.push(bytes.subarray(segmentStart, cursor));
    }
    offset += header + bodyLength;
  }
  return serial === null ? null : packets;
}

function concat(parts: Uint8Array[]): Uint8Array {
  if (parts.length === 1) return parts[0];
  const length = parts.reduce((sum, part) => sum + part.length, 0);
  const out = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

export function measureOgg(bytes: Uint8Array): AudioMeasurement {
  const packets = oggPackets(bytes);
  if (!packets) return unsupported;
  if (packets.length === 0) return malformed;
  const first = packets[0];
  let seconds: number | null;
  if (ascii(first, 0, "OpusHead")) {
    seconds = opusSeconds(packets);
  } else if (first[0] === 1 && ascii(first, 1, "vorbis")) {
    seconds = vorbisSeconds(packets);
  } else {
    return unsupported;
  }
  if (seconds === null) return malformed;
  return {
    ok: true,
    format: "ogg",
    mimeType: "audio/ogg",
    extension: "ogg",
    seconds,
  };
}

/// Samples (at 48 kHz) in one Opus packet, from its TOC byte (RFC 6716
/// section 3.1), or null when the packet is invalid.
export function opusPacketSamples(packet: Uint8Array): number | null {
  if (packet.length === 0) return null;
  const toc = packet[0];
  const config = toc >> 3;
  let frameSize: number;
  if (config < 12) {
    frameSize = [480, 960, 1920, 2880][config % 4]; // SILK 10–60 ms
  } else if (config < 16) {
    frameSize = [480, 960][config % 2]; // Hybrid 10–20 ms
  } else {
    frameSize = [120, 240, 480, 960][config % 4]; // CELT 2.5–20 ms
  }
  const code = toc & 0x3;
  let frames: number;
  if (code === 0) {
    frames = 1;
  } else if (code === 1 || code === 2) {
    frames = 2;
  } else {
    if (packet.length < 2) return null;
    frames = packet[1] & 0x3f;
    if (frames === 0) return null;
  }
  // A packet holds at most 120 ms.
  if (frames * frameSize > 5760) return null;
  return frames * frameSize;
}

function opusSeconds(packets: Uint8Array[]): number | null {
  const head = packets[0];
  if (head.length < 19 || head[8] !== 1) return null;
  const preSkip = view(head).getUint16(10, true);
  if (packets.length < 2 || !ascii(packets[1], 0, "OpusTags")) return null;
  let samples = 0;
  for (const packet of packets.slice(2)) {
    const count = opusPacketSamples(packet);
    if (count === null) return null;
    samples += count;
  }
  return Math.max(0, samples - preSkip) / 48000;
}

/// Reads bits of a Vorbis packet (least significant bit first).
class BitReader {
  private position = 0;
  constructor(private readonly bytes: Uint8Array) {}

  read(count: number): number | null {
    let value = 0;
    for (let index = 0; index < count; index++) {
      const byte = this.position >> 3;
      if (byte >= this.bytes.length) return null;
      const bit = (this.bytes[byte] >> (this.position & 7)) & 1;
      value |= bit << index;
      this.position++;
    }
    return value;
  }
}

/// Reads a Vorbis packet's bits from its end backwards: the last bit
/// first, multi-bit fields coming out as their forward values.
class ReverseBitReader {
  private position = 0;
  constructor(private readonly bytes: Uint8Array) {}

  get left(): number {
    return this.bytes.length * 8 - this.position;
  }

  get offset(): number {
    return this.position;
  }

  seek(position: number) {
    this.position = position;
  }

  read(count: number): number {
    let value = 0;
    for (let index = 0; index < count; index++) {
      const r = this.position++;
      const byte = this.bytes[this.bytes.length - 1 - (r >> 3)];
      value = value * 2 + ((byte >> (7 - (r & 7))) & 1);
    }
    return value;
  }
}

/// Each mode's block flag, from the end of a Vorbis setup header (the
/// modes are its last section; reading backwards finds them without
/// decoding the codebooks before). Null when there are none.
export function vorbisModeBlockFlags(setup: Uint8Array): boolean[] | null {
  if (setup[0] !== 5 || !ascii(setup, 1, "vorbis")) return null;
  const reader = new ReverseBitReader(setup.subarray(7));
  // Padding, then the framing bit.
  let framing = -1;
  while (reader.left > 97) {
    if (reader.read(1) === 1) {
      framing = reader.offset;
      break;
    }
  }
  if (framing < 0) return null;
  // Each mode backwards: mapping (8 bits, < 64), transform type (16, 0),
  // window type (16, 0), block flag (1). Before the first mode, the mode
  // count minus one (6 bits) must match.
  let count = 0;
  let modeCount = 0;
  while (reader.left >= 97) {
    if (reader.read(8) > 63 || reader.read(16) !== 0 || reader.read(16) !== 0) {
      break;
    }
    reader.read(1);
    count++;
    if (count > 64) break;
    const position = reader.offset;
    if (reader.read(6) + 1 === count) modeCount = count;
    reader.seek(position);
  }
  if (modeCount === 0) return null;
  reader.seek(framing);
  const flags: boolean[] = new Array(modeCount);
  for (let mode = modeCount - 1; mode >= 0; mode--) {
    reader.read(40);
    flags[mode] = reader.read(1) === 1;
  }
  return flags;
}

function ilog(value: number): number {
  let bits = 0;
  while (value > 0) {
    bits++;
    value >>= 1;
  }
  return bits;
}

function vorbisSeconds(packets: Uint8Array[]): number | null {
  const id = packets[0];
  if (id.length < 30) return null;
  const sampleRate = view(id).getUint32(12, true);
  const blockSizes = [1 << (id[28] & 0x0f), 1 << (id[28] >> 4)];
  if (
    sampleRate === 0 || blockSizes[0] < 64 || blockSizes[1] < blockSizes[0] ||
    blockSizes[1] > 8192
  ) {
    return null;
  }
  if (
    packets.length < 3 || packets[1][0] !== 3 ||
    !ascii(packets[1], 1, "vorbis")
  ) {
    return null;
  }
  const flags = vorbisModeBlockFlags(packets[2]);
  if (!flags) return null;
  const modeBits = ilog(flags.length - 1);
  let samples = 0;
  let previous: number | null = null;
  for (const packet of packets.slice(3)) {
    const reader = new BitReader(packet);
    // Not an audio packet, or one decoders can't use: no samples.
    if (reader.read(1) !== 0) continue;
    const mode = reader.read(modeBits);
    if (mode === null || mode >= flags.length) continue;
    const block = blockSizes[flags[mode] ? 1 : 0];
    if (previous !== null) {
      samples += previous / 4 + block / 4;
    }
    previous = block;
  }
  return samples / sampleRate;
}
