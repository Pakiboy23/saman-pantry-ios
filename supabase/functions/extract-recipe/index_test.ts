import { assert, assertEquals } from "jsr:@std/assert@1";

// Capture the actual entrypoint without starting a listening server.
let handler: (request: Request) => Promise<Response>;
const originalServe = Deno.serve;
Deno.serve = ((callback: typeof handler) => {
  handler = callback;
  return {};
}) as typeof Deno.serve;
try {
  await import("./index.ts");
} finally {
  Deno.serve = originalServe;
}

const userId = "00000000-0000-0000-0000-000000000001";
const slotId = "00000000-0000-0000-0000-000000000002";

async function exercise(options: {
  reservation?: unknown;
  rpcStatus?: number;
  authenticated?: boolean;
  body?: object;
  anthropic?: { status?: number; payload?: unknown };
  grandfathered?: boolean;
  revenueCatSecret?: string;
  revenueCatStatus?: number;
  revenueCatPayload?: unknown;
  request?: () => Request;
  env?: Record<string, string | undefined>;
  elevenlabs?: { status?: number; payload?: unknown; throws?: boolean; rawBody?: string };
}) {
  const calls: string[] = [];
  const logs: string[] = [];
  const deletes: string[] = [];
  const stt: { apiKey: string | null; form: FormData }[] = [];
  const originalFetch = globalThis.fetch;
  const originalLog = console.log;
  console.log = (...args: unknown[]) => {
    logs.push(args.map((arg) => typeof arg === "string" ? arg : JSON.stringify(arg)).join(" "));
  };
  const env: Record<string, string | undefined> = {
    SUPABASE_URL: "https://quota-test.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-role",
    ANTHROPIC_API_KEY: "synthetic-provider-key",
    REVENUECAT_SECRET_API_KEY: options.revenueCatSecret,
    ELEVENLABS_API_KEY: "synthetic-stt-key",
    elevenlabs_api_key: undefined,
    TRANSCRIBE_PROVIDER: undefined,
    ELEVENLABS_STT_MODEL: undefined,
    TRANSCRIBE_KEYTERMS: undefined,
    ...options.env,
  };
  const saved = Object.fromEntries(Object.keys(env).map((key) => [key, Deno.env.get(key)]));
  for (const [key, value] of Object.entries(env)) {
    if (value === undefined) Deno.env.delete(key);
    else Deno.env.set(key, value);
  }
  globalThis.fetch = (async (input, init) => {
    const url = String(input);
    calls.push(url);
    if (url.endsWith("/auth/v1/user")) {
      assertEquals(new Headers(init?.headers).get("Authorization"), "Bearer synthetic-user-token");
      return options.authenticated === false
        ? Response.json({ message: "Invalid session" }, { status: 401 })
        : Response.json({ id: userId });
    }
    if (url.includes("api.revenuecat.com/v1/subscribers/")) {
      return Response.json(
        options.revenueCatPayload ?? {},
        { status: options.revenueCatStatus ?? 500 },
      );
    }
    if (url.endsWith("/rest/v1/rpc/reserve_recipe_extraction")) {
      assertEquals(init?.method, "POST");
      assertEquals(JSON.parse(String(init?.body)), { p_user_id: userId });
      return Response.json(options.reservation ?? null, { status: options.rpcStatus ?? 200 });
    }
    if (url.includes("/rest/v1/recipe_extraction_events")) {
      assertEquals(init?.method, "DELETE");
      deletes.push((new URL(url).searchParams.get("id") ?? "").replace(/^eq\./, ""));
      return new Response(null, { status: 204 });
    }
    if (url === "https://api.elevenlabs.io/v1/speech-to-text") {
      // Paid call: only after a slot (or a verified Pro entitlement).
      if (!options.revenueCatSecret || options.revenueCatStatus !== 200) {
        assertEquals(options.reservation, slotId);
      }
      assertEquals(init?.method, "POST");
      assert(init?.body instanceof FormData);
      stt.push({ apiKey: new Headers(init?.headers).get("xi-api-key"), form: init.body });
      const reply = options.elevenlabs ?? {};
      if (reply.throws) throw new TypeError("network down");
      if (reply.rawBody !== undefined) {
        return new Response(reply.rawBody, { status: reply.status ?? 200 });
      }
      return Response.json(
        reply.payload ?? { text: "Synthetic recipe words long enough to extract.", language_code: "eng" },
        { status: reply.status ?? 200 },
      );
    }
    if (url.includes("/rest/v1/user_accounts")) {
      return Response.json([{ grandfathered: options.grandfathered ?? false }]);
    }
    if (url === "https://api.anthropic.com/v1/messages") {
      // Free-tier provider calls require a reserved slot. Pro skips reservation.
      if (!options.revenueCatSecret || options.revenueCatStatus !== 200) {
        assertEquals(options.reservation, slotId);
      }
      if (options.anthropic) {
        return Response.json(options.anthropic.payload ?? {}, { status: options.anthropic.status ?? 200 });
      }
      return new Response(null, { status: 503 });
    }
    throw new Error(`Unexpected request: ${url}`);
  }) as typeof fetch;
  try {
    const request = options.request?.() ?? new Request("https://edge.example/extract-recipe", {
      method: "POST",
      headers: { Authorization: "Bearer synthetic-user-token", "Content-Type": "application/json" },
      // An attacker-supplied user_id must not affect the reservation identity.
      body: JSON.stringify(options.body ?? { transcript: "Cook daal", user_id: slotId }),
    });
    const response = await handler(request);
    return { status: response.status, body: await response.json(), calls, logs, deletes, stt };
  } finally {
    console.log = originalLog;
    globalThis.fetch = originalFetch;
    for (const [key, value] of Object.entries(saved)) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
}

Deno.test("quota exhaustion returns the existing 402 contract without calling the provider", async () => {
  const result = await exercise({ reservation: null, grandfathered: false });
  assertEquals(result.status, 402);
  assertEquals(result.body.code, "quota_exceeded");
  assertEquals(result.body.grandfathered, false);
  assertEquals(result.calls.length, 3);
});

Deno.test("grandfathered quota exhaustion still returns 402 with grandfathered true", async () => {
  const result = await exercise({ reservation: null, grandfathered: true });
  assertEquals(result.status, 402);
  assertEquals(result.body.code, "quota_exceeded");
  assertEquals(result.body.grandfathered, true);
});

Deno.test("RevenueCat lookup failure returns 503 without reserving free quota", async () => {
  const result = await exercise({
    revenueCatSecret: "synthetic-rc-secret",
    revenueCatStatus: 500,
    reservation: slotId,
  });
  assertEquals(result.status, 503);
  assertEquals(result.body.code, "entitlement_unavailable");
  assertEquals(
    result.calls.some((url) => url.includes("/rest/v1/rpc/reserve_recipe_extraction")),
    false,
  );
});

Deno.test("active RevenueCat entitlement skips the free-tier reservation", async () => {
  const result = await exercise({
    revenueCatSecret: "synthetic-rc-secret",
    revenueCatStatus: 200,
    revenueCatPayload: {
      subscriber: {
        entitlements: {
          "Saman Pro": { expires_date: null },
        },
      },
    },
    reservation: slotId,
    anthropic: {
      status: 200,
      payload: {
        stop_reason: "end_turn",
        model: "claude-sonnet-4-6",
        content: [{
          type: "text",
          text: JSON.stringify({
            title: "Daal",
            attribution: null,
            ingredients: [{
              ingredient: "lentils",
              original_phrase: "daal",
              amount: null,
              unit: null,
              vague: true,
            }],
            steps: ["Boil"],
            notes: null,
          }),
        }],
      },
    },
  });
  assertEquals(result.status, 200);
  assertEquals(
    result.calls.some((url) => url.includes("/rest/v1/rpc/reserve_recipe_extraction")),
    false,
  );
});

Deno.test("RPC errors and malformed reservations fail closed", async () => {
  for (const options of [
    { rpcStatus: 500, reservation: { message: "database unavailable" } },
    { reservation: 42 },
    { reservation: "" },
  ]) {
    const result = await exercise(options);
    assertEquals(result.status, 500);
    assertEquals(result.calls.length, 2);
  }
});

Deno.test("valid reservation precedes the provider and provider failures keep the slot", async () => {
  const result = await exercise({ reservation: slotId });
  assertEquals(result.status, 502);
  assertEquals(result.calls.map((url) => new URL(url).pathname), [
    "/auth/v1/user", "/rest/v1/rpc/reserve_recipe_extraction", "/v1/messages",
  ]);
});

function modelLog(logs: string[]) {
  const line = logs.find((entry) => entry.includes("extract_recipe_model"));
  if (!line) throw new Error("missing extract_recipe_model log");
  return JSON.parse(line);
}

const recipeJSON = JSON.stringify({
  title: "Daal",
  attribution: null,
  ingredients: [{
    ingredient: "lentils",
    original_phrase: "daal",
    amount: 1,
    unit: "cup",
    vague: false,
  }],
  steps: ["Boil"],
  notes: null,
});

Deno.test("transcript no_recipe_text logs the model call and uses voice copy", async () => {
  const result = await exercise({
    reservation: slotId,
    body: { transcript: "But some of it crushed up really fine and some of it not" },
    anthropic: {
      payload: {
        stop_reason: "end_turn",
        model: "claude-sonnet-4-6",
        content: [{ type: "text", text: '{"error":"no_recipe"} sk-ant-secretvalue' }],
      },
    },
  });
  assertEquals(result.status, 422);
  assertEquals(result.body.code, "no_recipe_text");
  assertEquals(result.body.source, "transcript");
  assertEquals(
    result.body.error,
    "I only caught part of that. Try recording again, or type the ingredients and steps.",
  );
  const entry = modelLog(result.logs);
  assertEquals(entry.anthropic_status, 200);
  assertEquals(entry.stop_reason, "end_turn");
  assertEquals(entry.model, "claude-sonnet-4-6");
  assertEquals(entry.outcome, "no_recipe_text");
  assertEquals(entry.no_recipe_reason, "explicit_no_recipe");
  assertEquals(entry.input_length > 0, true);
  assertEquals("reply_excerpt" in entry, false);
  assertEquals(result.logs.join("\n").includes("sk-ant-secretvalue"), false);
  assertEquals(result.logs.join("\n").includes("But some of it"), false);
  assertEquals(result.logs.join("\n").includes("synthetic-provider-key"), false);
});

Deno.test("a recipe reply logs structural diagnostics without recipe text", async () => {
  const result = await exercise({
    reservation: slotId,
    anthropic: {
      payload: {
        stop_reason: "end_turn",
        model: "claude-sonnet-4-6",
        content: [{ type: "text", text: recipeJSON }],
      },
    },
  });
  assertEquals(result.status, 200);
  assertEquals(result.body.recipe.title, "Daal");
  const entry = modelLog(result.logs);
  assertEquals(entry.anthropic_status, 200);
  assertEquals(entry.stop_reason, "end_turn");
  assertEquals(entry.model, "claude-sonnet-4-6");
  assertEquals(entry.outcome, "recipe");
  assertEquals(entry.no_recipe_reason, null);
  assertEquals(entry.input_length > 0, true);
  assertEquals("reply_excerpt" in entry, false);
  assertEquals(result.logs.join("\n").includes("Daal"), false);
  assertEquals(result.logs.join("\n").includes("lentils"), false);
});

Deno.test("provider HTTP failures log the status without the API key", async () => {
  const result = await exercise({
    reservation: slotId,
    anthropic: { status: 529, payload: { error: { message: "overloaded" } } },
  });
  assertEquals(result.status, 502);
  const entry = modelLog(result.logs);
  assertEquals(entry.anthropic_status, 529);
  assertEquals(entry.outcome, "provider_error");
  assertEquals(entry.stop_reason, null);
  assertEquals("reply_excerpt" in entry, false);
  assertEquals(result.logs.join("\n").includes("overloaded"), false);
  assertEquals(result.logs.join("\n").includes("synthetic-provider-key"), false);
});

Deno.test("empty ingredients map to no_recipe_text with that reason", async () => {
  const result = await exercise({
    reservation: slotId,
    anthropic: {
      payload: {
        stop_reason: "end_turn",
        model: "claude-sonnet-4-6",
        content: [{ type: "text", text: '{"title":"Daal","ingredients":[]}' }],
      },
    },
  });
  assertEquals(result.status, 422);
  assertEquals(result.body.code, "no_recipe_text");
  assertEquals(modelLog(result.logs).no_recipe_reason, "empty_ingredients");
});

Deno.test("invalid sessions and empty inputs never reserve quota", async () => {
  const unauthorized = await exercise({ authenticated: false });
  assertEquals(unauthorized.status, 401);
  assertEquals(unauthorized.calls.length, 1);
  const empty = await exercise({ body: {} });
  assertEquals(empty.status, 400);
  assertEquals(empty.calls.length, 1);
});

// ---------------------------------------------------------------------------
// Audio route. Synthetic bytes only; no recordings or real transcripts.

const MAX_AUDIO_BYTES = 12 * 1024 * 1024;

function audioRequest(options: {
  size?: number;
  type?: string;
  name?: string;
  field?: string;
  extraFields?: Record<string, string>;
} = {}): () => Request {
  return () => {
    const form = new FormData();
    const bytes = new Uint8Array(options.size ?? 4096).fill(7);
    form.append(
      options.field ?? "audio",
      new File([bytes], options.name ?? "recipe.m4a", { type: options.type ?? "audio/mp4" }),
    );
    for (const [key, value] of Object.entries(options.extraFields ?? {})) form.append(key, value);
    return new Request("https://edge.example/extract-recipe", {
      method: "POST",
      headers: { Authorization: "Bearer synthetic-user-token" },
      body: form,
    });
  };
}

function rawAudioRequest(size: number, headers: Record<string, string> = {}): () => Request {
  return () =>
    new Request("https://edge.example/extract-recipe", {
      method: "POST",
      headers: {
        Authorization: "Bearer synthetic-user-token",
        "Content-Type": "multipart/form-data; boundary=synthetic",
        ...headers,
      },
      body: new Uint8Array(size),
    });
}

const okRecipeReply = {
  status: 200,
  payload: {
    stop_reason: "end_turn",
    model: "claude-sonnet-4-6",
    content: [{ type: "text", text: recipeJSON }],
  },
};

const pathOf = (url: string) => new URL(url).pathname;

Deno.test("audio: multipart builds the ElevenLabs call and returns the transcript", async () => {
  const result = await exercise({
    reservation: slotId,
    request: audioRequest({ type: "audio/x-m4a", name: "dinner.m4a" }),
    elevenlabs: { payload: { text: "  Synthetic okra recipe words for the extractor.  ", language_code: "eng" } },
    anthropic: okRecipeReply,
  });
  assertEquals(result.status, 200);
  assertEquals(result.body.recipe.title, "Daal");
  assertEquals(result.body.transcript, "Synthetic okra recipe words for the extractor.");
  assertEquals(typeof result.body.raw_json, "string");
  assertEquals(result.calls.map(pathOf), [
    "/auth/v1/user",
    "/rest/v1/rpc/reserve_recipe_extraction",
    "/v1/speech-to-text",
    "/v1/messages",
  ]);
  assertEquals(result.stt.length, 1);
  const { apiKey, form } = result.stt[0];
  assertEquals(apiKey, "synthetic-stt-key");
  assertEquals(form.get("model_id"), "scribe_v2");
  assertEquals(form.get("tag_audio_events"), "false");
  assertEquals(form.getAll("keyterms"), []);
  const file = form.get("file");
  assert(file instanceof File);
  assertEquals(file.name, "dinner.m4a");
  assertEquals(file.size, 4096);
  assertEquals(result.deletes, []);
});

Deno.test("audio: model and provider settings come from the server env", async () => {
  const result = await exercise({
    reservation: slotId,
    request: audioRequest(),
    env: { ELEVENLABS_STT_MODEL: "scribe_v3", TRANSCRIBE_KEYTERMS: "true" },
    anthropic: okRecipeReply,
  });
  assertEquals(result.status, 200);
  const { form } = result.stt[0];
  assertEquals(form.get("model_id"), "scribe_v3");
  const keyterms = form.getAll("keyterms");
  assert(keyterms.includes("zeera"));
  assert(keyterms.includes("laal mirch"));
  for (const term of keyterms) assert(String(term).split(/\s+/).length <= 5);
});

Deno.test("audio: oversized body returns 413 with no slot and no provider call", async () => {
  for (const request of [
    // Streamed past the cap, no Content-Length.
    rawAudioRequest(MAX_AUDIO_BYTES + 1),
    // Declared too large up front.
    rawAudioRequest(16, { "Content-Length": String(MAX_AUDIO_BYTES + 1) }),
    // A real multipart body whose file alone is over the cap.
    audioRequest({ size: MAX_AUDIO_BYTES + 1 }),
  ]) {
    const result = await exercise({ reservation: slotId, request });
    assertEquals(result.status, 413);
    assertEquals(result.body.code, "audio_too_large");
    assertEquals(result.calls.map(pathOf), ["/auth/v1/user"]);
  }
});

Deno.test("audio: unsupported type, missing part, and empty file are rejected before quota", async () => {
  const unsupported = await exercise({ reservation: slotId, request: audioRequest({ type: "video/mp4" }) });
  assertEquals(unsupported.status, 415);
  assertEquals(unsupported.body.code, "audio_unsupported_type");
  assertEquals(unsupported.calls.map(pathOf), ["/auth/v1/user"]);

  const wrongField = await exercise({ reservation: slotId, request: audioRequest({ field: "file" }) });
  assertEquals(wrongField.status, 400);
  assertEquals(wrongField.body.code, "audio_missing");
  assertEquals(wrongField.calls.map(pathOf), ["/auth/v1/user"]);

  const empty = await exercise({ reservation: slotId, request: audioRequest({ size: 0 }) });
  assertEquals(empty.status, 400);
  assertEquals(empty.calls.map(pathOf), ["/auth/v1/user"]);

  const garbled = await exercise({ reservation: slotId, request: rawAudioRequest(64) });
  assertEquals(garbled.status, 400);
  assertEquals(garbled.calls.map(pathOf), ["/auth/v1/user"]);
});

Deno.test("audio: every accepted type reaches the provider, including parameters", async () => {
  for (const type of ["audio/mp4", "audio/m4a", "audio/x-m4a", "audio/aac", "audio/mpeg", "audio/wav", "audio/mp4; codecs=mp4a.40.2"]) {
    const result = await exercise({ reservation: slotId, request: audioRequest({ type }), anthropic: okRecipeReply });
    assertEquals(result.status, 200, type);
  }
});

Deno.test("audio: no slot means no transcription call", async () => {
  const result = await exercise({ reservation: null, request: audioRequest() });
  assertEquals(result.status, 402);
  assertEquals(result.body.code, "quota_exceeded");
  assertEquals(result.stt.length, 0);
  assertEquals(result.calls.some((url) => url.includes("elevenlabs")), false);
});

Deno.test("audio: RevenueCat outage returns 503 before any provider call", async () => {
  const result = await exercise({
    revenueCatSecret: "synthetic-rc-secret",
    revenueCatStatus: 500,
    reservation: slotId,
    request: audioRequest(),
  });
  assertEquals(result.status, 503);
  assertEquals(result.body.code, "entitlement_unavailable");
  assertEquals(result.stt.length, 0);
});

Deno.test("audio: provider failures release the slot and return transcription_failed", async () => {
  for (const elevenlabs of [
    { status: 500, payload: { detail: "boom" } },
    { status: 401, payload: { detail: "bad key" } },
    { throws: true },
    { rawBody: "not json" },
    { payload: { language_code: "eng" } },
  ]) {
    const result = await exercise({ reservation: slotId, request: audioRequest(), elevenlabs });
    assertEquals(result.status, 502);
    assertEquals(result.body.code, "transcription_failed");
    assertEquals(result.deletes, [slotId]);
    assertEquals(result.calls.some((url) => url.includes("anthropic")), false);
  }
});

Deno.test("audio: empty or too-short transcript releases the slot with audio_no_speech", async () => {
  for (const text of ["", "   ", "uh hello"]) {
    const result = await exercise({
      reservation: slotId,
      request: audioRequest(),
      elevenlabs: { payload: { text } },
    });
    assertEquals(result.status, 422);
    assertEquals(result.body.code, "audio_no_speech");
    assertEquals(
      result.body.error,
      "I only caught part of that. Try recording again, or type the ingredients and steps.",
    );
    assertEquals(result.deletes, [slotId]);
    assertEquals(result.calls.some((url) => url.includes("anthropic")), false);
  }
});

Deno.test("audio: model failures after transcription keep the slot (text rule)", async () => {
  const providerDown = await exercise({ reservation: slotId, request: audioRequest() });
  assertEquals(providerDown.status, 502);
  assertEquals(providerDown.body.source, "audio");
  assertEquals(providerDown.deletes, []);

  const noRecipe = await exercise({
    reservation: slotId,
    request: audioRequest(),
    anthropic: {
      payload: { stop_reason: "end_turn", content: [{ type: "text", text: '{"error":"no_recipe"}' }] },
    },
  });
  assertEquals(noRecipe.status, 422);
  assertEquals(noRecipe.body.code, "no_recipe_text");
  assertEquals(noRecipe.body.source, "audio");
  assertEquals(
    noRecipe.body.error,
    "I only caught part of that. Try recording again, or type the ingredients and steps.",
  );
  // The slot is spent, so the client gets the text back to edit and retry.
  assertEquals(noRecipe.body.transcript, "Synthetic recipe words long enough to extract.");
  assertEquals(noRecipe.deletes, []);
});

Deno.test("audio: Pro skips the meter and has nothing to release", async () => {
  const pro = {
    revenueCatSecret: "synthetic-rc-secret",
    revenueCatStatus: 200,
    revenueCatPayload: { subscriber: { entitlements: { "Saman Pro": { expires_date: null } } } },
    reservation: slotId,
  };
  const ok = await exercise({ ...pro, request: audioRequest(), anthropic: okRecipeReply });
  assertEquals(ok.status, 200);
  assertEquals(ok.calls.some((url) => url.includes("reserve_recipe_extraction")), false);

  const failed = await exercise({ ...pro, request: audioRequest(), elevenlabs: { status: 500 } });
  assertEquals(failed.status, 502);
  assertEquals(failed.deletes, []);
});

Deno.test("audio: lowercase secret name works as a fallback", async () => {
  const result = await exercise({
    reservation: slotId,
    request: audioRequest(),
    env: { ELEVENLABS_API_KEY: undefined, elevenlabs_api_key: "synthetic-lowercase-key" },
    anthropic: okRecipeReply,
  });
  assertEquals(result.status, 200);
  assertEquals(result.stt[0].apiKey, "synthetic-lowercase-key");
});

Deno.test("audio: missing key or unknown provider is the existing not-configured 500", async () => {
  for (const env of [
    { ELEVENLABS_API_KEY: undefined, elevenlabs_api_key: undefined },
    { TRANSCRIBE_PROVIDER: "whisper" },
  ]) {
    const result = await exercise({ reservation: slotId, request: audioRequest(), env });
    assertEquals(result.status, 500);
    assertEquals(result.body.error, "Recipe extraction is not configured.");
    assertEquals(result.calls.map(pathOf), ["/auth/v1/user"]);
  }
});

Deno.test("audio: logs carry sizes and timings, never transcript text or keys", async () => {
  const secretWords = "Synthetic private chatter about the neighbours after the recipe.";
  const result = await exercise({
    reservation: slotId,
    request: audioRequest(),
    elevenlabs: { payload: { text: secretWords, language_code: "eng" } },
    anthropic: okRecipeReply,
  });
  assertEquals(result.status, 200);
  const line = result.logs.find((entry) => entry.includes("extract_recipe_transcription"));
  assert(line);
  const entry = JSON.parse(line);
  assertEquals(entry.provider, "elevenlabs");
  assertEquals(entry.model, "scribe_v2");
  assertEquals(entry.audio_bytes, 4096);
  assertEquals(entry.audio_type, "audio/mp4");
  assertEquals(entry.transcript_length, secretWords.length);
  assertEquals(entry.outcome, "ok");
  assertEquals(typeof entry.duration_ms, "number");
  const all = result.logs.join("\n");
  assertEquals(all.includes("neighbours"), false);
  assertEquals(all.includes("synthetic-stt-key"), false);
});

Deno.test("audio: unauthenticated multipart never reads the body or reserves quota", async () => {
  const result = await exercise({ authenticated: false, request: audioRequest() });
  assertEquals(result.status, 401);
  assertEquals(result.calls.length, 1);
});

Deno.test("JSON transcript route is unchanged and returns no transcript field", async () => {
  const result = await exercise({ reservation: slotId, anthropic: okRecipeReply });
  assertEquals(result.status, 200);
  assertEquals(Object.keys(result.body).sort(), ["raw_json", "recipe"]);
  assertEquals(result.calls.map(pathOf), [
    "/auth/v1/user", "/rest/v1/rpc/reserve_recipe_extraction", "/v1/messages",
  ]);
  assertEquals(result.deletes, []);
});
