import AVFoundation
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Saman

struct RecipeAudioTranscriptTests {
    @Test func spokenWordsAreReadyForTheExistingExtract() {
        #expect(RecipeAudioTranscript.readyForExtract("  put haldi andaza se  ") == "put haldi andaza se")
        #expect(RecipeAudioTranscript.readyForExtract("   \n") == nil)
        #expect(RecipeAudioTranscript.readyForExtract("") == nil)
    }

    @Test func audioFileLocationIsNotATranscript() {
        #expect(RecipeAudioTranscript.readyForExtract("file:///tmp/mom.m4a") == nil)
        #expect(RecipeAudioTranscript.readyForExtract("/tmp/samaan-recipe-audio.m4a") == nil)
        #expect(RecipeAudioTranscript.readyForExtract("/tmp/samaan-recipe-audio.mp3") == nil)
        #expect(RecipeAudioTranscript.readyForExtract("haldi") == "haldi")
    }

    @Test func recordingIgnoresATypedLinkAndUsesTheTranscript() {
        let route = RecipeCaptureRoute.route(
            linkRaw: "https://www.youtube.com/watch?v=abc",
            transcriptRaw: "put haldi andaza se",
            fromAudio: true
        )
        #expect(route == .transcript("put haldi andaza se"))
    }

    @Test func pastedLinkStillWinsOverPastedWords() {
        let route = RecipeCaptureRoute.route(
            linkRaw: "https://www.youtube.com/watch?v=abc",
            transcriptRaw: "put haldi andaza se",
            fromAudio: false
        )
        #expect(route == .url("https://www.youtube.com/watch?v=abc"))
    }

    @Test func pastedURLInTheTextFieldStillExtractsAsALink() {
        let route = RecipeCaptureRoute.route(
            linkRaw: "",
            transcriptRaw: "https://example.com/chicken-karahi",
            fromAudio: false
        )
        #expect(route == .url("https://example.com/chicken-karahi"))
    }

    @Test func spokenURLStaysOnTheTranscriptPath() {
        let route = RecipeCaptureRoute.route(
            linkRaw: "",
            transcriptRaw: "https://example.com/chicken-karahi",
            fromAudio: true
        )
        #expect(route == .transcript("https://example.com/chicken-karahi"))
    }

    @Test func invalidLinkDoesNotFallThroughToPastedWords() {
        let route = RecipeCaptureRoute.route(
            linkRaw: "not a link",
            transcriptRaw: "put haldi andaza se",
            fromAudio: false
        )
        #expect(route == .invalidLink)
    }

    @Test func pickerAcceptsAudioAndNotPlainText() {
        let ids = Set(RecipeAudioFile.acceptedTypes.map(\.identifier))
        #expect(ids.contains(UTType.audio.identifier))
        #expect(ids.contains(UTType.mp3.identifier))
        #expect(!ids.contains(UTType.plainText.identifier))
        #expect(!ids.contains(UTType.image.identifier))
    }

    @Test func familyCardStillOmitsRawTranscriptAndRecordings() throws {
        #expect(!FamilyRecipeBookCard.publicFieldKeys.contains("raw_transcript"))
        #expect(!FamilyRecipeBookCard.publicFieldKeys.contains { $0.contains("audio") || $0.contains("recording") })
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let card = try String(
            contentsOf: repoRoot.appendingPathComponent("Saman/Features/Recipes/FamilyRecipeCardDetailView.swift"),
            encoding: .utf8
        )
        #expect(card.contains("Never shows raw_transcript"))
        #expect(!card.contains("rawTranscript"))
        #expect(!card.contains("AVAudio"))
        let capture = try String(
            contentsOf: repoRoot.appendingPathComponent("Saman/Features/Recipes/RecipeCaptureView.swift"),
            encoding: .utf8
        )
        #expect(capture.contains("extract(recording:"))
        #expect(capture.contains("prepareUpload(from:"))
        #expect(capture.contains(".fileImporter"))
        #expect(capture.contains("extract(transcript:"))
        #expect(capture.contains("extract(url:"))
        #expect(capture.contains("captureAlertTitle"))
    }

    /// `failure` prefers the server-reported source over the caller's route, falling back when absent or unknown.
    @MainActor @Test func noRecipeResponseUsesServerRouteWithLegacyFallback() {
        let cases: [(String, RecipeExtractionRoute, String)] = [
            (#"{"code":"no_recipe_text","error":"No recipe"}"#, .transcript, "Couldn't find a recipe"),
            (#"{"code":"no_recipe_text","error":"No recipe"}"#, .url, "Couldn't open that link"),
            (#"{"code":"no_recipe_text","source":"url"}"#, .transcript, "Couldn't open that link"),
            (#"{"code":"no_recipe_text","source":"transcript"}"#, .url, "Couldn't find a recipe"),
            (#"{"code":"no_recipe_text","source":"unknown"}"#, .transcript, "Couldn't find a recipe"),
        ]
        for (body, route, title) in cases {
            let error = RecipeExtractionService.failure(status: 422, data: Data(body.utf8), route: route)
            #expect(error.captureAlertTitle == title)
        }
    }

    @Test func transcriptNoRecipeUsesVoiceCopyAndLinkNoRecipeKeepsLinkCopy() {
        let voice = RecipeExtractionService.ExtractionError.noRecipeText(.transcript)
        let link = RecipeExtractionService.ExtractionError.noRecipeText(.url)
        #expect(voice.captureAlertTitle == "Couldn't find a recipe")
        #expect(voice.localizedDescription == "I only caught part of that. Try recording again, or type the ingredients and steps.")
        #expect(voice.localizedDescription.contains("link") == false)
        #expect(link.captureAlertTitle == "Couldn't open that link")
        #expect(link.localizedDescription == "Couldn't find a recipe in that link. Paste the description or caption text and I'll try from that.")
    }

    // MARK: - Server transcription (recording upload)

    @Test func noOnDeviceSpeechRecognitionRemains() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let recorder = try String(
            contentsOf: repoRoot.appendingPathComponent("Saman/Core/Services/RecipeAudioRecorder.swift"),
            encoding: .utf8
        )
        #expect(!recorder.contains("import Speech"))
        #expect(!recorder.contains("SFSpeech"))
        let project = try String(
            contentsOf: repoRoot.appendingPathComponent("Saman.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        #expect(!project.contains("NSSpeechRecognitionUsageDescription"))
        #expect(project.contains("NSMicrophoneUsageDescription"))
    }

    @MainActor @Test func uploadPlanSendsAACAndMP3AsTheyAreAndReencodesTheRest() {
        let small = 1_000_000
        #expect(RecipeAudioFile.uploadPlan(fileExtension: "m4a", byteCount: small) == .direct(mimeType: "audio/mp4"))
        #expect(RecipeAudioFile.uploadPlan(fileExtension: "M4A", byteCount: small) == .direct(mimeType: "audio/mp4"))
        #expect(RecipeAudioFile.uploadPlan(fileExtension: "aac", byteCount: small) == .direct(mimeType: "audio/aac"))
        #expect(RecipeAudioFile.uploadPlan(fileExtension: "mp3", byteCount: small) == .direct(mimeType: "audio/mpeg"))
        #expect(RecipeAudioFile.uploadPlan(fileExtension: "wav", byteCount: small) == .transcode)
        #expect(RecipeAudioFile.uploadPlan(fileExtension: "aiff", byteCount: small) == .transcode)
        #expect(RecipeAudioFile.uploadPlan(fileExtension: "caf", byteCount: small) == .transcode)
        #expect(RecipeAudioFile.uploadPlan(fileExtension: "m4a", byteCount: RecipeAudioFile.maxUploadBytes + 1) == .transcode)
        #expect(RecipeAudioFile.uploadPlan(fileExtension: "m4a", byteCount: 0) == .transcode)
    }

    @MainActor @Test func recordingLimitsMatchTheServer() {
        #expect(RecipeAudioFile.maxDuration == 600)
        #expect(RecipeAudioFile.warnAfter < RecipeAudioFile.maxDuration)
        #expect(RecipeAudioFile.maxUploadBytes < 12 * 1024 * 1024)
        // Ten minutes of mono AAC at 32 kbps is far under the cap.
        let bitRate = RecipeAudioFile.recordingSettings[AVEncoderBitRateKey] as? Int ?? 0
        #expect(bitRate > 0)
        #expect(Int(RecipeAudioFile.maxDuration) * bitRate / 8 < RecipeAudioFile.maxUploadBytes)
        #expect(RecipeAudioFile.recordingSettings[AVNumberOfChannelsKey] as? Int == 1)
    }

    @MainActor @Test func clockAndLevelFormatting() {
        #expect(RecipeAudioFile.clock(0) == "0:00")
        #expect(RecipeAudioFile.clock(65.9) == "1:05")
        #expect(RecipeAudioFile.clock(600) == "10:00")
        #expect(RecipeAudioRecorder.normalizedLevel(-160) == 0)
        #expect(RecipeAudioRecorder.normalizedLevel(0) == 1)
        #expect(RecipeAudioRecorder.normalizedLevel(-25) == 0.5)
        #expect(RecipeAudioRecorder.normalizedLevel(.nan) == 0)
    }

    @MainActor @Test func uploadNameNeverCarriesThePickedFileName() {
        let recording = RecipeRecording(url: URL(fileURLWithPath: "/tmp/Ammi's dal 2024.MP3"), mimeType: "audio/mpeg")
        #expect(recording.uploadFilename == "recording.mp3")
    }

    @MainActor @Test func multipartBodyHasOneAudioPart() throws {
        let audio = Data([0x00, 0x01, 0x02])
        let body = RecipeExtractionService.multipartBody(
            audio: audio, filename: "recording.m4a", mimeType: "audio/mp4", boundary: "b0undary"
        )
        let head = "--b0undary\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"recording.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n"
        let tail = "\r\n--b0undary--\r\n"
        #expect(body == Data(head.utf8) + audio + Data(tail.utf8))
    }

    @MainActor @Test func audioErrorCodesMapToTheirOwnCases() {
        func map(_ status: Int, _ json: String) -> RecipeExtractionService.ExtractionError {
            RecipeExtractionService.failure(status: status, data: Data(json.utf8), route: .audio)
        }
        let tooLarge = map(413, #"{"code":"audio_too_large","error":"x"}"#)
        #expect(tooLarge.captureAlertTitle == "Couldn't send the recording")
        #expect(!tooLarge.keepsRecordingForRetry)
        let tooLargeNoBody = map(413, "")
        #expect(tooLargeNoBody.captureAlertTitle == "Couldn't send the recording")
        let unsupported = map(415, #"{"code":"audio_unsupported_type","error":"x"}"#)
        #expect(!unsupported.keepsRecordingForRetry)
        let noSpeech = map(422, #"{"code":"audio_no_speech","error":"x","source":"audio"}"#)
        #expect(noSpeech.captureAlertTitle == "Didn't catch that")
        #expect(!noSpeech.keepsRecordingForRetry)
        let sttDown = map(502, #"{"code":"transcription_failed","error":"x","source":"audio"}"#)
        #expect(sttDown.captureAlertTitle == "Couldn't read the recording")
        #expect(sttDown.keepsRecordingForRetry)
        #expect(map(402, #"{"code":"quota_exceeded"}"#).keepsRecordingForRetry)
        #expect(map(503, #"{"code":"entitlement_unavailable","error":"Could not verify subscription. Try again."}"#).keepsRecordingForRetry)
    }

    @MainActor @Test func noRecipeInARecordingHandsTheWordsBack() {
        let body = #"{"code":"no_recipe_text","source":"audio","error":"x","transcript":"we talked about the weather"}"#
        let error = RecipeExtractionService.failure(status: 422, data: Data(body.utf8), route: .audio)
        guard case .noRecipeInRecording(let transcript) = error else {
            Issue.record("expected noRecipeInRecording, got \(error)")
            return
        }
        #expect(transcript == "we talked about the weather")
        #expect(error.captureAlertTitle == "Couldn't find a recipe")
        #expect(error.localizedDescription.contains("box below"))
        #expect(!error.keepsRecordingForRetry)

        let withoutWords = RecipeExtractionService.failure(
            status: 422, data: Data(#"{"code":"no_recipe_text","source":"audio"}"#.utf8), route: .audio
        )
        #expect(withoutWords.localizedDescription == "I only caught part of that. Try recording again, or type the ingredients and steps.")
    }

    @MainActor @Test func consentAsksEveryoneAgainAndNamesBothProviders() {
        #expect(AIProcessingConsent.storageKey != "samaan.consent.anthropicExtraction.v1")
        #expect(AIProcessingConsent.message.contains("ElevenLabs"))
        #expect(AIProcessingConsent.message.contains("Anthropic"))
        #expect(!AIProcessingConsent.message.contains("transcribed on your iPhone"))
        #expect(!AIProcessingConsent.message.contains("not uploaded"))
        #expect(!AIProcessingConsent.message.contains("\u{2014}"))
    }
}
