// Looking up a callback host name for the SSRF check (ssrf.ts).
//
// Deno.resolveDns is used first. Where the runtime does not offer it (it
// throws something other than "no such record"), the same question is asked of
// Cloudflare's public resolver over HTTPS (DNS JSON API), so the check never
// has to be skipped. A host with no record of the type gives an empty list.
import type { Resolver } from "./ssrf.ts";

const DOH_URL = "https://cloudflare-dns.com/dns-query";
const TYPE_NUMBERS = { A: 1, AAAA: 28 } as const;

/// A resolver that asks Cloudflare over HTTPS.
export function dohResolver(fetcher: typeof fetch): Resolver {
  return async (host, type) => {
    const url = new URL(DOH_URL);
    url.searchParams.set("name", host);
    url.searchParams.set("type", type);
    const response = await fetcher(url, {
      headers: { Accept: "application/dns-json" },
      signal: AbortSignal.timeout(3000),
    });
    if (!response.ok) {
      throw new Error(`dns_over_https_${response.status}`);
    }
    const answer = await response.json() as {
      Status?: number;
      Answer?: { type?: number; data?: string }[];
    };
    // 0: no error, 3: the name does not exist.
    if (answer.Status === 3) {
      return [];
    }
    if (answer.Status !== 0) {
      throw new Error(`dns_over_https_status_${answer.Status}`);
    }
    return (answer.Answer ?? [])
      .filter((record) => record.type === TYPE_NUMBERS[type])
      .map((record) => record.data ?? "")
      .filter((data) => data !== "");
  };
}

/// The runtime's own resolver, falling back to [fallback] when it cannot be
/// used at all.
export function systemResolver(
  runtime: {
    resolveDns?: (host: string, type: "A" | "AAAA") => Promise<string[]>;
  },
  fallback: Resolver,
): Resolver {
  return async (host, type) => {
    if (typeof runtime.resolveDns !== "function") {
      return await fallback(host, type);
    }
    try {
      return await runtime.resolveDns(host, type);
    } catch (error) {
      const name = error instanceof Error ? error.name : "";
      // The name has no such record: an answer, not a failure.
      if (name === "NotFound") {
        return [];
      }
      return await fallback(host, type);
    }
  };
}
