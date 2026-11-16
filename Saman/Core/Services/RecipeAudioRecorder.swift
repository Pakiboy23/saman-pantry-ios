import AVFoundation
import Combine
import Foundation
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

/// A recording waiting to be sent to `extract-recipe`. The file is a temp
/// copy the capture screen owns: it is kept until the server returns a recipe
/// so a failed upload can be retried without recording again, then deleted.
/// It is never stored on a recipe or a family-book card.
struct RecipeRecording: Equatable {
    let url: URL
    let mimeType: String

    /// Fixed upload name, so a picked file's own name never leaves the phone.
    var uploadFilename: String {
        "recording.\(url.pathExtension.isEmpty ? "m4a" : url.pathExtension.lowercased())"
    }

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Upload rules shared by the recorder and the file picker.
/// Server limits live in `supabase/functions/extract-recipe/index.ts`.
enum RecipeAudioFile {
    /// Audio types the capture screen can open. Not text, and not a photo.
    static let acceptedTypes: [UTType] = [.audio, .mpeg4Audio, .mp3, .wav, .aiff]

    /// Matches the server's 12 MiB body cap, less room for the multipart wrapper.
    static let maxUploadBytes = 12 * 1024 * 1024 - 64 * 1024
    /// Recordings stop at 10 minutes. About 2.4 MB at the settings below.
    static let maxDuration: TimeInterval = 600
    /// When the screen warns that the recording is about to stop.
    static let warnAfter: TimeInterval = 540

    /// Mono AAC at 16 kHz, about 32 kbps. Plenty for speech.
    static let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32_000,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
    ]

    enum UploadPlan: Equatable {
        case direct(mimeType: String)
        case transcode
    }

    /// AAC and MP3 under the size cap go up as they are. Anything else
    /// (WAV, AIFF, CAF, or an oversized file) is re-encoded to AAC first.
    static func uploadPlan(fileExtension: String, byteCount: Int) -> UploadPlan {
        guard byteCount > 0, byteCount <= maxUploadBytes else { return .transcode }
        switch fileExtension.lowercased() {
        case "m4a", "mp4": return .direct(mimeType: "audio/mp4")
        case "aac": return .direct(mimeType: "audio/aac")
        case "mp3": return .direct(mimeType: "audio/mpeg")
        default: return .transcode
        }
    }

    static func newRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("samaan-recipe-recording-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
    }

    static func byteCount(of url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }

    /// "1:05" for 65 seconds.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    /// Copies a picked file, checks its length, and re-encodes it if the
    /// server would not take it as it is. Throws `tooLong` past 10 minutes:
    /// it never trims a recording silently.
    static func prepareUpload(from picked: URL) async throws -> RecipeRecording {
        let copy = try temporaryCopy(of: picked)
        do {
            let asset = AVURLAsset(url: copy)
            let seconds: Double
            do {
                seconds = try await asset.load(.duration).seconds
            } catch {
                throw RecipeAudioError.unreadableFile
            }
            guard seconds.isFinite, seconds > 0 else { throw RecipeAudioError.unreadableFile }
            guard seconds <= maxDuration + 0.5 else { throw RecipeAudioError.tooLong }

            switch uploadPlan(fileExtension: copy.pathExtension, byteCount: byteCount(of: copy)) {
            case .direct(let mimeType):
                return RecipeRecording(url: copy, mimeType: mimeType)
            case .transcode:
                let encoded = try await transcode(asset)
                try? FileManager.default.removeItem(at: copy)
                return encoded
            }
        } catch {
            try? FileManager.default.removeItem(at: copy)
            throw error
        }
    }

    private static func transcode(_ asset: AVURLAsset) async throws -> RecipeRecording {
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecipeAudioError.unreadableFile
        }
        let output = newRecordingURL()
        if #available(iOS 18, *) {
            do {
                try await export.export(to: output, as: .m4a)
            } catch {
                try? FileManager.default.removeItem(at: output)
                throw RecipeAudioError.unreadableFile
            }
        } else {
            export.outputURL = output
            export.outputFileType = .m4a
            await export.export()
            guard export.status == .completed else {
                try? FileManager.default.removeItem(at: output)
                throw RecipeAudioError.unreadableFile
            }
        }
        guard byteCount(of: output) <= maxUploadBytes else {
            try? FileManager.default.removeItem(at: output)
            throw RecipeAudioError.tooLarge
        }
        return RecipeRecording(url: output, mimeType: "audio/mp4")
    }

    /// Copies a security-scoped pick into a temp file the app can read.
    private static func temporaryCopy(of url: URL) throws -> URL {
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
}

enum RecipeAudioError: LocalizedError, Equatable {
    case microphoneDenied
    case unreadableFile
    case tooLong
    case tooLarge
    case failed

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "The microphone is off. Turn it on in Settings to record a recipe."
        case .unreadableFile:
            return "Couldn't read that recording. Try an m4a, mp3, or wav file, or record it in the app."
        case .tooLong:
            return "That recording is longer than 10 minutes. Trim it to the recipe and try again."
        case .tooLarge:
            return "That recording is too big to send. Trim it to the recipe and try again."
        case .failed:
            return "Couldn't start recording. Try again."
        }
    }
}

/// Records a recipe to a mono AAC file. No speech recognition happens on the
/// phone: the file goes to `extract-recipe`, which transcribes it on the server.
@MainActor
final class RecipeAudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    /// 0...1, for the level meter.
    @Published private(set) var level: Float = 0
    /// Bumps when the recorder stops on its own (10-minute limit or an
    /// audio interruption). The capture screen then sends what it has.
    @Published private(set) var autoStopCount = 0

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var meterTask: Task<Void, Never>?
    private var operationID = UUID()

    var isNearLimit: Bool { isRecording && elapsed >= RecipeAudioFile.warnAfter }

    func start() async throws {
        guard !isRecording, recorder == nil else { return }
        operationID = UUID()
        let operation = operationID
        let allowed = await AVAudioApplication.requestRecordPermission()
        // Cancelled while the permission prompt was up.
        guard operation == operationID, !Task.isCancelled else { return }
        guard allowed else { throw RecipeAudioError.microphoneDenied }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default, options: [])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw RecipeAudioError.failed
        }

        let url = RecipeAudioFile.newRecordingURL()
        let recorder: AVAudioRecorder
        do {
            recorder = try AVAudioRecorder(url: url, settings: RecipeAudioFile.recordingSettings)
        } catch {
            deactivateSession()
            throw RecipeAudioError.failed
        }
        recorder.isMeteringEnabled = true
        // The recorder itself enforces the 10-minute cap.
        guard recorder.record(forDuration: RecipeAudioFile.maxDuration) else {
            deactivateSession()
            try? FileManager.default.removeItem(at: url)
            throw RecipeAudioError.failed
        }
        self.recorder = recorder
        fileURL = url
        elapsed = 0
        level = 0
        isRecording = true
        startMeter()
    }

    /// Stops and hands back the file. The caller owns it from here.
    func stop() -> RecipeRecording? {
        guard let recorder, let url = fileURL else { return nil }
        meterTask?.cancel()
        meterTask = nil
        if recorder.isRecording { recorder.stop() }
        self.recorder = nil
        fileURL = nil
        isRecording = false
        level = 0
        deactivateSession()
        guard RecipeAudioFile.byteCount(of: url) > 0 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return RecipeRecording(url: url, mimeType: "audio/mp4")
    }

    /// Stops and deletes the file.
    func cancel() {
        operationID = UUID()
        stop()?.delete()
        elapsed = 0
    }

    private func startMeter() {
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, let recorder = self.recorder else { return }
                guard recorder.isRecording else {
                    // Hit the 10-minute cap, or iOS stopped us for a call.
                    self.meterTask = nil
                    self.autoStopCount += 1
                    return
                }
                recorder.updateMeters()
                self.elapsed = recorder.currentTime
                self.level = Self.normalizedLevel(recorder.averagePower(forChannel: 0))
            }
        }
    }

    /// Maps -50...0 dB onto 0...1.
    nonisolated static func normalizedLevel(_ decibels: Float) -> Float {
        guard decibels.isFinite else { return 0 }
        return min(1, max(0, (decibels + 50) / 50))
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
