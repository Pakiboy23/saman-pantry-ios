# Privacy Disclosure Worksheet

This worksheet is not legal advice; use it to prepare App Store Connect privacy answers and the public privacy policy.

## Data flows to disclose/review

| Feature | Data involved | Destination | Purpose |
| --- | --- | --- | --- |
| Account auth | Email address, Supabase user ID | Supabase | Account creation, sign-in, sync ownership |
| Pantry inventory | Item names, quantities, notes, expiry dates, optional image URL/barcode | Supabase | Cross-device sync |
| Shopping lists | List names, item quantities, purchase status, estimated prices | Supabase | Cross-device sync |
| Recipe extraction | User-entered recipe transcript and extracted recipe JSON | Supabase Edge Function, Anthropic provider from server | Convert transcript into structured recipe |
| Purchases | App user ID, subscription/customer info | RevenueCat, App Store | Entitlement and purchase management |
| Barcode lookup | Barcode value | Product lookup provider used by app | Product lookup/scanner convenience |

## App Store Connect preparation

- Confirm whether data is linked to user identity through Supabase auth or RevenueCat app user IDs.
- Confirm whether analytics/diagnostics are collected by third-party SDKs beyond the app code in this repo.
- Confirm data retention/deletion process for Supabase account deletion requests.
- Confirm whether optional pantry notes or recipe transcripts can contain sensitive user-provided content.
- Ensure the public privacy policy names Supabase, RevenueCat, and the server-side AI extraction provider as applicable.
