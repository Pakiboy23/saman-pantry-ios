# Family recipe book (local acceptance harness)

`008_recipe_book.sql` is the production migration (owner applies it; do not apply from agents).

`recipe_book.ts` mirrors the publish rules so Linux CI can run the A / Sally cases without an iOS simulator or production Supabase:

```bash
deno test --allow-read supabase/functions/recipe-book/recipe_book_test.ts
```

Reading the book does not write to `recipe_extraction_events`. URL extracts never become cards. Transcript cards never expose `raw_transcript`.
