import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  classifyModelRecipe,
  parseRecipeURL,
  resolveRecipeSource,
  SourceError,
} from "./recipe_source.ts";
import {
  createTranscriptionProvider,
  TranscriptionError,
  transcriptionConfigFromEnv,
} from "./transcribe.ts";
import { ingredientMapForPrompt } from "./vocabulary.ts";

// Recipe extraction is proxied so the Anthropic key never ships in the iOS
// binary. The caller must be a signed-in user: the anon key as Bearer is a
// valid JWT but getUser rejects it, which is what closed the open proxy.
//
// Free-tier quota (see migration 011):
//   - grandfathered users: 5 extractions / rolling 24h
//   - new free users: 5 lifetime extractions
// Pro (`Saman Pro` RevenueCat entitlement) skips the quota. The iOS client
// opens the paywall on 402 for free users.
// Counted in recipe_extraction_events (service role only; see 004, 009, 011).
//
// Body is JSON { transcript } and/or { url }, or multipart/form-data with one
// `audio` part. A transcript that is only an http(s) link is read as a URL.
// Text transcripts still consume a slot before the model call, including when
// the provider fails. URL fetches that fail (blocked, Instagram caption
// missing, no recipe text) do not consume a slot. A URL that returns a
// complete schema.org Recipe, or that is sent to the model, consumes one slot.
//
// Audio: type and size are checked before the quota. The slot is taken before
// the transcription call, so a user with no slot never reaches the paid
// provider. A transcription failure or an empty transcript releases the slot.
// Once a transcript reaches the model, the text rule applies. Audio is never
// stored or logged; it passes through to the provider.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const anthropicEndpoint = "https://api.anthropic.com/v1/messages";
const anthropicModel = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-4-6";
const revenueCatEntitlementID = "Saman Pro";
const TRANSCRIPT_NO_RECIPE =
  "I only caught part of that. Try recording again, or type the ingredients and steps.";
const LINK_NO_RECIPE =
  "Couldn't find a recipe in that link. Paste the description or caption text and I'll try from that.";

const MAX_AUDIO_BYTES = 12 * 1024 * 1024;
const MIN_TRANSCRIPT_CHARS = 20;
const AUDIO_TYPES = new Set([
  "audio/mp4",
  "audio/m4a",
  "audio/x-m4a",
  "audio/aac",
  "audio/mpeg",
  "audio/wav",
]);

type ExtractRoute = "transcript" | "url" | "audio";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!apiKey || !supabaseUrl || !serviceRoleKey) {
    return json({ error: "Recipe extraction is not configured." }, 500);
  }

  const authHeader = request.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) {
    return json({ error: "Missing authorization." }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: userData, error: userError } = await admin.auth.getUser(jwt);
  if (userError || !userData?.user) {
    return json({ error: "Invalid or expired session." }, 401);
  }
  const userId = userData.user.id;

  let slotId: string | null = null;
  let transcript = "";
  let url = "";
  const contentType = request.headers.get("content-type") ?? "";
  if (/^multipart\/form-data\b/i.test(contentType)) {
    return await handleAudio(request, contentType, {
      anthropicKey: apiKey,
      takeQuotaSlot: () => takeQuotaSlot(),
      releaseSlot: () => releaseSlot(),
    });
  }

  try {
    const body = await request.json();
    transcript = String(body.transcript ?? "").trim();
    url = String(body.url ?? "").trim();
  } catch {
    return json({ error: "Request body must be JSON." }, 400);
  }

  if (!url && transcript && !/\s/.test(transcript) && parseRecipeURL(transcript)) {
    url = transcript;
  }

  if (!url && !transcript) {
    return json({ error: "A recipe transcript or link is required." }, 400);
  }

  async function takeQuotaSlot(): Promise<Response | null> {
    const entitlement = await lookupProEntitlement(userId);
    if (entitlement === "active") {
      // Pro is uncapped. Do not write recipe_extraction_events — those rows
      // are the free-tier meter, and a later downgrade must not inherit them.
      slotId = null;
      return null;
    }
    if (entitlement === "unknown") {
      // RevenueCat outage or timeout: do not meter the user as free.
      return json(
        {
          error: "Could not verify subscription. Try again.",
          code: "entitlement_unavailable",
        },
        503,
      );
    }

    // The RPC locks admissions for this user through counting and insertion.
    // A provider failure still counts; URL fetches that fail before here do not.
    const { data: reservedSlotId, error } = await admin.rpc(
      "reserve_recipe_extraction",
      { p_user_id: userId },
    );

    if (error) {
      console.error("quota reservation failed:", error.message);
      return json({ error: "Could not check extraction quota." }, 500);
    }

    if (reservedSlotId === null) {
      const { data: account } = await admin
        .from("user_accounts")
        .select("grandfathered")
        .eq("id", userId)
        .maybeSingle();
      const grandfathered = account?.grandfathered === true;
      return json(
        {
          error: grandfathered
            ? "Daily recipe extraction limit reached."
            : "Free recipe extraction limit reached.",
          code: "quota_exceeded",
          grandfathered,
        },
        402,
      );
    }

    if (typeof reservedSlotId !== "string" || !reservedSlotId) {
      return json({ error: "Could not record extraction." }, 500);
    }
    slotId = reservedSlotId;
    return null;
  }

  // Free-tier rows only. Pro never wrote one, so there is nothing to release.
  async function releaseSlot(): Promise<void> {
    if (slotId === null) return;
    const { error } = await admin.from("recipe_extraction_events").delete().eq("id", slotId);
    if (error) console.error("quota release failed:", error.message);
    slotId = null;
  }

  if (url) {
    let source;
    try {
      source = await resolveRecipeSource(url, {
        youtubeApiKey: Deno.env.get("YOUTUBE_API_KEY") ?? "",
      });
    } catch (error) {
      if (error instanceof SourceError) {
        return json({ error: error.message, code: error.code }, error.status);
      }
      console.error("url extract failed:", error instanceof Error ? error.message : "unknown");
      return json(
        { error: "Couldn't open that link. Check it and try again, or paste the recipe text.", code: "url_fetch_failed" },
        422,
      );
    }

    const slot = await takeQuotaSlot();
    if (slot) return slot;

    if (source.kind === "recipe") {
      return json({ recipe: source.recipe, raw_json: JSON.stringify(source.recipe) });
    }

    const userText = `Recipe source:\n\n${source.text}\n\nReturn the structured recipe as JSON.`;
    const response = await extractWithModel(apiKey, userText, pageSystemPrompt, "url");
    if (response.status === 422) {
      // The page had no usable recipe: same as a failed fetch, no slot used.
      await releaseSlot();
    }
    return response;
  }

  const slot = await takeQuotaSlot();
  if (slot) return slot;

  const userText = `Transcript:\n\n${transcript}\n\nReturn the structured recipe as JSON.`;
  return await extractWithModel(apiKey, userText, systemPrompt, "transcript");
});

type AudioDeps = {
  anthropicKey: string;
  takeQuotaSlot: () => Promise<Response | null>;
  releaseSlot: () => Promise<void>;
};

async function handleAudio(request: Request, contentType: string, deps: AudioDeps): Promise<Response> {
  const config = transcriptionConfigFromEnv();
  if (!config) {
    return json({ error: "Recipe extraction is not configured." }, 500);
  }

  // Size and type are checked before any paid call or quota write.
  const declaredLength = Number(request.headers.get("content-length") ?? "");
  if (Number.isFinite(declaredLength) && declaredLength > MAX_AUDIO_BYTES) {
    await request.body?.cancel();
    return audioTooLarge();
  }
  const bytes = await readBodyCapped(request, MAX_AUDIO_BYTES);
  if (bytes === null) return audioTooLarge();

  let audio: File;
  try {
    const form = await new Response(bytes, { headers: { "content-type": contentType } }).formData();
    const part = form.get("audio");
    if (!(part instanceof File) || part.size === 0) {
      return json({ error: "A recording is required.", code: "audio_missing" }, 400);
    }
    audio = part;
  } catch {
    return json({ error: "Request body must be multipart form data.", code: "audio_missing" }, 400);
  }

  const audioType = audio.type.split(";")[0].trim().toLowerCase();
  if (!AUDIO_TYPES.has(audioType)) {
    return json(
      { error: "That recording format isn't supported. Use M4A, AAC, MP3, or WAV.", code: "audio_unsupported_type" },
      415,
    );
  }

  const slot = await deps.takeQuotaSlot();
  if (slot) return slot;

  const provider = createTranscriptionProvider(config);
  const started = Date.now();
  let text: string;
  try {
    const result = await provider.transcribe(audio, audio.name || "recording.m4a");
    text = result.text.trim();
    logTranscription({
      provider: result.provider,
      model: result.model,
      providerStatus: 200,
      audioBytes: audio.size,
      audioType,
      durationMs: Date.now() - started,
      transcriptLength: text.length,
      languageCode: result.languageCode ?? null,
      outcome: text.length < MIN_TRANSCRIPT_CHARS ? "no_speech" : "ok",
    });
  } catch (error) {
    const known = error instanceof TranscriptionError ? error : null;
    logTranscription({
      provider: provider.provider,
      model: provider.model,
      providerStatus: known?.providerStatus ?? null,
      audioBytes: audio.size,
      audioType,
      durationMs: Date.now() - started,
      transcriptLength: null,
      languageCode: null,
      outcome: known?.reason ?? "error",
    });
    await deps.releaseSlot();
    return json(
      { error: "Couldn't turn that recording into text. Try again.", code: "transcription_failed", source: "audio" },
      502,
    );
  }

  if (text.length < MIN_TRANSCRIPT_CHARS) {
    await deps.releaseSlot();
    return json({ error: TRANSCRIPT_NO_RECIPE, code: "audio_no_speech", source: "audio" }, 422);
  }

  // From here the text rule applies: model failures keep the slot.
  const userText = `Transcript:\n\n${text}\n\nReturn the structured recipe as JSON.`;
  return await extractWithModel(deps.anthropicKey, userText, systemPrompt, "audio", { transcript: text });
}

function audioTooLarge(): Response {
  return json({ error: "That recording is too long to upload. Keep it under 10 minutes.", code: "audio_too_large" }, 413);
}

/** Reads at most `max` bytes. Returns null as soon as the body is larger. */
async function readBodyCapped(request: Request, max: number): Promise<Uint8Array<ArrayBuffer> | null> {
  if (!request.body) return new Uint8Array();
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > max) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return out;
}

function logTranscription(entry: {
  provider: string;
  model: string;
  providerStatus: number | null;
  audioBytes: number;
  audioType: string;
  durationMs: number;
  transcriptLength: number | null;
  languageCode: string | null;
  outcome: string;
}) {
  console.log(JSON.stringify({
    event: "extract_recipe_transcription",
    provider: entry.provider,
    model: entry.model,
    provider_status: entry.providerStatus,
    audio_bytes: entry.audioBytes,
    audio_type: entry.audioType,
    duration_ms: entry.durationMs,
    transcript_length: entry.transcriptLength,
    language_code: entry.languageCode,
    outcome: entry.outcome,
  }));
}

type ProEntitlementLookup = "active" | "inactive" | "unknown";

const revenueCatLookupTimeoutMs = 2_500;

async function lookupProEntitlement(appUserId: string): Promise<ProEntitlementLookup> {
  const secret = Deno.env.get("REVENUECAT_SECRET_API_KEY")?.trim();
  if (!secret) {
    // Secret is set when Pro products are live. Until then, free-tier quota
    // applies to everyone so we never silently grant unlimited extracts.
    return "inactive";
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), revenueCatLookupTimeoutMs);
  try {
    const response = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}`,
      {
        headers: {
          Authorization: `Bearer ${secret}`,
          "Content-Type": "application/json",
        },
        signal: controller.signal,
      },
    );
    // Unknown subscriber is a confirmed free user. Other non-2xx are indeterminate.
    if (response.status === 404) return "inactive";
    if (!response.ok) {
      console.error("revenuecat subscriber lookup failed:", response.status);
      return "unknown";
    }
    const payload = await response.json() as {
      subscriber?: {
        entitlements?: Record<string, { expires_date?: string | null }>;
      };
    };
    const entitlement = payload.subscriber?.entitlements?.[revenueCatEntitlementID];
    if (!entitlement) return "inactive";
    if (entitlement.expires_date == null) return "active";
    return Date.parse(entitlement.expires_date) > Date.now() ? "active" : "inactive";
  } catch (error) {
    console.error("revenuecat subscriber lookup error:", error instanceof Error ? error.message : "unknown");
    return "unknown";
  } finally {
    clearTimeout(timer);
  }
}

async function extractWithModel(
  apiKey: string,
  userText: string,
  system: string,
  route: ExtractRoute,
  extra: Record<string, string> = {},
): Promise<Response> {
  const anthropicResponse = await fetch(anthropicEndpoint, {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: anthropicModel,
      max_tokens: 4096,
      system,
      messages: [{ role: "user", content: userText }],
    }),
  });

  const replyBody = await anthropicResponse.text();
  let providerPayload: {
    stop_reason?: string;
    model?: string;
    content?: { type?: string; text?: string }[];
  } = {};
  try {
    providerPayload = replyBody ? JSON.parse(replyBody) : {};
  } catch {
    providerPayload = {};
  }
  const stopReason = typeof providerPayload.stop_reason === "string" ? providerPayload.stop_reason : null;
  const model = typeof providerPayload.model === "string" ? providerPayload.model : anthropicModel;
  const rawText = providerPayload.content?.find((block) => block.type === "text")?.text ?? "";

  if (!anthropicResponse.ok) {
    logModelCall({
      status: anthropicResponse.status,
      stopReason,
      model,
      inputLength: userText.length,
      outcome: "provider_error",
      noRecipeReason: null,
    });
    return json({ error: "Recipe extraction provider failed.", source: route, ...extra }, 502);
  }

  if (!rawText) {
    logModelCall({
      status: anthropicResponse.status,
      stopReason,
      model,
      inputLength: userText.length,
      outcome: "empty_reply",
      noRecipeReason: null,
    });
    return json({ error: "Recipe extraction returned no content.", source: route, ...extra }, 502);
  }

  const classified = classifyModelRecipe(rawText);
  switch (classified.outcome) {
    case "no_recipe":
      logModelCall({
        status: anthropicResponse.status,
        stopReason,
        model,
        inputLength: userText.length,
        outcome: "no_recipe_text",
        noRecipeReason: classified.reason,
      });
      return json(
        {
          error: route === "url" ? LINK_NO_RECIPE : TRANSCRIPT_NO_RECIPE,
          code: "no_recipe_text",
          source: route,
          ...extra,
        },
        422,
      );
    case "unparseable":
      logModelCall({
        status: anthropicResponse.status,
        stopReason,
        model,
        inputLength: userText.length,
        outcome: "unparseable",
        noRecipeReason: null,
      });
      return json({ error: "Recipe extraction returned invalid JSON.", source: route, ...extra }, 502);
    case "recipe":
      logModelCall({
        status: anthropicResponse.status,
        stopReason,
        model,
        inputLength: userText.length,
        outcome: "recipe",
        noRecipeReason: null,
      });
      return json({ recipe: classified.recipe, raw_json: JSON.stringify(classified.recipe), ...extra });
    default: {
      const unreachable: never = classified;
      return unreachable;
    }
  }
}

function logModelCall(entry: {
  status: number;
  stopReason: string | null;
  model: string;
  inputLength: number;
  outcome: string;
  noRecipeReason: string | null;
}) {
  console.log(JSON.stringify({
    event: "extract_recipe_model",
    anthropic_status: entry.status,
    stop_reason: entry.stopReason,
    model: entry.model,
    input_length: entry.inputLength,
    outcome: entry.outcome,
    no_recipe_reason: entry.noRecipeReason,
  }));
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

const systemPrompt = `
You convert a spoken, phone-call recipe into a structured recipe. The speaker is a South Asian parent. The transcript is code-switched (Urdu/Hindi/Punjabi + English) and the measurements are mostly approximate.

You will follow three rules without exception:

RULE 1 - NEVER INVENT A NUMBER.
If the speaker gave a vague measurement ("andaza se", "thori si", "a handful", "to taste", "apne hisaab se", "mutthi bhar", "chutki bhar"), set amount to null and vague to true. Do NOT convert vague amounts into grams, cups, or any number. Inventing "30g" for "a fistful" is the single worst thing you can do.
A number is allowed ONLY when the speaker actually said one: "ek pyaaz" -> 1, "do cup" -> 2, "half teaspoon" -> 0.5 tsp, "ek kilo" -> 1 kg.

RULE 2 - NEVER DISCARD HER WORDS.
For every ingredient, original_phrase holds the speaker's exact phrasing, code-switch intact ("haldi just a little, andaza se").

RULE 3 - MAP THE NAME FOR THE GROCERY LIST.
ingredient is the English shopping term so it can go on a list (${ingredientMapForPrompt()}). original_phrase still keeps the original word.

Return ONLY valid JSON matching this schema, no prose, no markdown fences:
{"title":"string - recipe name","attribution":"string|null","ingredients":[{"ingredient":"string - English grocery-list term","original_phrase":"string - speaker's exact words","amount":"number|null - ONLY if a real quantity was spoken, else null","unit":"string|null","vague":"boolean - true if measurement was approximate"}],"steps":["string - loose step, no invented precision"],"notes":"string|null"}
`;

const pageSystemPrompt = `
You convert a recipe page, video description, or caption into a structured recipe. The cook is a South Asian home cook. The text may be English or code-switched Urdu/Hindi/Punjabi. It may include a title, channel, or author line.

You will follow three rules without exception:

RULE 1 - NEVER INVENT A NUMBER.
If the source gave a vague measurement ("andaza se", "thori si", "a handful", "to taste", "apne hisaab se", "mutthi bhar", "chutki bhar"), set amount to null and vague to true. Do NOT convert vague amounts into grams, cups, or any number. Inventing "30g" for "a fistful" is the single worst thing you can do.
A number is allowed ONLY when the source text actually states one: "ek pyaaz" -> 1, "2 cups" -> 2, "half teaspoon" -> 0.5 tsp, "1 kg" -> 1 kg.

RULE 2 - NEVER DISCARD THE SOURCE WORDS.
For every ingredient, original_phrase holds the source's exact phrasing, code-switch intact ("haldi just a little, andaza se").

RULE 3 - MAP THE NAME FOR THE GROCERY LIST.
ingredient is the English shopping term so it can go on a list (${ingredientMapForPrompt()}). original_phrase still keeps the original word.
If a channel or author is given, use it as attribution. Otherwise attribution is null.
If the source lists several recipes, return only the single main recipe (the first complete one with ingredients). If the source has no recipe with ingredients, return exactly {"error":"no_recipe"}.

Return ONLY valid JSON matching this schema, no prose, no markdown fences:
{"title":"string - recipe name","attribution":"string|null","ingredients":[{"ingredient":"string - English grocery-list term","original_phrase":"string - source's exact words","amount":"number|null - ONLY if a real quantity was written, else null","unit":"string|null","vague":"boolean - true if measurement was approximate"}],"steps":["string - step from the source, no invented precision"],"notes":"string|null"}
`;
