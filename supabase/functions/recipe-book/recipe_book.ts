/** Pure publish rules for the public family recipe book.
 *  Mirrors supabase/migrations/008_recipe_book.sql so Linux CI can exercise
 *  the A / Sally cases without an iOS simulator or production Supabase.
 */

export type SourceKind = "transcript" | "url";

export type ExtractedIngredient = {
  ingredient: string;
  original_phrase: string;
  amount?: number | null;
  unit?: string | null;
  vague?: boolean;
};

export type ExtractedRecipe = {
  title: string;
  attribution?: string | null;
  ingredients: ExtractedIngredient[];
  steps: string[];
  notes?: string | null;
};

export type RecipeRow = {
  id: string;
  user_id: string;
  title: string;
  raw_transcript: string;
  extracted_json: string | null;
  attribution: string | null;
  source_kind: SourceKind;
  created_at: string;
  updated_at: string;
};

export type RecipeBookCard = {
  id: string;
  owner_id: string;
  title: string;
  attribution: string | null;
  steps: string[];
  ingredient_phrases: string[];
  added_by_label: string;
  created_at: string;
  updated_at: string;
};

export type RecipeBookNote = {
  id: string;
  card_id: string;
  author_id: string;
  body: string;
  created_at: string;
};

export type ShoppingList = {
  id: string;
  user_id: string;
  name: string;
  items: string[];
};

export function shouldPublishToBook(sourceKind: SourceKind): boolean {
  return sourceKind === "transcript";
}

export function cardFromRecipe(
  recipe: RecipeRow,
  addedByLabel: string,
): RecipeBookCard | null {
  if (!shouldPublishToBook(recipe.source_kind)) return null;

  let parsed: ExtractedRecipe = {
    title: recipe.title,
    ingredients: [],
    steps: [],
  };
  if (recipe.extracted_json) {
    try {
      parsed = JSON.parse(recipe.extracted_json) as ExtractedRecipe;
    } catch {
      // Keep empty steps / phrases; never fall back to raw_transcript.
    }
  }

  return {
    id: recipe.id,
    owner_id: recipe.user_id,
    title: recipe.title,
    attribution: recipe.attribution,
    steps: Array.isArray(parsed.steps) ? [...parsed.steps] : [],
    ingredient_phrases: (parsed.ingredients ?? []).map((ing) =>
      ing.original_phrase || ing.ingredient || ""
    ),
    added_by_label: addedByLabel,
    created_at: recipe.created_at,
    updated_at: recipe.updated_at,
  };
}

/** Card payload never includes the raw transcript or recording. */
export function publicCardFields(card: RecipeBookCard): Record<string, unknown> {
  return {
    id: card.id,
    owner_id: card.owner_id,
    title: card.title,
    attribution: card.attribution,
    steps: card.steps,
    ingredient_phrases: card.ingredient_phrases,
    added_by_label: card.added_by_label,
    created_at: card.created_at,
    updated_at: card.updated_at,
  };
}

export function labelFromEmail(email: string | null | undefined): string {
  const local = (email ?? "").split("@")[0]?.trim() ?? "";
  return local || "A cook in the village";
}

export class LocalRecipeBookStore {
  recipes = new Map<string, RecipeRow>();
  cards = new Map<string, RecipeBookCard>();
  notes = new Map<string, RecipeBookNote>();
  lists = new Map<string, ShoppingList>();
  extractionEvents: { user_id: string; created_at: string }[] = [];
  emails = new Map<string, string>();

  readonly extractPerDay = 5;

  upsertRecipe(recipe: RecipeRow): void {
    this.recipes.set(recipe.id, { ...recipe });
    this.syncCard(recipe);
  }

  deleteRecipe(id: string, asUserId: string): boolean {
    const row = this.recipes.get(id);
    if (!row || row.user_id !== asUserId) return false;
    this.recipes.delete(id);
    this.cards.delete(id);
    for (const [noteId, note] of [...this.notes.entries()]) {
      if (note.card_id === id) this.notes.delete(noteId);
    }
    return true;
  }

  private syncCard(recipe: RecipeRow): void {
    if (!shouldPublishToBook(recipe.source_kind)) {
      this.cards.delete(recipe.id);
      return;
    }
    const card = cardFromRecipe(
      recipe,
      labelFromEmail(this.emails.get(recipe.user_id)),
    );
    if (card) this.cards.set(card.id, card);
  }

  /** Owner-only recipe read (003_recipes.sql). */
  ownerRecipes(userId: string): RecipeRow[] {
    return [...this.recipes.values()]
      .filter((r) => r.user_id === userId)
      .sort((a, b) => b.created_at.localeCompare(a.created_at));
  }

  /** Authenticated family book: cards only, newest first. */
  bookForSignedInUser(_userId: string): RecipeBookCard[] {
    return [...this.cards.values()].sort((a, b) =>
      b.created_at.localeCompare(a.created_at)
    );
  }

  cardForSignedInUser(cardId: string, _userId: string): RecipeBookCard | null {
    return this.cards.get(cardId) ?? null;
  }

  addNote(cardId: string, authorId: string, body: string): RecipeBookNote | null {
    if (!this.cards.has(cardId)) return null;
    const trimmed = body.trim();
    if (!trimmed) return null;
    const note: RecipeBookNote = {
      id: crypto.randomUUID(),
      card_id: cardId,
      author_id: authorId,
      body: trimmed,
      created_at: new Date().toISOString(),
    };
    this.notes.set(note.id, note);
    return note;
  }

  notesForCard(cardId: string): RecipeBookNote[] {
    return [...this.notes.values()]
      .filter((n) => n.card_id === cardId)
      .sort((a, b) => a.created_at.localeCompare(b.created_at));
  }

  /** Adding missing ingredients writes only that reader's own list. */
  addIngredientsToOwnList(
    userId: string,
    listName: string,
    phrases: string[],
  ): ShoppingList {
    const list: ShoppingList = {
      id: crypto.randomUUID(),
      user_id: userId,
      name: listName,
      items: [...phrases],
    };
    this.lists.set(list.id, list);
    return list;
  }

  listsFor(userId: string): ShoppingList[] {
    return [...this.lists.values()].filter((l) => l.user_id === userId);
  }

  tryExtract(userId: string, now = new Date()): { ok: true } | { ok: false; code: "quota_exceeded" } {
    const since = now.getTime() - 24 * 60 * 60 * 1000;
    const count = this.extractionEvents.filter(
      (e) => e.user_id === userId && Date.parse(e.created_at) >= since,
    ).length;
    if (count >= this.extractPerDay) {
      return { ok: false, code: "quota_exceeded" };
    }
    this.extractionEvents.push({
      user_id: userId,
      created_at: now.toISOString(),
    });
    return { ok: true };
  }

  /** Opening the book must not consume a quota slot. */
  openBook(userId: string): RecipeBookCard[] {
    return this.bookForSignedInUser(userId);
  }
}
