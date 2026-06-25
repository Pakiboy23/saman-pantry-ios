import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// In-app account deletion (App Store Guideline 5.1.1(v)). The iOS client cannot
// delete an auth user with the anon key, so this runs with the service-role key.
// Deleting the auth user cascades to every owned row via the ON DELETE CASCADE
// foreign keys in supabase/migrations/001_initial_schema.sql.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "Account deletion is not configured." }, 500);
  }

  const authHeader = request.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) {
    return json({ error: "Missing authorization." }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Validate the caller's token and resolve which user is being deleted.
  const { data: userData, error: userError } = await admin.auth.getUser(jwt);
  if (userError || !userData?.user) {
    return json({ error: "Invalid or expired session." }, 401);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(userData.user.id);
  if (deleteError) {
    return json({ error: "Could not delete account. Please try again." }, 500);
  }

  return json({ ok: true });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}
