# Edge Functions & Account Deletion — specs + code

Two server-side pieces are required for a clean launch:

1. **`extract-recipe`** — proxies Anthropic so the secret key leaves the client (fixes AI-01),
   and meters usage per user (fixes MON-01 / AI-02).
2. **`delete-account`** — deletes the auth user server-side (fixes AUTH-001 / 5.1.1(v)); the
   client-held anon key cannot do this, so it must be a service-role Edge Function.

Both validate the caller's Supabase JWT. Set secrets once:

```bash
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...   # the NEW key, after revoking the leaked one
# SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected into Edge Functions automatically.
```

---

## 1. `supabase/functions/extract-recipe/index.ts`

```ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Keep this identical to the current on-device system prompt (RecipeExtractionService.swift:130).
const SYSTEM_PROMPT = `You convert a spoken, phone-call recipe into a structured recipe. ...`;

const FREE_MONTHLY_QUOTA = 5; // free tier; Pro = unlimited (checked via RevenueCat entitlement or a flag)

serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace("Bearer ", "");
  if (!jwt) return json({ error: "unauthorized" }, 401);

  // Validate the user's JWT.
  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);
  const { data: userData, error: userErr } = await supabase.auth.getUser(jwt);
  if (userErr || !userData.user) return json({ error: "unauthorized" }, 401);
  const userId = userData.user.id;

  // Server-side metering: count this user's extractions this calendar month.
  // Table: recipe_usage(user_id uuid, created_at timestamptz default now()), RLS owner read.
  const monthStart = new Date(); monthStart.setUTCDate(1); monthStart.setUTCHours(0,0,0,0);
  const { count } = await supabase
    .from("recipe_usage")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("created_at", monthStart.toISOString());

  const isPro = await callerIsPro(userId); // implement via RevenueCat REST or a synced entitlement flag
  if (!isPro && (count ?? 0) >= FREE_MONTHLY_QUOTA) {
    return json({ error: "quota_exceeded", remaining: 0 }, 402);
  }

  const { transcript } = await req.json();
  if (!transcript || typeof transcript !== "string") return json({ error: "bad_request" }, 400);

  const anthropicResp = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: "claude-sonnet-4-6",
      max_tokens: 2000,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: `Transcript:\n\n${transcript}\n\nReturn the structured recipe as JSON.` }],
    }),
  });

  if (!anthropicResp.ok) return json({ error: "upstream" }, 502);
  const data = await anthropicResp.json();
  const text = data.content?.find((b: any) => b.type === "text")?.text ?? "";

  await supabase.from("recipe_usage").insert({ user_id: userId });

  // Return the model's JSON text; the client decodes it exactly as it does today.
  return json({ recipe: text, remaining: isPro ? null : FREE_MONTHLY_QUOTA - (count ?? 0) - 1 }, 200);
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}
async function callerIsPro(_userId: string): Promise<boolean> { return false; /* TODO */ }
```

Deploy: `supabase functions deploy extract-recipe`.

### Client change (`RecipeExtractionService.swift`)
- Delete `Config.anthropicAPIKey`.
- Point `endpoint` at `"\(Config.supabaseURL)/functions/v1/extract-recipe"`.
- Add `Authorization: Bearer <access token>` from `supabase.auth.session.accessToken`.
- Body becomes `{ "transcript": text }`; response field `recipe` is the same JSON string you
  already strip fences from and decode. Surface `quota_exceeded` (402) by showing the paywall.

---

## 2. `supabase/functions/delete-account/index.ts`

```ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
  if (!jwt) return new Response("unauthorized", { status: 401 });

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
  const { data, error } = await admin.auth.getUser(jwt);
  if (error || !data.user) return new Response("unauthorized", { status: 401 });

  // ON DELETE CASCADE on every table's user_id FK (001_initial_schema.sql) removes all rows.
  const { error: delErr } = await admin.auth.admin.deleteUser(data.user.id);
  if (delErr) return new Response(JSON.stringify({ error: delErr.message }), { status: 500 });

  return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "content-type": "application/json" } });
});
```

Deploy: `supabase functions deploy delete-account`.

### Client change — `AuthService.swift`
```swift
func deleteAccount() async {
    isLoading = true; errorMessage = nil
    do {
        guard let token = try? await supabase.auth.session.accessToken else {
            throw URLError(.userAuthenticationRequired)
        }
        var req = URLRequest(url: URL(string: "\(Config.supabaseURL)/functions/v1/delete-account")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        try? await supabase.auth.signOut()   // ends the session locally
        // Caller must ALSO wipe the local SwiftData store (see AUTH-002 fix) and Purchases.logOut().
    } catch {
        errorMessage = "Couldn't delete your account. Please try again."
    }
    isLoading = false
}
```

### Client change — `SettingsView.swift` (Account card)
Add below "Sign out":
```swift
Button(role: .destructive) { showDeleteConfirm = true } label: {
    HStack {
        Image(systemName: "trash").foregroundStyle(Color.accentAnaar)
        Text("Delete account").foregroundStyle(Color.accentAnaar)
        Spacer()
    }.font(.system(size: 15))
}
.confirmationDialog(
    "Delete your account? This permanently removes your pantry, lists, and recipes. This can't be undone.",
    isPresented: $showDeleteConfirm, titleVisibility: .visible
) {
    Button("Delete Account", role: .destructive) {
        Task { await appEnv.auth.deleteAccount(); appEnv.clearLocalStore() }
    }
}
```

> `appEnv.clearLocalStore()` is the same helper needed for AUTH-002 (wipe local SwiftData on
> sign-out / account switch). Implement it once and use it in both places.

---

## Related migration (for delete-propagation + metering)
```sql
-- recipe_usage: server-side AI metering
create table if not exists recipe_usage (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now()
);
alter table recipe_usage enable row level security;
create policy "owner" on recipe_usage using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Optional: soft-delete tombstones for delete-propagation (DATA-02), one per syncable table
-- alter table items add column if not exists deleted_at timestamptz;
-- ...repeat for pantries, products, stores, shopping_lists, shopping_list_items
```
