import { assert, assertEquals } from "jsr:@std/assert@1";
import { pageSystemPrompt, systemPrompt, transcriptUserText } from "./prompts.ts";
import { ingredientMapForPrompt } from "./vocabulary.ts";

Deno.test("speech prompt keeps rules 1 to 3 and adds the transcript rules in order", () => {
  const order = [
    "RULE 1 - NEVER INVENT A NUMBER.",
    "RULE 2 - NEVER DISCARD HER WORDS.",
    "RULE 3 - MAP THE NAME FOR THE GROCERY LIST.",
    "RULE 4 - REPAIR A MISHEARD INGREDIENT ONLY WHEN CONTEXT SUPPORTS IT.",
    "RULE 5 - A REPEATED PHRASE IS NOT A SECOND INGREDIENT.",
    "RULE 6 - ONLY THE RECIPE.",
    "Return ONLY valid JSON",
  ];
  let at = -1;
  for (const marker of order) {
    const next = systemPrompt.indexOf(marker);
    assert(next > at, `${marker} missing or out of order`);
    at = next;
  }
  assert(systemPrompt.includes("original_phrase stays exactly as the transcript has it. Never repair it."));
  assert(systemPrompt.includes("Say so in notes"));
  assert(systemPrompt.includes("Never repeat unrelated personal details"));
});

Deno.test("both prompts carry the shared vocabulary", () => {
  assert(systemPrompt.includes(`(${ingredientMapForPrompt()})`));
  assert(pageSystemPrompt.includes(`(${ingredientMapForPrompt()})`));
  assert(systemPrompt.includes("bhindi -> okra"));
});

Deno.test("page prompt does not get the speech-recognition rules", () => {
  assertEquals(pageSystemPrompt.includes("RULE 4"), false);
  assertEquals(pageSystemPrompt.includes("speech recognition"), false);
});

Deno.test("transcript user text wraps the transcript unchanged", () => {
  assertEquals(
    transcriptUserText("ek pyaaz"),
    "Transcript:\n\nek pyaaz\n\nReturn the structured recipe as JSON.",
  );
});
