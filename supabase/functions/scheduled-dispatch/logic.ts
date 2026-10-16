// Pure helpers of the scheduled-dispatch Edge Function.

export interface PushTarget {
  subscription_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  conversation_id: string;
  circle_id: string | null;
  title: string;
  body: string;
}

/// Where tapping the notification opens the app (hash routes on the web),
/// the same as the push function.
export function targetPath(target: PushTarget): string {
  return target.circle_id
    ? `/#/circles/${target.circle_id}?c=${target.conversation_id}`
    : `/#/chats/${target.conversation_id}`;
}

/// Whether [header] is `Bearer <secret>`, compared in constant time. An
/// empty secret (not configured) never matches.
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
