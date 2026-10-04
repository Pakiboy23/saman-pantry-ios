import { assertEquals, assertExists } from "jsr:@std/assert@1";
import {
  LocalRecipeBookStore,
  publicCardFields,
  type RecipeRow,
} from "./recipe_book.ts";

const A = "user-a-cousin";
const SALLY = "user-sally-georgia";

function transcriptRecipe(overrides: Partial<RecipeRow> & { id: string }): RecipeRow {
  const extracted = {
    title: overrides.title ?? "Chicken Karahi",
    attribution: overrides.attribution ?? "Mom",
    ingredients: [
      {
        ingredient: "turmeric",
        original_phrase: "haldi andaza se",
        amount: null,
        unit: null,
        vague: true,
      },
      {
        ingredient: "chicken",
        original_phrase: "1 kg chicken",
        amount: 1,
        unit: "kg",
        vague: false,
      },
    ],
    steps: ["Heat the oil", "Add chicken and haldi"],
  };
  return {
    id: overrides.id,
    user_id: overrides.user_id ?? A,
    title: overrides.title ?? "Chicken Karahi",
    raw_transcript: overrides.raw_transcript ??
      "Beta listen, chicken karahi… put in haldi andaza se",
    extracted_json: overrides.extracted_json ?? JSON.stringify(extracted),
    attribution: overrides.attribution ?? "Mom",
    source_kind: overrides.source_kind ?? "transcript",
    created_at: overrides.created_at ?? "2026-10-04T12:00:00.000Z",
    updated_at: overrides.updated_at ?? "2026-10-04T12:00:00.000Z",
  };
}

function makeStore(): LocalRecipeBookStore {
  const store = new LocalRecipeBookStore();
  store.emails.set(A, "cousin.a@example.com");
  store.emails.set(SALLY, "sally.smith@example.com");
  return store;
}

Deno.test("1. A's transcript save with andaza and haldi shows on Sally's book with no share tap; words stay as written", () => {
  const store = makeStore();
  store.upsertRecipe(transcriptRecipe({ id: "card-1" }));

  const sallyBook = store.bookForSignedInUser(SALLY);
  assertEquals(sallyBook.length, 1);
  assertEquals(sallyBook[0].title, "Chicken Karahi");
  assertEquals(sallyBook[0].ingredient_phrases.includes("haldi andaza se"), true);
  assertEquals(sallyBook[0].attribution, "Mom");
  assertEquals(sallyBook[0].added_by_label, "cousin.a");
  // No share tap required: publish happened on save.
  assertEquals(store.cards.has("card-1"), true);
});

Deno.test("2. A's url extract does not show for Sally; A still sees it", () => {
  const store = makeStore();
  store.upsertRecipe(transcriptRecipe({
    id: "url-1",
    source_kind: "url",
    raw_transcript: "https://www.youtube.com/watch?v=example",
    title: "YouTube Karahi",
  }));

  assertEquals(store.bookForSignedInUser(SALLY).length, 0);
  const aPrivate = store.ownerRecipes(A);
  assertEquals(aPrivate.length, 1);
  assertEquals(aPrivate[0].title, "YouTube Karahi");
  assertEquals(aPrivate[0].source_kind, "url");
});

Deno.test("3. Sally's card has no raw_transcript", () => {
  const store = makeStore();
  store.upsertRecipe(transcriptRecipe({ id: "card-1" }));
  const card = store.cardForSignedInUser("card-1", SALLY);
  assertExists(card);
  const publicFields = publicCardFields(card!);
  assertEquals("raw_transcript" in publicFields, false);
  assertEquals(JSON.stringify(publicFields).includes("Beta listen"), false);
  assertEquals(JSON.stringify(publicFields).includes("raw_transcript"), false);
});

Deno.test("4. Sally's note does not change A's steps", () => {
  const store = makeStore();
  store.upsertRecipe(transcriptRecipe({ id: "card-1" }));
  const before = [...store.cardForSignedInUser("card-1", A)!.steps];

  const note = store.addNote("card-1", SALLY, "I used less oil");
  assertExists(note);

  const after = store.cardForSignedInUser("card-1", A)!.steps;
  assertEquals(after, before);
  assertEquals(store.notesForCard("card-1")[0].body, "I used less oil");
  assertEquals(store.notesForCard("card-1")[0].author_id, SALLY);
});

Deno.test("5. Sally adding ingredients changes only Sally's list", () => {
  const store = makeStore();
  store.upsertRecipe(transcriptRecipe({ id: "card-1" }));
  const card = store.cardForSignedInUser("card-1", SALLY)!;

  store.addIngredientsToOwnList(SALLY, card.title, card.ingredient_phrases);

  assertEquals(store.listsFor(SALLY).length, 1);
  assertEquals(store.listsFor(SALLY)[0].items.includes("haldi andaza se"), true);
  assertEquals(store.listsFor(A).length, 0);
});

Deno.test("6. A second transcript with the same title is a second card", () => {
  const store = makeStore();
  store.upsertRecipe(transcriptRecipe({
    id: "card-1",
    created_at: "2026-10-04T12:00:00.000Z",
  }));
  store.upsertRecipe(transcriptRecipe({
    id: "card-2",
    created_at: "2026-10-04T13:00:00.000Z",
    raw_transcript: "Different telling, still Chicken Karahi with andaza",
  }));

  const book = store.bookForSignedInUser(SALLY);
  assertEquals(book.length, 2);
  assertEquals(book[0].id, "card-2"); // newest first
  assertEquals(book[1].id, "card-1");
  assertEquals(book[0].title, book[1].title);
});

Deno.test("7. A removes the first card; Sally no longer sees it", () => {
  const store = makeStore();
  store.upsertRecipe(transcriptRecipe({ id: "card-1" }));
  store.upsertRecipe(transcriptRecipe({
    id: "card-2",
    created_at: "2026-10-04T13:00:00.000Z",
  }));

  assertEquals(store.deleteRecipe("card-1", A), true);
  const book = store.bookForSignedInUser(SALLY);
  assertEquals(book.length, 1);
  assertEquals(book[0].id, "card-2");
});

Deno.test("8. A sixth extract in a day still hits the quota; opening the book does not", () => {
  const store = makeStore();
  const now = new Date("2026-10-04T15:00:00.000Z");
  for (let i = 0; i < 5; i++) {
    assertEquals(store.tryExtract(A, now).ok, true);
  }
  assertEquals(store.tryExtract(A, now), { ok: false, code: "quota_exceeded" });

  store.upsertRecipe(transcriptRecipe({ id: "card-1" }));
  const before = store.extractionEvents.length;
  store.openBook(SALLY);
  store.openBook(A);
  assertEquals(store.extractionEvents.length, before);
});
