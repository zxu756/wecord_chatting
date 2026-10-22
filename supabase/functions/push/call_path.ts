// Where a scheduled call's reminder leads (roadmap E2).
//
// The reminder of an event that carries a call, sent in the last 20 minutes
// before it starts, opens the event's call link: the app joins the call of
// the chat. The web app keeps its routes after a `#`, so the path is
// `/#/call/<code>`; it is the same route a shared call link opens
// (lib/features/voice/call_links).

const prefix = "/#/call/";
const codePattern = /^[a-z0-9]{12}$/;

/// The path that opens the call link [code], or null when [code] is empty or
/// not a call link code (so a bad row never builds a wrong address).
export function callPath(code: string | null | undefined): string | null {
  if (typeof code !== "string" || !codePattern.test(code)) {
    return null;
  }
  return `${prefix}${code}`;
}

/// Whether [url] is a call link's path.
export function isCallPath(url: unknown): boolean {
  return typeof url === "string" && url.startsWith(prefix);
}
