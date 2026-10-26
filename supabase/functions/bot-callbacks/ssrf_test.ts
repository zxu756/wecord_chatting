import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  checkCallbackUrl,
  ipv6Groups,
  isPublicAddress,
  isPublicIPv4,
  isPublicIPv6,
  type Resolver,
  resolveSafeUrl,
} from "./ssrf.ts";

Deno.test("addresses on the public internet pass", () => {
  for (
    const address of [
      "8.8.8.8",
      "1.1.1.1",
      "93.184.216.34",
      "172.15.255.255",
      "172.32.0.1",
      "100.63.255.255",
      "100.128.0.1",
      "11.0.0.1",
      "192.0.1.1",
      "198.17.0.1",
      "198.20.0.1",
    ]
  ) {
    assert(isPublicIPv4(address), address);
  }
});

Deno.test("private, loopback, link-local and reserved IPv4 addresses do not", () => {
  for (
    const address of [
      "0.0.0.0",
      "0.1.2.3",
      "10.0.0.1",
      "10.255.255.255",
      "127.0.0.1",
      "127.255.255.254",
      "100.64.0.1",
      "100.127.255.255",
      "169.254.169.254",
      "169.254.0.1",
      "172.16.0.1",
      "172.31.255.255",
      "192.0.0.1",
      "192.0.2.5",
      "192.88.99.1",
      "192.168.0.1",
      "198.18.0.1",
      "198.19.255.255",
      "198.51.100.7",
      "203.0.113.9",
      "224.0.0.1",
      "239.255.255.255",
      "240.0.0.1",
      "255.255.255.255",
      "1.2.3",
      "256.1.1.1",
      "not an address",
    ]
  ) {
    assertFalse(isPublicIPv4(address), address);
  }
});

Deno.test("IPv6 addresses are read in every notation", () => {
  assertEquals(ipv6Groups("::1"), [0, 0, 0, 0, 0, 0, 0, 1]);
  assertEquals(ipv6Groups("::"), [0, 0, 0, 0, 0, 0, 0, 0]);
  assertEquals(
    ipv6Groups("2606:4700:4700::1111"),
    [0x2606, 0x4700, 0x4700, 0, 0, 0, 0, 0x1111],
  );
  assertEquals(
    ipv6Groups("::ffff:127.0.0.1"),
    [0, 0, 0, 0, 0, 0xffff, 0x7f00, 1],
  );
  assertEquals(ipv6Groups("fe80::1%eth0"), [0xfe80, 0, 0, 0, 0, 0, 0, 1]);
  assertEquals(ipv6Groups("1:2:3:4:5:6:7:8"), [1, 2, 3, 4, 5, 6, 7, 8]);
  assertEquals(ipv6Groups("1::2::3"), null);
  assertEquals(ipv6Groups("12345::1"), null);
  assertEquals(ipv6Groups("1:2:3:4:5:6:7:8:9"), null);
  assertEquals(ipv6Groups("gggg::1"), null);
});

Deno.test("only global unicast IPv6 passes", () => {
  assert(isPublicIPv6("2606:4700:4700::1111"));
  assert(isPublicIPv6("2a00:1450:4001:81b::200e"));
  for (
    const address of [
      "::",
      "::1",
      "fe80::1",
      "fc00::1",
      "fd12:3456::1",
      "fec0::1",
      "ff02::1",
      "2001:db8::1",
      "2001::1",
      "2002:7f00:1::1",
      "64:ff9b::7f00:1",
      "::ffff:127.0.0.1",
      "::ffff:10.0.0.1",
      "::ffff:169.254.169.254",
      "::127.0.0.1",
      "100::1",
      "nonsense",
    ]
  ) {
    assertFalse(isPublicIPv6(address), address);
  }
  // An IPv4 address inside an IPv6 one is judged as that address.
  assert(isPublicIPv6("::ffff:8.8.8.8"));
  assertFalse(isPublicAddress("::1"));
  assert(isPublicAddress("8.8.8.8"));
});

Deno.test("addresses that are not ordinary https names are refused", () => {
  const refused: Record<string, string> = {
    "http://example.com/hook": "not_https",
    "ftp://example.com/": "not_https",
    "javascript:alert(1)": "not_https",
    "https://user@example.com/": "credentials_in_url",
    "https://user:pw@example.com/": "credentials_in_url",
    "https://example.com:8443/": "port_not_allowed",
    "https://example.com:22/": "port_not_allowed",
    "https://127.0.0.1/": "ip_address",
    "https://127.1/": "ip_address",
    "https://0x7f.1/": "ip_address",
    "https://2130706433/": "ip_address",
    "https://017700000001/": "ip_address",
    "https://[::1]/": "ip_address",
    "https://[::ffff:7f00:1]/": "ip_address",
    "https://169.254.169.254/latest/meta-data/": "ip_address",
    "https://localhost/": "inner_name",
    "https://LOCALHOST./": "inner_name",
    "https://app.localhost/": "inner_name",
    "https://printer.local/": "inner_name",
    "https://metadata.google.internal/": "inner_name",
    "https://nas.lan/": "inner_name",
    "https://host.localdomain/": "inner_name",
    "https://127.0.0.1.nip.io/": "inner_name",
    "https://10.0.0.1.sslip.io/": "inner_name",
    "https://x.localtest.me/": "inner_name",
    "https://1.0.0.127.in-addr.arpa/": "inner_name",
    "https://intranet/": "inner_name",
    "https://exa_mple.com/": "bad_host",
    "https://-example.com/": "bad_host",
    "https://example.com\\@evil.example/": "bad_url",
    "https://example.com/a b": "bad_url",
    "https://example.com/\u0000": "bad_url",
    "": "bad_url",
    " https://example.com/": "bad_url",
    "not a url": "bad_url",
  };
  for (const [raw, reason] of Object.entries(refused)) {
    const checked = checkCallbackUrl(raw);
    assertFalse(checked.ok, raw);
    if (!checked.ok) assertEquals(checked.reason, reason, raw);
  }
  assertFalse(checkCallbackUrl("https://example.com/" + "a".repeat(500)).ok);
});

Deno.test("an ordinary https name passes, in any case", () => {
  for (
    const raw of [
      "https://example.com/hook",
      "https://Bots.Example.CO.UK/wecord/hook?token=abc",
      "https://example.com:443/hook",
      "https://example.com./hook",
      "https://xn--bcher-kva.example/hook",
    ]
  ) {
    const checked = checkCallbackUrl(raw);
    assert(checked.ok, raw);
  }
  const checked = checkCallbackUrl("https://Bots.Example.CO.UK/x");
  assert(checked.ok);
  if (checked.ok) assertEquals(checked.host, "bots.example.co.uk");
});

function resolverOf(
  records: Record<string, { A?: string[]; AAAA?: string[] }>,
): Resolver {
  return (host, type) => {
    const found = records[host];
    if (!found) return Promise.reject(new Error("NotFound"));
    return Promise.resolve(found[type] ?? []);
  };
}

Deno.test("a name must resolve, and only to public addresses", async () => {
  const resolve = resolverOf({
    "good.example.com": { A: ["93.184.216.34"], AAAA: ["2606:4700::1"] },
    "v4only.example.com": { A: ["93.184.216.34"] },
    "inner.example.com": { A: ["10.0.0.5"] },
    "mixed.example.com": { A: ["93.184.216.34", "127.0.0.1"] },
    "mixed6.example.com": { A: ["93.184.216.34"], AAAA: ["::1"] },
    "mapped.example.com": { AAAA: ["::ffff:169.254.169.254"] },
    "empty.example.com": {},
  });
  assertEquals(
    (await resolveSafeUrl("https://good.example.com/hook", resolve)).ok,
    true,
  );
  assertEquals(
    (await resolveSafeUrl("https://v4only.example.com/hook", resolve)).ok,
    true,
  );
  for (
    const [host, reason] of [
      ["inner.example.com", "inner_address"],
      ["mixed.example.com", "inner_address"],
      ["mixed6.example.com", "inner_address"],
      ["mapped.example.com", "inner_address"],
      ["empty.example.com", "dns_failed"],
      ["unknown.example.com", "dns_failed"],
    ]
  ) {
    const result = await resolveSafeUrl(`https://${host}/hook`, resolve);
    assertFalse(result.ok, host);
    if (!result.ok) assertEquals(result.reason, reason, host);
  }
  // A bad address never reaches the resolver.
  let asked = 0;
  const counting: Resolver = () => {
    asked++;
    return Promise.resolve(["93.184.216.34"]);
  };
  const refused = await resolveSafeUrl("https://127.0.0.1/", counting);
  assertFalse(refused.ok);
  assertEquals(asked, 0);
});
