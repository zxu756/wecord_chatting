// The inline PasskeyAuthenticator in web/index.html (G4): the passkeys
// plugin's web half calls it, so it has to turn the WebAuthn JSON form
// (base64url fields) into what navigator.credentials wants and back.
//
//   deno test --allow-read tool/web_tests/passkeys_bridge_test.ts
import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";

const html = Deno.readTextFileSync(
  new URL("../../web/index.html", import.meta.url),
);

/** The script that defines window.PasskeyAuthenticator. */
function bridgeSource(): string {
  const marker = "window.PasskeyAuthenticator = {";
  const at = html.indexOf(marker);
  assert(at > 0, "the bridge is in index.html");
  const start = html.lastIndexOf("<script>", at) + "<script>".length;
  const end = html.indexOf("</script>", at);
  return html.slice(start, end);
}

// deno-lint-ignore no-explicit-any
type Any = any;

function bytes(...values: number[]): ArrayBuffer {
  return new Uint8Array(values).buffer;
}

function load(credentials: Any): Any {
  const window: Any = { PublicKeyCredential: {} };
  const navigator = { credentials };
  new Function(
    "window",
    "navigator",
    "atob",
    "btoa",
    "AbortController",
    bridgeSource(),
  )(
    window,
    navigator,
    atob,
    btoa,
    AbortController,
  );
  return window.PasskeyAuthenticator;
}

Deno.test("the page has the bridge inline and loads nothing for it", () => {
  const source = bridgeSource();
  assert(!/src\s*=/.test(source));
  assert(!source.includes("http"));
  // Defined before the app starts.
  assert(
    html.indexOf("window.PasskeyAuthenticator") <
      html.indexOf('<script src="flutter_bootstrap.js"'),
  );
  const api = load({});
  for (
    const name of [
      "init",
      "register",
      "login",
      "cancelCurrentAuthenticatorOperation",
      "isUserVerifyingPlatformAuthenticatorAvailable",
      "isConditionalMediationAvailable",
      "hasPasskeySupport",
    ]
  ) {
    assertEquals(typeof api[name], "function", name);
  }
  assertEquals(api.hasPasskeySupport(), true);
});

Deno.test("register turns the JSON options into buffers and the credential back", async () => {
  let seen: Any;
  const api = load({
    create: (options: Any) => {
      seen = options;
      return Promise.resolve({
        id: "AQID",
        rawId: bytes(1, 2, 3),
        type: "public-key",
        authenticatorAttachment: "platform",
        response: {
          clientDataJSON: bytes(251, 255),
          attestationObject: bytes(9, 8),
          getTransports: () => ["internal", "hybrid"],
        },
        getClientExtensionResults: () => ({ credProps: { rk: true } }),
      });
    },
  });
  const out = JSON.parse(
    await api.register(JSON.stringify({
      publicKey: {
        rp: { id: "wecord.jokebear.fyi", name: "WeCord" },
        user: { id: "AQID", name: "ada@example.com", displayName: "Ada" },
        challenge: "_-8",
        pubKeyCredParams: [{ type: "public-key", alg: -7 }],
        authenticatorSelection: null,
        excludeCredentials: [{ type: "public-key", id: "BAU", transports: [] }],
        timeout: null,
      },
    })),
  );
  const publicKey = seen.publicKey;
  assertEquals([...new Uint8Array(publicKey.challenge)], [255, 239]);
  assertEquals([...new Uint8Array(publicKey.user.id)], [1, 2, 3]);
  assertEquals([...new Uint8Array(publicKey.excludeCredentials[0].id)], [4, 5]);
  // A null is an option that is not there.
  assertEquals("authenticatorSelection" in publicKey, false);
  assertEquals("timeout" in publicKey, false);
  assertEquals(publicKey.excludeCredentials[0].transports, undefined);

  assertEquals(out.id, "AQID");
  assertEquals(out.rawId, "AQID");
  // base64url: no padding, - and _ instead of + and /.
  assertEquals(out.response.clientDataJSON, "-_8");
  assertEquals(out.response.attestationObject, "CQg");
  assertEquals(out.response.transports, ["internal", "hybrid"]);
  assertEquals(out.clientExtensionResults.credProps.rk, true);
});

Deno.test("login asks for any passkey and sends back the assertion", async () => {
  let seen: Any;
  const api = load({
    get: (options: Any) => {
      seen = options;
      return Promise.resolve({
        id: "AQID",
        rawId: bytes(1, 2, 3),
        type: "public-key",
        response: {
          clientDataJSON: bytes(1),
          authenticatorData: bytes(2),
          signature: bytes(3),
          userHandle: null,
        },
        getClientExtensionResults: () => ({}),
      });
    },
  });
  const out = JSON.parse(
    await api.login(JSON.stringify({
      mediation: "optional",
      publicKey: {
        challenge: "AQID",
        rpId: "wecord.jokebear.fyi",
        allowCredentials: [],
        userVerification: "preferred",
      },
    })),
  );
  assertEquals(seen.mediation, "optional");
  assertEquals(seen.publicKey.allowCredentials, []);
  assert(seen.signal);
  assertEquals(out.response.signature, "Aw");
  assertEquals(out.response.userHandle, null);
});

Deno.test("failures reach the plugin as the codes it understands", async () => {
  const cases: [string, string][] = [
    ["NotAllowedError", "cancelled"],
    ["SecurityError", "domain-not-associated"],
    ["NotSupportedError", "deviceNotSupported"],
    ["InvalidStateError", "exclude-credentials-match"],
    ["Whatever", "Whatever"],
  ];
  for (const [name, code] of cases) {
    const api = load({
      get: () => Promise.reject({ name, message: "nope" }),
      create: () => Promise.reject({ name, message: "nope" }),
    });
    const options = JSON.stringify({
      publicKey: {
        challenge: "AQID",
        user: { id: "AQID" },
        allowCredentials: [],
      },
    });
    for (const call of [api.login, api.register]) {
      const error = await assertRejects(() => call(options)) as unknown;
      assertEquals(JSON.parse(error as string).code, code);
    }
  }
});

Deno.test("cancel aborts a running login", async () => {
  let signal: Any;
  const api = load({
    get: (options: Any) => {
      signal = options.signal;
      return new Promise(() => {});
    },
  });
  api.login(JSON.stringify({ publicKey: { challenge: "AQID" } }));
  api.cancelCurrentAuthenticatorOperation();
  assertEquals(signal.aborted, true);
  await Promise.resolve();
});
