// Desi ingredient vocabulary shared by the extraction prompts (rule 3) and the
// transcription provider (optional keyterms). One list so the words the model
// is told to map are the same words the recognizer is biased toward.
//
// Changing this list changes both prompts. Run the recording test set first.

export type DesiIngredient = {
  /** Spoken forms, as a desi speaker says them. */
  heard: readonly string[];
  /** English grocery-list term. */
  english: string;
};

export const DESI_INGREDIENTS: readonly DesiIngredient[] = [
  { heard: ["haldi"], english: "turmeric" },
  { heard: ["pyaaz"], english: "onion" },
  { heard: ["zeera", "jeera"], english: "cumin" },
  { heard: ["lehsun"], english: "garlic" },
  { heard: ["adrak"], english: "ginger" },
  { heard: ["tamatar"], english: "tomato" },
  { heard: ["dhaniya"], english: "cilantro/coriander" },
  { heard: ["chawal"], english: "rice" },
  { heard: ["doodh"], english: "milk" },
  { heard: ["cheeni"], english: "sugar" },
  { heard: ["elaichi"], english: "cardamom" },
  { heard: ["namak"], english: "salt" },
  { heard: ["laal mirch"], english: "red chili" },
  { heard: ["gobi"], english: "cauliflower" },
  { heard: ["aloo"], english: "potato" },
  { heard: ["dahi"], english: "yogurt" },
];

/** Rule 3 map as it appears in the prompts: "haldi -> turmeric, ...". */
export function ingredientMapForPrompt(): string {
  return DESI_INGREDIENTS
    .map((entry) => `${entry.heard.join("/")} -> ${entry.english}`)
    .join(", ");
}

/** Spoken forms only. ElevenLabs keyterms must be five words or fewer each. */
export const DESI_KEYTERMS: readonly string[] = DESI_INGREDIENTS.flatMap((entry) => entry.heard);
