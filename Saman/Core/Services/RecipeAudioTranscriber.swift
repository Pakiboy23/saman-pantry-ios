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
            volatileSegment = trimmed
        }
    }

    /// URL / file recognition: each callback is usually the transcript so far.
    /// When a result resets (shorter / unrelated), treat it as a new utterance.
    mutating func applyCumulative(segment: String, isFinal: Bool) {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if isFinal { volatileSegment = "" }
            return
        }

        let committed = Self.join(segments: committedSegments)
        if committed.isEmpty {
            if isFinal {
                committedSegments = [trimmed]
                volatileSegment = ""
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
    private var accumulator = RecipeTranscriptAccumulator()
    private var tapInstalled = false
    private let requestSlot = RecognitionRequestSlot()
    private var recordingFileURL: URL?
    private var recordingFile: AVAudioFile?
    private var recordingFileBox: RecordingFileBox?
    private var isStopping = false
    private var listenGeneration = 0
    private var consecutiveRestartErrors = 0

    func startRecording() async throws {
        guard !isRecording else { return }
        let recognizer = try await prepareRecognizer()
        guard await Self.requestMicrophoneAccess() else { throw RecipeAudioError.microphoneDenied }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw RecipeAudioError.failed
        }

        accumulator.reset()
        partialTranscript = ""
        isStopping = false
        listenGeneration = 0
        consecutiveRestartErrors = 0
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

        // Keep a temp copy of the mic audio so we can re-transcribe the whole
        // take if live recognition ends empty after a long pause.
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
        parkEngine()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        requestSlot.set(nil)
        defer {
            clearRecordingFile(delete: true)
            isStopping = false
        }
        // A thrown live result is the empty-after-error case the file
        // fallback is meant to cover. Do not let it skip that path.
        let produced: String = (try? await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate(continuation)
            recordingGate = gate
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                gate.resume(returning: self.accumulator.fullText)
            }
        }) ?? ""
        // Drop the live task before any file fallback reuses recognitionTask.
        recognitionTask?.cancel()
        recognitionTask = nil
        if let ready = RecipeAudioTranscript.readyForExtract(produced) {
            finishTask()
            partialTranscript = ""
            return ready
        }
        // Live session ended empty — try the saved take once.
        let fallbackURL = recordingFileURL
        finishTask()
        if let url = fallbackURL {
            do {
                let fromFile = try await transcribeFile(at: url)
                partialTranscript = ""
                return fromFile
            } catch {
                // Fall through to emptyTranscript below.
            }
        }
        throw RecipeAudioError.emptyTranscript
    }

    func cancelRecording() {
        guard isRecording || audioEngine != nil || recognitionTask != nil else { return }
        isRecording = false
        isStopping = true
        recordingGate?.resume(returning: "")
        recordingGate = nil
        parkEngine()
        recognitionRequest = nil
        requestSlot.set(nil)
        finishTask()
        clearRecordingFile(delete: true)
        partialTranscript = ""
        accumulator.reset()
        isStopping = false
    }

    func transcribeFile(at url: URL) async throws -> String {
        guard !isRecording else { throw RecipeAudioError.failed }
        let recognizer = try await prepareRecognizer()
        let request = SFSpeechURLRecognitionRequest(url: url)
        configure(request)
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
                try? await Task.sleep(nanoseconds: 90_000_000_000)
                gate.resume(throwing: RecipeAudioError.failed)
            }
        }
        recognitionTask?.cancel()
        recognitionTask = nil
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
        listenGeneration += 1
        let generation = listenGeneration
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                guard let self else { return }
                guard generation == self.listenGeneration else { return }
                if let text {
                    self.accumulator.applyUtterance(segment: text, isFinal: isFinal, taskID: generation)
                    self.partialTranscript = self.accumulator.fullText
                }
                if isFinal {
                    self.consecutiveRestartErrors = 0
                    if self.isRecording, !self.isStopping {
                        // Recognizer finished an utterance after a pause. Keep
                        // the mic open and start a fresh task so later sentences
                        // are not lost.
                        self.restartListening(with: recognizer)
                    } else {
                        self.recordingGate?.resume(returning: self.accumulator.fullText)
                    }
                    return
                }
                if let error {
                    if self.isRecording, !self.isStopping {
                        if self.consecutiveRestartErrors < 3 {
                            self.consecutiveRestartErrors += 1
                            self.restartListening(with: recognizer)
                        }
                    } else if RecipeAudioTranscript.readyForExtract(self.accumulator.fullText) != nil {
                        self.recordingGate?.resume(returning: self.accumulator.fullText)
                    } else if self.recordingGate != nil {
                        self.recordingGate?.resume(throwing: self.friendly(error))
                    }
                }
            }
        }
    }

    private func restartListening(with recognizer: SFSpeechRecognizer) {
        recognitionTask?.cancel()
        recognitionTask = nil
        // Invalidate in-flight callbacks from the cancelled task before the
        // next listen() takes a new generation.
        listenGeneration += 1
        let request = SFSpeechAudioBufferRecognitionRequest()
        configure(request)
        recognitionRequest = request
        requestSlot.set(request)
        listen(recognizer: recognizer, request: request)
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
