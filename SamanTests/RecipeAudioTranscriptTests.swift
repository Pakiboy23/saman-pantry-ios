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

    // MARK: - Transcript accumulation (live recording + file)

    @Test func utteranceAccumulatorKeepsEarlierSegmentsAfterAPause() {
        var accumulator = RecipeTranscriptAccumulator()
        accumulator.applyUtterance(segment: "chicken karahi bahut easy hai", isFinal: false)
        #expect(accumulator.fullText == "chicken karahi bahut easy hai")

        accumulator.applyUtterance(segment: "chicken karahi bahut easy hai", isFinal: true)
        #expect(accumulator.fullText == "chicken karahi bahut easy hai")

        // Next recognizer task starts fresh after silence — must not wipe the first sentence.
        accumulator.applyUtterance(segment: "do tablespoon oil", isFinal: false)
        #expect(accumulator.fullText == "chicken karahi bahut easy hai do tablespoon oil")

        accumulator.applyUtterance(segment: "do tablespoon oil garam masala", isFinal: false)
        #expect(accumulator.fullText == "chicken karahi bahut easy hai do tablespoon oil garam masala")

        accumulator.applyUtterance(segment: "do tablespoon oil garam masala", isFinal: true)
        #expect(accumulator.fullText == "chicken karahi bahut easy hai do tablespoon oil garam masala")
    }

    @Test func utteranceAccumulatorDoesNotDuplicateIdenticalFinal() {
        var accumulator = RecipeTranscriptAccumulator()
        accumulator.applyUtterance(segment: "put haldi", isFinal: true)
        accumulator.applyUtterance(segment: "put haldi", isFinal: true)
        #expect(accumulator.fullText == "put haldi")
        #expect(accumulator.committedSegments == ["put haldi"])
    }

    @Test func cumulativeFileResultsGrowWithinOneTask() {
        var accumulator = RecipeTranscriptAccumulator()
        accumulator.applyCumulative(segment: "put oil", isFinal: false)
        accumulator.applyCumulative(segment: "put oil in the pan", isFinal: false)
        #expect(accumulator.fullText == "put oil in the pan")

        accumulator.applyCumulative(segment: "put oil in the pan", isFinal: true)
        #expect(accumulator.fullText == "put oil in the pan")
        #expect(accumulator.committedSegments == ["put oil in the pan"])
    }

    @Test func cumulativeFileResultsAppendWhenRecognizerResets() {
        var accumulator = RecipeTranscriptAccumulator()
        accumulator.applyCumulative(segment: "first heat the oil", isFinal: true)
        #expect(accumulator.fullText == "first heat the oil")

        // A later segment that does not extend the committed text (reset-style).
        accumulator.applyCumulative(segment: "then add the chicken", isFinal: false)
        #expect(accumulator.fullText == "first heat the oil then add the chicken")

        accumulator.applyCumulative(segment: "then add the chicken", isFinal: true)
        #expect(accumulator.fullText == "first heat the oil then add the chicken")
    }

    @Test func replacingOnlyLatestSegmentIsTheBugWeFixed() {
        // Mimic the old bug: assigning formattedString overwrites prior speech.
        var broken = ""
        broken = "chicken karahi bahut easy hai"
        broken = "do tablespoon oil"
        #expect(broken == "do tablespoon oil")

        var fixed = RecipeTranscriptAccumulator()
        fixed.applyUtterance(segment: "chicken karahi bahut easy hai", isFinal: true)
        fixed.applyUtterance(segment: "do tablespoon oil", isFinal: true)
        #expect(fixed.fullText == "chicken karahi bahut easy hai do tablespoon oil")
    }
}
