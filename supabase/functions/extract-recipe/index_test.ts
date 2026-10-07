import { assertEquals } from "jsr:@std/assert@1";

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
}) {
  const calls: string[] = [];
  const logs: string[] = [];
  const originalFetch = globalThis.fetch;
  const originalLog = console.log;
  console.log = (...args: unknown[]) => {
    logs.push(args.map((arg) => typeof arg === "string" ? arg : JSON.stringify(arg)).join(" "));
  };
  const env = {
    SUPABASE_URL: "https://quota-test.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-role",
    ANTHROPIC_API_KEY: "synthetic-provider-key",
  };
  const saved = Object.fromEntries(Object.keys(env).map((key) => [key, Deno.env.get(key)]));
  for (const [key, value] of Object.entries(env)) Deno.env.set(key, value);
  globalThis.fetch = (async (input, init) => {
    const url = String(input);
    calls.push(url);
    if (url.endsWith("/auth/v1/user")) {
      assertEquals(new Headers(init?.headers).get("Authorization"), "Bearer synthetic-user-token");
      return options.authenticated === false
        ? Response.json({ message: "Invalid session" }, { status: 401 })
        : Response.json({ id: userId });
    }
    if (url.endsWith("/rest/v1/rpc/reserve_recipe_extraction")) {
      assertEquals(init?.method, "POST");
      assertEquals(JSON.parse(String(init?.body)), { p_user_id: userId });
      return Response.json(options.reservation ?? null, { status: options.rpcStatus ?? 200 });
    }
    if (url === "https://api.anthropic.com/v1/messages") {
      // A provider failure must occur only after a successful reservation.
      assertEquals(options.reservation, slotId);
      if (options.anthropic) {
        return Response.json(options.anthropic.payload ?? {}, { status: options.anthropic.status ?? 200 });
      }
      return new Response(null, { status: 503 });
    }
    throw new Error(`Unexpected request: ${url}`);
  }) as typeof fetch;
  try {
    const response = await handler(new Request("https://edge.example/extract-recipe", {
      method: "POST",
      headers: { Authorization: "Bearer synthetic-user-token", "Content-Type": "application/json" },
      // An attacker-supplied user_id must not affect the reservation identity.
      body: JSON.stringify(options.body ?? { transcript: "Cook daal", user_id: slotId }),
    }));
    return { status: response.status, body: await response.json(), calls, logs };
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
  const result = await exercise({ reservation: null });
  assertEquals(result.status, 402);
  assertEquals(result.body.code, "quota_exceeded");
  assertEquals(result.calls.length, 2);
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
