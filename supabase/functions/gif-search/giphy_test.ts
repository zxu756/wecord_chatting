import { assertEquals } from "jsr:@std/assert@1";
import {
  cleanMediaUrl,
  DEFAULT_LIMIT,
  giphyUrl,
  mapGiphyResponse,
  MAX_LIMIT,
  parseGifRequest,
  readGiphyKey,
} from "./giphy.ts";

Deno.test("the API key comes from GIPHY_API_KEY", () => {
  assertEquals(readGiphyKey((name) => ({ GIPHY_API_KEY: " k " })[name]), "k");
  assertEquals(readGiphyKey(() => " "), null);
  assertEquals(readGiphyKey(() => undefined), null);
});

Deno.test("reads the query, limit and offset", () => {
  assertEquals(parseGifRequest({}), {
    query: "",
    limit: DEFAULT_LIMIT,
    offset: 0,
  });
  assertEquals(parseGifRequest(null), {
    query: "",
    limit: DEFAULT_LIMIT,
    offset: 0,
  });
  assertEquals(
    parseGifRequest({ query: "  happy   cat ", limit: 500, offset: -3 }),
    { query: "happy cat", limit: MAX_LIMIT, offset: 0 },
  );
  assertEquals(parseGifRequest({ query: "x".repeat(80) })?.query.length, 50);
  assertEquals(parseGifRequest({ query: 3 }), null);
  assertEquals(parseGifRequest("cats"), null);
  assertEquals(parseGifRequest([]), null);
});

Deno.test("trending without a query, search with one", () => {
  const trending = giphyUrl("key", { query: "", limit: 10, offset: 0 });
  assertEquals(trending.pathname, "/v1/gifs/trending");
  assertEquals(trending.searchParams.get("q"), null);
  assertEquals(trending.searchParams.get("api_key"), "key");
  assertEquals(trending.searchParams.get("rating"), "pg-13");

  const search = giphyUrl("key", { query: "cat & dog", limit: 5, offset: 20 });
  assertEquals(search.pathname, "/v1/gifs/search");
  assertEquals(search.searchParams.get("q"), "cat & dog");
  assertEquals(search.searchParams.get("limit"), "5");
  assertEquals(search.searchParams.get("offset"), "20");
});

Deno.test("media URLs must be https GIPHY GIFs and lose their query", () => {
  assertEquals(
    cleanMediaUrl("https://media2.giphy.com/media/abc/200.gif?cid=x&rid=y"),
    "https://media2.giphy.com/media/abc/200.gif",
  );
  assertEquals(cleanMediaUrl("http://media.giphy.com/media/abc/200.gif"), null);
  assertEquals(cleanMediaUrl("https://evil.example/media/abc/200.gif"), null);
  assertEquals(cleanMediaUrl("https://notgiphy.com/a.gif"), null);
  assertEquals(
    cleanMediaUrl("https://media.giphy.com/media/abc/200.mp4"),
    null,
  );
  assertEquals(cleanMediaUrl(42), null);
});

Deno.test("maps GIPHY answers to what the picker shows", () => {
  const gifs = mapGiphyResponse({
    data: [
      {
        id: "abc",
        title: " Happy Cat GIF ",
        images: {
          downsized: {
            url: "https://media1.giphy.com/media/abc/giphy-downsized.gif?cid=1",
            width: "320",
            height: "240",
          },
          fixed_width: {
            url: "https://media1.giphy.com/media/abc/200w.gif?cid=1",
            width: "200",
            height: "150",
          },
        },
      },
      { id: "no-images" },
      {
        id: "bad-host",
        images: {
          original: { url: "https://example.com/x.gif" },
          fixed_width: { url: "https://example.com/y.gif" },
        },
      },
      "junk",
    ],
  });
  assertEquals(gifs, [
    {
      id: "abc",
      title: "Happy Cat GIF",
      url: "https://media1.giphy.com/media/abc/giphy-downsized.gif",
      preview_url: "https://media1.giphy.com/media/abc/200w.gif",
      width: 320,
      height: 240,
    },
  ]);
  assertEquals(mapGiphyResponse({}), []);
  assertEquals(mapGiphyResponse(null), []);
});
