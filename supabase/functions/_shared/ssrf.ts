// Keeping the callback away from inner addresses (SSRF).
//
// The database refuses an address when the manager sets it
// (bot_callback_url_problem, migration 202610280650). This is the second,
// stronger check, made before every send: the host name is looked up and
// every address it has must be a public one. Nothing here sends a request.
//
// What is refused: anything but https on the default port; user names and
// passwords in the address; IP addresses written out in any form (the name
// must be a name); names that are local by convention (.local, .internal,
// .lan, localhost, ...); and names that resolve to a loopback, private,
// link-local, shared, documentation, multicast or otherwise reserved address,
// IPv4 or IPv6 (also an IPv4 address inside an IPv6 one).
//
// A name could resolve to something else between this check and the send
// (DNS rebinding). The send never follows redirects and carries no cookies,
// and the answer is never read, so the most that can happen is one signed
// POST of the bot's own press data to the address the bot's manager chose.

const BLOCKED_SUFFIXES = [
  "localhost",
  "local",
  "localdomain",
  "internal",
  "lan",
  "home",
  "corp",
  "intranet",
  "private",
  "arpa",
  "nip.io",
  "sslip.io",
  "xip.io",
  "localtest.me",
  "lvh.me",
  "traefik.me",
];

const HOST_PATTERN =
  /^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z][a-z0-9-]*[a-z0-9]$/;

export type UrlCheck =
  | { ok: true; url: URL; host: string }
  | { ok: false; reason: string };

/// Control characters, spaces, quotes, angle brackets, back ticks and
/// backslashes have no place in a callback address.
function hasForbiddenCharacters(text: string): boolean {
  for (const character of text) {
    const code = character.codePointAt(0)!;
    if (code <= 0x20 || code === 0x7f || '"<>`\\'.includes(character)) {
      return true;
    }
    if (/\s/.test(character)) {
      return true;
    }
  }
  return false;
}

/// The parts of the address that can be checked without the network.
export function checkCallbackUrl(raw: string): UrlCheck {
  if (raw.length > 500 || raw !== raw.trim() || hasForbiddenCharacters(raw)) {
    return { ok: false, reason: "bad_url" };
  }
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return { ok: false, reason: "bad_url" };
  }
  if (url.protocol !== "https:") {
    return { ok: false, reason: "not_https" };
  }
  if (url.username !== "" || url.password !== "") {
    return { ok: false, reason: "credentials_in_url" };
  }
  if (url.port !== "") {
    return { ok: false, reason: "port_not_allowed" };
  }
  const host = url.hostname.toLowerCase().replace(/\.$/, "");
  if (host.startsWith("[") || ipv4Parts(host) !== null || host.includes(":")) {
    return { ok: false, reason: "ip_address" };
  }
  for (const suffix of BLOCKED_SUFFIXES) {
    if (host === suffix || host.endsWith("." + suffix)) {
      return { ok: false, reason: "inner_name" };
    }
  }
  if (!HOST_PATTERN.test(host)) {
    return { ok: false, reason: "bad_host" };
  }
  return { ok: true, url, host };
}

/// Four numbers if [text] is a dotted IPv4 address, else null.
function ipv4Parts(text: string): number[] | null {
  const match = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(text);
  if (!match) {
    return null;
  }
  const parts = match.slice(1).map(Number);
  return parts.every((part) => part <= 255) ? parts : null;
}

/// Whether [text] is an IPv4 address anyone on the internet could own.
export function isPublicIPv4(text: string): boolean {
  const parts = ipv4Parts(text);
  if (parts === null) {
    return false;
  }
  const [a, b, c] = parts;
  if (a === 0 || a === 10 || a === 127) return false;
  if (a === 100 && b >= 64 && b <= 127) return false; // shared (carrier NAT)
  if (a === 169 && b === 254) return false; // link-local, cloud metadata
  if (a === 172 && b >= 16 && b <= 31) return false;
  if (a === 192 && b === 0 && c === 0) return false;
  if (a === 192 && b === 0 && c === 2) return false;
  if (a === 192 && b === 88 && c === 99) return false;
  if (a === 192 && b === 168) return false;
  if (a === 198 && (b === 18 || b === 19)) return false;
  if (a === 198 && b === 51 && c === 100) return false;
  if (a === 203 && b === 0 && c === 113) return false;
  if (a >= 224) return false; // multicast, reserved, broadcast
  return true;
}

/// The eight 16-bit groups of an IPv6 address, or null if it is not one.
export function ipv6Groups(text: string): number[] | null {
  let address = text.toLowerCase();
  const zone = address.indexOf("%");
  if (zone !== -1) {
    address = address.slice(0, zone);
  }
  // An IPv4 tail ("::ffff:1.2.3.4") is two groups.
  const tail = /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/.exec(address);
  if (tail) {
    const v4 = ipv4Parts(tail[1]);
    if (v4 === null) {
      return null;
    }
    address = address.slice(0, tail.index) +
      ((v4[0] << 8) | v4[1]).toString(16) + ":" +
      ((v4[2] << 8) | v4[3]).toString(16);
  }
  const halves = address.split("::");
  if (halves.length > 2) {
    return null;
  }
  const read = (part: string): number[] | null => {
    if (part === "") {
      return [];
    }
    const groups: number[] = [];
    for (const piece of part.split(":")) {
      if (!/^[0-9a-f]{1,4}$/.test(piece)) {
        return null;
      }
      groups.push(parseInt(piece, 16));
    }
    return groups;
  };
  const head = read(halves[0]);
  const rest = halves.length === 2 ? read(halves[1]) : [];
  if (head === null || rest === null) {
    return null;
  }
  if (halves.length === 1) {
    return head.length === 8 ? head : null;
  }
  const missing = 8 - head.length - rest.length;
  if (missing < 1) {
    return null;
  }
  return [...head, ...new Array<number>(missing).fill(0), ...rest];
}

/// Whether [text] is an IPv6 address that is global unicast and not one of
/// the ranges set aside for documentation, tunnels or translation. Anything
/// that holds an IPv4 address (mapped, NAT64, 6to4) is judged as that
/// address, or refused.
export function isPublicIPv6(text: string): boolean {
  const g = ipv6Groups(text);
  if (g === null) {
    return false;
  }
  // ::ffff:a.b.c.d (mapped) and ::a.b.c.d (compatible): the IPv4 address.
  const leadingZeros = g.slice(0, 5).every((group) => group === 0);
  if (leadingZeros && (g[5] === 0xffff || g[5] === 0)) {
    const v4 = `${g[6] >> 8}.${g[6] & 255}.${g[7] >> 8}.${g[7] & 255}`;
    return isPublicIPv4(v4);
  }
  // Only 2000::/3 is global unicast.
  if (g[0] < 0x2000 || g[0] > 0x3fff) return false;
  if (g[0] === 0x2001 && g[1] === 0) return false; // Teredo
  if (g[0] === 0x2001 && g[1] === 0xdb8) return false; // documentation
  if (g[0] === 0x2001 && g[1] >= 0x10 && g[1] <= 0x2f) return false; // ORCHID
  if (g[0] === 0x2002) return false; // 6to4
  if (g[0] === 0x3fff && g[1] <= 0x0fff) return false; // documentation
  return true;
}

export function isPublicAddress(address: string): boolean {
  return address.includes(":") ? isPublicIPv6(address) : isPublicIPv4(address);
}

export type Resolver = (host: string, type: "A" | "AAAA") => Promise<string[]>;

export type SafeUrl =
  | { ok: true; url: URL }
  | { ok: false; reason: string };

/// The address checked and its name looked up: every A and AAAA record must be
/// public, and there must be at least one.
export async function resolveSafeUrl(
  raw: string,
  resolve: Resolver,
): Promise<SafeUrl> {
  const checked = checkCallbackUrl(raw);
  if (!checked.ok) {
    return checked;
  }
  const found: string[] = [];
  for (const type of ["A", "AAAA"] as const) {
    try {
      found.push(...await resolve(checked.host, type));
    } catch {
      // No record of this kind.
    }
  }
  if (found.length === 0) {
    return { ok: false, reason: "dns_failed" };
  }
  if (!found.every(isPublicAddress)) {
    return { ok: false, reason: "inner_address" };
  }
  return { ok: true, url: checked.url };
}
