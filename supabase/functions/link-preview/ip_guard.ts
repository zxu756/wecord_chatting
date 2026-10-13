// Pure URL and address checks for the link-preview function. Kept free of
// network and Deno APIs so they can be unit tested.

export const MAX_URL_LENGTH = 2048;

export type UrlCheck =
  | { ok: true; url: URL }
  | { ok: false; reason: "invalid" | "unsupported" | "blocked" };

/**
 * Parses and normalizes a link: http(s) only, default ports only, no
 * credentials, no fragment, no internal-looking host names.
 */
export function normalizePreviewUrl(raw: string, base?: string): UrlCheck {
  const value = raw.trim();
  if (value.length === 0 || value.length > MAX_URL_LENGTH) {
    return { ok: false, reason: "invalid" };
  }
  let url: URL;
  try {
    url = base === undefined ? new URL(value) : new URL(value, base);
  } catch {
    return { ok: false, reason: "invalid" };
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    return { ok: false, reason: "unsupported" };
  }
  if (url.username !== "" || url.password !== "") {
    return { ok: false, reason: "unsupported" };
  }
  if (url.port !== "" && url.port !== "80" && url.port !== "443") {
    return { ok: false, reason: "blocked" };
  }
  url.hash = "";
  if (url.href.length > MAX_URL_LENGTH) {
    return { ok: false, reason: "invalid" };
  }
  const host = bareHostname(url.hostname);
  if (host.length === 0) {
    return { ok: false, reason: "invalid" };
  }
  if (isIpLiteral(host)) {
    return isBlockedAddress(host)
      ? { ok: false, reason: "blocked" }
      : { ok: true, url };
  }
  if (isInternalHostname(host)) {
    return { ok: false, reason: "blocked" };
  }
  return { ok: true, url };
}

/** Strips IPv6 brackets and a trailing root dot. */
export function bareHostname(hostname: string): string {
  let host = hostname.toLowerCase();
  if (host.startsWith("[") && host.endsWith("]")) {
    host = host.slice(1, -1);
  }
  if (host.endsWith(".")) {
    host = host.slice(0, -1);
  }
  return host;
}

export function isIpLiteral(host: string): boolean {
  return parseIpv4(host) !== null || parseIpv6(host) !== null;
}

/** Single-label names and reserved suffixes never point at the internet. */
export function isInternalHostname(host: string): boolean {
  if (!host.includes(".")) {
    return true;
  }
  return [".localhost", ".local", ".internal", ".home.arpa", ".lan"].some(
    (suffix) => host.endsWith(suffix),
  );
}

/**
 * True for loopback, private, link-local, CGNAT, metadata, multicast,
 * documentation and other non-public addresses (IPv4 or IPv6).
 */
export function isBlockedAddress(address: string): boolean {
  const host = bareHostname(address);
  const v4 = parseIpv4(host);
  if (v4 !== null) {
    return isBlockedIpv4(v4);
  }
  const v6 = parseIpv6(host);
  if (v6 !== null) {
    return isBlockedIpv6(v6);
  }
  // Anything unparseable is treated as unsafe.
  return true;
}

export function parseIpv4(value: string): number[] | null {
  const parts = value.split(".");
  if (parts.length !== 4) {
    return null;
  }
  const octets: number[] = [];
  for (const part of parts) {
    if (!/^\d{1,3}$/.test(part)) {
      return null;
    }
    const octet = Number(part);
    if (octet > 255) {
      return null;
    }
    octets.push(octet);
  }
  return octets;
}

/** Parses an IPv6 address (with optional embedded IPv4) into 8 groups. */
export function parseIpv6(value: string): number[] | null {
  let text = value;
  const zone = text.indexOf("%");
  if (zone !== -1) {
    text = text.slice(0, zone);
  }
  if (!text.includes(":")) {
    return null;
  }
  // Rewrite a trailing dotted quad as two hex groups.
  const lastColon = text.lastIndexOf(":");
  const lastPart = text.slice(lastColon + 1);
  if (lastPart.includes(".")) {
    const v4 = parseIpv4(lastPart);
    if (v4 === null) {
      return null;
    }
    const high = ((v4[0] << 8) | v4[1]).toString(16);
    const low = ((v4[2] << 8) | v4[3]).toString(16);
    text = `${text.slice(0, lastColon + 1)}${high}:${low}`;
  }
  const doubleColon = text.indexOf("::");
  if (doubleColon !== text.lastIndexOf("::")) {
    return null;
  }
  const parseGroups = (part: string): number[] | null => {
    if (part === "") {
      return [];
    }
    const groups: number[] = [];
    for (const group of part.split(":")) {
      if (!/^[0-9a-f]{1,4}$/i.test(group)) {
        return null;
      }
      groups.push(parseInt(group, 16));
    }
    return groups;
  };
  if (doubleColon === -1) {
    const groups = parseGroups(text);
    return groups !== null && groups.length === 8 ? groups : null;
  }
  const head = parseGroups(text.slice(0, doubleColon));
  const rest = parseGroups(text.slice(doubleColon + 2));
  if (head === null || rest === null) {
    return null;
  }
  const missing = 8 - head.length - rest.length;
  if (missing < 1) {
    return null;
  }
  return [...head, ...new Array<number>(missing).fill(0), ...rest];
}

function isBlockedIpv4([a, b, c]: number[]): boolean {
  return (
    a === 0 || // "this" network
    a === 10 || // private
    a === 127 || // loopback
    (a === 100 && b >= 64 && b <= 127) || // CGNAT
    (a === 169 && b === 254) || // link-local, cloud metadata
    (a === 172 && b >= 16 && b <= 31) || // private
    (a === 192 && b === 168) || // private
    (a === 192 && b === 0 && c === 0) || // IETF protocol assignments
    (a === 192 && b === 0 && c === 2) || // TEST-NET-1
    (a === 192 && b === 88 && c === 99) || // 6to4 relay anycast
    (a === 198 && (b === 18 || b === 19)) || // benchmarking
    (a === 198 && b === 51 && c === 100) || // TEST-NET-2
    (a === 203 && b === 0 && c === 113) || // TEST-NET-3
    a >= 224 // multicast, reserved, broadcast
  );
}

function embeddedIpv4(groups: number[], start: number): number[] {
  return [
    groups[start] >> 8,
    groups[start] & 0xff,
    groups[start + 1] >> 8,
    groups[start + 1] & 0xff,
  ];
}

function isBlockedIpv6(groups: number[]): boolean {
  const first = groups[0];
  const allZero = (start: number, end: number) =>
    groups.slice(start, end).every((group) => group === 0);

  // ::, ::1, and IPv4-compatible ::a.b.c.d
  if (allZero(0, 6)) {
    return true;
  }
  // IPv4-mapped ::ffff:a.b.c.d
  if (allZero(0, 5) && groups[5] === 0xffff) {
    return isBlockedIpv4(embeddedIpv4(groups, 6));
  }
  // NAT64 64:ff9b::a.b.c.d
  if (first === 0x64 && groups[1] === 0xff9b && allZero(2, 6)) {
    return isBlockedIpv4(embeddedIpv4(groups, 6));
  }
  // 6to4 2002:a.b.c.d::
  if (first === 0x2002) {
    return isBlockedIpv4(embeddedIpv4(groups, 1));
  }
  return (
    (first & 0xfe00) === 0xfc00 || // unique local fc00::/7
    (first & 0xffc0) === 0xfe80 || // link-local fe80::/10
    (first & 0xffc0) === 0xfec0 || // site-local fec0::/10
    (first & 0xff00) === 0xff00 || // multicast
    (first === 0x2001 && groups[1] === 0x0db8) || // documentation
    (first === 0x2001 && groups[1] < 0x0200) || // Teredo, ORCHID, etc.
    first === 0x0100 // discard-only 100::/64
  );
}
