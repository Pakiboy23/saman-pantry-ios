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
        #expect(capture.contains("runExtraction(fromAudio: true)"))
        #expect(capture.contains("transcribeFile"))
        #expect(capture.contains(".fileImporter"))
        #expect(capture.contains("extract(transcript:"))
        #expect(capture.contains("extract(url:"))
    }
}
