import { assert } from "jsr:@std/assert@1";
import { isAuthorized } from "./auth.ts";

Deno.test("only the dispatch secret as a bearer token is let in", () => {
  assert(isAuthorized("Bearer s3cret", "s3cret"));
  assert(!isAuthorized("Bearer other", "s3cret"));
  assert(!isAuthorized("s3cret", "s3cret"));
  assert(!isAuthorized("Bearer s3cret ", "s3cret"));
  assert(!isAuthorized(null, "s3cret"));
});

Deno.test("nothing is let in while no secret is configured", () => {
  assert(!isAuthorized("Bearer ", ""));
  assert(!isAuthorized("", ""));
  assert(!isAuthorized(null, ""));
});
