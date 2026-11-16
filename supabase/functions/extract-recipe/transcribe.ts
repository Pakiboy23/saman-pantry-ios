import { DESI_KEYTERMS } from "./vocabulary.ts";

// Server-side speech-to-text for recorded recipes. The engine is a server
// setting (TRANSCRIBE_PROVIDER / ELEVENLABS_STT_MODEL) so it can change
// without an app release. Audio is forwarded as a Blob and never stored or
// logged here. Callers log sizes, timings, and status codes only.

export interface TranscriptionResult {
  text: string;
  languageCode?: string;
  provider: string;
  model: string;
}

export interface TranscriptionProvider {
  readonly provider: string;
  readonly model: string;
  transcribe(audio: Blob, filename: string): Promise<TranscriptionResult>;
}

/** Provider error, timeout, or unreadable reply. Never carries audio or text. */
export class TranscriptionError extends Error {
  constructor(
    message: string,
    readonly providerStatus: number | null,
    readonly reason: "http_error" | "timeout" | "network" | "bad_reply",
  ) {
    super(message);
    this.name = "TranscriptionError";
  }
}

export type FetchLike = (url: string, init: RequestInit) => Promise<Response>;

export type TranscriptionConfig = {
  provider: "elevenlabs";
  model: string;
  apiKey: string;
  keyterms: boolean;
  timeoutMs?: number;
  fetchImpl?: FetchLike;
};

export const DEFAULT_TRANSCRIBE_PROVIDER = "elevenlabs";
export const DEFAULT_ELEVENLABS_STT_MODEL = "scribe_v2";
export const TRANSCRIBE_TIMEOUT_MS = 60_000;
export const ELEVENLABS_STT_ENDPOINT = "https://api.elevenlabs.io/v1/speech-to-text";

type EnvReader = { get(key: string): string | undefined };

/**
 * Reads the transcription settings. Returns null when the provider is unknown
 * or its key is missing; the caller answers with the existing "not
 * configured" 500 before any quota or paid call.
 */
export function transcriptionConfigFromEnv(env: EnvReader = Deno.env): TranscriptionConfig | null {
  const provider = (env.get("TRANSCRIBE_PROVIDER")?.trim() || DEFAULT_TRANSCRIBE_PROVIDER).toLowerCase();
  if (provider !== "elevenlabs") return null;

  // The owner saved the secret in lowercase and may rename it later.
  const apiKey = env.get("ELEVENLABS_API_KEY")?.trim() || env.get("elevenlabs_api_key")?.trim() || "";
  if (!apiKey) return null;

  return {
    provider,
    model: env.get("ELEVENLABS_STT_MODEL")?.trim() || DEFAULT_ELEVENLABS_STT_MODEL,
    apiKey,
    keyterms: isOn(env.get("TRANSCRIBE_KEYTERMS")),
  };
}

function isOn(value: string | undefined): boolean {
  return ["1", "true", "on", "yes"].includes((value ?? "").trim().toLowerCase());
}

export function createTranscriptionProvider(config: TranscriptionConfig): TranscriptionProvider {
  switch (config.provider) {
    case "elevenlabs":
      return new ElevenLabsProvider(config);
    default: {
      const unreachable: never = config.provider;
      throw new Error(`Unknown transcription provider: ${unreachable}`);
    }
  }
}

class ElevenLabsProvider implements TranscriptionProvider {
  readonly provider = "elevenlabs";
  readonly model: string;
  readonly #apiKey: string;
  readonly #keyterms: boolean;
  readonly #timeoutMs: number;
  readonly #fetch: FetchLike;

  constructor(config: TranscriptionConfig) {
    this.model = config.model;
    this.#apiKey = config.apiKey;
    this.#keyterms = config.keyterms;
    this.#timeoutMs = config.timeoutMs ?? TRANSCRIBE_TIMEOUT_MS;
    this.#fetch = config.fetchImpl ?? ((url, init) => fetch(url, init));
  }

  async transcribe(audio: Blob, filename: string): Promise<TranscriptionResult> {
    const form = new FormData();
    form.append("model_id", this.model);
    form.append("file", audio, filename);
    form.append("tag_audio_events", "false");
    if (this.#keyterms) {
      // Keyterms bill about 20% more. Off unless the test set shows it helps.
      for (const term of DESI_KEYTERMS) form.append("keyterms", term);
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.#timeoutMs);
    let response: Response;
    try {
      response = await this.#fetch(ELEVENLABS_STT_ENDPOINT, {
        method: "POST",
        headers: { "xi-api-key": this.#apiKey },
        body: form,
        signal: controller.signal,
      });
    } catch (error) {
      if (controller.signal.aborted) {
        throw new TranscriptionError("Transcription timed out.", null, "timeout");
      }
      throw new TranscriptionError(
        error instanceof Error ? error.name : "Transcription request failed.",
        null,
        "network",
      );
    } finally {
      clearTimeout(timer);
    }

    if (!response.ok) {
      // Drain without reading the reply into logs or errors.
      await response.body?.cancel();
      throw new TranscriptionError("Transcription provider failed.", response.status, "http_error");
    }

    let payload: { text?: unknown; language_code?: unknown };
    try {
      payload = await response.json();
    } catch {
      throw new TranscriptionError("Transcription reply was not JSON.", response.status, "bad_reply");
    }
    if (typeof payload?.text !== "string") {
      throw new TranscriptionError("Transcription reply had no text.", response.status, "bad_reply");
    }

    return {
      text: payload.text,
      languageCode: typeof payload.language_code === "string" ? payload.language_code : undefined,
      provider: this.provider,
      model: this.model,
    };
  }
}
