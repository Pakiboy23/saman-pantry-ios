# Saman App Store Connect Readiness Assessment

Assessment date: 2026-06-21

## Overall verdict

**Closer, but still not fully ready for App Store Connect submission.** Repository-side blockers that could be fixed without external credentials have been addressed: the private Anthropic key was removed from the iOS client, recipe extraction now targets a Supabase Edge Function, deployment targets were normalized, a StoreKit test artifact was added, smoke tests were expanded, release/privacy docs were added, logging was hardened, CI was scaffolded, and a secret-check script was added. Final submission readiness still depends on owner-controlled actions: rotating the exposed Anthropic key, deploying/configuring Supabase, verifying RevenueCat/App Store Connect IAPs, and running archive/validation in Xcode.

## What appears ready

- **App target metadata exists:** bundle identifier `com.samanpantry.Saman`, marketing version `1.0`, build number `1`, automatic signing, development team, app icon asset name, and iPhone/iPad device families are configured in the Xcode project.
- **Privacy usage string exists:** the generated Info.plist values include `NSCameraUsageDescription` for barcode scanning.
- **Export compliance baseline exists:** `ITSAppUsesNonExemptEncryption = NO` is configured.
- **App icon assets exist:** the asset catalog includes an AppIcon app icon set with 1024px icon variants.
- **RevenueCat dependencies are linked:** `RevenueCat` and `RevenueCatUI` are present through Swift Package Manager.
- **Supabase schema includes RLS:** the checked-in migrations enable row-level security and owner policies for the primary synced tables.
- **Basic authentication flow exists:** Supabase email/password sign-in, sign-up, confirmation resend, and sign-out paths are implemented.
- **Client-side AI secret exposure has been remediated in source:** the app now calls `Config.recipeExtractionEndpoint`, which points to a Supabase Edge Function, rather than calling Anthropic directly.
- **Deployment targets are normalized in the checked-in project:** iOS targets now use `IPHONEOS_DEPLOYMENT_TARGET = 17.0`.

## Completed repo-side remediation

- Removed the hard-coded Anthropic private key from `Config.swift` and replaced it with `recipeExtractionEndpoint`.
- Reworked `RecipeExtractionService` to call the Supabase Edge Function endpoint with Supabase anon authentication headers.
- Added `supabase/functions/extract-recipe`, which reads `ANTHROPIC_API_KEY` from Supabase secrets and calls Anthropic server-side.
- Added `supabase/functions/README.md` with deployment and secret setup instructions.
- Added `ci_scripts/check_secrets.sh` and a GitHub Actions workflow with static checks plus a macOS `xcodebuild test` job for real CI environments.
- Normalized deployment targets to iOS 17.0, macOS 14.0, and visionOS 1.0 build settings.
- Added `Saman/Saman.storekit` as a local StoreKit test artifact for a provisional Saman Pro monthly subscription.
- Replaced ad hoc release logging calls with `AppLogger` using `OSLog`.
- Replaced placeholder unit tests with smoke tests for config safety and preview SwiftData model creation.
- Added `docs/APP_STORE_RELEASE_CHECKLIST.md` and `docs/PRIVACY_DISCLOSURE_WORKSHEET.md`.

## Remaining submission blockers requiring owner intervention

1. **Rotate/revoke the previously exposed Anthropic key.** The key is no longer in the current source, but it was previously committed/shared and must be revoked in Anthropic or the provider account.
2. **Deploy and configure the Supabase Edge Function.** `ANTHROPIC_API_KEY` must be set as a Supabase secret and `extract-recipe` must be deployed to the production Supabase project.
3. **Verify RevenueCat/App Store Connect IAP setup.** The app still checks entitlement `Saman Pro`; confirm this exactly matches RevenueCat, offerings, packages, and App Store Connect product IDs or update the code/config accordingly.
4. **Run a clean Xcode build/test/archive/upload validation.** This container does not include Xcode, so archive/export/App Store validation must run on macOS with Xcode and signing access.
5. **Create reviewer credentials and finalize privacy disclosures.** Production Supabase access, legal/privacy approval, App Store Connect account access, and a working reviewer account are still required.

## High-priority review risks

- **Privacy disclosures must match behavior.** The app uses Supabase auth/database, RevenueCat, product barcode lookup, and server-side AI recipe extraction. App Privacy answers should cover account identifiers, user content such as recipes/items, purchases, diagnostics if collected by SDKs, and third-party data processing.
- **Account requirement/reviewer access:** the app gates the main tab shell behind Supabase authentication. App Review should receive a working demo account, or the app should offer a review-friendly path if sign-up requires email confirmation.
- **Network/service availability:** readiness depends on the live Supabase project having migrations and Edge Functions applied exactly as expected.
- **Scanner permission flow:** camera usage text exists, but reviewer/device behavior should be verified on a physical device.

## Recommended pre-submission checklist

### Owner must complete before upload

- Rotate/revoke the exposed Anthropic key.
- Deploy `supabase/functions/extract-recipe` and set `ANTHROPIC_API_KEY` as a Supabase secret.
- Confirm Supabase production RLS policies and migrations are applied to the live project.
- Verify RevenueCat app, offering, package, product IDs, entitlement ID, and App Store Connect IAP status.
- Create a real reviewer test account and document review credentials in App Store Connect.
- Run a clean Release archive on macOS with Xcode and resolve any compiler/signing/archive issues.

### Should complete before review

- Validate physical-device scanner behavior and screenshots.
- Confirm App Privacy answers using `docs/PRIVACY_DISCLOSURE_WORKSHEET.md`.
- Validate support URL, privacy policy URL, age rating, screenshots, subtitle, keywords, and marketing copy.
- Decide whether `Saman Pro` should remain the RevenueCat entitlement identifier or be changed to a slug-like ID.

## Completion ownership and what can be done from this repository

### Completed in this repo/environment

- Removed the hard-coded Anthropic secret from the iOS client.
- Added repository-side guardrails for private API keys.
- Lowered/normalized deployment settings in the Xcode project.
- Added meaningful smoke tests to replace placeholder-only tests.
- Added StoreKit test artifacts.
- Improved release documentation.
- Replaced ad hoc `print` diagnostics with a release-safe logging wrapper.
- Added CI configuration.

### Partially completed, paused on owner-provided values or service access

- **Supabase Edge Function deployment.** Function code and instructions are present, but deploying it requires Supabase project access and setting the Anthropic API key as a server-side secret.
- **Supabase production verification.** Checked-in migrations and app expectations can be audited, but confirming the live database requires access to the Supabase project or a schema dump.
- **RevenueCat/IAP mapping.** Local StoreKit and documentation were added, but confirming offerings, packages, entitlements, and App Store Connect product states requires RevenueCat and App Store Connect access.
- **Privacy policy and App Privacy answers.** A worksheet was drafted, but the legal/policy owner must approve the final policy and App Store Connect disclosures.
- **Reviewer demo account instructions.** Release checklist guidance was added, but creating/confirming the account requires access to the production auth project and email inbox.

### Cannot complete in this container

- **Run `xcodebuild`, archive, export, or App Store validation.** This environment does not have Xcode command-line tooling installed.
- **Take physical-device scanner screenshots or validate camera behavior.** That requires a real iOS device or a macOS/Xcode simulator workflow with the project buildable.
- **Rotate/revoke exposed third-party secrets.** This requires access to the Anthropic dashboard or wherever the key is managed.
- **Submit or validate the binary in App Store Connect.** That requires Apple Developer/App Store Connect access and a macOS signing/archive environment.
