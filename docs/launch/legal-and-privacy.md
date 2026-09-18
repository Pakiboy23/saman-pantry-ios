# Legal & Privacy — live URLs and page substance

Privacy, Terms, and Support URLs are **live** and shown in-app **without a login** (#20).
Do not treat them as missing. A subscription still makes Terms + Privacy on the paywall
mandatory under Guideline 3.1.2; that inset already ships.

| Surface | URLs |
|---------|------|
| `Config.swift` | `privacyPolicyURL`, `termsOfUseURL`, `supportURL` |
| Settings → LEGAL, AuthView footer, paywall inset | same three |

Live (verified 29 Aug 2026; keep in App Store Connect):

- Privacy: `https://samanpantry.com/privacy` (200; apex 307s to `www`)
- Terms: Apple standard EULA (`Config.termsOfUseURL`)
- Support: `https://samanpantry.com/support` (200)

The public pages still need to match actual data behavior. Substance below is for those
hosted pages, not a to-do to invent new URLs.

---

## 1. Privacy Policy  (required by App Store Connect + paywall)
Must accurately describe **actual** data behavior (App Privacy label must match this):

- **Who:** Samaan Technologies LLC, contact email.
- **What we collect:** account email; an internal user ID; the pantry items, shopping lists,
  and recipes you enter; subscription/purchase status.
- **Where it goes / processors:**
  - **Supabase** — stores your account and your kitchen data (hosting/backend).
  - **Anthropic** — receives the recipe transcript text you choose to capture, to structure it
    into ingredients. (After the Edge Function move, the path is app → our server → Anthropic.)
  - **RevenueCat / Apple** — process and verify subscriptions; receive your user ID.
- **What we do NOT do:** no advertising, no cross-app tracking, no selling data, no analytics
  SDKs. (Only claim this if it stays true — there are currently no analytics SDKs in the build.)
- **Data retention & deletion:** you can delete your account and all associated data in-app
  (Settings → Delete Account); describe how, and how long backups persist.
- **Children:** not directed at children under 13.
- **Contact + effective date.**

## 2. Terms of Use / EULA  (required on the paywall for subscriptions)
- You may use Apple's **standard EULA** (link: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/)
  unless you need custom terms. If you use the standard EULA you still must link it on the paywall.
- Cover: subscription terms (price, period, auto-renewal, cancellation via App Store),
  acceptable use, disclaimer of warranties (esp. that expiry/stock info is user-maintained and
  **not** food-safety advice), limitation of liability, governing law.

## 3. Support URL  (required)
- A simple page with a support email (or a form) and a short FAQ. Can be one section of the
  same site. App Store Connect rejects submissions with no reachable support URL.

---

## Where they already appear
1. **Settings → LEGAL** (`SettingsView.swift`): Privacy Policy, Terms of Use, Support. Visible
   to guests (gear on Home/Pantry). Do not restore a login wall to reach them.
2. **AuthView footer** and **paywall** (`SamaanLegalLinks` / `SamaanPaywallView` safe-area inset):
   same links. RevenueCatUI has no `tosUrl`/`privacyUrl` modifier — keep the in-binary inset.
3. **App Store Connect**: App Privacy → Privacy Policy URL; App Information → Support URL;
   subscription group localization carries the Terms. Keep these pointed at the live URLs above.

## Food-safety / expiry disclaimer (do this)
The app shows "expiring" status. Add one line to Terms and ideally near the expiry UI:
"Expiry and stock information is what you enter and maintain; Samaan is not a food-safety
authority and does not verify freshness." This pre-empts the "implies food-safety accuracy"
rejection vector and protects you from liability.
