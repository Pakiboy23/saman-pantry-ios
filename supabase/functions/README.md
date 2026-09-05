# Supabase Edge Functions

## `extract-recipe`

The iOS app calls `https://<project-ref>.supabase.co/functions/v1/extract-recipe` instead of calling Anthropic directly. This keeps private AI provider credentials out of the app binary.

The caller must send the **user JWT** (`Authorization: Bearer <access_token>`). The anon key as Bearer is rejected. After 5 attempts in a rolling 24h the function returns **402** `{ code: "quota_exceeded" }`. The client opens the paywall for free users.

Requires `supabase/migrations/004_recipe_extraction_events.sql` applied in prod before this deploy, or every extract 500s.

### Required Supabase secrets

```sh
supabase secrets set ANTHROPIC_API_KEY=<rotated-production-key>
# Optional override; defaults to claude-sonnet-4-6
supabase secrets set ANTHROPIC_MODEL=claude-sonnet-4-6
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically.

### Deploy

```sh
supabase functions deploy extract-recipe
```

After deployment, revoke/rotate any Anthropic key that was previously committed or shipped in a client binary.

## `delete-account`

In-app account deletion, required by App Store Guideline 5.1.1(v). The iOS app
calls `https://<project-ref>.supabase.co/functions/v1/delete-account` with the
signed-in user's JWT. The function validates the token and deletes the auth user
with the service-role key; `ON DELETE CASCADE` foreign keys remove all owned rows.

### Required secrets

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected into Edge Functions
automatically — no manual secret setup is needed.

### Deploy

```sh
supabase functions deploy delete-account
```

Verify that every table's `user_id` foreign key is declared `on delete cascade`
(see `supabase/migrations/001_initial_schema.sql`) so deletion fully removes user data.
