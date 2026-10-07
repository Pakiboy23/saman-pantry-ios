import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  classifyModelRecipe,
  parseRecipeURL,
  resolveRecipeSource,
  SourceError,
} from "./recipe_source.ts";

// Recipe extraction is proxied so the Anthropic key never ships in the iOS
// binary. The caller must be a signed-in user: the anon key as Bearer is a
// valid JWT but getUser rejects it, which is what closed the open proxy.
// Quota is 5 extractions per rolling 24h for every signed-in user, including
// Pro. This function does not read RevenueCat.
// The iOS client must show "try tomorrow" on 402 — do not open the Pro
// paywall until a higher Pro cap actually exists here.
// Counted in recipe_extraction_events (service role only; see 004 and 009).
//
// Body is { transcript } and/or { url }. A transcript that is only an http(s)
// link is read as a URL. Text transcripts still consume a slot before the
// model call, including when the provider fails. URL fetches that fail
// (blocked, Instagram caption missing, no recipe text) do not consume a slot.
// A URL that returns a complete schema.org Recipe, or that is sent to the
// model, consumes one slot.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const anthropicEndpoint = "https://api.anthropic.com/v1/messages";
const anthropicModel = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-4-6";
const TRANSCRIPT_NO_RECIPE =
  "I only caught part of that. Try recording again, or type the ingredients and steps.";
const LINK_NO_RECIPE =
  "Couldn't find a recipe in that link. Paste the description or caption text and I'll try from that.";

type ExtractRoute = "transcript" | "url";

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

  let transcript = "";
  let url = "";
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

  let slotId: string | null = null;

  async function takeQuotaSlot(): Promise<Response | null> {
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
      return json(
        { error: "Daily recipe extraction limit reached.", code: "quota_exceeded" },
        402,
      );
    }

    if (typeof reservedSlotId !== "string" || !reservedSlotId) {
      return json({ error: "Could not record extraction." }, 500);
    }
    slotId = reservedSlotId;
    return null;
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
    if (response.status === 422 && slotId !== null) {
      // The page had no usable recipe: same as a failed fetch, no slot used.
      await admin.from("recipe_extraction_events").delete().eq("id", slotId);
    }
    return response;
  }

  const slot = await takeQuotaSlot();
  if (slot) return slot;

  const userText = `Transcript:\n\n${transcript}\n\nReturn the structured recipe as JSON.`;
  return await extractWithModel(apiKey, userText, systemPrompt, "transcript");
});

async function extractWithModel(
  apiKey: string,
  userText: string,
  system: string,
  route: ExtractRoute,
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
    return json({ error: "Recipe extraction provider failed.", source: route }, 502);
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
    return json({ error: "Recipe extraction returned no content.", source: route }, 502);
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
          error: route === "transcript" ? TRANSCRIPT_NO_RECIPE : LINK_NO_RECIPE,
          code: "no_recipe_text",
          source: route,
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
      return json({ error: "Recipe extraction returned invalid JSON.", source: route }, 502);
    case "recipe":
      logModelCall({
        status: anthropicResponse.status,
        stopReason,
        model,
        inputLength: userText.length,
        outcome: "recipe",
        noRecipeReason: null,
      });
      return json({ recipe: classified.recipe, raw_json: JSON.stringify(classified.recipe) });
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
ingredient is the English shopping term so it can go on a list (haldi -> turmeric, pyaaz -> onion, zeera/jeera -> cumin, lehsun -> garlic, adrak -> ginger, tamatar -> tomato, dhaniya -> cilantro/coriander, chawal -> rice, doodh -> milk, cheeni -> sugar, elaichi -> cardamom, namak -> salt, laal mirch -> red chili, gobi -> cauliflower, aloo -> potato, dahi -> yogurt). original_phrase still keeps the original word.

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
ingredient is the English shopping term so it can go on a list (haldi -> turmeric, pyaaz -> onion, zeera/jeera -> cumin, lehsun -> garlic, adrak -> ginger, tamatar -> tomato, dhaniya -> cilantro/coriander, chawal -> rice, doodh -> milk, cheeni -> sugar, elaichi -> cardamom, namak -> salt, laal mirch -> red chili, gobi -> cauliflower, aloo -> potato, dahi -> yogurt). original_phrase still keeps the original word.
If a channel or author is given, use it as attribution. Otherwise attribution is null.
If the source lists several recipes, return only the single main recipe (the first complete one with ingredients). If the source has no recipe with ingredients, return exactly {"error":"no_recipe"}.

Return ONLY valid JSON matching this schema, no prose, no markdown fences:
{"title":"string - recipe name","attribution":"string|null","ingredients":[{"ingredient":"string - English grocery-list term","original_phrase":"string - source's exact words","amount":"number|null - ONLY if a real quantity was written, else null","unit":"string|null","vague":"boolean - true if measurement was approximate"}],"steps":["string - step from the source, no invented precision"],"notes":"string|null"}
`;
