const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const anthropicEndpoint = "https://api.anthropic.com/v1/messages";
const anthropicModel = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-4-6";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    return json({ error: "Recipe extraction is not configured." }, 500);
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
