# Family recipe book (local acceptance harness)

`008_recipe_book.sql` is the production migration (owner applies it; do not apply from agents).

`recipe_book.ts` mirrors the publish rules so Linux CI can run the A / Sally cases without an iOS simulator or production Supabase:

```bash
deno test --allow-read supabase/functions/recipe-book/recipe_book_test.ts
```

Reading the book does not write to `recipe_extraction_events`. URL extracts never become cards. Transcript cards never expose `raw_transcript`.

## Database authorization regression

The TypeScript harness does not exercise PostgreSQL RLS or privileged triggers.
Use an **empty disposable PostgreSQL 17 database**, with a superuser connection:

```bash
psql -X -v ON_ERROR_STOP=1 "$TEST_DATABASE_URL" -f supabase/tests/recipe_book_security_setup.sql
psql -X -v ON_ERROR_STOP=1 "$TEST_DATABASE_URL" -f supabase/tests/recipe_book_security.sql
psql -X -v ON_ERROR_STOP=1 "$TEST_DATABASE_URL" -f supabase/migrations/009_recipe_book_card_ownership.sql
psql -X -v ON_ERROR_STOP=1 "$TEST_DATABASE_URL" -f supabase/tests/recipe_book_security.sql
```

The setup creates minimal synthetic auth roles and tables; never run it against
production. Tests run as `authenticated` and roll back their fixture data.
They cover cross-owner ID collisions on recipe insert/update/delete, unchanged
victim cards and notes, and normal publication, privacy flips and owner deletion.

For installations that already applied `008`, the owner must apply
`009_recipe_book_card_ownership.sql` to install the hardened trigger function.
