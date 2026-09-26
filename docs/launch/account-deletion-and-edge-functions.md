# Edge Functions & Account Deletion

This June spec is obsolete. Do not copy the old `recipe_usage` / `callerIsPro` snippets into a new function.

Live source of truth:

- [`supabase/functions/extract-recipe/`](../../supabase/functions/extract-recipe/) — user JWT, 5 attempts / 24h via `recipe_extraction_events` (not `recipe_usage`). Client uses `Config.recipeExtractionEndpoint`.
- [`supabase/functions/delete-account/`](../../supabase/functions/delete-account/) — user JWT + service role. Client uses `Config.deleteAccountEndpoint`.
- [`supabase/functions/README.md`](../../supabase/functions/README.md) — secrets and deploy commands.
- [`supabase/migrations/004_recipe_extraction_events.sql`](../../supabase/migrations/004_recipe_extraction_events.sql) — quota table.

Owner still must apply `003`/`004` in prod and deploy both functions. Keep those blockers in `MEMORY.md` only.
