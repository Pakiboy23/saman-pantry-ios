import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Recipe extraction is proxied so the Anthropic key never ships in the iOS
// binary. The caller must be a signed-in user: the anon key as Bearer is a
// valid JWT but getUser rejects it, which is what closed the open proxy.
// Quota is 5 successful-or-attempted extractions per rolling 24h, counted in
// recipe_extraction_events (service role only; see 004_recipe_extraction_events.sql).

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const anthropicEndpoint = "https://api.anthropic.com/v1/messages";
const anthropicModel = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-4-6";
const DAILY_LIMIT = 5;

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
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count, error: countError } = await admin
    .from("recipe_extraction_events")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("created_at", since);

  if (countError) {
    console.error("quota count failed:", countError.message);
    return json({ error: "Could not check extraction quota." }, 500);
  }

  if ((count ?? 0) >= DAILY_LIMIT) {
    return json(
      { error: "Daily recipe extraction limit reached.", code: "quota_exceeded" },
      402,
    );
  }

  let transcript = "";
  try {
    const body = await request.json();
    transcript = String(body.transcript ?? "").trim();
  } catch {
    return json({ error: "Request body must be JSON." }, 400);
  }

  if (!transcript) {
    return json({ error: "Transcript is required." }, 400);
  }

  // Consume the slot before calling Anthropic so parallel retries cannot
  // burst past the daily cap. A provider failure still counts.
  const { error: insertError } = await admin
    .from("recipe_extraction_events")
    .insert({ user_id: userId });
  if (insertError) {
    console.error("quota insert failed:", insertError.message);
    return json({ error: "Could not record extraction." }, 500);
  }

  const anthropicResponse = await fetch(anthropicEndpoint, {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: anthropicModel,
      max_tokens: 2000,
      system: systemPrompt,
      messages: [{ role: "user", content: `Transcript:\n\n${transcript}\n\nReturn the structured recipe as JSON.` }],
    }),
  });

  if (!anthropicResponse.ok) {
    return json({ error: "Recipe extraction provider failed." }, 502);
  }

  const providerPayload = await anthropicResponse.json();
  const rawText = providerPayload.content?.find((block: { type?: string; text?: string }) => block.type === "text")?.text;
  if (!rawText) {
    return json({ error: "Recipe extraction returned no content." }, 502);
  }

  const rawJson = rawText.replaceAll("```json", "").replaceAll("```", "").trim();

  try {
    const recipe = JSON.parse(rawJson);
    return json({ recipe, raw_json: rawJson });
  } catch {
    return json({ error: "Recipe extraction returned invalid JSON." }, 502);
  }
});

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
