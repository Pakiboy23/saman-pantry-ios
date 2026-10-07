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
        #expect(capture.contains("captureAlertTitle"))
    }

    // MARK: - Transcript accumulation (live recording + file)

    @Test func utteranceAccumulatorKeepsEarlierSegmentsAfterAPause() {
        var accumulator = RecipeTranscriptAccumulator()
        accumulator.applyUtterance(segment: "chicken karahi bahut easy hai", isFinal: false, taskID: 1)
        #expect(accumulator.fullText == "chicken karahi bahut easy hai")

        accumulator.applyUtterance(segment: "chicken karahi bahut easy hai", isFinal: true, taskID: 1)
        #expect(accumulator.fullText == "chicken karahi bahut easy hai")

        // Next recognizer task starts fresh after silence — must not wipe the first sentence.
        accumulator.applyUtterance(segment: "do tablespoon oil", isFinal: false, taskID: 2)
        #expect(accumulator.fullText == "chicken karahi bahut easy hai do tablespoon oil")

        accumulator.applyUtterance(segment: "do tablespoon oil garam masala", isFinal: false, taskID: 2)
        #expect(accumulator.fullText == "chicken karahi bahut easy hai do tablespoon oil garam masala")

        accumulator.applyUtterance(segment: "do tablespoon oil garam masala", isFinal: true, taskID: 2)
        #expect(accumulator.fullText == "chicken karahi bahut easy hai do tablespoon oil garam masala")
    }

    @Test func utteranceAccumulatorDoesNotDuplicateIdenticalFinalFromTheSameTask() {
        var accumulator = RecipeTranscriptAccumulator()
        accumulator.applyUtterance(segment: "put haldi", isFinal: true, taskID: 1)
        accumulator.applyUtterance(segment: "put haldi", isFinal: true, taskID: 1)
        #expect(accumulator.fullText == "put haldi")
        #expect(accumulator.committedSegments == ["put haldi"])
    }

    @Test func utteranceAccumulatorKeepsRepeatedPhraseFromALaterTask() {
        var accumulator = RecipeTranscriptAccumulator()
        accumulator.applyUtterance(segment: "put haldi", isFinal: true, taskID: 1)
        accumulator.applyUtterance(segment: "put haldi", isFinal: true, taskID: 2)
        #expect(accumulator.fullText == "put haldi put haldi")
        #expect(accumulator.committedSegments == ["put haldi", "put haldi"])
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

    @Test func commitVolatileKeepsInFlightWordsBeforeARestart() {
        var accumulator = RecipeTranscriptAccumulator()
        accumulator.applyUtterance(segment: "first heat the oil", isFinal: true, taskID: 1)
        accumulator.applyUtterance(segment: "then add the chicken", isFinal: false, taskID: 2)
        accumulator.commitVolatile(taskID: 2)
        #expect(accumulator.fullText == "first heat the oil then add the chicken")
        accumulator.applyUtterance(segment: "and the tomatoes", isFinal: true, taskID: 3)
        #expect(accumulator.fullText == "first heat the oil then add the chicken and the tomatoes")
    }

    @Test func cumulativeFileResetWhileNothingCommittedKeepsEarlierSpan() {
        var accumulator = RecipeTranscriptAccumulator()
        accumulator.applyCumulative(segment: "first heat the oil", isFinal: false)
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

    @Test func partialResetAfterAPauseKeepsTheEarlierSentence() {
        var accumulator = RecipeTranscriptAccumulator()
        accumulator.applyUtterance(segment: "Heat the oil and add the chicken.", isFinal: false, taskID: 1)
        accumulator.applyUtterance(
            segment: "But some of it crushed up really fine and some of it not",
            isFinal: false,
            taskID: 1
        )
        #expect(accumulator.fullText == "Heat the oil and add the chicken. But some of it crushed up really fine and some of it not")
    }

    @Test func growingPartialStaysOneUtterance() {
        var accumulator = RecipeTranscriptAccumulator()
        accumulator.applyUtterance(segment: "Heat the oil", isFinal: false, taskID: 1)
        accumulator.applyUtterance(segment: "Heat the oil and add the chicken", isFinal: false, taskID: 1)
        #expect(accumulator.committedSegments.isEmpty)
        #expect(accumulator.fullText == "Heat the oil and add the chicken")
    }

    @Test func stopWithoutAFinalKeepsFirstSentenceAndLastPartial() {
        var session = RecipeRecognitionSession()
        session.start()
        let first = session.openTask()
        _ = session.applyCallback(generation: first, text: "First heat the oil.", isFinal: true, failed: false)
        let second = session.openTask()
        _ = session.applyCallback(
            generation: second,
            text: "But some of it crushed up really fine and some of it not",
            isFinal: false,
            failed: false
        )
        let stopID = session.beginStop()
        let text = session.finishStopWithoutFinal(stopID: stopID)
        #expect(text == "First heat the oil. But some of it crushed up really fine and some of it not")
        let dropped = session.applyCallback(generation: second, text: "this arrived too late", isFinal: true, failed: false)
        #expect(dropped == .ignored)
        #expect(session.accumulator.fullText.contains("too late") == false)
    }

    @Test func finalAfterStopKeepsEarlierSentencesAndTheCompletedLastOne() {
        var session = RecipeRecognitionSession()
        session.start()
        let first = session.openTask()
        let restart = session.applyCallback(generation: first, text: "Heat the oil.", isFinal: true, failed: false)
        #expect(restart == .restart("Heat the oil."))
        let second = session.openTask()
        _ = session.applyCallback(generation: second, text: "Add the chicken", isFinal: false, failed: false)
        let stopID = session.beginStop()
        let finished = session.applyCallback(
            generation: second,
            text: "Add the chicken and tomatoes.",
            isFinal: true,
            failed: false
        )
        switch finished {
        case .finish(let text):
            #expect(text == "Heat the oil. Add the chicken and tomatoes.")
        case .updated, .restart, .failed, .ignored:
            #expect(finished == .finish("Heat the oil. Add the chicken and tomatoes."))
        }
        #expect(session.finishStopWithoutFinal(stopID: stopID) == nil)
        let stale = session.applyCallback(generation: first, text: "nope", isFinal: true, failed: false)
        #expect(stale == .ignored)
    }

    @Test func errorBeforeRestartCommitsTheInFlightPartial() {
        var session = RecipeRecognitionSession()
        session.start()
        let generation = session.openTask()
        _ = session.applyCallback(generation: generation, text: "Heat the oil", isFinal: false, failed: false)
        let effect = session.applyCallback(generation: generation, text: nil, isFinal: false, failed: true)
        #expect(effect == .restart("Heat the oil"))
    }

    @Test func fileTranscriptReplacesALiveLineThatIsShorterThanTheTake() {
        let live = "But some of it crushed up really fine and some of it not"
        let file = "Heat the oil and add the chicken. Cook until browned. But some of it crushed up really fine and some of it not fully cooked."
        let chosen = RecipeTranscriptReconciliation.choose(live: live, fromFile: file, duration: 25)
        #expect(chosen == file)
        #expect(chosen.hasPrefix("Heat the oil"))
        #expect(chosen.contains("not fully cooked"))
        #expect(RecipeTranscriptReconciliation.isClearlyShorterThanTake(live, duration: 25))
        let rewritten = "First heat the oil and then add the chicken and tomatoes and cook the masala down."
        #expect(RecipeTranscriptReconciliation.choose(live: live, fromFile: rewritten, duration: 20) == rewritten)
    }

    @Test func fileTranscriptDoesNotReplaceACompleteLiveTake() {
        let live = "Heat the oil. Add the chicken and tomatoes. Simmer until the masala is done."
        let file = "Heat the oil. Add the chicken and tomatoes. Simmer until the masala is done"
        let chosen = RecipeTranscriptReconciliation.choose(live: live, fromFile: file, duration: 8)
        #expect(chosen == live)
        #expect(RecipeTranscriptReconciliation.choose(live: "", fromFile: file, duration: 8) == file)
        #expect(RecipeTranscriptReconciliation.choose(live: live, fromFile: nil, duration: 8) == live)
        #expect(RecipeTranscriptReconciliation.choose(live: live, fromFile: live, duration: 8) == live)
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
}
