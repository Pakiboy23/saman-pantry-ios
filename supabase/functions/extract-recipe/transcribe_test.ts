import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  createTranscriptionProvider,
  ELEVENLABS_STT_ENDPOINT,
  TranscriptionError,
  transcriptionConfigFromEnv,
} from "./transcribe.ts";
import { DESI_KEYTERMS, ingredientMapForPrompt } from "./vocabulary.ts";

function env(values: Record<string, string>) {
  return { get: (key: string) => values[key] };
}

Deno.test("config defaults to ElevenLabs scribe_v2 with keyterms off", () => {
  const config = transcriptionConfigFromEnv(env({ ELEVENLABS_API_KEY: "k" }));
  assertEquals(config?.provider, "elevenlabs");
  assertEquals(config?.model, "scribe_v2");
  assertEquals(config?.keyterms, false);
});

Deno.test("config prefers the uppercase secret and falls back to lowercase", () => {
  assertEquals(transcriptionConfigFromEnv(env({ ELEVENLABS_API_KEY: "upper", elevenlabs_api_key: "lower" }))?.apiKey, "upper");
  assertEquals(transcriptionConfigFromEnv(env({ elevenlabs_api_key: "lower" }))?.apiKey, "lower");
  assertEquals(transcriptionConfigFromEnv(env({ ELEVENLABS_API_KEY: "  " })), null);
  assertEquals(transcriptionConfigFromEnv(env({})), null);
});

Deno.test("unknown provider is unconfigured", () => {
  assertEquals(transcriptionConfigFromEnv(env({ TRANSCRIBE_PROVIDER: "whisper", ELEVENLABS_API_KEY: "k" })), null);
  assertEquals(transcriptionConfigFromEnv(env({ TRANSCRIBE_PROVIDER: "ElevenLabs", ELEVENLABS_API_KEY: "k" }))?.provider, "elevenlabs");
});

Deno.test("provider times out with an AbortController", async () => {
  const provider = createTranscriptionProvider({
    provider: "elevenlabs",
    model: "scribe_v2",
    apiKey: "k",
    keyterms: false,
    timeoutMs: 10,
    fetchImpl: (_url, init) =>
      new Promise((_resolve, reject) => {
        init.signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
      }),
  });
  const error = await assertRejects(() => provider.transcribe(new Blob([new Uint8Array(4)]), "a.m4a"), TranscriptionError);
  assertEquals(error.reason, "timeout");
});

Deno.test("provider forwards bytes as a Blob to the speech-to-text endpoint", async () => {
  let seen: { url: string; body: unknown } | null = null;
  const provider = createTranscriptionProvider({
    provider: "elevenlabs",
    model: "scribe_v2",
    apiKey: "k",
    keyterms: false,
    fetchImpl: (url, init) => {
      seen = { url, body: init.body };
      return Promise.resolve(Response.json({ text: "hello", language_code: "urd" }));
    },
  });
  const result = await provider.transcribe(new Blob([new Uint8Array([1, 2, 3])], { type: "audio/mp4" }), "a.m4a");
  assertEquals(result, { text: "hello", languageCode: "urd", provider: "elevenlabs", model: "scribe_v2" });
  assert(seen);
  const { url, body } = seen as { url: string; body: unknown };
  assertEquals(url, ELEVENLABS_STT_ENDPOINT);
  assert(body instanceof FormData);
  const file = body.get("file");
  assert(file instanceof File);
  assertEquals(new Uint8Array(await file.arrayBuffer()), new Uint8Array([1, 2, 3]));
});

Deno.test("prompt map is byte-identical to the pre-refactor rule 3 text", () => {
  assertEquals(
    ingredientMapForPrompt(),
    "haldi -> turmeric, pyaaz -> onion, zeera/jeera -> cumin, lehsun -> garlic, adrak -> ginger, tamatar -> tomato, dhaniya -> cilantro/coriander, chawal -> rice, doodh -> milk, cheeni -> sugar, elaichi -> cardamom, namak -> salt, laal mirch -> red chili, gobi -> cauliflower, aloo -> potato, dahi -> yogurt",
  );
});

Deno.test("keyterms are the spoken forms, each five words or fewer", () => {
  assert(DESI_KEYTERMS.includes("zeera"));
  assert(DESI_KEYTERMS.includes("jeera"));
  assertEquals(DESI_KEYTERMS.includes("cumin"), false);
  for (const term of DESI_KEYTERMS) assert(term.split(/\s+/).length <= 5);
});
