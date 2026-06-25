# Legal & Privacy — what to publish and where to wire it

Three URLs are **required to submit** and are currently missing both in-app and in App Store
Connect. A subscription makes Terms + Privacy on the paywall mandatory under Guideline 3.1.2.

Cheapest correct path: one static site (GitHub Pages, Vercel, or a Notion public page) with
three pages. A generator like the Apple-cited iubenda/Termly is fine; the content below is the
substance reviewers and users need.

---

## 1. Privacy Policy  (required by App Store Connect + paywall)
Must accurately describe **actual** data behavior (App Privacy label must match this):

- **Who:** Saman Technologies LLC, contact email.
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

## Where to wire them in-app
1. **Settings → About card** (`SettingsView.swift`): add rows "Privacy Policy", "Terms of Use",
   "Support" opening the URLs (and they double as your discoverable legal surface since Settings
   is a sheet, not a tab — see P2-SETTINGS-REACH-003).
2. **Paywall** (`PaywallView.swift` / RevenueCat dashboard): set the Terms and Privacy URLs in
   the RevenueCat paywall configuration (or via `.tosUrl`/`.privacyUrl` modifiers). Verify they
   render on the live paywall — MON-04 flags this as unproven in code today.
3. **App Store Connect**: App Privacy → Privacy Policy URL; App Information → Support URL;
   and the subscription group localization carries the Terms.

## Food-safety / expiry disclaimer (do this)
The app shows "expiring" status. Add one line to Terms and ideally near the expiry UI:
"Expiry and stock information is what you enter and maintain; Saman is not a food-safety
authority and does not verify freshness." This pre-empts the "implies food-safety accuracy"
rejection vector and protects you from liability.
