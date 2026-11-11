# Product analytics

Two independent sinks. Neither receives recipe text, transcripts, audio,
emails, names, list names, or item names.

| Sink | Identity | Payload |
|------|----------|---------|
| Supabase `events` | Random per-install UUID (`samaan.analytics.installID`) | `event`, `install_id`, `app_version`. Anon key INSERT only. Not tied to the account. |
| HeyCatch | After sign-in, the Supabase user id | Fixed screen name or event name. PostHog iOS SDK pointed at HeyCatch ingest. |

`Analytics.track` writes both. Extra HeyCatch-only names
(`onboarding_completed`, `purchase_completed`, `heycatchScreen(...)`) do not
insert a Supabase row.

## When it runs

`HeyCatch.start()` is called from `SamaanApp.init`. Tests, SwiftUI previews,
and screenshot / `-UITesting` launches never start the SDK
(`Analytics.isEnabled == false`).

After the cached session is known, `SamaanApp` calls `HeyCatch.bind` then
`HeyCatch.releaseQueuedEvents`. Splash, Onboarding, Home, and Auth can appear
before that bind; the outbox holds their screen/event names so they are not
sent under the previous person. `ui-testing` is not an account id.

Call `HeyCatch.bind(userID:)` on session changes. Do not call `identify` or
`reset` from feature code — `bind` owns that, then re-registers the project
group after every reset.

Guests are not identified (#71). Signed-out with a prior bind → `reset()`.
Account switch → reset, then identify the new Supabase user id. Bound id is
stored in `samaan.heycatch.boundUserID`.

## What to add

New product outcomes go through `AnalyticsEvent` + `Analytics.track` when a
Supabase row is wanted, or `HeyCatch.capture("fixed_name")` for HeyCatch only.
Names are fixed strings. No properties.

Autocapture, session replay, surveys, SDK screen views, and swizzling stay
off in `HeyCatch.start()`.

## Privacy

Engineering copy for the hosted privacy page is in
`docs/launch/legal-and-privacy.md`. Update that live page before shipping a
build that includes HeyCatch. The ingest token is a write-only HeyCatch value
already in the binary; do not paste it into docs or tickets.
