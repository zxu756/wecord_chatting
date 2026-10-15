// Pure helpers for the gif-search function: reading the request, building
// the GIPHY API URL and trimming its answer to what the app shows. No
// network.

export const DEFAULT_LIMIT = 24;
export const MAX_LIMIT = 50;
export const MAX_OFFSET = 4999;
export const MAX_QUERY_LENGTH = 50;

export interface GifRequest {
  /// Empty for trending GIFs.
  query: string;
  limit: number;
  offset: number;
}

export interface Gif {
  id: string;
  title: string;
  /// The GIF to send: a GIPHY media URL without tracking parameters.
  url: string;
  /// A smaller rendition for the picker.
  preview_url: string;
  width: number;
  height: number;
}

/// The GIPHY API key from the environment, or null when GIF search is not
/// set up for this project yet.
export function readGiphyKey(
  get: (name: string) => string | undefined,
): string | null {
  const key = get("GIPHY_API_KEY")?.trim();
  return key ? key : null;
}

function clampInt(value: unknown, min: number, max: number, fallback: number) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return fallback;
  }
  return Math.min(max, Math.max(min, Math.trunc(value)));
}

/// The search from a request body ({query?, limit?, offset?}), or null when
/// the body is not an object or the query is not text.
export function parseGifRequest(body: unknown): GifRequest | null {
  if (body === null || body === undefined) {
    body = {};
  }
  if (typeof body !== "object" || Array.isArray(body)) {
    return null;
  }
  const fields = body as Record<string, unknown>;
  const rawQuery = fields.query ?? "";
  if (typeof rawQuery !== "string") {
    return null;
  }
  return {
    query: rawQuery.trim().replace(/\s+/g, " ").slice(0, MAX_QUERY_LENGTH),
    limit: clampInt(fields.limit, 1, MAX_LIMIT, DEFAULT_LIMIT),
    offset: clampInt(fields.offset, 0, MAX_OFFSET, 0),
  };
}

/// The GIPHY endpoint for [request]: trending without a query, search with
/// one. Ratings stop at PG-13.
export function giphyUrl(apiKey: string, request: GifRequest): URL {
  const url = new URL(
    request.query === ""
      ? "https://api.giphy.com/v1/gifs/trending"
      : "https://api.giphy.com/v1/gifs/search",
  );
  url.searchParams.set("api_key", apiKey);
  if (request.query !== "") {
    url.searchParams.set("q", request.query);
    url.searchParams.set("lang", "en");
  }
  url.searchParams.set("limit", String(request.limit));
  url.searchParams.set("offset", String(request.offset));
  url.searchParams.set("rating", "pg-13");
  url.searchParams.set("bundle", "messaging_non_clips");
  return url;
}

/// [raw] as an https GIPHY media URL without its query string, or null.
export function cleanMediaUrl(raw: unknown): string | null {
  if (typeof raw !== "string" || raw === "") {
    return null;
  }
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  const host = url.hostname.toLowerCase();
  if (
    url.protocol !== "https:" ||
    !(host === "giphy.com" || host.endsWith(".giphy.com")) ||
    !url.pathname.toLowerCase().endsWith(".gif")
  ) {
    return null;
  }
  return `https://${host}${url.pathname}`;
}

type Rendition = { url?: unknown; width?: unknown; height?: unknown };

function rendition(images: Record<string, Rendition>, names: string[]) {
  for (const name of names) {
    const candidate = images[name];
    const url = cleanMediaUrl(candidate?.url);
    if (candidate && url) {
      return {
        url,
        width: Number(candidate.width) || 0,
        height: Number(candidate.height) || 0,
      };
    }
  }
  return null;
}

/// The GIFs in a GIPHY search or trending answer, skipping any without
/// usable renditions.
export function mapGiphyResponse(json: unknown): Gif[] {
  if (typeof json !== "object" || json === null) {
    return [];
  }
  const data = (json as { data?: unknown }).data;
  if (!Array.isArray(data)) {
    return [];
  }
  const gifs: Gif[] = [];
  for (const item of data) {
    if (typeof item !== "object" || item === null) {
      continue;
    }
    const record = item as {
      id?: unknown;
      title?: unknown;
      images?: Record<string, Rendition>;
    };
    if (typeof record.id !== "string" || !record.images) {
      continue;
    }
    const full = rendition(record.images, ["downsized", "original"]);
    const preview = rendition(record.images, [
      "fixed_width",
      "fixed_width_downsampled",
      "downsized",
    ]);
    if (!full || !preview) {
      continue;
    }
    gifs.push({
      id: record.id,
      title: typeof record.title === "string" ? record.title.trim() : "",
      url: full.url,
      preview_url: preview.url,
      width: full.width,
      height: full.height,
    });
  }
  return gifs;
}
