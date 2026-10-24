# Family cookbooks (1.6): go-steps

Nothing here is applied, deployed, or configured yet. Each step needs Haaris's go.

## 1. Database (project mcknboqvblbonmaebmjg)
1. Validate on a Supabase dev branch first: apply `supabase/migrations/20261024000000_family_books.sql`,
   run `supabase/tests/family_books_setup.sql` then `family_books_security.sql` in a disposable DB
   (expect `family_books_security: ok`), and check the security advisor.
2. Production: `supabase db push --project-ref mcknboqvblbonmaebmjg` (or apply the one file in the SQL editor).
   Only this file. 010 is not applied on prod and is not part of this step.

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
Families store a display label (the part of the email before @), family names, notes and recipe snapshots
linked to the user. No contacts or invitee emails are collected; invites are a code or link shared by the user.
Review "User Content: Other User Content" (linked to user, app functionality) before submitting 1.6.
