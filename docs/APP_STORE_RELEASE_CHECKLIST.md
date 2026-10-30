# App Store Release Checklist

## Before archive

- Confirm `Config.recipeExtractionEndpoint` points at the production Supabase Edge Function.
- Apply `011_billing_grandfathered_and_quota.sql` **before** deploying `extract-recipe`, or every extract 500s. Apply `012_recipe_book_url_opt_in.sql` or URL community-book opt-in is a no-op on the server. See `docs/billing-and-extract-quota.md`.
- Deploy `supabase/functions/extract-recipe` and set `ANTHROPIC_API_KEY` as a Supabase secret. Optional: `YOUTUBE_API_KEY` (YouTube Data API v3). Without it, YouTube links use the public watch page. Set `REVENUECAT_SECRET_API_KEY` or Pro subscribers stay on the free-tier meter.
- Family cookbooks: follow `docs/family-books-go-steps.md` (SQL pair, `revenuecat-webhook`, `revenuecat-sync` + `REVENUECAT_SECRET_KEY`, Associated Domains / AASA). Architecture: `docs/family-cookbooks.md`.
- Apply `supabase/migrations/007_recipe_shared_event.sql` or `recipe_shared` inserts are rejected by the events check constraint.
- Rotate/revoke any Anthropic key that was previously committed or shared.
- Confirm Supabase migrations in `supabase/migrations` have been applied to production.
- Verify RevenueCat app, offering, package, entitlement (`Saman Pro`), and product IDs against App Store Connect. Fixture prices in-repo are $7.99 / $59.99; live cards use the offering. After sign-in the SDK `logIn`s with the lowercased Supabase user id.
- Update the hosted privacy page from `docs/launch/legal-and-privacy.md` (HeyCatch + family cookbooks) before submitting a 1.6 build.
- Create and test a reviewer account with a known email/password.
- Run `ci_scripts/check_secrets.sh`.
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
- Mention that recipe extraction sends a user-provided transcript or link to the server-side extraction service. The server may fetch that public page (or a YouTube title, description, and captions) and send the text to Anthropic when it is not already a schema.org Recipe.
- Free extract is 5 lifetime for new accounts (grandfathered accounts keep 5/day). Samaan Pro is unlimited extracts and can start a family cookbook. Joining a family is free. Restore Purchases is on the free Settings surface and on the paywall.
