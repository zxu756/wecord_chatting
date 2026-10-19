// Who may call expire-stories: the database (pg_cron through pg_net) with the
// shared secret DISPATCH_SECRET as the bearer token, like scheduled-dispatch.

/// Whether [header] is `Bearer <secret>`, compared in constant time. An empty
/// secret (not configured) never matches.
export function isAuthorized(header: string | null, secret: string): boolean {
  if (secret === "" || header === null) {
    return false;
  }
  const expected = new TextEncoder().encode(`Bearer ${secret}`);
  const given = new TextEncoder().encode(header);
  let difference = expected.length ^ given.length;
  for (let index = 0; index < expected.length; index++) {
    difference |= expected[index] ^ (given[index] ?? 0);
  }
  return difference === 0;
}
