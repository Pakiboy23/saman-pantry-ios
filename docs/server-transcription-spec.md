# Server transcription for recorded recipes

Status: approved direction, not built. Owner: Haaris. Written 2026-11-16.

This spec replaces on-device speech recognition with server-side transcription
for recorded and imported audio. It is written so a coding agent can build it
in four small PRs. Read `THESIS.md` and `MEMORY.md` first. Where this spec and
`THESIS.md` disagree, stop and ask.

## 1. Why

The recorder does not work for the product's main promise. On 2026-11-16 the
same family recording was run through four engines. The speaker mixes English
with Urdu food words.

| Spoken | Apple on-device (shipping) | Whisper large-v3 | ElevenLabs Scribe v2 |
|---|---|---|---|
| "three packets of frozen bhindi" | "frozen beans" | "frozen Bhindi" | "frozen bhindi" |
| "more in it than bhindi" | "more than Mindy" | "than bindi" | "more in it than bhindi" |
| "one tablespoon of zeera" | "1 tablespoon of 0" | "tablespoon of Cedar" | "one tablespoon of zeera" |
| end of recording | cut off about 20 s early | complete | complete |

Three separate defects in the current path (`RecipeAudioTranscriber.swift`):

1. **Wrong engine.** `SFSpeechRecognizer`, on device, English locale, no
   vocabulary. It cannot produce Urdu or Hindi words. True since #46.
2. **Duplicated text.** Since #49 and #60 the accumulator commits the previous
   partial whenever a new partial is not a word-for-word extension. The
   recognizer revises words constantly, so every revision is appended. A live
   run stored 2,519 characters for about 36 seconds of speech.
3. **Cut-off ending.** The file path returned a transcript missing the last
   20 seconds. Cause not confirmed. It no longer matters once this path is
   removed.

The extraction prompt and model are unchanged since 2026-10-04 and behaved
correctly. They reported honestly on bad transcripts.

## 2. Decisions already made by the owner

- Transcription moves to the server. The on-device promise ends. Privacy copy
  will be updated.
- Engine: **ElevenLabs Scribe v2** (`scribe_v2`). Chosen on independent
  code-switching benchmarks and confirmed on a real recording.
- The engine must be a server setting so it can change without an app release.
- The fix has three parts: new engine, a transcript-aware extraction prompt,
  and a recording test set that gates releases.

## 3. Guardrails

- Nothing goes to App Review without Haaris's explicit OK.
- The owner applies migrations and deploys functions. Do not run
  `supabase db push` or `supabase functions deploy` against production.
- Do not commit recordings, transcripts of real people, or API keys. This
  repo is public.
- Never log audio bytes or transcript text on the server. Log sizes, timings,
  and status codes only.
- Never store audio on the server. It passes through to the provider.
- Delete dead code instead of leaving it. That is the habit in this repo.
- Update `MEMORY.md` and `.claude/skills/samaan-pantry-expert/SKILL.md` in
  each PR that changes what is true.

## 4. Build order

| PR | Scope | Ships to users when |
|---|---|---|
| A | Server: `extract-recipe` accepts audio | Owner deploys. Old app versions are unaffected. |
| B | Prompt: transcript-aware rules, plus the eval script | Owner deploys. Helps old app versions a little. |
| C | iOS: record to file, upload, remove the Apple recognizer | Next App Store release |
| D | Copy and privacy: consent, usage strings, docs, store listing | Same release as C. Owner approves every string. |

A and B are independent. C depends on A being deployed. D lands with C.

## 5. PR A: server

### 5.1 Contract

Same function, `supabase/functions/extract-recipe`. One new request shape.

Request:

- `POST`, `Authorization: Bearer <user JWT>` as today.
- `Content-Type: multipart/form-data` with one part named `audio`.
- Accepted types: `audio/mp4`, `audio/m4a`, `audio/x-m4a`, `audio/aac`,
  `audio/mpeg`, `audio/wav`.
- Max body size: 12 MB. Larger returns `413` with code `audio_too_large`.

The existing JSON shape (`{ transcript }` and `{ url }`) keeps working
unchanged. Old clients must not break.

Response on success, same as today plus the transcript:

```json
{ "recipe": { }, "raw_json": "…", "transcript": "…" }
```

The client stores `transcript` as the recipe's `rawTranscript`.

### 5.2 Order of operations

1. Method, config, and JWT checks. Unchanged.
2. Validate content type and size. Reject before any paid call.
3. `takeQuotaSlot()`. Same entitlement and quota path as a transcript. No slot
   means no transcription. This is what prevents a cost leak.
4. Transcribe with the provider.
5. If transcription fails, or the transcript is empty or under about 20
   characters: release the slot and return an error. Use the same delete on
   `recipe_extraction_events` that the URL route uses for a 422.
   - Provider error or timeout: `502`, code `transcription_failed`.
   - No usable speech: `422`, code `audio_no_speech`, with the existing
     `TRANSCRIPT_NO_RECIPE` message.
6. Run the existing transcript extraction on the text.
7. Model failures follow the existing transcript rule. Do not invent a new
   quota rule for them.

Add `"audio"` to `ExtractRoute`. Check migrations 004, 009, and 011 for a
check constraint on the event route or source column. If one exists, add a
migration and say so in the PR. Do not apply it.

### 5.3 Provider adapter

New file `supabase/functions/extract-recipe/transcribe.ts`.

```ts
export interface TranscriptionResult {
  text: string;
  languageCode?: string;
  provider: string;
  model: string;
}
export interface TranscriptionProvider {
  transcribe(audio: Blob, filename: string): Promise<TranscriptionResult>;
}
```

- `TRANSCRIBE_PROVIDER`, default `elevenlabs`.
- `ELEVENLABS_STT_MODEL`, default `scribe_v2`.
- Key: read `ELEVENLABS_API_KEY`. Fall back to `elevenlabs_api_key`. The
  owner saved the secret in lowercase and may rename it. Missing key returns
  the existing "not configured" 500.
- ElevenLabs call: `POST https://api.elevenlabs.io/v1/speech-to-text`, header
  `xi-api-key`, multipart fields `model_id`, `file`, `tag_audio_events=false`.
  Read `text` and `language_code` from the JSON response.
- Timeout: 60 seconds with `AbortController`. Edge Functions return 504 after
  150 seconds idle.
- Forward the uploaded bytes as a `Blob`. Do not base64 them. The runtime has
  256 MB of memory.
- `TRANSCRIBE_KEYTERMS`, default off. When on, send the desi vocabulary list
  as repeated `keyterms` fields. Keyterms cost 20% more and each must be five
  words or fewer. The first test recording was correct without them. Turn
  this on only if the test set shows it helps.

Keep the vocabulary list in one exported constant so the prompt and the
provider share it. Seed it from the ingredient map in `systemPrompt` rule 3.

### 5.4 Tests

Extend `index_test.ts` with a mocked `fetch`. Cover:

- Multipart request builds the right ElevenLabs call.
- Oversized body returns 413 and makes no provider call and takes no slot.
- Provider failure releases the slot.
- Empty transcript releases the slot and returns `audio_no_speech`.
- Lowercase secret name works as a fallback.
- JSON transcript and URL routes behave exactly as before.

### 5.5 Docs

Update `supabase/functions/README.md` and `docs/billing-and-extract-quota.md`
with the audio route, the new secrets, and the slot-release rule.

## 6. PR B: prompt and eval

### 6.1 Prompt

Add to `systemPrompt`. Keep rules 1 to 3 intact.

- The transcript may come from speech recognition. Words can be misheard.
- `original_phrase` stays exactly as the transcript has it. No repairs there.
- If a word is not a plausible ingredient in context and sounds like a desi
  ingredient, the ingredient name may use the likely word. Say so in `notes`
  in plain words. If context does not support a guess, keep the heard word.
- Ignore speech that is not about the recipe. Never repeat unrelated personal
  details in `notes`, the title, or the steps.

Any prompt change must pass the test set before it merges. The old on-device
transcripts are useful regression inputs: the app still has users on versions
that produce them.

### 6.2 Eval script

A script under `scripts/`, Deno or Python, that:

- Reads a manifest of cases from a path outside the repo.
- For each case, sends the audio to the provider and, optionally, the
  transcript through extraction.
- Checks `must_include` and `must_not_include` ingredient names.
- Prints one line per case and exits non-zero on any failure.

Manifest shape:

```json
{
  "cases": [
    {
      "id": "okra-with-onions",
      "audio": "okra-with-onions.m4a",
      "must_include": ["okra", "onion", "cumin", "salt", "red chili"],
      "must_include_any": [["lemon juice", "vinegar"]],
      "must_not_include": ["beans", "milk"]
    }
  ]
}
```

Recordings live in a private location the owner picks. The repo holds the
script, the manifest schema, and a `.gitignore` entry. It never holds audio
or real transcripts. Trim each recording to the recipe before adding it.
People keep talking after the recipe ends.

Add one line to `docs/APP_STORE_RELEASE_CHECKLIST.md`: the test set passes
before any build goes to review.

## 7. PR C: iOS

### 7.1 Recording

- Record to a file with `AVAudioRecorder`. AAC, mono, 16 kHz, about 32 kbps,
  `.m4a`. Ten minutes is about 2.4 MB.
- Hard stop at 10 minutes. Tell the user before it happens.
- Show a timer and a level meter. Remove the live transcript text. There is
  no live text any more.
- Keep the file until the server returns a recipe. A failed upload must be
  retryable without recording again. Delete the file after success or when
  the user discards the capture.

### 7.2 Choose a recording

- If the file is over the size limit or not AAC or MP3, transcode to the same
  mono AAC settings before upload.
- If it runs past 10 minutes, say so and stop. Do not truncate silently.

### 7.3 Upload

- New `RecipeExtractionService.extract(audioFile:)`. Multipart, user JWT,
  field name `audio`.
- Map the new codes: `audio_too_large`, `audio_no_speech`,
  `transcription_failed`. Reuse the existing 402 paywall path.
- No network: keep the recording and offer retry.
- Progress copy can stay: "Turning your recording into text…" then "Reading
  the recipe…".

### 7.4 Remove

- The `SFSpeechRecognizer` path, `RecipeTranscriptAccumulator`,
  `RecipeTranscriptReconciliation`, and their tests in
  `SamanTests/RecipeAudioTranscriptTests.swift`.
- The speech recognition permission request and
  `NSSpeechRecognitionUsageDescription`.
- The `Speech` framework import if nothing else uses it.

CI compiles with `xcodebuild build-for-testing` and does not run tests. Run
the test target locally before asking for review.

## 8. PR D: copy and privacy

Every string here needs the owner's approval. Draft, do not finalize.

- `AIProcessingConsent`: new storage key so everyone is asked again. The
  message must say that recordings are uploaded, name ElevenLabs for audio and
  Anthropic for text, and drop "transcribed on your iPhone and is not
  uploaded".
- `NSMicrophoneUsageDescription`: drop any claim that audio stays on the phone.
- `PrivacyInfo.xcprivacy`: audio data is now collected for app functionality.
- `docs/PRIVACY_DISCLOSURE_WORKSHEET.md`, `docs/launch/legal-and-privacy.md`,
  `docs/launch/app-store-metadata.md`: remove on-device claims.
- Comment in `FamilyService.swift` about the transcript staying in the cook's
  book: check it is still accurate.
- Outside this repo, for the owner: App Store description, the App Privacy
  answers in App Store Connect, and the privacy page in `saman-landing`.

Retention fact for the policy: ElevenLabs offers zero-retention mode to
enterprise customers only. On a standard plan, assume the provider keeps
request logs and transcripts.

## 9. Open decisions for the owner

1. **Private speech after the recipe.** Recordings can include unrelated
   personal talk. Today the full transcript is stored with the recipe. Options:
   store it as is, show a transcript review before saving, or store only the
   part the model used. The prompt rule in 6.1 covers the recipe output, not
   the stored transcript.
2. **Keyterms on or off.** Decide after the test set has five or more
   recordings.
3. **Old app versions.** They keep the broken on-device path. Decide whether
   to force an update prompt once the new release is live.
4. **Scribe v3.** It exists and accepts secondary language codes. It was also
   correct on the test recording. Evaluate on the test set before switching.

## 10. Acceptance

- The okra recording produces a recipe with okra, onion, cumin, salt, red
  chili, and lemon juice or vinegar. No beans. No milk.
- A user with no free extractions left cannot trigger a provider call.
- A provider outage does not cost the user a slot.
- An old app build sending `{ transcript }` gets the same response as before.
- No audio or transcript text appears in function logs.
- The repo contains no recording and no real person's transcript.
- All on-device transcription claims are gone from the app, the docs, and the
  store listing drafts.

## 11. Cost

Scribe v2 lists at about $0.22 per audio hour. A two-minute recording costs
under one cent. The quota gate and the 12 MB cap bound abuse.
