# App Store Release Checklist

## Before archive

- Confirm `Config.recipeExtractionEndpoint` points at the production Supabase Edge Function.
- Deploy `supabase/functions/extract-recipe` and set `ANTHROPIC_API_KEY` as a Supabase secret.
- Rotate/revoke any Anthropic key that was previously committed or shared.
- Confirm Supabase migrations in `supabase/migrations` have been applied to production.
- Verify RevenueCat app, offering, package, entitlement, and product IDs against App Store Connect.
- Create and test a reviewer account with a known email/password.
- Run `ci_scripts/check_secrets.sh`.
- Run unit/UI tests on a macOS/Xcode environment.

## Archive and validation

```sh
xcodebuild archive \
  -project Saman.xcodeproj \
  -scheme Saman \
  -configuration Release \
  -archivePath build/Saman.xcarchive
```

Then upload and validate using Xcode Organizer or `xcrun altool`/Transporter according to the team's preferred release process.

## App Review notes

- Provide reviewer credentials for the production Supabase project.
- Mention that camera access is used only for barcode scanning.
- Mention that recipe extraction sends user-provided recipe transcripts to the server-side extraction service.
- If IAP is present, provide steps to reach the paywall and test restore purchases.
