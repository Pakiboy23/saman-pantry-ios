# Privacy Disclosure Worksheet

This worksheet is not legal advice; use it to prepare App Store Connect privacy answers and the public privacy policy.

## Data flows to disclose/review

| Feature | Data involved | Destination | Purpose |
| --- | --- | --- | --- |
| Account auth | Email address, Supabase user ID | Supabase | Account creation, sign-in, sync ownership |
| Pantry inventory | Item names, quantities, notes, expiry dates, optional image URL/barcode | Supabase | Cross-device sync |
| Shopping lists | List names, item quantities, purchase status, estimated prices | Supabase | Cross-device sync |
| Recipe extraction | User-entered recipe transcript or link, and the extracted recipe JSON. For a link, the server fetches the public page. YouTube: title, description, and best-effort captions (YouTube Data API when `YOUTUBE_API_KEY` is set, otherwise the public watch page). Instagram: caption only, when the page exposes it. A complete schema.org Recipe is parsed on the server and is not sent to the model. | Supabase Edge Function. Anthropic receives the text when the page is not already a complete Recipe. Google receives the video id only when the YouTube Data API key is set. | Convert a transcript or link into a structured recipe |
| Recipe share | Recipe text (and an on-device image card) the user sends through the iOS share sheet. Anonymous `recipe_shared` event: install id, event name, app version — same payload as the other product-interaction events, no recipe content. | Destinations the user picks in the share sheet. Supabase `events` insert for the event name only. | Share a recipe the user already saved |
| Purchases | App user ID, subscription/customer info | RevenueCat, App Store | Entitlement and purchase management |
| Barcode lookup | Barcode value | Product lookup provider used by app | Product lookup/scanner convenience |

## App Store Connect preparation

- Confirm whether data is linked to user identity through Supabase auth or RevenueCat app user IDs.
- Confirm whether analytics/diagnostics are collected by third-party SDKs beyond the app code in this repo.
- Confirm data retention/deletion process for Supabase account deletion requests.
- Confirm whether optional pantry notes or recipe transcripts can contain sensitive user-provided content.
- Ensure the public privacy policy names Supabase, RevenueCat, and the server-side AI extraction provider as applicable. For 1.2, also say a pasted link may be fetched (page text, YouTube title/description/captions, Instagram caption) and that YouTube Data API receives the video id when that key is configured. `PrivacyInfo.xcprivacy` did not gain a new data type: pasted links are the existing Other User Content category, and `recipe_shared` is the existing Product Interaction category (not linked, not tracking). The live page at samanpantry.com/privacy is hosted outside this repo — update it from `docs/launch/legal-and-privacy.md` before shipping 1.2.
