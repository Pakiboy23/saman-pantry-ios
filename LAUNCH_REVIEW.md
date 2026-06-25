# Saman Pantry — Pre-Launch Comprehensive Review

**Reviewer role:** Senior product / engineering / App Store / GTM
**Date:** 2026-06-25
**Build reviewed:** branch `claude/optimistic-clarke-wdc16x`, marketing version `1.0 (1)`, bundle `com.samanpantry.Saman`
**Method:** Direct code read of every service, model, and feature view + a 34-agent parallel audit with adversarial verification (53 findings, 28 Critical/High each independently re-verified against the source — 0 refuted).

---

> ### ⏱ Status update (post-review work on this branch)
> This review was written against the branch as originally forked. `main` had since advanced, and this branch now merges it. Net state:
>
> **Already fixed on `main` (verified):** AI-01 Anthropic key moved to a Supabase Edge Function (`extract-recipe`); secret-scanning CI; StoreKit config; deployment target normalized to iOS 17; readiness docs.
>
> **Fixed on this branch (this PR):**
> - Build breaks that existed on `main` but were never compiled there (`AppEnvironment`/`SyncManager` main-actor isolation; `mainContext` test).
> - **Core loop (P3-02/03/04/07):** Pantry tab, pantry-first onboarding, "Add desi staples" seed, delete affordances, and **mark-bought → pantry restock**.
> - **AUTH-001 + P2-LEGALURLS:** in-app account deletion (`delete-account` Edge Function + Settings UI) and Privacy/Terms/Support links; plus local-store wipe on sign-out/delete (**AUTH-002**).
> - Hardened the (never-run) CI workflow: dynamic simulator selection + unit-tests-only (the template UI tests hang on the network-gated splash in CI).
>
> **Still owner-only (cannot be done from the repo):** revoke the old Anthropic key; deploy both Edge Functions + set secrets; RevenueCat/ASC IAP verification; publish the Privacy/Support pages and point `Config` at them; reviewer demo account; screenshots/metadata (drafts in `docs/launch/`).
>
> **Deliberately deferred (launch risks, not blockers):** notifications (P3-05), pull-sync/multi-device (DATA-01), recipe sync. Per "ship clean, not bloated."

---

> The three goals — clean App Store approval, organic activation/retention, defensible revenue — are in tension. Where they conflict this doc surfaces the trade-off and makes a call. The single most important call is at the top of Phase 5: **the shipped app contradicts its own thesis, and that incoherence is the root cause of half the findings below.**

---

## TL;DR — what to do before you submit

You cannot submit this build today. It will be rejected on at least three guideline grounds and, separately, it ships a live secret that bills your company. In priority order:

1. **Revoke the Anthropic key in `Config.swift:18` right now.** It is a live `sk-ant-` org secret, in the binary and in git history on `origin`. Anyone can extract it and spend your Anthropic balance with no cap. This is a money leak, not a theoretical one. (AI-01)
2. **Add in-app account deletion.** Hard Guideline 5.1.1(v) rejection — you create accounts and offer no delete. (AUTH-001)
3. **Add a Privacy Policy URL, Terms URL, and Support URL**, in-app and in App Store Connect. You sell an auto-renewing subscription, so Terms + Privacy on the paywall are also required by 3.1.2. (P2-LEGALURLS-002)
4. **Add a `PrivacyInfo.xcprivacy` manifest** and fill the App Privacy "nutrition label" to match real behavior (email, user ID→RevenueCat, pantry/recipe content to Supabase, transcripts to Anthropic). (PRIV-01..04)
5. **Give App Review a pre-confirmed demo account** (or disable email confirmation), or the reviewer is stuck at the "Check your email" wall and rejects under 2.1. (P3-01)
6. **Fix the broken core loop and the missing Pantry tab** before public launch — not for Apple, but because the app does not currently do the one thing it promises. (P3-02, P3-03)

Everything else is real but secondary. Ship clean on the six above and you have a submittable, honest 1.0.

---

## Phase 1 — Current-State Assessment (no optimism)

### What is actually built and works
- **Auth:** email/password sign-up, sign-in, sign-out, email-confirmation screen with resend, session persistence, auth-state observer. Supabase RLS owner policies are real on all 6 server tables.
- **Local persistence:** SwiftData container with 7 models (Item, Pantry, Product, Store, ShoppingList, ShoppingListItem, Recipe). Solid.
- **Barcode scanning:** VisionKit `DataScannerViewController` tap-to-scan works end-to-end; looks up local cache → Open Food Facts; manual-add fallback on unknown.
- **AI recipe extraction:** genuinely functional and genuinely good. Pastes a code-switched transcript, calls Claude (`claude-sonnet-4-6`), parses structured ingredients, lets you select and push to a shopping list. The system prompt ("never invent a number", keep the speaker's exact phrase, map to English grocery terms) is the most differentiated thing in the product.
- **Monetization plumbing:** RevenueCat configured, entitlement `Saman Pro`, native Paywall + Customer Center, restore wired via `.onRestoreCompleted`.
- **Design system:** coherent, distinctive Saag color system, bilingual (Cormorant + Noto Nastaliq Urdu), dark mode, app icon (light/dark/tinted) present.

### What is partially built
- **Sync** uploads but never downloads (see "broken"). Functional as a one-way push only.
- **Error handling** surfaces raw Supabase/network strings to users; no field validation.
- **Expiry tracking** exists as data + on-screen status but nothing populates an expiry date at add-time and nothing ever reminds the user.

### What is stubbed / mocked / inert
- **`image_url`** is modeled, migrated, and upserted but **never populated** — no photo picker, no Storage upload, no `NSPhotoLibraryUsageDescription`. Dead column.
- **Notifications:** zero. No `UNUserNotificationCenter` anywhere, yet the UI says "Alert me when below" and "Expires within 7 days." The alerts never fire.

### What is broken
- **No pull sync.** `SyncManager` only `.upsert`s. Reinstall or new device → the cloud copy is unreadable and the user starts empty. (DATA-01)
- **Core loop dead-ends.** Marking a shopping item "bought" never updates the pantry — the list and pantry are disjoint object graphs with no link. The product's one-sentence promise does not execute. (P3-02)
- **Deletes never propagate.** Local-only `context.delete`; server rows live forever and will resurrect once pull exists. (DATA-02)
- **Cross-account leak on shared devices.** Sign-out doesn't clear the local store; push-only sync re-stamps User A's pantry into User B's account. (AUTH-002)
- **Recipes never sync at all** — local-only model with a meaningless `isDirty`. Reinstall wipes the headline feature. (DATA-05)

### What is missing
- In-app **account deletion** (hard blocker).
- **Password reset** — forget your password and you are locked out forever. (AUTH-003)
- **`PrivacyInfo.xcprivacy`**, Privacy Policy / Terms / Support URLs.
- **Any onboarding.** First screen is a sign-in wall. No guest mode, no demo.
- **A Pantry tab.** Tabs are Home / Recipes / Lists. The pantry — the supposed core — has no home and is unreachable on cold start.
- **Notifications / re-engagement** of any kind.

### What depends on manual work or assumptions
- Assumes Supabase email-confirmation is enabled (code branches into "check your email" unconditionally). If it's off, users are stranded; if it's on, reviewers are stranded.
- Assumes App Store Connect metadata + screenshots + the App Privacy label are done by hand later. None exist in the repo.
- `IPHONEOS_DEPLOYMENT_TARGET = 26.4` and `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone **and iPad**) appear to be defaults, not decisions — see Phase 2.

---

## Phase 2 — Submission Readiness (rejection vectors + fixes)

### CRITICAL — will block submission or get pulled

**AI-01 — Live Anthropic secret key in the client + git.** `Config.swift:18`, used at `RecipeExtractionService.swift:59`.
*Why it matters:* uncapped billing theft against Saman Technologies LLC; also a Guideline 5.6/2.3 and automated-secret-scanner exposure. The in-file comment itself admits it.
*Fix (in order):* (1) **Revoke** the key now. (2) Move the call into a **Supabase Edge Function** `extract-recipe` that reads `ANTHROPIC_API_KEY` from Edge secrets, validates the caller's JWT, enforces a per-user daily quota, and proxies to Anthropic. (3) Client calls `${SUPABASE_URL}/functions/v1/extract-recipe` with the user's access token; **delete `Config.anthropicAPIKey`**. (4) Scrub history (`git filter-repo --replace-text`) after rotation. Spec + code in `docs/launch/account-deletion-and-edge-functions.md`. Model string `claude-sonnet-4-6` is current — only the key custody and call site move.

**AUTH-001 — No in-app account deletion.** `SettingsView.swift:74-91` (Account card = Sign out only).
*Why:* Guideline 5.1.1(v) requires it for any account-creating app. Guaranteed rejection.
*Fix:* Add "Delete Account" (destructive, double-confirm) → call a `delete-account` Edge Function (service-role key) that deletes the auth user; `ON DELETE CASCADE` already removes their rows. Sign out locally + wipe the local store on success. Code in the same doc.

**P2-LEGALURLS-002 — No Privacy Policy / Terms / Support URL.** Absent in-app (`SettingsView` About card shows only Version/Build) and not in ASC.
*Why:* ASC requires a Privacy Policy URL to submit; 3.1.2 requires Terms (EULA) + Privacy **on the paywall** for an auto-renew subscription; a Support URL is required.
*Fix:* Publish three pages (a one-page GitHub Pages or Vercel site is fine), add them to the Settings "About" card and to the RevenueCat paywall config (`.tosUrl` / `.privacyUrl` or dashboard fields), and fill the ASC fields. Draft copy obligations in `docs/launch/legal-and-privacy.md`.

**PRIV-01 — No `PrivacyInfo.xcprivacy`.**
*Why:* Apple requires the manifest for apps using required-reason APIs and lists RevenueCat/Supabase-class SDKs; missing/incorrect manifests increasingly draw ITMS-91053 rejections, and the App Privacy label must match real data flow or you risk 5.1.1 metadata rejection.
*Fix:* Add the manifest in `docs/launch/PrivacyInfo.xcprivacy` to the app target; fill the App Privacy label per the data map below.

> **Settings reachability (P2-SETTINGS-REACH-003, Medium):** Settings — your only legal-link surface and the home of account deletion — is a sheet behind a gear icon, not a tab. Reviewers look for these in obvious places. Keep it a sheet if you must, but make sure deletion + legal links are also discoverable; a "Privacy & Terms" row in the About card costs nothing.

### Data-collection map (what the App Privacy label + manifest MUST declare)
| Data | Where it goes | Linked to user? | Purpose | Tracking? |
|---|---|---|---|---|
| Email address | Supabase Auth | Yes | Account / app functionality | No |
| User ID (Supabase UUID) | Supabase + **sent to RevenueCat as appUserID** | Yes | App functionality, purchase | No |
| Pantry/list/product/store content | Supabase tables | Yes | App functionality | No |
| Recipe **transcript text** | **Anthropic API** (currently direct from device) + stored locally | Yes | App functionality (AI) | No |
| Purchase history | RevenueCat / App Store | Yes | Purchase | No |

PRIV-03 (user-ID linkage to RevenueCat, Low) and PRIV-02 (transcripts to a third party, High) **must** be reflected — undisclosed third-party egress of family voice transcripts is exactly the mismatch App Review and users punish.

### MEDIUM — friction, not certain rejection
- **`TARGETED_DEVICE_FAMILY = "1,2"`** ships iPad, but the UI is iPhone-designed and there are no iPad screenshots. *Fix:* set to `"1"` (iPhone only) unless you commit to an iPad layout + screenshots. (P2-APPICON-MAC-007 also: drop the empty Mac icon slots.)
- **`IPHONEOS_DEPLOYMENT_TARGET = 26.4`** needlessly excludes most of the install base; the code only needs iOS 18 (`TabView { Tab(...) }`). *Fix:* lower to `18.0` to maximize reach. (Phase 6, Marketing/Eng)
- **`ITSAppUsesNonExemptEncryption = NO`** while calling HTTPS endpoints — fine (standard exemption), just answer the ASC export-compliance question consistently. (P2-ENCRYPTION-ANTHROPIC-008, Low)
- **Email-confirmation strand (AUTH-005):** if confirmation is disabled in Supabase, the "check your email" screen shows but no email arrives. Make the post-signup state match the project's actual confirmation setting.

### Positioning believability (App Store copy)
The app must read as *"a practical pantry tool that helps you know what you have, what you're low on, and capture the recipes you actually cook."* **Do not** claim grocery automation, food-safety/expiration accuracy, nutrition, or that the scanner "recognizes" products (Open Food Facts will miss most desi staples — AI-04). The AI is recipe **structuring**, not a recipe engine or meal planner. Draft metadata that stays inside what's built is in `docs/launch/app-store-metadata.md`.

---

## Phase 3 — Product Quality & Retention

**Core question — does the app make keeping a pantry accurate easier than doing nothing? Today: no.** The loop doesn't close and the pantry has no front door.

### The retention-critical defects
- **P3-03 (Critical) — no Pantry tab, unreachable on cold start.** Tabs are Home/Recipes/Lists; `InventoryView` is reachable *only* through "See all pantry items," which only renders when low-stock items already exist. A new user literally cannot open the pantry, and the empty state funnels them to "Capture a Recipe" — the thing the THESIS says the app is **not**. *Fix:* add a **Pantry tab** → `InventoryView` (already built); make the Home empty state pantry-first ("Add your first item"), recipe capture secondary.
- **P3-02 (Critical) — "mark bought" never restocks the pantry.** `ShoppingListItem` and pantry `Item` are disjoint; there's no link. The most important step of the promise is a no-op. *Fix:* add `item: Item?` to `ShoppingListItem`; on purchase, increment the linked pantry item's quantity by the purchased quantity (fall back to normalized-name match), `markDirty`/save/sync; handle un-toggle to avoid double-counting. **But** nothing currently *originates* a list item from a low pantry item — so you must also build the "add low item → list" step or the link stays nil. This is the loop; it's worth doing right.
- **P3-01 (High) — mandatory account + email confirmation, zero onboarding.** Forced sign-up before any value is both an activation killer and a reviewer-lockout risk. *Fix:* ship a **local/guest mode** (the app is local-first SwiftData already — auth is only needed for sync), or at minimum a pre-confirmed demo account in review notes + a value-first first run. Guest mode is the bigger activation unlock and the cleaner review story.
- **P3-05 (High) — promised alerts never fire.** Copy says "Alert me / Expires within 7 days"; there is no notification code. A weekly-use app with no nudge has near-zero re-engagement. *Fix:* implement local notifications (low-stock digest + expiry reminders) with a value-framed pre-permission screen — **or** change the copy to "Flag as low / Track expiry" and stop promising it. Don't ship the promise without the mechanism.
- **P3-04 (High) — empty-pantry death.** No seed content. Typing 30 items by hand before any value is exactly where pantry apps get abandoned. *Fix:* a dismissible **"Add desi staples"** one-tap pack (~15-20 items at qty 0 so they surface as "to buy": atta, basmati, toor/masoor dal, ghee, haldi, jeera, garam masala, chai, paneer…). Highest-leverage activation lever and it reinforces the niche. Gate on a first-run flag, not container creation.
- **P3-07 (High) — can't delete items, lists, or recipes.** No reachable delete on pantry items, shopping lists, or recipes (the only `delete` lives in the unreachable `PantryListView`). "Can't even delete an item" is a direct 1-star. *Fix:* `.swipeActions`/`.onDelete` on inventory rows, list rows, and recipe rows + a delete in the detail views; confirm destructive ones.

### Quality/UX issues that generate 1-stars
- **AI-04 (Medium)** scanner returns "Unknown product" for the target audience's real groceries → feels broken. Reframe as "scan to capture & name," and **persist user-named barcodes** to build your own desi coverage over time.
- **P3-06 (Medium)** every recipe capture spawns a brand-new list + duplicate products; capture "onion" three times → three Products, three lists, zero pantry link. *Fix:* `findOrCreateProduct(name:)` dedupe + "add to existing list" + pantry-awareness.
- **P3-08 (Medium)** dead/unreachable code: `PricesView`, `ReorderView`, `PantryListView(+Detail)`, `ItemRepository`. The Reorder writeback work in `MEMORY.md` is now orphaned by the pivot. *Fix:* delete it (ship clean) — but salvage `RestockSheet` for P3-02.
- **P3-09 (Medium)** emoji enrichment is all Western groceries; desi staples fall back to a generic cart. Cheap, on-brand win.
- **AUTH-004 (Medium)** raw Supabase error strings shown to users.
- **DATA-04 (Medium)** all sync failures are silent `print`s — the user believes they're backed up when they may not be. Add a "Last synced…/Sync failed" signal.
- **P3-10 (Medium)** 30-item hard paywall on *adding inventory* — see Phase 4; gating storage is the wrong thing to gate.

**Accessibility / performance / offline / crash surfaces:** no obvious force-unwrap crash sites in the hot paths; SwiftData `@Query` is fine at expected scale. Offline behavior is "silently does nothing and looks synced" (DATA-04). Accessibility wasn't deeply audited — Dynamic Type and VoiceOver labels on the custom card components are a Post-Launch pass.

---

## Phase 4 — Revenue & Monetization

**The model is economically inverted and that's the headline.** (MON-01, High/Critical)

- **What's gated (Pro):** >30 pantry items, a 2nd shopping list (`>=1`), a 2nd pantry (`>=1`) — all **local SwiftData rows that cost you nothing.**
- **What's free and uncapped:** the **AI recipe extraction**, the only feature with a real per-use marginal cost (Claude tokens on your key).

So the free tier carries your cost and the paid tier sells free storage. One enthusiastic user — or one person who extracts the key — runs up an unbounded Anthropic bill against zero revenue.

**Other monetization gaps:**
- **MON-03 (Medium)** no app-owned Restore button visible to *non-Pro* users (restore is only inside the RevenueCat paywall/Customer Center). Add an explicit "Restore Purchases" affordance.
- **MON-04 (Medium)** Terms + Privacy on the paywall not proven in code (delegated to the RC dashboard) — 3.1.2 requires them. Verify in the RevenueCat dashboard before submitting.
- **MON-02 (Medium)** no IAP product/price/offering in the codebase — all remote. Make sure the offering + products actually exist and are "Ready to Submit," or the paywall is empty in review.
- **MON-05 (Medium)** gates are duplicated at five call sites with magic numbers and **only enforced at manual add-buttons** (recipe-push and some paths bypass them). A reviewer can hit the 1-list / 1-pantry wall during normal evaluation → "limits feel arbitrary."
- **MON-06 (Medium)** the paywall's only pitch is "Upgrade to Pro to support development." That's a donation ask, not a value proposition.

**Recommended launch strategy: free-first, with the recurring *cost* as the only thing behind the paywall.** (MON-07)
- **Free and generous:** the entire pantry + list + shopping loop, multiple lists and pantries, manual item entry, barcode capture. Removes most gating/review risk and honors the "lighter than a spreadsheet" promise.
- **Paid ("Saman Pro"):** **unlimited AI recipe capture** (free tier = 3–5 captures/month, metered **server-side** in the Edge Function) **+ multi-device sync** once pull exists. These are the two features that actually cost you money and deliver recurring value — the only honest basis for a recurring charge.
- **Pricing:** a pantry utility is low-urgency; don't over-ask. ~$2.99/mo or **$14.99/yr**, lead with annual. Strongly consider a **one-time "Saman Pro" unlock (~$19.99)** for everything-local + a separate small AI credit model — it fits a utility far better than a subscription and slashes your 3.1.2 compliance surface. Trade-off: lower LTV, no recurring revenue to cover Anthropic — which is why AI must be metered either way.
- **Do not** charge a monthly fee for local row counts. It maximizes churn and review exposure for the weakest possible value story.

**Habit before money:** gate nothing that blocks the first satisfying loop. The paywall should appear when a user hits their 4th AI capture in a month or taps "sync to my other phone" — moments of demonstrated value — not when they add their 31st item.

---

## Phase 5 — Independent Review & Organic Growth

### The decision you have to make first: resolve the thesis drift (P2-THESIS-DRIFT-004, AI-05)
`THESIS.md` says, in writing: *"What it is not: A meal planner. A recipe app."* The shipped app's Home empty-state CTA is **"Capture a Recipe,"** Recipes is a **top-level tab**, and the pantry has **no tab at all**. The build currently does the worst of both worlds: it half-abandons the pantry (broken loop, no front door) while leading with a recipe feature that is itself half-built (paste-only, no pantry reconciliation, uncapped cost). That incoherence is the root cause of P3-02, P3-03, P3-06, and the inverted monetization.

**You have two coherent paths. Pick one and make the other serve it:**

- **(A) Pantry-first (honor the thesis).** Restore the Pantry tab, fix the loop, and make recipe capture the *signature feature inside* a pantry app — the fast, magical way to turn "my mom's karahi" into a shopping list and then into tracked stock. Pantry is the daily-use retention engine; recipe is the wow and the paid hook.
- **(B) Recipe-first (rewrite the thesis).** Make "capture your family's recipes, auto-build the list, track what you have" the identity; pantry becomes the downstream ledger.

**Recommendation: (A).** The generic pantry tracker is a commodity, but **"never lose your parents' code-switched, andaza-and-all recipes — and let them quietly run your kitchen"** is a genuinely defensible, emotionally resonant wedge that no Paprika/Samsung Food competitor occupies. Keep that as the differentiator *inside* a pantry-first app that actually closes its loop. This resolves the tension, keeps the app shippable and honest, and gives you the strongest possible word-of-mouth ("it kept my mom's recipe exactly how she said it").

### Strongest organic positioning angle (P5-POSITIONING-010)
**Cultural specificity, not "AI."** Lead with the desi-kitchen identity and the recipe-keepsake angle; let AI be invisible plumbing. Recommended line:

> **Saman — your desi kitchen, sorted.** Know what's in the cabinet, capture the recipes you actually cook (in the words they were said), and stop buying atta you already have.

This earns word-of-mouth from exactly the people the app is for (diaspora home cooks, families, roommates) and reads as a benefit in seconds. "AI grocery intelligence" would read as generic and over-promised; the moat is the specificity.

### What would earn praise vs. punishment in this category
- **Praise:** feels lighter than a spreadsheet; one-tap staple seeding; the recipe-keepsake moment; honest, quiet design; the bilingual identity.
- **Punishment:** can't delete an item; "it never reminds me of anything"; "scanned my atta, said unknown"; "reinstalled and lost everything"; forced signup before I could try it; a paywall on my 31st item.

### App Store page
Screenshots must show **real use** (a pantry with desi staples and low-stock dots; a captured recipe with "haldi — andaza se" preserved; a shopping list mid-checkout), not empty UI. Draft store copy: `docs/launch/app-store-metadata.md`.

---

## Phase 6 — Launch Prioritization

### ✗ Launch Blockers — fix before submission / public launch
| # | Issue | Impact | Effort | Owner | Action |
|---|---|---|---|---|---|
| AI-01 | Live Anthropic key in client + git | Money leak + 5.6/2.3 | M | Eng/Infra | Revoke → Edge Function proxy → delete key → scrub history |
| AUTH-001 | No account deletion | 5.1.1(v) rejection | M | Eng | Delete-account Edge Function + Settings UI |
| P2-LEGALURLS | No Privacy/Terms/Support URL | ASC + 3.1.2 reject | S–M | Legal/Founder | Publish 3 pages; wire into Settings + paywall + ASC |
| PRIV-01..04 | No privacy manifest / label mismatch | ITMS-91053 + 5.1.1 | M | Eng/Product | Add `PrivacyInfo.xcprivacy`; fill App Privacy label to match egress |
| P3-01 (review) | Email-confirm reviewer lockout | 2.1 reject | S | Eng/Founder | Demo account in review notes, or guest mode, or confirm-off |
| P3-03 | No Pantry tab / unreachable | Product is non-functional for its purpose | S | Product/Eng | Add Pantry tab; pantry-first empty state |
| P3-02 | Core loop dead-ends | The promise doesn't execute | M | Eng | Link list↔item; restock on "bought"; add low→list origin |

### ◐ Launch Risks — won't necessarily block, will hurt approval/retention/conversion
AUTH-002 (cross-account leak), DATA-01 (no pull / reinstall data-loss — at minimum stop marketing "sync"), DATA-02 (delete resurrection), AUTH-003 (no password reset), P3-04 (empty-pantry seeding), P3-05 (alerts promised, never fire), P3-07 (no deletes), MON-01/05 (inverted + leaky gating), MON-03/04 (restore + paywall legal links), AI-04 (scanner coverage), P3-06 (recipe dedupe), device-family iPad, deployment-target 26.4.

### ✓ Post-Launch Improvements — don't delay launch
DATA-03 (updated_at conflict policy), DATA-04 (sync status UI), P3-08 (delete dead code — quick), P3-09 (desi emoji), AUTH-004 (friendly errors), MON-06 (paywall value copy), accessibility pass, PRIV-05 (`image_url` / photos — only if you actually ship item photos).

### ⨯ Do Not Build Yet — distractions from proving the product
Household/shared pantry (THESIS gates it on 500 WAU + 30% demand — keep it gated), meal planning, recipe engine/discovery, price history / store comparison (kill `PricesView`), receipt scanning, multi-pantry templates, Sign in with Apple (only needed if you add social login), item photos, iPad-optimized layout. None of these prove the core loop; several actively contradict the "ship clean, not bloated" mandate.

---

## Concrete artifacts in this PR
- `docs/launch/PrivacyInfo.xcprivacy` — ready-to-add privacy manifest (annotated; verify each entry against final code).
- `docs/launch/app-store-metadata.md` — name, subtitle, keywords, promo text, description, review notes, screenshot shot-list.
- `docs/launch/legal-and-privacy.md` — what the Privacy Policy / Terms / Support pages must say, and where to wire them.
- `docs/launch/account-deletion-and-edge-functions.md` — Edge Function specs + client code for the Anthropic proxy and account deletion.

*No source code was modified.* The fixes touch architecture and a monetization decision; this review lays them out so you can choose scope. See the closing question in the PR for what to implement first.
