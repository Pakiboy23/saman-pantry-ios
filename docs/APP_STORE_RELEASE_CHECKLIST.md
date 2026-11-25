# App Store Release Checklist

## Before archive

- Confirm `Config.recipeExtractionEndpoint` points at the production Supabase Edge Function.
- Apply `011_billing_grandfathered_and_quota.sql` **before** deploying `extract-recipe`, or every extract 500s. Apply `012_recipe_book_url_opt_in.sql` or URL community-book opt-in is a no-op on the server. See `docs/billing-and-extract-quota.md`.
- Deploy `supabase/functions/extract-recipe` and set `ANTHROPIC_API_KEY` as a Supabase secret. Optional: `YOUTUBE_API_KEY` (YouTube Data API v3). Without it, YouTube links use the public watch page. Set `REVENUECAT_SECRET_API_KEY` or Pro subscribers stay on the free-tier meter.
- Family cookbooks: follow `docs/family-books-go-steps.md` (SQL pair already applied and `revenuecat-sync` #94 deployed; remaining: `revenuecat-webhook` #78, Associated Domains / AASA). Architecture: `docs/family-cookbooks.md`.
- Apply `supabase/migrations/007_recipe_shared_event.sql` or `recipe_shared` inserts are rejected by the events check constraint.
- Rotate/revoke any Anthropic key that was previously committed or shared.
- Confirm Supabase migrations in `supabase/migrations` have been applied to production.
- Verify RevenueCat app, offering, package, entitlement (`Saman Pro`), and product IDs against App Store Connect. Fixture prices in-repo are $7.99 / $59.99; live cards use the offering. After sign-in the SDK `logIn`s with the lowercased Supabase user id.
- Keep the hosted privacy page in step with `docs/launch/legal-and-privacy.md`. It was last updated 21 Nov 2026 (HeyCatch, family cookbooks, server transcription).
- Create and test a reviewer account with a known email/password.
- Run `ci_scripts/check_secrets.sh`.
- Run the recording test set and confirm every case passes: `deno run --allow-env --allow-read --allow-net scripts/recipe-eval.ts --manifest <private manifest>`. No build goes to review on a failing case.
- Run unit/UI tests on a macOS/Xcode environment.

## Archive and validation

```sh
xcodebuild archive \
  -project Saman.xcodeproj \
  -scheme Saman \
  -configuration Release \
  -archivePath build/Samaan.xcarchive
```

Then upload and validate using Xcode Organizer or `xcrun altool`/Transporter according to the team's preferred release process.

## App Review notes

- Provide reviewer credentials for the production Supabase project.
- First launch is a 3-page onboarding, then Home / Pantry / Lists / Recipes without an account. Sign-in is required only for Sync now, Extract Recipe, community-book opt-in, family cookbooks, and Delete account.
- Mention that camera access is used only for barcode scanning.
- Mention that recipe extraction sends a recording, a chosen audio file, a link, or pasted words to the server. Recordings go to ElevenLabs for transcription, then that text (or a link/page the server fetched) goes to Anthropic unless it is already a structured recipe. Audio is not stored on our server.
- Free extract is 5 lifetime for new accounts (grandfathered accounts keep 5/day). Samaan Pro is unlimited extracts and can start a family cookbook. Joining a family is free. Restore Purchases is on the free Settings surface and on the paywall.
