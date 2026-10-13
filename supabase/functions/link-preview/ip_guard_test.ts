import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  isBlockedAddress,
  isInternalHostname,
  normalizePreviewUrl,
  parseIpv6,
} from "./ip_guard.ts";

Deno.test("blocks private, loopback, link-local and CGNAT IPv4", () => {
  for (
    const address of [
      "0.0.0.0",
      "0.1.2.3",
      "10.0.0.1",
      "10.255.255.255",
      "100.64.0.1",
      "100.127.255.254",
      "127.0.0.1",
      "127.255.0.9",
      "169.254.169.254",
      "172.16.0.1",
      "172.31.255.255",
      "192.168.1.1",
      "192.0.0.8",
      "198.18.0.1",
      "224.0.0.1",
      "255.255.255.255",
    ]
  ) {
    assert(isBlockedAddress(address), address);
  }
});

Deno.test("allows public IPv4", () => {
  for (
    const address of [
      "1.1.1.1",
      "8.8.8.8",
      "93.184.215.14",
      "100.63.255.255",
      "100.128.0.1",
      "172.15.255.255",
      "172.32.0.1",
      "169.253.1.1",
      "192.169.0.1",
    ]
  ) {
    assertFalse(isBlockedAddress(address), address);
  }
});

Deno.test("blocks private and mapped IPv6", () => {
  for (
    const address of [
      "::",
      "::1",
      "[::1]",
      "fc00::1",
      "fd12:3456::1",
      "fe80::1",
      "fe80::1%en0",
      "febf::1",
      "ff02::1",
      "::ffff:127.0.0.1",
      "::ffff:7f00:1",
      "::ffff:10.0.0.1",
      "::ffff:169.254.169.254",
      "::127.0.0.1",
      "64:ff9b::a9fe:a9fe",
      "2002:7f00:1::",
      "2001:db8::1",
    ]
  ) {
    assert(isBlockedAddress(address), address);
  }
});

Deno.test("allows public IPv6", () => {
  for (
    const address of [
      "2606:4700:4700::1111",
      "2a00:1450:4009:81f::200e",
      "::ffff:8.8.8.8",
      "64:ff9b::808:808",
    ]
  ) {
    assertFalse(isBlockedAddress(address), address);
  }
});

Deno.test("unparseable addresses are blocked", () => {
  assert(isBlockedAddress("not-an-ip"));
  assert(isBlockedAddress("1.2.3"));
  assert(isBlockedAddress("1:2:3:4:5:6:7:8:9"));
});

Deno.test("parses compressed IPv6 forms", () => {
  assertEquals(parseIpv6("::1"), [0, 0, 0, 0, 0, 0, 0, 1]);
  assertEquals(parseIpv6("1::"), [1, 0, 0, 0, 0, 0, 0, 0]);
  assertEquals(
    parseIpv6("::ffff:1.2.3.4"),
    [0, 0, 0, 0, 0, 0xffff, 0x0102, 0x0304],
  );
  assertEquals(parseIpv6("1:2:3:4:5:6:7:8"), [1, 2, 3, 4, 5, 6, 7, 8]);
  assertEquals(parseIpv6("1::2::3"), null);
  assertEquals(parseIpv6("1.2.3.4"), null);
});

Deno.test("normalizes http(s) urls and drops fragments", () => {
  const result = normalizePreviewUrl("  https://Example.COM/a?b=1#frag ");
  assert(result.ok);
  assertEquals(result.url.href, "https://example.com/a?b=1");
  const explicitPort = normalizePreviewUrl("https://example.com:443/");
  assert(explicitPort.ok);
  assertEquals(explicitPort.url.href, "https://example.com/");
});

Deno.test("rejects other schemes, credentials and ports", () => {
  const cases: [string, string][] = [
    ["ftp://example.com", "unsupported"],
    ["file:///etc/passwd", "unsupported"],
    ["javascript:alert(1)", "unsupported"],
    ["https://user:pass@example.com", "unsupported"],
    ["https://example.com:8443/", "blocked"],
    ["http://example.com:22/", "blocked"],
    ["not a url", "invalid"],
    ["", "invalid"],
    [`https://example.com/${"a".repeat(2100)}`, "invalid"],
  ];
  for (const [url, reason] of cases) {
    const result = normalizePreviewUrl(url);
    assertFalse(result.ok, url);
    if (!result.ok) {
      assertEquals(result.reason, reason, url);
    }
  }
});

Deno.test("rejects internal hosts and private literals", () => {
  for (
    const url of [
      "http://127.0.0.1/",
      "http://169.254.169.254/latest/meta-data/",
      "http://localhost:54321/",
      "http://localhost/",
      "http://foo.localhost/",
      "http://kong/",
      "http://metadata.google.internal/",
      "http://printer.local/",
      "http://[::1]/",
      "http://[::ffff:127.0.0.1]/",
      "http://2130706433/",
      "http://0x7f.0.0.1/",
      "http://10.1/",
    ]
  ) {
    const result = normalizePreviewUrl(url);
    assertFalse(result.ok, url);
    if (!result.ok) {
      assertEquals(result.reason, "blocked", url);
    }
  }
});

Deno.test("resolves relative redirect targets", () => {
  const result = normalizePreviewUrl("/next", "https://example.com/start");
  assert(result.ok);
  assertEquals(result.url.href, "https://example.com/next");
  const internal = normalizePreviewUrl(
    "http://127.0.0.1/",
    "https://example.com/",
  );
  assertFalse(internal.ok);
});

Deno.test("internal hostname suffixes", () => {
  assert(isInternalHostname("localhost"));
  assert(isInternalHostname("db"));
  assert(isInternalHostname("svc.internal"));
  assertFalse(isInternalHostname("example.com"));
});
