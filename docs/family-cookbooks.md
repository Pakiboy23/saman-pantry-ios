# Family cookbooks (1.6)

Private, invite-only cookbooks on the Recipes tab **Families** shelf.
Not household mode (no shared pantry or list). Not the public community
book. Ops to apply SQL and deploy the webhook:
[`family-books-go-steps.md`](./family-books-go-steps.md).

## Intent

A Pro (or grandfathered) cook starts a family and invites people they
already cook with. Members read a **snapshot** of recipes someone added.
Spoken words and recordings stay in the author's own book.

## Three recipe surfaces

| Shelf | Table | Who sees it |
|-------|--------|-------------|
| **Yours** | `recipes` | The owner. Syncs with the account. |
| **Families** | `family_recipes` | Members of that family only. |
| **Community** | `recipe_book_cards` | Signed-in readers. Transcript saves auto-publish; URL recipes need `share_in_family_book`. |

Do not mix the two "family" names. THESIS "family recipe book" is
Community. 1.6 "family cookbooks" are Families.

## Who can do what

| Action | Pro? | Notes |
|--------|------|--------|
| Create a family | Yes, or `user_accounts.grandfathered` | RPC `create_family`. Cap 5 owned families. |
| Join / read / invite / add recipes / notes / save a local copy | No | Join is free. |
| Owner's Pro lapses | Family keeps working | Tested in `family_books_security.sql`. |

iOS: unsigned users see a sign-in prompt on the Families shelf
(`FamilyCopy.signInBody`). Create also checks `PurchaseService.isPro` and
`user_accounts.is_pro` / `grandfathered`; otherwise `SamaanPaywallView(trigger: .createFamily)`.

If the device shows Pro but the RPC returns `pro_required`, the client
maps that to `.proSyncing` ("Your Samaan Pro is still syncing").

## Invites

Share URL (universal link): `https://www.samanpantry.com/join/<token>`

- Hosts accepted: `samanpantry.com` and `www.samanpantry.com` (`FamilyInviteLink`).
- Apex redirects to www; AASA cannot follow a redirect, so share links
  use **www**.
- 8-character code: `^[A-HJ-NP-Z2-9]{8}$`. Expires in 7 days. Default
  20 uses, max 50.
- Rate limits: 20 invites created per family per rolling day; 10 failed
  preview/redeem attempts per user per hour.

RPCs: `create_family_invite` (raw token once), `preview_family_invite`,
`redeem_family_invite`. `revoke_family_invite` and `list_family_invites`
exist in SQL; **the iOS app does not call them.**

Associated Domains on the app target: `applinks:samanpantry.com` and
`applinks:www.samanpantry.com`. AASA is hosted on the landing site, not
this repo — see go-steps.

## Snapshot rules

`add_recipe_to_family` copies title, attribution, steps, and ingredient
phrases through `family_recipe_snapshot`. `source_url` is copied only
when `source_kind = 'url'` and `raw_transcript` is an http(s) URL.
Spoken or pasted words are not copied.

A trigger on `recipes` (`sync_family_recipes`) updates snapshots when
the author edits, and deletes family rows when the author deletes the
source recipe. Members never receive `raw_transcript`
(`FamilyRecipe.memberFieldKeys`).

**Known gap on `main`:** `FamilyRecipeDetailView.saveCopy()` inserts a
local `Recipe` with `sourceKind: .transcript` when there is no
`sourceUrl`. Transcript-kind recipes auto-publish to Community. Open
draft [#79](https://github.com/Pakiboy23/saman-pantry-ios/pull/79) would
force a private `.url` copy. Do not document that fix as shipped.
`recipes.copied_from` is a column with no Swift writer.

## Display names

`user_accounts.display_name`: trimmed, 1–40 characters.
RPC `set_my_display_name`. Labels fall back to the email local-part,
then `"A cook"`.

Family name: 1–60 characters. Notes: 1–2000 characters.

## Limits (SQL)

- 50 members per family
- 20 families a user may join
- 5 families a user may own

## Schema (engineer map)

Tables: `families`, `family_members`, `family_invites`, `family_recipes`,
`family_recipe_notes`, `family_invite_attempts` (no client access).

RLS: members SELECT; no direct INSERT on families/members/invites
(RPCs only). `public.is_family_member` / `is_family_owner` were dropped
in the follow-up migration; policies call `private.*`.

RPCs the app calls today: `create_family`, `create_family_invite`,
`preview_family_invite`, `redeem_family_invite`, `remove_family_member`,
`transfer_family_ownership`, `delete_family`, `add_recipe_to_family`,
`set_my_display_name`.

Account deletion: trigger `handoff_families_on_user_delete` transfers
ownership to the longest-standing member, or the family goes away with
the last owner. Snapshots can remain after the author is gone
(`added_by` may become null). No RevenueCat customer delete in-repo.

## iOS files

- `Saman/Core/Services/FamilyService.swift`
- `Saman/Features/Recipes/FamilyViews.swift`
- `Saman/Features/Recipes/RecipesView.swift` (shelf + deep link)
- `Saman/SamaanApp.swift` (`routeFamilyJoin`)
- `SamanTests/FamilyBookTests.swift`

SQL tests: `supabase/tests/family_books_setup.sql`,
`family_books_security.sql` (plain SQL, rolls back).

## Not applied yet

Family migrations and the webhook are on `main` and are **not** live
until Haaris applies them. Agents do not `db push` or deploy.
