// Recording test set for recipe capture. Gates prompt changes and releases.
//
// Runs each case through the same transcription adapter and extraction prompt
// that extract-recipe uses, then checks the ingredient names. It calls the
// providers directly with this checkout's code, so a prompt change is tested
// before it is deployed.
//
//   ELEVENLABS_API_KEY=... ANTHROPIC_API_KEY=... \
//   deno run --allow-env --allow-read --allow-net \
//     scripts/recipe-eval.ts --manifest ~/samaan-eval/manifest.json
//
// Options:
//   --manifest <path>         Required. Must be outside this repo.
//   --only <id>               Run one case.
//   --save-transcripts <dir>  Write each transcript to <dir>/<id>.txt for
//                             review or reuse as a regression input. Must be
//                             outside this repo. Needs --allow-write.
//
// Engine and prompt settings come from the same env vars as the function:
// TRANSCRIBE_PROVIDER, ELEVENLABS_STT_MODEL, TRANSCRIBE_KEYTERMS,
// ANTHROPIC_MODEL. Compare engines by running twice with different values.
//
// Recordings, transcripts, and manifests never go in this repo. It is public.
// Trim each recording to the recipe first: people keep talking after it ends.
// Output names ingredients only. It never prints transcript text.
//
// Exit codes: 0 all cases pass, 1 any case fails, 2 bad setup.

import { classifyModelRecipe, type StructuredRecipe } from "../supabase/functions/extract-recipe/recipe_source.ts";
import { DEFAULT_ANTHROPIC_MODEL, systemPrompt, transcriptUserText } from "../supabase/functions/extract-recipe/prompts.ts";
import {
  createTranscriptionProvider,
  transcriptionConfigFromEnv,
} from "../supabase/functions/extract-recipe/transcribe.ts";

export type EvalCase = {
  id: string;
  /** Recording path, relative to the manifest. */
  audio?: string;
  /** Plain-text transcript path, relative to the manifest. Skips transcription. */
  transcript?: string;
  must_include: string[];
  must_include_any: string[][];
  must_not_include: string[];
};

export type CheckResult = {
  missing: string[];
  missingAny: string[][];
  unexpected: string[];
};

const AUDIO_TYPES: Record<string, string> = {
  ".m4a": "audio/mp4",
  ".mp4": "audio/mp4",
  ".aac": "audio/aac",
  ".mp3": "audio/mpeg",
  ".wav": "audio/wav",
};

// Mirrors extract-recipe: shorter than this is "no speech".
const MIN_TRANSCRIPT_CHARS = 20;

export class SetupError extends Error {}

// ---------------------------------------------------------------------------
// Manifest

export function parseManifest(raw: unknown): EvalCase[] {
  if (!raw || typeof raw !== "object" || !Array.isArray((raw as { cases?: unknown }).cases)) {
    throw new SetupError('Manifest must be an object with a "cases" array.');
  }
  const seen = new Set<string>();
  return (raw as { cases: unknown[] }).cases.map((entry, index) => {
    const where = `cases[${index}]`;
    if (!entry || typeof entry !== "object") throw new SetupError(`${where} must be an object.`);
    const item = entry as Record<string, unknown>;
    const id = item.id;
    if (typeof id !== "string" || !/^[a-z0-9][a-z0-9_-]*$/i.test(id)) {
      throw new SetupError(`${where}.id must be letters, digits, "-" or "_".`);
    }
    if (seen.has(id)) throw new SetupError(`Duplicate case id "${id}".`);
    seen.add(id);
    const audio = optionalString(item.audio, `${id}.audio`);
    const transcript = optionalString(item.transcript, `${id}.transcript`);
    if (Boolean(audio) === Boolean(transcript)) {
      throw new SetupError(`${id}: set exactly one of "audio" or "transcript".`);
    }
    if (audio && !AUDIO_TYPES[extension(audio)]) {
      throw new SetupError(`${id}: audio must be ${Object.keys(AUDIO_TYPES).join(", ")}.`);
    }
    const mustInclude = stringList(item.must_include ?? [], `${id}.must_include`);
    const mustNot = stringList(item.must_not_include ?? [], `${id}.must_not_include`);
    const anyRaw = item.must_include_any ?? [];
    if (!Array.isArray(anyRaw)) throw new SetupError(`${id}.must_include_any must be an array of arrays.`);
    const mustAny = anyRaw.map((group, i) => {
      const list = stringList(group, `${id}.must_include_any[${i}]`);
      if (list.length === 0) throw new SetupError(`${id}.must_include_any[${i}] is empty.`);
      return list;
    });
    if (mustInclude.length === 0 && mustAny.length === 0 && mustNot.length === 0) {
      throw new SetupError(`${id}: add at least one ingredient check.`);
    }
    return {
      id,
      ...(audio ? { audio } : { transcript }),
      must_include: mustInclude,
      must_include_any: mustAny,
      must_not_include: mustNot,
    };
  });
}

function optionalString(value: unknown, where: string): string | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "string" || !value.trim()) throw new SetupError(`${where} must be a non-empty string.`);
  return value;
}

function stringList(value: unknown, where: string): string[] {
  if (!Array.isArray(value) || value.some((v) => typeof v !== "string" || !v.trim())) {
    throw new SetupError(`${where} must be an array of non-empty strings.`);
  }
  return value as string[];
}

function extension(path: string): string {
  const dot = path.lastIndexOf(".");
  return dot < 0 ? "" : path.slice(dot).toLowerCase();
}

// ---------------------------------------------------------------------------
// Matching. Checks the English `ingredient` field only, never original_phrase,
// so a misheard word kept in the speaker's phrase does not count.

function words(value: string): string[] {
  return value
    .toLowerCase()
    .replace(/chilli/g, "chili")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .split(" ")
    .filter(Boolean);
}

function sameWord(a: string, b: string): boolean {
  return a === b || a === `${b}s` || b === `${a}s` || a === `${b}es` || b === `${a}es`;
}

/** True when every word of `term` appears in order, adjacent, in `ingredient`. Plurals match. */
export function ingredientMatches(ingredient: string, term: string): boolean {
  const have = words(ingredient);
  const want = words(term);
  if (want.length === 0) return false;
  for (let start = 0; start + want.length <= have.length; start++) {
    if (want.every((word, i) => sameWord(have[start + i], word))) return true;
  }
  return false;
}

export function checkIngredients(ingredients: string[], c: EvalCase): CheckResult {
  const has = (term: string) => ingredients.some((name) => ingredientMatches(name, term));
  return {
    missing: c.must_include.filter((term) => !has(term)),
    missingAny: c.must_include_any.filter((group) => !group.some(has)),
    unexpected: c.must_not_include.filter(has),
  };
}

export function passed(result: CheckResult): boolean {
  return result.missing.length === 0 && result.missingAny.length === 0 && result.unexpected.length === 0;
}

export function describeFailure(result: CheckResult): string {
  const parts: string[] = [];
  if (result.missing.length) parts.push(`missing: ${result.missing.join(", ")}`);
  for (const group of result.missingAny) parts.push(`none of: ${group.join(" | ")}`);
  if (result.unexpected.length) parts.push(`unexpected: ${result.unexpected.join(", ")}`);
  return parts.join("; ");
}

// ---------------------------------------------------------------------------
// Paths

export function repoRoot(): string {
  return Deno.realPathSync(new URL("..", import.meta.url));
}

/** Rejects any path inside this repo. Recordings and transcripts stay private. */
export function assertOutsideRepo(path: string, root: string, what: string): string {
  let resolved: string;
  try {
    resolved = Deno.realPathSync(path);
  } catch {
    throw new SetupError(`${what} not found: ${path}`);
  }
  const base = root.endsWith("/") ? root : `${root}/`;
  if (resolved === root || resolved.startsWith(base)) {
    throw new SetupError(`${what} is inside the repo (${resolved}). Keep recordings and transcripts outside it.`);
  }
  return resolved;
}

function dirname(path: string): string {
  const slash = path.lastIndexOf("/");
  return slash <= 0 ? "/" : path.slice(0, slash);
}

function resolveFrom(base: string, path: string): string {
  if (path.startsWith("/")) return path;
  if (path.startsWith("~/")) return `${Deno.env.get("HOME") ?? ""}/${path.slice(2)}`;
  return `${base}/${path}`;
}

// ---------------------------------------------------------------------------
// Providers

async function extract(apiKey: string, transcript: string): Promise<StructuredRecipe | string> {
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: Deno.env.get("ANTHROPIC_MODEL") ?? DEFAULT_ANTHROPIC_MODEL,
      max_tokens: 4096,
      system: systemPrompt,
      messages: [{ role: "user", content: transcriptUserText(transcript) }],
    }),
  });
  const payload = await response.json().catch(() => ({})) as { content?: { type?: string; text?: string }[] };
  if (!response.ok) return `model HTTP ${response.status}`;
  const text = payload.content?.find((block) => block.type === "text")?.text ?? "";
  const classified = classifyModelRecipe(text);
  if (classified.outcome === "recipe") return classified.recipe;
  if (classified.outcome === "no_recipe") return `model found no recipe (${classified.reason})`;
  return "model returned invalid JSON";
}

// ---------------------------------------------------------------------------
// CLI

function parseArgs(args: string[]): { manifest: string; only?: string; saveDir?: string } {
  const out: { manifest?: string; only?: string; saveDir?: string } = {};
  for (let i = 0; i < args.length; i++) {
    const flag = args[i];
    const value = args[i + 1];
    if (!value) throw new SetupError(`Unknown or incomplete option: ${flag}`);
    if (flag === "--manifest") out.manifest = value;
    else if (flag === "--only") out.only = value;
    else if (flag === "--save-transcripts") out.saveDir = value;
    else throw new SetupError(`Unknown option: ${flag}`);
    i++;
  }
  if (!out.manifest) throw new SetupError("Missing --manifest <path>.");
  return out as { manifest: string; only?: string; saveDir?: string };
}

async function main(): Promise<number> {
  const root = repoRoot();
  const args = parseArgs(Deno.args);
  const manifestPath = assertOutsideRepo(resolveFrom(Deno.cwd(), args.manifest), root, "Manifest");
  const saveDir = args.saveDir
    ? assertOutsideRepo(resolveFrom(Deno.cwd(), args.saveDir), root, "Transcript folder")
    : undefined;
  let cases = parseManifest(JSON.parse(await Deno.readTextFile(manifestPath)));
  if (args.only) {
    cases = cases.filter((c) => c.id === args.only);
    if (cases.length === 0) throw new SetupError(`No case with id "${args.only}".`);
  }

  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY")?.trim();
  if (!anthropicKey) throw new SetupError("Set ANTHROPIC_API_KEY.");
  const needsAudio = cases.some((c) => c.audio);
  const sttConfig = transcriptionConfigFromEnv();
  if (needsAudio && !sttConfig) throw new SetupError("Set ELEVENLABS_API_KEY (or check TRANSCRIBE_PROVIDER).");
  const stt = sttConfig ? createTranscriptionProvider(sttConfig) : null;

  const base = dirname(manifestPath);
  console.log(
    `recipe-eval: ${cases.length} case(s), stt ${stt ? `${stt.provider}/${stt.model}` : "none"}` +
      `${sttConfig?.keyterms ? " +keyterms" : ""}, model ${Deno.env.get("ANTHROPIC_MODEL") ?? DEFAULT_ANTHROPIC_MODEL}`,
  );

  let failures = 0;
  for (const c of cases) {
    const started = Date.now();
    let transcript: string;
    try {
      if (c.audio) {
        const path = assertOutsideRepo(resolveFrom(base, c.audio), root, `${c.id} audio`);
        const bytes = await Deno.readFile(path);
        const blob = new Blob([bytes], { type: AUDIO_TYPES[extension(path)] });
        transcript = (await stt!.transcribe(blob, path.slice(path.lastIndexOf("/") + 1))).text.trim();
      } else {
        const path = assertOutsideRepo(resolveFrom(base, c.transcript!), root, `${c.id} transcript`);
        transcript = (await Deno.readTextFile(path)).trim();
      }
    } catch (error) {
      if (error instanceof SetupError) throw error;
      failures++;
      console.log(`FAIL ${c.id}  transcription failed (${error instanceof Error ? error.message : "error"})`);
      continue;
    }
    if (saveDir && c.audio) await Deno.writeTextFile(`${saveDir}/${c.id}.txt`, `${transcript}\n`);
    if (transcript.length < MIN_TRANSCRIPT_CHARS) {
      failures++;
      console.log(`FAIL ${c.id}  no usable speech (${transcript.length} chars)`);
      continue;
    }

    const recipe = await extract(anthropicKey, transcript);
    const seconds = ((Date.now() - started) / 1000).toFixed(1);
    if (typeof recipe === "string") {
      failures++;
      console.log(`FAIL ${c.id}  ${recipe}  ${seconds}s`);
      continue;
    }
    const names = recipe.ingredients.map((i) => String(i.ingredient ?? ""));
    const result = checkIngredients(names, c);
    if (passed(result)) {
      console.log(`PASS ${c.id}  ${names.length} ingredients  ${seconds}s`);
    } else {
      failures++;
      console.log(`FAIL ${c.id}  ${describeFailure(result)}  (got: ${names.join(", ")})  ${seconds}s`);
    }
  }

  console.log(`${cases.length - failures}/${cases.length} passed`);
  return failures === 0 ? 0 : 1;
}

if (import.meta.main) {
  try {
    Deno.exit(await main());
  } catch (error) {
    console.error(`recipe-eval: ${error instanceof Error ? error.message : String(error)}`);
    Deno.exit(error instanceof SetupError ? 2 : 1);
  }
}
