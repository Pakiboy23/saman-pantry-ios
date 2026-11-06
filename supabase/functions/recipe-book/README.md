# Family recipe book (local acceptance harness)

This harness is the **public community book** (`recipe_book_cards`). Private
invite-only cookbooks are a different surface: [`docs/family-cookbooks.md`](../../../docs/family-cookbooks.md).

`008_recipe_book.sql` is the original community-book migration. `012_recipe_book_url_opt_in.sql` lets an owner opt a URL recipe in. The owner applies both; do not apply them from agents.

`recipe_book.ts` mirrors the publish rules so Linux CI can run the A / Sally cases without an iOS simulator or production Supabase:

```bash
deno test --allow-read supabase/functions/recipe-book/recipe_book_test.ts
```

Reading the book does not write to `recipe_extraction_events`. URL extracts stay private unless `share_in_family_book` is true. A shared link card may include `source_url`. Transcript cards never expose `raw_transcript`.

## Database authorization regression

The TypeScript harness does not exercise PostgreSQL RLS or privileged triggers.
Use an **empty disposable PostgreSQL 17 database**, with a superuser connection:

```bash
psql -X -v ON_ERROR_STOP=1 "$TEST_DATABASE_URL" -f supabase/tests/recipe_book_security_setup.sql
psql -X -v ON_ERROR_STOP=1 "$TEST_DATABASE_URL" -f supabase/tests/recipe_book_security.sql
psql -X -v ON_ERROR_STOP=1 "$TEST_DATABASE_URL" -f supabase/migrations/010_recipe_book_card_ownership.sql
psql -X -v ON_ERROR_STOP=1 "$TEST_DATABASE_URL" -f supabase/tests/recipe_book_security.sql
psql -X -v ON_ERROR_STOP=1 "$TEST_DATABASE_URL" -f supabase/tests/recipe_book_url_opt_in.sql
psql -X -v ON_ERROR_STOP=1 "$TEST_DATABASE_URL" -f supabase/migrations/012_recipe_book_url_opt_in.sql
psql -X -v ON_ERROR_STOP=1 "$TEST_DATABASE_URL" -f supabase/tests/recipe_book_security.sql
```

`recipe_book_url_opt_in.sql` applies `012` inside its own transaction and rolls it back, so the disposable database is still on `010` afterward. The following `012` apply leaves the opt-in trigger in place, and the last security pass checks that the older publication and collision cases still hold.

The setup creates minimal synthetic auth roles and tables; never run it against
production. Tests run as `authenticated` and roll back their fixture data.
They cover cross-owner ID collisions on recipe insert/update/delete, unchanged
victim cards and notes, and normal publication, privacy flips and owner deletion.

For installations that already applied `008`, the owner must apply
`010_recipe_book_card_ownership.sql` to install the hardened trigger function,
then `012_recipe_book_url_opt_in.sql` for the link opt-in. Do not run either
against production from an agent.
