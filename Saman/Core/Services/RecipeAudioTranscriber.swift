import AVFoundation
import Combine
import Foundation
import Speech
import UniformTypeIdentifiers

/// Text that can go into the existing transcript extract.
/// An audio file location is never a recipe.
enum RecipeAudioTranscript {
    static func readyForExtract(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAudioLocation(trimmed) else { return nil }
        return trimmed
    }

    /// True when the string is a file path or file URL, not spoken words.
    static func isAudioLocation(_ value: String) -> Bool {
        if value.hasPrefix("file://") { return true }
        let lower = value.lowercased()
        let extensions = [".m4a", ".mp3", ".wav", ".caf", ".aiff", ".aac", ".m4b"]
        guard value.hasPrefix("/"), !value.contains(where: \.isWhitespace) else { return false }
        return extensions.contains { lower.hasSuffix($0) }
    }
}

/// Joins finalized speech segments with the current volatile partial.
///
/// On-device `SFSpeechRecognizer` often finalizes after a pause and the next
/// result's `bestTranscription.formattedString` starts fresh. Assigning that
/// string straight onto a single `latestText` keeps only the newest segment.
/// This accumulator keeps every finalized segment and overlays the in-flight one.
struct RecipeTranscriptAccumulator: Equatable {
    private(set) var committedSegments: [String] = []
    private(set) var volatileSegment: String = ""
    private var lastFinalTaskID: Int?

    var fullText: String {
        Self.join(segments: committedSegments + (volatileSegment.isEmpty ? [] : [volatileSegment]))
    }

    /// Live buffer recognition: each task covers one utterance. Partials replace
    /// the volatile segment; a final appends it onto the committed list.
    ///
    /// `taskID` is the recognition task that produced this callback. A second
    /// `isFinal` from the same task is ignored so the recognizer cannot double
    /// the last phrase. The same words from a later task are kept — the cook
    /// may have repeated them after a pause.
    mutating func applyUtterance(segment: String, isFinal: Bool, taskID: Int = 0) {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFinal {
            if !trimmed.isEmpty {
                let duplicateFromSameTask = lastFinalTaskID == taskID && committedSegments.last == trimmed
                if !duplicateFromSameTask {
                    committedSegments.append(trimmed)
                    lastFinalTaskID = taskID
                }
            }
            volatileSegment = ""
        } else {
            // Partials replace the in-flight utterance. A pause can reset that
            // string without isFinal; keep the previous words before replacing.
            if trimmed.isEmpty { return }
            let previous = volatileSegment.trimmingCharacters(in: .whitespacesAndNewlines)
            if !previous.isEmpty, !Self.continuesSameUtterance(previous, trimmed) {
                volatileSegment = ""
                applyUtterance(segment: previous, isFinal: true, taskID: taskID)
            }
            volatileSegment = trimmed
        }
    }

    /// True when `next` is a growth or small rewrite of `previous`, not a new sentence.
    static func continuesSameUtterance(_ previous: String, _ next: String) -> Bool {
        if next.hasPrefix(previous) || previous.hasPrefix(next) { return true }
        let prevWords = words(previous)
        let nextWords = words(next)
        guard !prevWords.isEmpty, !nextWords.isEmpty else { return false }
        var shared = 0
        for pair in zip(prevWords, nextWords) {
            if pair.0 != pair.1 { break }
            shared += 1
        }
        if shared >= 2 { return true }
        if shared >= 1, min(prevWords.count, nextWords.count) <= 3 { return true }
        // A one-word partial can gain or correct its opening sound as it grows
        // ("Eat" -> "Heat the"). Require a matching word tail so an unrelated
        // short utterance is still committed instead of silently replaced.
        if prevWords.count == 1, nextWords.count > 1 {
            let previousWord = prevWords[0]
            let nextWord = nextWords[0]
            if min(previousWord.count, nextWord.count) >= 3 {
                return previousWord == nextWord.dropFirst()
                    || previousWord.dropFirst() == nextWord
                    || previousWord.dropFirst() == nextWord.dropFirst()
            }
        }
        return false
    }

    private static func words(_ value: String) -> [String] {
        value.split(whereSeparator: \.isWhitespace).map { String($0).lowercased() }
    }

    /// Promote the in-flight partial to a committed segment before a task
    /// restart or an empty final, so an error cannot wipe spoken words.
    mutating func commitVolatile(taskID: Int = 0) {
        let trimmed = volatileSegment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        applyUtterance(segment: trimmed, isFinal: true, taskID: taskID)
    }

    /// URL / file recognition: each callback is usually the transcript so far.
    /// When a result resets (shorter / unrelated), treat it as a new utterance.
    mutating func applyCumulative(segment: String, isFinal: Bool) {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if isFinal {
                commitVolatile()
            }
            return
        }

        let committed = Self.join(segments: committedSegments)
        if committed.isEmpty {
            if isFinal {
                // Keep any prior volatile that does not overlap this final.
                if !volatileSegment.isEmpty,
                   trimmed != volatileSegment,
                   !trimmed.hasPrefix(volatileSegment),
                   !volatileSegment.hasPrefix(trimmed) {
                    committedSegments.append(volatileSegment)
                }
                committedSegments.append(trimmed)
                volatileSegment = ""
            } else if !volatileSegment.isEmpty,
                      !trimmed.hasPrefix(volatileSegment),
                      !volatileSegment.hasPrefix(trimmed) {
                // Non-cumulative reset while nothing is committed yet.
                committedSegments.append(volatileSegment)
                volatileSegment = trimmed
            } else {
                volatileSegment = trimmed
            }
            return
        }

        if trimmed == committed || trimmed.hasPrefix(committed) {
            let remainder = trimmed.dropFirst(committed.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if isFinal {
                if !remainder.isEmpty {
                    committedSegments.append(remainder)
                }
                volatileSegment = ""
            } else {
                volatileSegment = remainder
            }
            return
        }

        if committed.hasPrefix(trimmed), !isFinal {
            // Recognition corrected downward; keep committed, clear volatile.
            volatileSegment = ""
            return
        }

        // Fresh utterance after a pause (non-cumulative results).
        applyUtterance(segment: trimmed, isFinal: isFinal)
    }

    mutating func reset() {
        committedSegments = []
        volatileSegment = ""
        lastFinalTaskID = nil
    }

    private static func join(segments: [String]) -> String {
        segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// Picks the transcript to keep after stop.
/// Live recognition can drop sentences across pauses. The saved take is the
/// backup, so a clearly longer file transcript replaces a short live one.
enum RecipeTranscriptReconciliation {
    static func choose(live: String, fromFile: String?, duration: TimeInterval) -> String {
        let liveText = RecipeAudioTranscript.readyForExtract(live) ?? ""
        let fileText = fromFile.flatMap(RecipeAudioTranscript.readyForExtract) ?? ""
        if fileText.isEmpty { return liveText }
        if liveText.isEmpty { return fileText }
        if fileText == liveText { return liveText }
        if fileText.count > liveText.count, extends(fileText, shorter: liveText) { return fileText }
        if liveText.count >= fileText.count, extends(liveText, shorter: fileText) { return liveText }
        if fileText.count > liveText.count {
            let gap = fileText.count - liveText.count
            let ratio = Double(gap) / Double(max(liveText.count, 1))
            if gap >= 24 || ratio >= 0.2 || isClearlyShorterThanTake(liveText, duration: duration) {
                return fileText
            }
        }
        return liveText
    }

    /// Under 8 characters per second on a take of at least 3 seconds is missing speech.
    static func isClearlyShorterThanTake(_ text: String, duration: TimeInterval) -> Bool {
        guard duration >= 3 else { return false }
        return Double(text.count) / duration < 8
    }

    private static func extends(_ longer: String, shorter: String) -> Bool {
        !shorter.isEmpty && (longer.hasPrefix(shorter) || longer.contains(shorter))
    }
}

/// Live recognition state the audio engine drives.
/// Stop does not retire the current task, so the final after `endAudio` can land.
struct RecipeRecognitionSession {
    enum Effect: Equatable {
        case updated(String)
        case restart(String)
        case finish(String)
        case failed
        case ignored
    }

    private(set) var accumulator = RecipeTranscriptAccumulator()
    private(set) var generation = 0
    private(set) var stopID = 0
    var isRecording = false
    var isStopping = false
    private var consecutiveRestartErrors = 0

    mutating func start() {
        accumulator.reset()
        isRecording = true
        isStopping = false
        consecutiveRestartErrors = 0
    }

    mutating func openTask() -> Int {
        generation += 1
        return generation
    }

    /// Returns the id a later timeout must echo. Does not bump `generation`.
    mutating func beginStop() -> Int {
        isRecording = false
        isStopping = true
        stopID += 1
        return stopID
    }

    mutating func cancel() {
        stopID += 1
        isStopping = false
        isRecording = false
        generation += 1
        accumulator.reset()
    }

    mutating func applyCallback(generation taskGeneration: Int, text: String?, isFinal: Bool, failed: Bool) -> Effect {
        guard taskGeneration == generation else { return .ignored }
        if let text {
            accumulator.applyUtterance(segment: text, isFinal: isFinal, taskID: taskGeneration)
        }
        if isFinal {
            consecutiveRestartErrors = 0
            let transcript = accumulator.fullText
            if isRecording, !isStopping {
                return .restart(transcript)
            }
            isStopping = false
            generation += 1
            return .finish(transcript)
        }
        if failed {
            if isRecording, !isStopping {
                accumulator.commitVolatile(taskID: taskGeneration)
                let transcript = accumulator.fullText
                if consecutiveRestartErrors < 3 {
                    consecutiveRestartErrors += 1
                    return .restart(transcript)
                }
                return .updated(transcript)
            }
            let transcript = accumulator.fullText
            isStopping = false
            generation += 1
            if RecipeAudioTranscript.readyForExtract(transcript) != nil {
                return .finish(transcript)
            }
            return .failed
        }
        return .updated(accumulator.fullText)
    }

    /// Commit the in-flight partial when `endAudio` never delivers a final.
    /// A stale timeout (stop already finished, or a newer take started) returns nil.
    mutating func finishStopWithoutFinal(stopID: Int) -> String? {
        guard self.stopID == stopID, isStopping else { return nil }
        isStopping = false
        accumulator.commitVolatile(taskID: generation)
        let text = accumulator.fullText
        generation += 1
        return text
    }
}

/// Audio types the capture screen can open. Not text, and not a photo.
enum RecipeAudioFile {
    static let acceptedTypes: [UTType] = [.audio, .mpeg4Audio, .mp3, .wav, .aiff]
}

enum RecipeAudioError: LocalizedError {
    case speechDenied
    case microphoneDenied
    case recognizerUnavailable
    case onDeviceUnavailable
    case emptyTranscript
    case unreadableFile
    case failed

    var errorDescription: String? {
        switch self {
        case .speechDenied:
            return "Speech recognition is off. Turn it on in Settings so a recording can become a recipe."
        case .microphoneDenied:
            return "The microphone is off. Turn it on in Settings to record a recipe."
        case .recognizerUnavailable:
            return "Speech recognition isn't available right now. Try again in a moment, or paste the words."
        case .onDeviceUnavailable:
            return "On-device speech recognition isn't ready on this iPhone yet. Try again after it downloads, or paste the words."
        case .emptyTranscript:
            return "I didn't catch any words. Record again, choose another recording, or paste the recipe."
        case .unreadableFile:
            return "Couldn't read that recording. Try an m4a, mp3, or wav file, or record it in the app."
        case .failed:
            return "Couldn't transcribe that recording. Try again, or paste the words."
        }
    }
}

/// Holds the live recognition request so the audio tap can follow restarts.
private final class RecognitionRequestSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = self.request
        lock.unlock()
        request?.append(buffer)
    }
}

/// Records in the app, or reads an audio file, and returns words from SFSpeechRecognizer.
/// Recognition stays on device. The recording is not saved onto a recipe or a family-book card.
@MainActor
final class RecipeAudioTranscriber: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var partialTranscript = ""

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recordingGate: ResumeGate<String>?
    private var session = RecipeRecognitionSession()
    private var tapInstalled = false
    private let requestSlot = RecognitionRequestSlot()
    private var recordingFileURL: URL?
    private var recordingFile: AVAudioFile?
    private var recordingFileBox: RecordingFileBox?
    private var isStopping = false

    func startRecording() async throws {
        guard !isRecording, !isStopping else { return }
        let recognizer = try await prepareRecognizer()
        guard await Self.requestMicrophoneAccess() else { throw RecipeAudioError.microphoneDenied }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw RecipeAudioError.failed
        }

        self.session.start()
        partialTranscript = ""
        isStopping = false
        let request = SFSpeechAudioBufferRecognitionRequest()
        configure(request)
        recognitionRequest = request
        requestSlot.set(request)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecipeAudioError.microphoneDenied
        }

        // Keep a temp copy of the mic audio so stop can reconcile a short
        // live transcript against the whole take.
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("samaan-recipe-live-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        recordingFileURL = fileURL
        recordingFile = try? AVAudioFile(forWriting: fileURL, settings: format.settings)

        let slot = requestSlot
        let fileBox = RecordingFileBox(file: recordingFile)
        recordingFileBox = fileBox
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            slot.append(buffer)
            fileBox.write(buffer)
        }
        tapInstalled = true
        audioEngine = engine
        engine.prepare()
        do {
            try engine.start()
        } catch {
            teardownEngine()
            throw RecipeAudioError.failed
        }
        isRecording = true
        listen(recognizer: recognizer, request: request)
    }

    func stopRecording() async throws -> String {
        guard isRecording else { throw RecipeAudioError.emptyTranscript }
        isRecording = false
        isStopping = true
        // Keep the current generation so endAudio's final can still commit
        // the last sentence. Bumping it here was dropping that callback.
        let stopID = session.beginStop()
        parkEngine()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        requestSlot.set(nil)
        let fileURL = recordingFileURL
        defer {
            clearRecordingFile(delete: true)
            isStopping = false
        }
        let live: String = (try? await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate(continuation)
            recordingGate = gate
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let text = self.session.finishStopWithoutFinal(stopID: stopID)
                    ?? self.session.accumulator.fullText
                gate.resume(returning: text)
            }
        }) ?? ""
        recognitionTask?.cancel()
        recognitionTask = nil
        finishTask()
        let duration = fileURL.map(Self.audioDuration(of:)) ?? 0
        var fromFile: String?
        if let url = fileURL {
            // Reconciliation is best effort; imports retain the longer default.
            fromFile = try? await transcribeFile(at: url, timeoutNanoseconds: 5_000_000_000)
        }
        let chosen = RecipeTranscriptReconciliation.choose(live: live, fromFile: fromFile, duration: duration)
        partialTranscript = ""
        if let ready = RecipeAudioTranscript.readyForExtract(chosen) {
            return ready
        }
        throw RecipeAudioError.emptyTranscript
    }

    func cancelRecording() {
        guard isRecording || audioEngine != nil || recognitionTask != nil else { return }
        isRecording = false
        isStopping = true
        session.cancel()
        recordingGate?.resume(returning: "")
        recordingGate = nil
        parkEngine()
        recognitionRequest = nil
        requestSlot.set(nil)
        finishTask()
        clearRecordingFile(delete: true)
        partialTranscript = ""
        isStopping = false
    }

    func transcribeFile(at url: URL, timeoutNanoseconds: UInt64 = 90_000_000_000) async throws -> String {
        guard !isRecording else { throw RecipeAudioError.failed }
        let recognizer = try await prepareRecognizer()
        let request = SFSpeechURLRecognitionRequest(url: url)
        configure(request)
        defer {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        let text: String = try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate(continuation)
            let fileAccumulator = TranscriptAccumulatorBox()
            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    let segment = result.bestTranscription.formattedString
                    let soFar = fileAccumulator.applyCumulative(segment: segment, isFinal: result.isFinal)
                    if result.isFinal {
                        gate.resume(returning: soFar)
                        return
                    }
                }
                if let error {
                    let soFar = fileAccumulator.fullText
                    if RecipeAudioTranscript.readyForExtract(soFar) != nil {
                        gate.resume(returning: soFar)
                    } else {
                        gate.resume(throwing: error)
                    }
                }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                gate.resume(throwing: RecipeAudioError.failed)
            }
        }
        guard let ready = RecipeAudioTranscript.readyForExtract(text) else {
            throw RecipeAudioError.emptyTranscript
        }
        return ready
    }

    /// Copies a security-scoped pick into a temp file the speech recognizer can read.
    /// Caller deletes it. It is never stored on the recipe.
    static func temporaryCopy(of url: URL) throws -> URL {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("samaan-recipe-audio-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            throw RecipeAudioError.unreadableFile
        }
        return dest
    }

    private func prepareRecognizer() async throws -> SFSpeechRecognizer {
        guard await Self.requestSpeechAccess() else { throw RecipeAudioError.speechDenied }
        guard let recognizer = Self.onDeviceRecognizer() else {
            throw RecipeAudioError.onDeviceUnavailable
        }
        guard recognizer.isAvailable else { throw RecipeAudioError.recognizerUnavailable }
        return recognizer
    }

    private func listen(recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest) {
        let generation = session.openTask()
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let callbackError = error
            // Main queue, not unstructured Tasks, so a later partial cannot
            // overtake the final that should commit this utterance.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let effect = self.session.applyCallback(
                        generation: generation,
                        text: text,
                        isFinal: isFinal,
                        failed: callbackError != nil
                    )
                    switch effect {
                    case .updated(let transcript):
                        self.partialTranscript = transcript
                    case .restart(let transcript):
                        self.partialTranscript = transcript
                        self.restartListening(with: recognizer)
                    case .finish(let transcript):
                        self.partialTranscript = transcript
                        self.recordingGate?.resume(returning: transcript)
                    case .failed:
                        let failure = callbackError.map { self.friendly($0) } ?? RecipeAudioError.failed
                        self.recordingGate?.resume(throwing: failure)
                    case .ignored:
                        break
                    }
                }
            }
        }
    }

    private func restartListening(with recognizer: SFSpeechRecognizer) {
        recognitionTask?.cancel()
        recognitionTask = nil
        let request = SFSpeechAudioBufferRecognitionRequest()
        configure(request)
        recognitionRequest = request
        requestSlot.set(request)
        listen(recognizer: recognizer, request: request)
    }

    private static func audioDuration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let rate = file.fileFormat.sampleRate
        guard rate > 0 else { return 0 }
        return Double(file.length) / rate
    }

    private func parkEngine() {
        if tapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine?.stop()
        audioEngine = nil
        // Close the writer so a fallback file transcription can open it.
        recordingFileBox?.close()
        recordingFileBox = nil
        recordingFile = nil
    }

    private func finishTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func teardownEngine() {
        parkEngine()
        recognitionRequest = nil
        requestSlot.set(nil)
        finishTask()
        clearRecordingFile(delete: true)
    }

    private func clearRecordingFile(delete: Bool) {
        recordingFileBox?.close()
        recordingFileBox = nil
        recordingFile = nil
        if delete, let url = recordingFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingFileURL = nil
    }

    private func configure(_ request: SFSpeechRecognitionRequest) {
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
    }

    private func friendly(_ error: Error) -> Error {
        if error is RecipeAudioError { return error }
        let ns = error as NSError
        if ns.domain == "kAFAssistantErrorDomain", [203, 216, 1110].contains(ns.code) {
            return RecipeAudioError.emptyTranscript
        }
        let message = ns.localizedDescription.lowercased()
        if message.contains("on-device") || message.contains("not available") {
            return RecipeAudioError.onDeviceUnavailable
        }
        return RecipeAudioError.failed
    }

    private static func onDeviceRecognizer() -> SFSpeechRecognizer? {
        let locales = [Locale.current, Locale(identifier: "en-US")]
        for locale in locales {
            guard let recognizer = SFSpeechRecognizer(locale: locale),
                  recognizer.supportsOnDeviceRecognition else { continue }
            return recognizer
        }
        return nil
    }

    private static func requestSpeechAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private static func requestMicrophoneAccess() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}


/// Thread-safe box around `RecipeTranscriptAccumulator` for recognition callbacks.
private final class TranscriptAccumulatorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var accumulator = RecipeTranscriptAccumulator()

    var fullText: String {
        lock.lock()
        defer { lock.unlock() }
        return accumulator.fullText
    }

    @discardableResult
    func applyCumulative(segment: String, isFinal: Bool) -> String {
        lock.lock()
        defer { lock.unlock() }
        accumulator.applyCumulative(segment: segment, isFinal: isFinal)
        return accumulator.fullText
    }
}
/// Writes mic buffers from the audio tap without touching MainActor state.
private final class RecordingFileBox: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?

    init(file: AVAudioFile?) {
        self.file = file
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let file else { return }
        try? file.write(from: buffer)
    }

    func close() {
        lock.lock()
        file = nil
        lock.unlock()
    }
}

/// Resumes a continuation once, from the audio thread or the main actor.
private final class ResumeGate<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}
