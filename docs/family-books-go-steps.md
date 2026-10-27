# Family cookbooks (1.6): go-steps

Nothing here is applied, deployed, or configured yet. Each step needs Haaris's go.

## 1. Database (project mcknboqvblbonmaebmjg)
Two files, applied in order:
- `supabase/migrations/20261024000000_family_books.sql`: tables, RLS, RPCs.
  Passed on a dev branch on Oct 24 (about 12:02 to 12:10 AM ET).
- `supabase/migrations/20261024010000_family_books_followup.sql`:
  - `user_accounts.display_name` (trimmed, 1 to 40 characters) and the `set_my_display_name` RPC.
    Member and recipe labels use the name, then the part of the email before @, then "A cook".
  - `is_family_member` and `is_family_owner` move to a `private` schema that the API doesn't expose.
    The public versions are dropped, and the RPCs and policies now call the private ones.
  - Indexes on `family_invites.created_by`, `family_recipe_notes.author_id` and `family_recipes.added_by`,
    a primary key on `family_invite_attempts`, and `(select auth.uid())` in policies.

1. Validate on a Supabase dev branch: apply both migrations, then run
   `supabase/tests/family_books_setup.sql` and `family_books_security.sql` in the SQL editor or psql.
   Both files are plain SQL now, with no `\set` or `\echo`. The security file passes if it finishes
   with no error, and it rolls back either way. Check the security and performance advisors: the
   `is_family_member` and `is_family_owner` warnings and the four performance items should be gone.
2. Production: `supabase db push --project-ref mcknboqvblbonmaebmjg`, or apply the two files in order
   in the SQL editor. Only these files. 010 is not applied on prod and is not part of this step.

## 2. RevenueCat webhook Edge Function
1. `supabase secrets set REVENUECAT_WEBHOOK_AUTH=<long random string> --project-ref mcknboqvblbonmaebmjg`
   (`REVENUECAT_SECRET_API_KEY` is already set for extract-recipe.)
2. `supabase functions deploy revenuecat-webhook --no-verify-jwt --project-ref mcknboqvblbonmaebmjg`
3. RevenueCat > project Saman (proje8d554d5) > Integrations > Webhooks > Add:
   URL `https://mcknboqvblbonmaebmjg.supabase.co/functions/v1/revenuecat-webhook`,
   Authorization header = the same secret, all events, production + sandbox.
4. Send a test event; it should return 200 with `matched: 0`.
5. Backfill current Pro users once (set `user_accounts.is_pro` from RevenueCat customers),
   or have each Pro user reopen the app after a renewal event. Grandfathered users can already create families.

## 3. Apple
1. Developer portal > Identifiers > com.samanpantry.Saman > enable Associated Domains, regenerate profiles
   (Xcode Cloud uses automatic signing).
2. Merge the saman-landing PR so `https://samanpantry.com/.well-known/apple-app-site-association`
   serves JSON with team `6KTSZRW2J6`.

## 4. App Privacy (App Store Connect)
Families store a display name the user chooses (or, if blank, the part of the email before @), family names, notes and recipe snapshots
linked to the user. No contacts or invitee emails are collected; invites are a code or link shared by the user.
Review "User Content: Other User Content" (linked to user, app functionality) before submitting 1.6.
