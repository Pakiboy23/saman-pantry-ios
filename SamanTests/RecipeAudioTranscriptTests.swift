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

    @Test func openingWordCorrectionReplacesThePartial() {
        var accumulator = RecipeTranscriptAccumulator()
        accumulator.applyUtterance(segment: "Eat", isFinal: false, taskID: 1)
        accumulator.applyUtterance(segment: "Heat the", isFinal: false, taskID: 1)
        accumulator.applyUtterance(segment: "Heat the oil", isFinal: true, taskID: 1)
        #expect(accumulator.fullText == "Heat the oil")
        #expect(accumulator.committedSegments == ["Heat the oil"])
    }

    @Test func unrelatedShortUtteranceKeepsThePreviousWords() {
        var accumulator = RecipeTranscriptAccumulator()
        accumulator.applyUtterance(segment: "Oil", isFinal: false, taskID: 1)
        accumulator.applyUtterance(segment: "Add the chicken", isFinal: false, taskID: 1)
        #expect(accumulator.fullText == "Oil Add the chicken")
        #expect(accumulator.committedSegments == ["Oil"])
        #expect(!RecipeTranscriptAccumulator.continuesSameUtterance("Heat the oil", "Eat the rice"))
    }

    /// Overlapping audio ranges mark a correction, so the final wording wins even when the opening word changes.
    @Test func sameAudioCorrectionsReplaceWordsEvenWhenTheOpeningChanges() {
        var accumulator = RecipeTranscriptAccumulator()
        accumulator.applyUtterance(segment: "Heat the oil until hot", isFinal: false, audioRange: 0..<2)
        accumulator.applyUtterance(segment: "Heat the ghee until melted", isFinal: false, audioRange: 0..<2.5)
        accumulator.applyUtterance(segment: "Eat the ghee until melted", isFinal: true, audioRange: 0..<2.5)
        #expect(accumulator.fullText == "Eat the ghee until melted")
        #expect(accumulator.committedSegments.count == 1)
    }

    /// Non-overlapping audio ranges keep both utterances, even if they share an opening or are identical.
    @Test func laterAudioKeepsSharedOpeningsAndIdenticalInstructions() {
        for final in [false, true] {
            for next in ["Add the chicken", "Add the oil", "Add the oil slowly"] {
                var accumulator = RecipeTranscriptAccumulator()
                accumulator.applyUtterance(segment: "Add the oil", isFinal: false, audioRange: 0..<1)
                accumulator.applyUtterance(segment: next, isFinal: final, audioRange: 2..<3)
                #expect(accumulator.fullText == "Add the oil " + next)
            }
        }
    }

    /// Without audio timestamps, the word-based fallback still keeps two steps that share an opening.
    @Test func missingTimestampsDoNotDiscardSharedOpeningInstructions() {
        for final in [false, true] {
            var accumulator = RecipeTranscriptAccumulator()
            accumulator.applyUtterance(segment: "Add the oil", isFinal: false)
            accumulator.applyUtterance(segment: "Add the chicken", isFinal: final)
            #expect(accumulator.fullText == "Add the oil Add the chicken")
        }
        #expect(!RecipeTranscriptAccumulator.continuesSameUtterance("Add oil", "Add ghee to the pan"))
        #expect(RecipeTranscriptAccumulator.continuesSameUtterance("Heat the oil", "Heat the"))
    }

    /// `applyCumulative` with audio ranges resolves file-result corrections the same way as live utterances.
    @Test func fileCorrectionsAndLaterUtterancesUseAudioTiming() {
        var accumulator = RecipeTranscriptAccumulator()
        accumulator.applyCumulative(segment: "Add the coil", isFinal: false, audioRange: 0..<1)
        accumulator.applyCumulative(segment: "Add the oil", isFinal: false, audioRange: 0..<1)
        accumulator.applyCumulative(segment: "Add the chicken", isFinal: true, audioRange: 2..<3)
        #expect(accumulator.fullText == "Add the oil Add the chicken")
    }

    /// An empty final result must not erase the last non-empty partial.
    @Test func emptyFinalKeepsTheLastPartial() {
        var session = RecipeRecognitionSession()
        session.start()
        let generation = session.openTask()
        _ = session.applyCallback(generation: generation, text: "Add salt", isFinal: false, failed: false)
        _ = session.beginStop()
        #expect(session.applyCallback(generation: generation, text: "", isFinal: true, failed: false) == .finish("Add salt"))
    }

    /// Cancelling while the speech-access prompt is pending must stop recording or file import once it resolves.
    @MainActor @Test func cancellationDuringPermissionWaitStopsRecordingAndFileImport() async {
        for importFile in [false, true] {
            var permission: CheckedContinuation<Bool, Never>?
            var transcriber: RecipeAudioTranscriber?
            var work: Task<Void, Error>?
            await withCheckedContinuation { (entered: CheckedContinuation<Void, Never>) in
                let service = RecipeAudioTranscriber(speechAccess: {
                    await withCheckedContinuation { pending in
                        permission = pending
                        entered.resume()
                    }
                })
                transcriber = service
                work = Task {
                    if importFile {
                        _ = try await service.transcribeFile(at: URL(fileURLWithPath: "/unused.caf"))
                    } else {
                        try await service.startRecording()
                    }
                }
            }
            transcriber?.cancelRecording()
            permission?.resume(returning: true)
            do {
                try await work?.value
                Issue.record("Cancelled permission request must not start recognition")
            } catch {
                #expect(error is CancellationError)
            }
            #expect(transcriber?.isRecording == false)
            #expect(transcriber?.partialTranscript == "")
        }
    }

    @Test func completedStopRetiresFinalAndFailedTasks() {
        for failed in [false, true] {
            for text in ["Heat the oil", ""] {
                var session = RecipeRecognitionSession()
                session.start()
                let generation = session.openTask()
                let stopID = session.beginStop()
                let effect = session.applyCallback(
                    generation: generation, text: text, isFinal: !failed, failed: failed
                )
                if failed && text.isEmpty {
                    #expect(effect == .failed)
                } else {
                    #expect(effect == .finish(text))
                }
                #expect(session.generation > generation)
                #expect(!session.isStopping)
                let saved = session.accumulator
                #expect(session.applyCallback(
                    generation: generation, text: "late partial", isFinal: false, failed: false
                ) == .ignored)
                #expect(session.applyCallback(
                    generation: generation, text: "late final", isFinal: true, failed: false
                ) == .ignored)
                #expect(session.accumulator == saved)
                #expect(session.finishStopWithoutFinal(stopID: stopID) == nil)
            }
        }
    }

    @Test func newTakeDoesNotReuseCancelledTaskGeneration() {
        var session = RecipeRecognitionSession()
        session.start()
        let oldGeneration = session.openTask()
        session.cancel()
        let retiredGeneration = session.generation
        session.start()
        #expect(session.generation == retiredGeneration)
        let newGeneration = session.openTask()
        #expect(newGeneration > retiredGeneration)
        #expect(session.applyCallback(
            generation: oldGeneration, text: "previous take", isFinal: true, failed: false
        ) == .ignored)
        #expect(session.applyCallback(
            generation: newGeneration, text: "new take", isFinal: false, failed: false
        ) == .updated("new take"))
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

    /// A final segment that only adds punctuation should replace the partial, not duplicate it.
    @Test func punctuationCorrectionsDoNotCreateDuplicateInstructions() {
        var accumulator = RecipeTranscriptAccumulator()
        accumulator.applyUtterance(segment: "Add the oil", isFinal: false)
        accumulator.applyUtterance(segment: "Add the oil.", isFinal: true)
        #expect(accumulator.fullText == "Add the oil.")
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
