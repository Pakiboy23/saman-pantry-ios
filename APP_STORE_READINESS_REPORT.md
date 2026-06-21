# Saman App Store Connect Readiness Assessment

Assessment date: 2026-06-21

## Overall verdict

**Not ready for App Store Connect submission yet.** The repository contains a coherent SwiftUI app with authentication, local persistence, Supabase-backed sync, barcode scanning, recipes, shopping lists, RevenueCat paywall integration, app icons, camera privacy text, and encryption export metadata. However, it has several submission blockers and material risks that should be resolved before uploading a build for review.

## What appears ready

- **App target metadata exists:** bundle identifier `com.samanpantry.Saman`, marketing version `1.0`, build number `1`, automatic signing, development team, app icon asset name, and iPhone/iPad device families are configured in the Xcode project.
- **Privacy usage string exists:** the generated Info.plist values include `NSCameraUsageDescription` for barcode scanning.
- **Export compliance baseline exists:** `ITSAppUsesNonExemptEncryption = NO` is configured.
- **App icon assets exist:** the asset catalog includes an AppIcon app icon set with 1024px icon variants.
- **RevenueCat dependencies are linked:** `RevenueCat` and `RevenueCatUI` are present through Swift Package Manager.
- **Supabase schema includes RLS:** the checked-in migrations enable row-level security and owner policies for the primary synced tables.
- **Basic authentication flow exists:** Supabase email/password sign-in, sign-up, confirmation resend, and sign-out paths are implemented.

## Submission blockers

1. **A production AI API secret is embedded in the app binary.** `Config.anthropicAPIKey` is hard-coded in source. This creates a billing/security risk and is likely unacceptable for production. Move recipe extraction behind a server-side endpoint, such as a Supabase Edge Function, and revoke/rotate the exposed key.
2. **The deployment target is set to iOS 26.4 / SDK 26.4-era settings.** App Store upload readiness depends on using an actual installed Xcode/iOS SDK and realistic minimum deployment target. If this project is opened in currently available public Xcode tooling, these values may fail or severely limit device availability.
3. **The current environment cannot build, test, archive, or validate the app.** `xcodebuild` is not installed here, so there is no verified clean build, test run, archive, export, or App Store validation result.
4. **RevenueCat entitlement identifier contains a space and must be verified against the dashboard.** The app checks for entitlement `Saman Pro`; RevenueCat entitlement IDs are commonly slug-like identifiers. If the dashboard ID does not exactly match, purchases will not unlock Pro.
5. **StoreKit/App Store Connect in-app purchase setup is not represented in the repository.** The app has a paywall wrapper, but there is no local StoreKit configuration file or automated purchase path verification.
6. **Test coverage is placeholder-level.** Unit and UI test targets exist, but the checked-in tests do not assert meaningful launch, auth, sync, purchase, scanner, recipe, or persistence behavior.

## High-priority review risks

- **Privacy disclosures must match behavior.** The app uses Supabase auth/database, RevenueCat, product barcode lookup, and an AI recipe extraction network call. App Privacy answers in App Store Connect should cover account identifiers, user content such as recipes/items, purchases, diagnostics if collected by SDKs, and any third-party data processing.
- **Account requirement/reviewer access:** the app gates the main tab shell behind Supabase authentication. App Review should receive a working demo account, or the app should offer a review-friendly path if sign-up requires email confirmation.
- **Network/service availability:** Supabase migrations are checked in, but readiness depends on the live project having these migrations applied and auth policies configured exactly as expected.
- **Recipe extraction reliability:** the Anthropic API call currently goes directly from the client and treats non-2xx responses generically. Production should have server-side key handling, rate limiting, observability, and more actionable failure states.
- **Scanner permission flow:** camera usage text exists, but reviewer/device behavior should be verified on a physical device.

## Recommended pre-submission checklist

### Must fix before upload

- Move `anthropicAPIKey` out of the iOS client and revoke/rotate the exposed key.
- Normalize deployment targets to a publicly supported Xcode/iOS SDK and a deliberate minimum iOS version.
- Run a clean Release archive on macOS with Xcode and resolve any compiler/signing/archive issues.
- Verify RevenueCat app, offering, package, product IDs, entitlement ID, and App Store Connect IAP status.
- Create a real reviewer test account and document review credentials in App Store Connect.

### Should fix before review

- Add meaningful smoke tests for model container creation, auth gating, sync payload encoding, and launch.
- Add a StoreKit configuration or test plan for purchase/restore behavior.
- Confirm Supabase production RLS policies and migrations are applied to the live project.
- Prepare App Privacy answers for Supabase, RevenueCat, barcode lookup, and AI recipe extraction data flows.
- Validate screenshots, age rating, support URL, privacy policy URL, and marketing copy.

### Nice to have

- Add CI that runs a build/test job on macOS.
- Replace console `print` diagnostics with a release-safe logging strategy.
- Add release notes and a repeatable archive/export checklist.

## Commands run during this assessment

- `git status --short`
- `rg --files`
- `rg -n "PRODUCT_BUNDLE_IDENTIFIER|MARKETING_VERSION|CURRENT_PROJECT_VERSION|INFOPLIST|DEVELOPMENT_TEAM|CODE_SIGN|IPHONEOS_DEPLOYMENT_TARGET|ASSETCATALOG_COMPILER_APPICON_NAME|NSCameraUsageDescription|ITSAppUsesNonExemptEncryption|RevenueCat|StoreKit|SUPABASE|OPENAI|TODO|FIXME|fatalError|print\\(" -S Saman.xcodeproj/project.pbxproj Saman Secrets.xcconfig.example supabase ci_scripts`
- `xcodebuild -version && xcodebuild -list -project Saman.xcodeproj`
- `python3 - <<'PY' ... validate asset catalog JSON ... PY`

## Completion ownership and what can be done from this repository

### I can complete in this repo/environment

- **Remove the hard-coded Anthropic secret from the iOS client.** I can replace the client-side Anthropic call with a server-proxy call interface, add environment/config placeholders, and add a Supabase Edge Function scaffold for recipe extraction. I cannot rotate the already-exposed key, but I can ensure the iOS code no longer embeds it.
- **Add repository-side guardrails for secrets.** I can add documentation and lightweight checks that fail when private API-key patterns are committed.
- **Lower/normalize deployment settings in the Xcode project.** I can change the checked-in deployment target values to a deliberate supported iOS version, subject to product requirements.
- **Add meaningful smoke tests.** I can replace placeholder tests with tests for config validation, model-container setup, sync payload assumptions where accessible, and basic launch/UI smoke coverage.
- **Add StoreKit test artifacts.** I can add a local `.storekit` configuration and document how RevenueCat/App Store Connect products should map to local test products.
- **Improve release documentation.** I can add a repeatable App Store archive/export checklist, reviewer-account checklist, and privacy-disclosure worksheet.
- **Reduce release logging.** I can replace ad hoc `print` diagnostics with a minimal release-safe logging wrapper.
- **Add CI configuration.** I can add a macOS/Xcode GitHub Actions workflow or Xcode Cloud notes, but it will only run where macOS/Xcode runners and signing secrets are configured.

### I can partially complete, but need owner-provided values or service access

- **Supabase Edge Function deployment.** I can write the function and expected secrets, but deploying it requires Supabase project access and setting the Anthropic API key as a server-side secret.
- **Supabase production verification.** I can audit checked-in migrations and app expectations, but confirming the live database requires access to the Supabase project or a schema dump.
- **RevenueCat/IAP mapping.** I can update code to use a safer entitlement constant and add local docs/tests, but confirming offerings, packages, entitlements, and App Store Connect product states requires RevenueCat and App Store Connect access.
- **Privacy policy and App Privacy answers.** I can draft the data-flow worksheet and recommended answers, but the legal/policy owner must approve the final policy and App Store Connect disclosures.
- **Reviewer demo account instructions.** I can add the checklist and in-app review guidance, but creating/confirming the account requires access to the production auth project and email inbox.

### I cannot complete in this container

- **Run `xcodebuild`, archive, export, or App Store validation.** This environment does not have Xcode command-line tooling installed.
- **Take physical-device scanner screenshots or validate camera behavior.** That requires a real iOS device or a macOS/Xcode simulator workflow with the project buildable.
- **Rotate/revoke exposed third-party secrets.** This requires access to the Anthropic dashboard or wherever the key is managed.
- **Submit or validate the binary in App Store Connect.** That requires Apple Developer/App Store Connect access and a macOS signing/archive environment.
