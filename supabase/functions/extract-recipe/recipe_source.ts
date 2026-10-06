// Turn a pasted http(s) URL into either a complete schema.org Recipe or
// plain text for the model. No network policy lives in index.ts — callers
// inject fetch and the safety check so tests stay offline.
//
// SSRF: http/https only, no credentials, no single-label or internal hosts,
// no private/loopback/link-local addresses, DNS answers re-checked, redirects
// re-checked, timeouts, and a response size cap.

export const MAX_RESPONSE_BYTES = 3_000_000;
export const FETCH_TIMEOUT_MS = 12_000;
export const MAX_REDIRECTS = 4;
export const MAX_SOURCE_CHARS = 12_000;

const NOT_ALLOWED =
  "That link isn't one I can open. Paste a public http or https recipe link.";
const FETCH_FAILED =
  "Couldn't open that link. Check it and try again, or paste the recipe text.";
const NO_RECIPE =
  "Couldn't find a recipe in that link. Paste the description or caption text and I'll try from that.";
const INSTAGRAM_CAPTION =
  "Couldn't read the caption on this Instagram link. Paste the caption text instead and I'll pull the recipe from that.";
const YOUTUBE_LINK =
  "That YouTube link doesn't point at a video. Paste a watch, shorts, or youtu.be link.";

export class SourceError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(message: string, code: string, status: number) {
    super(message);
    this.name = "SourceError";
    this.code = code;
    this.status = status;
  }
}

export type StructuredIngredient = {
  ingredient: string;
  original_phrase: string;
  amount: number | null;
  unit: string | null;
  vague: boolean;
};

export type StructuredRecipe = {
  title: string;
  attribution: string | null;
  ingredients: StructuredIngredient[];
  steps: string[];
  notes: string | null;
};

export type ResolvedSource =
  | { kind: "recipe"; recipe: StructuredRecipe; source: "web" }
  | { kind: "text"; text: string; source: "youtube" | "instagram" | "web" };

export type RecipeUrlClass = "youtube" | "instagram" | "web" | "blocked" | "invalid";

export type FetchLike = (url: string, init: RequestInit) => Promise<Response>;

export type DnsResolve = (hostname: string) => Promise<string[]>;

export type FetchCtx = {
  youtubeApiKey?: string;
  fetchImpl?: FetchLike;
  assertSafe?: (url: URL) => Promise<void>;
  maxBytes?: number;
  timeoutMs?: number;
};

const BARE_HOST =
  /^(?:www\.|m\.|music\.)?(?:youtube\.com|youtu\.be|youtube-nocookie\.com|instagram\.com|instagr\.am)\b/i;

const BLOCKED_HOSTS = new Set([
  "localhost",
  "localhost.localdomain",
  "metadata",
  "metadata.google.internal",
  "host.docker.internal",
]);

const FETCH_HEADERS = {
  "user-agent":
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  "accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
  "accept-language": "en",
};

export function parseRecipeURL(raw: string): URL | null {
  let value = raw.trim();
  if (!value || /\s/.test(value)) return null;
  if (!/^[a-z][a-z0-9+.-]*:/i.test(value)) {
    if (BARE_HOST.test(value) || /^www\./i.test(value)) {
      value = `https://${value}`;
    } else {
      return null;
    }
  }
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return null;
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") return null;
  if (!url.hostname) return null;
  return url;
}

export function classifyRecipeUrl(raw: string): RecipeUrlClass {
  const url = parseRecipeURL(raw);
  if (!url) return "invalid";
  try {
    assertPublicHttpUrl(url);
  } catch {
    return "blocked";
  }
  if (isYouTubeHost(url.hostname)) {
    return youtubeVideoId(url) ? "youtube" : "web";
  }
  if (isInstagramHost(url.hostname)) return "instagram";
  return "web";
}

export function normalizeHost(hostname: string): string {
  let host = hostname.trim().toLowerCase();
  if (host.startsWith("[") && host.endsWith("]")) host = host.slice(1, -1);
  while (host.endsWith(".")) host = host.slice(0, -1);
  return host;
}

export function assertPublicHttpUrl(url: URL): void {
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new SourceError(NOT_ALLOWED, "url_not_allowed", 400);
  }
  if (url.username || url.password) {
    throw new SourceError(NOT_ALLOWED, "url_not_allowed", 400);
  }
  const host = normalizeHost(url.hostname);
  if (!host) throw new SourceError(NOT_ALLOWED, "url_not_allowed", 400);
  if (isIpLiteral(host)) {
    if (isPrivateAddress(host)) throw new SourceError(NOT_ALLOWED, "url_not_allowed", 400);
    return;
  }
  if (BLOCKED_HOSTS.has(host) || hostBlockedSuffix(host) || !host.includes(".")) {
    throw new SourceError(NOT_ALLOWED, "url_not_allowed", 400);
  }
}

function hostBlockedSuffix(host: string): boolean {
  return host.endsWith(".localhost") ||
    host.endsWith(".local") ||
    host.endsWith(".internal") ||
    host.endsWith(".localdomain");
}

export async function assertResolvedPublic(
  hostname: string,
  resolve: DnsResolve = defaultDnsResolve,
): Promise<void> {
  const host = normalizeHost(hostname);
  if (isIpLiteral(host)) {
    if (isPrivateAddress(host)) throw new SourceError(NOT_ALLOWED, "url_not_allowed", 400);
    return;
  }
  let addresses: string[] = [];
  try {
    addresses = await resolve(host);
  } catch (error) {
    console.error("dns resolve failed:", host, errorLabel(error));
    throw new SourceError(FETCH_FAILED, "url_fetch_failed", 422);
  }
  if (addresses.length === 0) throw new SourceError(FETCH_FAILED, "url_fetch_failed", 422);
  for (const address of addresses) {
    if (isPrivateAddress(address)) throw new SourceError(NOT_ALLOWED, "url_not_allowed", 400);
  }
}

export async function defaultAssertSafe(url: URL): Promise<void> {
  assertPublicHttpUrl(url);
  await assertResolvedPublic(url.hostname);
}

async function defaultDnsResolve(hostname: string): Promise<string[]> {
  const found: string[] = [];
  for (const recordType of ["A", "AAAA"] as const) {
    try {
      const rows = await Deno.resolveDns(hostname, recordType);
      found.push(...rows);
    } catch {
      // No records of this type.
    }
  }
  return found;
}

export function isIpLiteral(host: string): boolean {
  const value = normalizeHost(host);
  if (value.includes(":")) return true;
  return /^\d{1,3}(?:\.\d{1,3}){3}$/.test(value);
}

export function isPrivateAddress(raw: string): boolean {
  const value = normalizeHost(raw);
  if (!value) return true;
  if (value.includes(":")) return isPrivateIPv6(value);
  const parts = parseIPv4(value);
  if (!parts) return true;
  return isPrivateIPv4(parts);
}

function parseIPv4(host: string): [number, number, number, number] | null {
  const pieces = host.split(".");
  if (pieces.length !== 4) return null;
  const nums: number[] = [];
  for (const piece of pieces) {
    if (!/^\d{1,3}$/.test(piece)) return null;
    if (piece.length > 1 && piece.startsWith("0")) return null;
    const n = Number(piece);
    if (!Number.isInteger(n) || n > 255) return null;
    nums.push(n);
  }
  return [nums[0], nums[1], nums[2], nums[3]];
}

function isPrivateIPv4(parts: [number, number, number, number]): boolean {
  const [a, b] = parts;
  if (a === 0 || a === 10 || a === 127) return true;
  if (a === 100 && b >= 64 && b <= 127) return true;
  if (a === 169 && b === 254) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  if (a >= 224) return true;
  return false;
}

function isPrivateIPv6(ip: string): boolean {
  const mapped = ip.match(/^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i);
  if (mapped) return isPrivateAddress(mapped[1]);
  const hexMapped = ip.match(/^::ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$/i);
  if (hexMapped) {
    const hi = parseInt(hexMapped[1], 16);
    const lo = parseInt(hexMapped[2], 16);
    const v4: [number, number, number, number] = [
      (hi >> 8) & 255,
      hi & 255,
      (lo >> 8) & 255,
      lo & 255,
    ];
    return isPrivateIPv4(v4);
  }
  if (ip === "::" || ip === "::1") return true;
  if (/^(0+:)+0*1$/.test(ip) || /^(0+:)+0+$/.test(ip)) return true;
  const firstGroup = ip.split("::")[0].split(":")[0] || "0";
  const n = parseInt(firstGroup, 16);
  if (!Number.isFinite(n)) return true;
  if ((n & 0xfe00) === 0xfc00) return true;
  if ((n & 0xffc0) === 0xfe80) return true;
  if ((n & 0xff00) === 0xff00) return true;
  return false;
}

function isYouTubeHost(hostname: string): boolean {
  const host = normalizeHost(hostname);
  return host === "youtu.be" ||
    host === "youtube.com" ||
    host.endsWith(".youtube.com") ||
    host === "youtube-nocookie.com" ||
    host.endsWith(".youtube-nocookie.com");
}

function isInstagramHost(hostname: string): boolean {
  const host = normalizeHost(hostname);
  return host === "instagram.com" ||
    host.endsWith(".instagram.com") ||
    host === "instagr.am" ||
    host.endsWith(".instagr.am");
}

export function youtubeVideoId(url: URL): string | null {
  const host = normalizeHost(url.hostname);
  if (host === "youtu.be") {
    const id = url.pathname.split("/").filter(Boolean)[0] ?? "";
    return isVideoId(id) ? id : null;
  }
  if (!isYouTubeHost(host)) return null;
  if (url.pathname === "/watch" || url.pathname === "/watch/") {
    const id = url.searchParams.get("v") ?? "";
    return isVideoId(id) ? id : null;
  }
  const parts = url.pathname.split("/").filter(Boolean);
  if (parts.length >= 2 && (parts[0] === "shorts" || parts[0] === "embed" || parts[0] === "live" || parts[0] === "v")) {
    return isVideoId(parts[1]) ? parts[1] : null;
  }
  return null;
}

function isVideoId(id: string): boolean {
  return /^[A-Za-z0-9_-]{11}$/.test(id);
}

export async function resolveRecipeSource(raw: string, ctx: FetchCtx = {}): Promise<ResolvedSource> {
  const url = parseRecipeURL(raw);
  if (!url) throw new SourceError(NOT_ALLOWED, "url_not_allowed", 400);
  const assertSafe = ctx.assertSafe ?? defaultAssertSafe;
  await assertSafe(url);
  const fetcher = makeSafeFetch(ctx, assertSafe);

  if (isYouTubeHost(url.hostname)) {
    const id = youtubeVideoId(url);
    if (!id) throw new SourceError(YOUTUBE_LINK, "url_fetch_failed", 422);
    const text = await loadYouTube(id, fetcher, ctx.youtubeApiKey?.trim() || undefined);
    return { kind: "text", text, source: "youtube" };
  }
  if (isInstagramHost(url.hostname)) {
    const text = await loadInstagram(url, fetcher);
    return { kind: "text", text, source: "instagram" };
  }
  return await loadWebPage(url, fetcher);
}

function makeSafeFetch(ctx: FetchCtx, assertSafe: (url: URL) => Promise<void>): FetchLike {
  const fetchImpl = ctx.fetchImpl ?? ((url, init) => fetch(url, init));
  const maxBytes = ctx.maxBytes ?? MAX_RESPONSE_BYTES;
  const timeoutMs = ctx.timeoutMs ?? FETCH_TIMEOUT_MS;

  return async (target: string) => {
    let current = new URL(target);
    for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
      await assertSafe(current);
      let response: Response;
      try {
        response = await fetchImpl(current.toString(), {
          method: "GET",
          redirect: "manual",
          headers: FETCH_HEADERS,
          signal: AbortSignal.timeout(timeoutMs),
        });
      } catch (error) {
        if (error instanceof SourceError) throw error;
        console.error("source fetch failed:", current.hostname, errorLabel(error));
        throw new SourceError(FETCH_FAILED, "url_fetch_failed", 422);
      }
      if (isRedirect(response.status)) {
        const location = response.headers.get("location");
        await response.body?.cancel();
        if (!location) throw new SourceError(FETCH_FAILED, "url_fetch_failed", 422);
        current = new URL(location, current);
        continue;
      }
      if (!response.ok) {
        await response.body?.cancel();
        console.error("source fetch status:", current.hostname, response.status);
        throw new SourceError(FETCH_FAILED, "url_fetch_failed", 422);
      }
      if (!contentTypeAllowed(response.headers.get("content-type"))) {
        await response.body?.cancel();
        throw new SourceError(
          "That link isn't a recipe page I can read. Paste the recipe text instead.",
          "url_fetch_failed",
          422,
        );
      }
      const body = await readCapped(response, maxBytes);
      return new Response(body, { status: response.status, headers: response.headers });
    }
    throw new SourceError(FETCH_FAILED, "url_fetch_failed", 422);
  };
}

function errorLabel(error: unknown): string {
  if (error instanceof Error) return `${error.name}: ${error.message}`.slice(0, 200);
  return String(error).slice(0, 200);
}

function isRedirect(status: number): boolean {
  return status === 301 || status === 302 || status === 303 || status === 307 || status === 308;
}

function contentTypeAllowed(header: string | null): boolean {
  if (!header) return true;
  const base = header.split(";")[0].trim().toLowerCase();
  if (base.startsWith("text/")) return true;
  if (base.includes("json") || base.includes("xml") || base.includes("html")) return true;
  return false;
}

async function readCapped(response: Response, maxBytes: number): Promise<string> {
  const declared = Number(response.headers.get("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > maxBytes) {
    await response.body?.cancel();
    throw new SourceError(
      "That page is too large to read. Paste the recipe text instead.",
      "url_fetch_failed",
      422,
    );
  }
  if (!response.body) return "";
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    if (!value) continue;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel();
      throw new SourceError(
        "That page is too large to read. Paste the recipe text instead.",
        "url_fetch_failed",
        422,
      );
    }
    chunks.push(value);
  }
  const buf = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    buf.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(buf);
}

async function loadYouTube(id: string, fetchImpl: FetchLike, apiKey?: string): Promise<string> {
  let title = "";
  let description = "";
  let channel = "";
  let watchHtml: string | null = null;
  const watchURL = `https://www.youtube.com/watch?v=${id}`;

  if (apiKey) {
    try {
      const api = new URL("https://www.googleapis.com/youtube/v3/videos");
      api.searchParams.set("part", "snippet");
      api.searchParams.set("id", id);
      api.searchParams.set("fields", "items(snippet(title,description,channelTitle))");
      api.searchParams.set("key", apiKey);
      const response = await fetchImpl(api.toString(), {});
      const json = JSON.parse(response.body ? await response.text() : "") as {
        items?: Array<{ snippet?: { title?: string; description?: string; channelTitle?: string } }>;
      };
      const snippet = json.items?.[0]?.snippet;
      if (snippet) {
        title = String(snippet.title ?? "");
        description = String(snippet.description ?? "");
        channel = String(snippet.channelTitle ?? "");
      }
    } catch (error) {
      if (error instanceof SourceError && error.code === "url_not_allowed") throw error;
      console.error("youtube data api failed; using the no-key fallback");
    }
  }

  const pageNeeded = !title || !description || !looksLikeRecipe(description);
  if (pageNeeded) {
    try {
      const response = await fetchImpl(watchURL, {});
      watchHtml = await response.text();
      const parsed = parseYouTubeWatchPage(watchHtml);
      if (!title) title = parsed.title;
      if (!channel) channel = parsed.channel;
      if (parsed.description && (!description || !looksLikeRecipe(description))) {
        description = parsed.description;
      }
    } catch (error) {
      if (error instanceof SourceError && error.code === "url_not_allowed") throw error;
    }
  }

  let captions = "";
  if (!looksLikeRecipe(description)) {
    const captionUrl = watchHtml ? captionTrackUrl(watchHtml) : null;
    if (captionUrl && isYouTubeCaptionUrl(captionUrl)) {
      try {
        const response = await fetchImpl(captionUrl, {});
        captions = captionsToText(await response.text());
      } catch (error) {
        if (error instanceof SourceError && error.code === "url_not_allowed") throw error;
      }
    }
  }

  if (!title && !description && !captions) {
    try {
      const oembed = new URL("https://www.youtube.com/oembed");
      oembed.searchParams.set("url", watchURL);
      oembed.searchParams.set("format", "json");
      const response = await fetchImpl(oembed.toString(), {});
      const json = JSON.parse(await response.text()) as { title?: string; author_name?: string };
      title = String(json.title ?? "");
      if (!channel) channel = String(json.author_name ?? "");
    } catch (error) {
      if (error instanceof SourceError && error.code === "url_not_allowed") throw error;
    }
  }

  const body = [description, captions].filter((part) => part.trim().length > 0).join("\n\n").trim();
  if (body.length < 40 && !looksLikeRecipe(body)) {
    throw new SourceError(
      "Couldn't find a recipe in this video. Paste the description or caption text and I'll pull it from that.",
      "no_recipe_text",
      422,
    );
  }

  const pieces = [
    `URL: ${watchURL}`,
    title ? `Title: ${title}` : "",
    channel ? `Channel: ${channel}` : "",
    description ? `Description:\n${description}` : "",
    captions ? `Transcript:\n${captions}` : "",
  ].filter(Boolean);
  return clip(pieces.join("\n\n"));
}

function isYouTubeCaptionUrl(raw: string): boolean {
  try {
    const url = new URL(raw);
    return isYouTubeHost(url.hostname);
  } catch {
    return false;
  }
}

async function loadInstagram(url: URL, fetchImpl: FetchLike): Promise<string> {
  let html = "";
  try {
    const response = await fetchImpl(url.toString(), {});
    html = await response.text();
  } catch (error) {
    if (error instanceof SourceError && error.code === "url_not_allowed") throw error;
    throw new SourceError(INSTAGRAM_CAPTION, "instagram_caption_unavailable", 422);
  }
  const caption = extractInstagramCaption(html);
  if (!caption) throw new SourceError(INSTAGRAM_CAPTION, "instagram_caption_unavailable", 422);
  return clip(`Instagram caption:\n\n${caption}`);
}

async function loadWebPage(url: URL, fetchImpl: FetchLike): Promise<ResolvedSource> {
  const response = await fetchImpl(url.toString(), {});
  const html = await response.text();
  const recipe = recipeFromJsonLd(html);
  if (recipe) return { kind: "recipe", recipe, source: "web" };
  const text = htmlToText(html);
  if (text.length < 40 && !looksLikeRecipe(text)) {
    throw new SourceError(NO_RECIPE, "no_recipe_text", 422);
  }
  return { kind: "text", text: clip(`URL: ${url.toString()}\n\n${text}`), source: "web" };
}

function clip(value: string): string {
  return value.length <= MAX_SOURCE_CHARS ? value : value.slice(0, MAX_SOURCE_CHARS);
}

const RECIPE_HINT =
  /\b(ingredients?|instructions?|directions?|method|recipe|tablespoons?|teaspoons?|tbsp|tsp|cups?|grams?|kilograms?|andaza|chammach|pyaaz|haldi|preheat|simmer|saut[eé]|chopped|minced|bake|fry|boil|cook)\b/gi;

export function looksLikeRecipe(text: string): boolean {
  const value = text.trim();
  if (value.length < 20) return false;
  const hits = value.match(RECIPE_HINT);
  const count = hits?.length ?? 0;
  if (count >= 2) return true;
  if (count >= 1 && value.length >= 180) return true;
  return false;
}

export function parseYouTubeWatchPage(html: string): {
  title: string;
  description: string;
  channel: string;
  captionUrl: string | null;
} {
  const player = extractAssignedJson(html, "ytInitialPlayerResponse") as {
    videoDetails?: { title?: string; shortDescription?: string; author?: string };
    captions?: { playerCaptionsTracklistRenderer?: { captionTracks?: CaptionTrack[] } };
  } | null;
  const details = player?.videoDetails;
  const title = stringVal(details?.title) || metaContent(html, "og:title") || "";
  const description = stringVal(details?.shortDescription) ||
    metaContent(html, "og:description") ||
    metaContent(html, "description") ||
    "";
  const channel = stringVal(details?.author) || "";
  const tracks = player?.captions?.playerCaptionsTracklistRenderer?.captionTracks ?? [];
  return {
    title,
    description,
    channel,
    captionUrl: pickCaptionUrl(tracks),
  };
}

type CaptionTrack = { baseUrl?: string; languageCode?: string; kind?: string };

export function captionTrackUrl(html: string): string | null {
  return parseYouTubeWatchPage(html).captionUrl;
}

function pickCaptionUrl(tracks: CaptionTrack[]): string | null {
  const usable = tracks.filter((track) => typeof track.baseUrl === "string" && track.baseUrl.length > 0);
  if (usable.length === 0) return null;
  const rank = (track: CaptionTrack) => {
    const lang = (track.languageCode ?? "").toLowerCase();
    const auto = track.kind === "asr" ? 1 : 0;
    if (lang === "en") return 0 + auto;
    if (lang.startsWith("en")) return 2 + auto;
    if (lang === "hi" || lang === "ur" || lang === "pa") return 4 + auto;
    return 6 + auto;
  };
  usable.sort((a, b) => rank(a) - rank(b));
  return usable[0].baseUrl ?? null;
}

export function captionsToText(body: string): string {
  const trimmed = body.trim();
  if (!trimmed) return "";
  if (trimmed.startsWith("{")) {
    try {
      const json = JSON.parse(trimmed) as { events?: Array<{ segs?: Array<{ utf8?: string }> }> };
      const parts: string[] = [];
      for (const event of json.events ?? []) {
        for (const seg of event.segs ?? []) {
          if (seg.utf8) parts.push(seg.utf8);
        }
      }
      const text = parts.join("").replace(/\s+/g, " ").trim();
      if (text) return text;
    } catch {
      // Timed text is often XML instead.
    }
  }
  const parts: string[] = [];
  const re = /<text\b[^>]*>([\s\S]*?)<\/text>/gi;
  let match: RegExpExecArray | null;
  while ((match = re.exec(trimmed)) !== null) {
    parts.push(decodeHtml(match[1].replace(/<[^>]+>/g, " ")));
  }
  return parts.join(" ").replace(/\s+/g, " ").trim();
}

const INSTAGRAM_GENERIC =
  /log in to instagram|sign up to see|create an account or log in|login • instagram|see this post|content isn't available|instagram photos and videos/i;

export function extractInstagramCaption(html: string): string | null {
  const og = metaContent(html, "og:description") ?? metaContent(html, "description");
  if (og && og.trim().length > 20 && !INSTAGRAM_GENERIC.test(og)) return og.trim();
  const idx = html.indexOf("edge_media_to_caption");
  if (idx < 0) return null;
  const slice = html.slice(idx, idx + 5000);
  const text = slice.match(/"text"\s*:\s*"((?:\\.|[^"\\])*)"/);
  if (!text) return null;
  try {
    const value = JSON.parse(`"${text[1]}"`) as string;
    const caption = value.trim();
    if (caption.length > 10 && !INSTAGRAM_GENERIC.test(caption)) return caption;
  } catch {
    return null;
  }
  return null;
}

export function recipeFromJsonLd(html: string): StructuredRecipe | null {
  for (const block of extractJsonLdBlocks(html)) {
    const found: unknown[] = [];
    findRecipes(block, found);
    for (const node of found) {
      if (!node || typeof node !== "object") continue;
      const recipe = structuredFromRecipeNode(node as Record<string, unknown>);
      if (recipe) return recipe;
    }
  }
  return null;
}

function extractJsonLdBlocks(html: string): unknown[] {
  const blocks: unknown[] = [];
  const re = /<script\b[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
  let match: RegExpExecArray | null;
  while ((match = re.exec(html)) !== null) {
    const raw = match[1].trim();
    const parsed = parseJsonLd(raw) ?? parseJsonLd(decodeHtml(raw));
    if (parsed !== null) blocks.push(parsed);
  }
  return blocks;
}

function parseJsonLd(raw: string): unknown | null {
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function findRecipes(node: unknown, out: unknown[]): void {
  if (!node) return;
  if (Array.isArray(node)) {
    for (const item of node) findRecipes(item, out);
    return;
  }
  if (typeof node !== "object") return;
  const obj = node as Record<string, unknown>;
  if (isRecipeType(obj["@type"])) out.push(obj);
  if (obj["@graph"]) findRecipes(obj["@graph"], out);
  if (obj.mainEntity) findRecipes(obj.mainEntity, out);
}

function isRecipeType(type: unknown): boolean {
  const values = Array.isArray(type) ? type : [type];
  return values.some((value) => {
    if (typeof value !== "string") return false;
    const trimmed = value.trim().toLowerCase();
    return trimmed === "recipe" || trimmed.endsWith("/recipe");
  });
}

function structuredFromRecipeNode(node: Record<string, unknown>): StructuredRecipe | null {
  const title = stringVal(node.name) ?? stringVal(node.headline);
  const ingredients = ingredientLines(node.recipeIngredient).map(parseIngredientLine);
  const steps = instructionLines(node.recipeInstructions);
  if (!title || ingredients.length === 0 || steps.length === 0) return null;
  return {
    title,
    attribution: authorName(node.author) ?? authorName(node.creator),
    ingredients,
    steps,
    notes: noteFrom(node.description, title),
  };
}

function ingredientLines(value: unknown): string[] {
  if (value == null) return [];
  const list = Array.isArray(value) ? value : [value];
  const out: string[] = [];
  for (const item of list) {
    if (typeof item === "string") {
      const text = stripTags(decodeHtml(item)).trim();
      if (text) out.push(text);
    } else if (item && typeof item === "object") {
      const obj = item as Record<string, unknown>;
      const text = stringVal(obj.text) ?? stringVal(obj.name);
      if (text) out.push(text);
    }
  }
  return out;
}

function instructionLines(value: unknown): string[] {
  const out: string[] = [];
  collectInstructions(value, out, null);
  return out;
}

function collectInstructions(value: unknown, out: string[], section: string | null): void {
  if (value == null) return;
  if (typeof value === "string") {
    const text = stripTags(decodeHtml(value)).trim();
    for (const part of text.split(/\n+/)) {
      const line = part.trim();
      if (!line) continue;
      out.push(section ? `${section}: ${line}` : line);
    }
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) collectInstructions(item, out, section);
    return;
  }
  if (typeof value !== "object") return;
  const obj = value as Record<string, unknown>;
  const typeStr = typeText(obj["@type"]);
  if (/howtosection/i.test(typeStr)) {
    const name = stringVal(obj.name);
    collectInstructions(obj.itemListElement ?? obj.recipeInstructions, out, name);
    return;
  }
  const text = stringVal(obj.text) ?? (obj.text == null ? stringVal(obj.name) : null);
  if (text && (/howto/i.test(typeStr) || obj.text != null)) {
    const clean = stripTags(text).trim();
    if (clean) out.push(section ? `${section}: ${clean}` : clean);
    return;
  }
  if (obj.itemListElement) collectInstructions(obj.itemListElement, out, section);
}

function typeText(type: unknown): string {
  if (Array.isArray(type)) return type.filter((item) => typeof item === "string").join(" ");
  return typeof type === "string" ? type : "";
}

function authorName(author: unknown): string | null {
  if (!author) return null;
  if (typeof author === "string") {
    const name = author.trim();
    return name || null;
  }
  if (Array.isArray(author)) return authorName(author[0]);
  if (typeof author === "object") {
    const name = stringVal((author as Record<string, unknown>).name);
    return name;
  }
  return null;
}

function noteFrom(description: unknown, title: string): string | null {
  const text = stringVal(description);
  if (!text || text.toLowerCase() === title.toLowerCase()) return null;
  return text.length > 300 ? `${text.slice(0, 297)}...` : text;
}

function stringVal(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const text = stripTags(decodeHtml(value)).trim();
  return text || null;
}

const FRACTIONS: Record<string, number> = {
  "½": 1 / 2,
  "¼": 1 / 4,
  "¾": 3 / 4,
  "⅓": 1 / 3,
  "⅔": 2 / 3,
  "⅛": 1 / 8,
  "⅜": 3 / 8,
  "⅝": 5 / 8,
  "⅞": 7 / 8,
};

const UNIT_RE =
  /^(tablespoons?|tbsp|teaspoons?|tsp|cups?|grams?|kilograms?|kg|milliliters?|ml|liters?|ounces?|oz|pounds?|lbs?|cloves?|pieces?|slices?|cans?|pinches?|bunches?|sticks?|g|l)\b\.?\s*/i;

const VAGUE_RE = /\b(to taste|as needed|andaza(?:\s+se)?|a pinch|handful|mutthi|chutki|thori|q\.?\s*s\.?|optional)\b/i;

export function parseIngredientLine(line: string): StructuredIngredient {
  const original = line.trim();
  let rest = original.replace(/^[-*•]\s*/, "");
  const vaguePhrase = VAGUE_RE.test(rest);
  const leading = parseLeadingQuantity(rest);
  let amount: number | null = null;
  let vague = vaguePhrase;
  if (leading) {
    amount = leading.amount;
    rest = leading.rest;
    const range = rest.match(/^[–—-]\s*(?:\d+(?:\.\d+)?|\d+\s*\/\s*\d+)\s*/);
    if (range) {
      vague = true;
      rest = rest.slice(range[0].length).trim();
    }
  } else {
    vague = true;
  }
  let unit: string | null = null;
  const unitMatch = rest.match(UNIT_RE);
  if (unitMatch) {
    unit = unitMatch[1].toLowerCase();
    rest = rest.slice(unitMatch[0].length).trim();
  }
  if (amount == null) unit = null;
  const ingredient = cleanIngredientName(rest, original);
  return {
    ingredient,
    original_phrase: original,
    amount,
    unit,
    vague,
  };
}

function parseLeadingQuantity(input: string): { amount: number; rest: string } | null {
  let rest = input.trim();
  const mixed = rest.match(/^(\d+)\s+(\d+)\s*\/\s*(\d+)\b/);
  if (mixed && Number(mixed[3]) !== 0) {
    return {
      amount: Number(mixed[1]) + Number(mixed[2]) / Number(mixed[3]),
      rest: rest.slice(mixed[0].length).trim(),
    };
  }
  const fraction = rest.match(/^(\d+)\s*\/\s*(\d+)\b/);
  if (fraction && Number(fraction[2]) !== 0) {
    return {
      amount: Number(fraction[1]) / Number(fraction[2]),
      rest: rest.slice(fraction[0].length).trim(),
    };
  }
  const decimal = rest.match(/^(\d+(?:\.\d+)?)/);
  if (decimal) {
    let amount = Number(decimal[1]);
    rest = rest.slice(decimal[0].length).trim();
    const glyph = rest[0];
    if (glyph && FRACTIONS[glyph] != null) {
      amount += FRACTIONS[glyph];
      rest = rest.slice(1).trim();
    }
    return { amount, rest };
  }
  const glyph = rest[0];
  if (glyph && FRACTIONS[glyph] != null) {
    return { amount: FRACTIONS[glyph], rest: rest.slice(1).trim() };
  }
  return null;
}

function cleanIngredientName(rest: string, original: string): string {
  let name = rest.replace(/,?\s*(?:or\s+)?(?:to taste|as needed|andaza(?:\s+se)?|optional)\b/ig, " ");
  name = name.replace(/^(?:a |an )?(?:handful of|pinch of|bit of)\s+/i, "");
  name = name.replace(/\s+/g, " ").replace(/^[,.\-–—\s]+|[,.\-–—\s]+$/g, "").trim();
  if (!name) return original.trim();
  return name;
}

export function htmlToText(html: string): string {
  let text = html
    .replace(/<!--[\s\S]*?-->/g, " ")
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(/<noscript\b[^>]*>[\s\S]*?<\/noscript>/gi, " ")
    .replace(/<svg\b[^>]*>[\s\S]*?<\/svg>/gi, " ")
    .replace(/<nav\b[^>]*>[\s\S]*?<\/nav>/gi, " ")
    .replace(/<footer\b[^>]*>[\s\S]*?<\/footer>/gi, " ")
    .replace(/<header\b[^>]*>[\s\S]*?<\/header>/gi, " ");
  text = text
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(p|div|li|h[1-6]|tr|section)>/gi, "\n")
    .replace(/<[^>]+>/g, " ");
  // Collapse runs first so removing whitespace before newlines cannot rescan
  // overlapping suffixes of a long space/tab run when no newline follows.
  text = decodeHtml(text)
    .replace(/[ \t]{2,}/g, " ")
    .replace(/[ \t]\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  return text;
}

export function metaContent(html: string, key: string): string | null {
  const tags = html.match(/<meta\b[^>]*>/gi) ?? [];
  const wanted = key.toLowerCase();
  for (const tag of tags) {
    const attr = /(?:property|name|itemprop)\s*=\s*["']([^"']+)["']/i.exec(tag);
    const content = /content\s*=\s*["']([^"']*)["']/i.exec(tag);
    if (!attr || !content) continue;
    if (attr[1].toLowerCase() === wanted) return decodeHtml(content[1]).trim();
  }
  return null;
}

export function decodeHtml(value: string): string {
  return value
    .replace(/&#x([0-9a-f]+);/gi, (_, hex: string) => codepoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, dec: string) => codepoint(parseInt(dec, 10)))
    .replace(/&nbsp;/gi, " ")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&amp;/gi, "&");
}

function codepoint(code: number): string {
  if (!Number.isFinite(code) || code < 0 || code > 0x10ffff) return "";
  try {
    return String.fromCodePoint(code);
  } catch {
    return "";
  }
}

function stripTags(value: string): string {
  return value.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
}

function extractAssignedJson(html: string, marker: string): unknown | null {
  const at = html.indexOf(marker);
  if (at < 0) return null;
  let i = at + marker.length;
  while (i < html.length && /\s/.test(html[i])) i++;
  if (html[i] === "=") {
    i++;
    while (i < html.length && /\s/.test(html[i])) i++;
  }
  if (html[i] !== "{") return null;
  const end = matchJsonEnd(html, i);
  if (end < 0) return null;
  try {
    return JSON.parse(html.slice(i, end));
  } catch {
    return null;
  }
}

function matchJsonEnd(source: string, start: number): number {
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = start; i < source.length; i++) {
    const char = source[i];
    if (inString) {
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char === "\\") {
        escaped = true;
        continue;
      }
      if (char === '"') inString = false;
      continue;
    }
    if (char === '"') {
      inString = true;
      continue;
    }
    if (char === "{") depth++;
    else if (char === "}") {
      depth--;
      if (depth === 0) return i + 1;
    }
  }
  return -1;
}

// Model output is supposed to be one bare JSON object, but page text can make
// it wrap the object in prose or code fences. Pull out the first balanced
// {...} and accept it only if it is a usable recipe. Returns "no_recipe" when
// the model says the source has no recipe or returns one with no ingredients.
export function parseModelRecipe(rawText: string): StructuredRecipe | "no_recipe" | null {
  const text = rawText.replaceAll("```json", "").replaceAll("```", "").trim();
  let parsed: unknown = null;
  try {
    parsed = JSON.parse(text);
  } catch {
    const start = text.indexOf("{");
    if (start < 0) return null;
    const end = matchJsonEnd(text, start);
    if (end < 0) return null;
    try {
      parsed = JSON.parse(text.slice(start, end));
    } catch {
      return null;
    }
  }
  if (Array.isArray(parsed)) parsed = parsed[0];
  if (!parsed || typeof parsed !== "object") return null;
  const obj = parsed as Record<string, unknown>;
  if (obj.error === "no_recipe") return "no_recipe";
  const title = typeof obj.title === "string" ? obj.title.trim() : "";
  const ingredients = Array.isArray(obj.ingredients) ? obj.ingredients : [];
  if (!title || ingredients.length === 0) return "no_recipe";
  return {
    title,
    attribution: typeof obj.attribution === "string" ? obj.attribution : null,
    ingredients: ingredients as StructuredIngredient[],
    steps: Array.isArray(obj.steps) ? obj.steps.filter((step): step is string => typeof step === "string") : [],
    notes: typeof obj.notes === "string" ? obj.notes : null,
  };
}
