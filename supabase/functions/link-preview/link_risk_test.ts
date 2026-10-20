import { assert, assertEquals } from "jsr:@std/assert@1";
import cases from "../../../test/fixtures/link_risk_cases.json" with {
  type: "json",
};
import { assessLink, assessRedirect, registrableDomain } from "./link_risk.ts";

// The same cases run against the app's copy of the rules
// (test/features/safety/link_risk_test.dart), so the two cannot drift apart.
for (const testCase of cases) {
  Deno.test(`risk of ${testCase.url}`, () => {
    const risk = assessLink(testCase.url);
    assertEquals(risk.level, testCase.level, JSON.stringify(risk));
    assertEquals([...risk.reasons].sort(), [...testCase.reasons].sort());
  });
}

Deno.test("a redirect to something worse is worse", () => {
  const plain = assessRedirect("https://example.com/a", null);
  assertEquals(plain.level, "none");

  const hidden = assessRedirect(
    "https://bit.ly/abc",
    "https://paypal-login.com/",
  );
  assertEquals(hidden.level, "high");
  assert(hidden.reasons.includes("redirects_risky"));
  assert(hidden.reasons.includes("short_link"));

  // A redirect to somewhere as safe leaves the link as it was.
  const same = assessRedirect("https://bit.ly/abc", "https://example.com/");
  assertEquals(same.level, "caution");
  assert(!same.reasons.includes("redirects_risky"));
});

Deno.test("registrable domains", () => {
  assertEquals(registrableDomain("example.com"), "example.com");
  assertEquals(registrableDomain("a.b.example.com"), "example.com");
  assertEquals(registrableDomain("evil.example.co.uk"), "example.co.uk");
});
