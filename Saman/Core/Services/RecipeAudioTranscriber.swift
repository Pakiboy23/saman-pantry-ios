import AVFoundation
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
    private var latestText = ""
    private var tapInstalled = false

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

        let request = SFSpeechAudioBufferRecognitionRequest()
        configure(request)
        recognitionRequest = request
        latestText = ""
        partialTranscript = ""

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecipeAudioError.microphoneDenied
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
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
        parkEngine()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        defer { finishTask() }
        let produced: String = try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate(continuation)
            recordingGate = gate
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                gate.resume(returning: self.latestText)
            }
        }
        guard let ready = RecipeAudioTranscript.readyForExtract(produced) else {
            throw RecipeAudioError.emptyTranscript
        }
        partialTranscript = ""
        return ready
    }

    func cancelRecording() {
        guard isRecording || audioEngine != nil || recognitionTask != nil else { return }
        isRecording = false
        recordingGate?.resume(returning: "")
        recordingGate = nil
        parkEngine()
        recognitionRequest = nil
        finishTask()
        partialTranscript = ""
        latestText = ""
    }

    func transcribeFile(at url: URL) async throws -> String {
        guard !isRecording else { throw RecipeAudioError.failed }
        let recognizer = try await prepareRecognizer()
        let request = SFSpeechURLRecognitionRequest(url: url)
        configure(request)
        let text: String = try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate(continuation)
            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    gate.resume(returning: result.bestTranscription.formattedString)
                    return
                }
                if let error {
                    gate.resume(throwing: error)
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
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                guard let self else { return }
                if let text {
                    self.latestText = text
                    self.partialTranscript = text
                    if isFinal {
                        self.recordingGate?.resume(returning: text)
                    }
                }
                if let error, !isFinal {
                    if RecipeAudioTranscript.readyForExtract(self.latestText) != nil {
                        self.recordingGate?.resume(returning: self.latestText)
                    } else if self.recordingGate != nil {
                        self.recordingGate?.resume(throwing: self.friendly(error))
                    }
                }
            }
        }
    }

    private func parkEngine() {
        if tapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine?.stop()
        audioEngine = nil
    }

    private func finishTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func teardownEngine() {
        parkEngine()
        recognitionRequest = nil
        finishTask()
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
