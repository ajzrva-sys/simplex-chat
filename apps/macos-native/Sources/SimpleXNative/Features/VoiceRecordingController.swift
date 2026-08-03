import AVFoundation
import Foundation

@MainActor
final class VoiceRecordingController: NSObject, ObservableObject, AVAudioRecorderDelegate {
    enum State: Equatable {
        case idle
        case recording(elapsed: TimeInterval, level: Float)
        case review(url: URL, duration: TimeInterval)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var startedAt: Date?
    private let maximumDuration: TimeInterval = 5 * 60

    func start() {
        guard state == .idle else { return }
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard allowed else {
                state = .failed("Microphone access is required to record a voice message.")
                return
            }
            beginRecording()
        }
    }

    func stop() {
        guard recorder?.isRecording == true else { return }
        recorder?.stop()
        finishRecording()
    }

    func cancel() {
        let url = recorder?.url ?? reviewURL
        recorder?.stop()
        reset()
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    func consumeReview() {
        reset()
    }

    private var reviewURL: URL? {
        if case let .review(url, _) = state { return url }
        return nil
    }

    private func beginRecording() {
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("NativeChatVoice", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("Voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: maximumDuration) else {
                throw NativeChatError.unavailable("macOS could not start recording.")
            }
            self.recorder = recorder
            startedAt = Date()
            state = .recording(elapsed: 0, level: 0)
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.updateMeters() }
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func updateMeters() {
        guard let recorder, recorder.isRecording else {
            if recorder != nil { finishRecording() }
            return
        }
        recorder.updateMeters()
        let elapsed = min(Date().timeIntervalSince(startedAt ?? Date()), maximumDuration)
        let decibels = recorder.averagePower(forChannel: 0)
        let level = max(0, min(1, pow(10, decibels / 20)))
        state = .recording(elapsed: elapsed, level: level)
        if elapsed >= maximumDuration { stop() }
    }

    private func finishRecording() {
        guard let recorder else { return }
        let duration = max(recorder.currentTime, Date().timeIntervalSince(startedAt ?? Date()))
        meterTimer?.invalidate()
        meterTimer = nil
        self.recorder = nil
        startedAt = nil
        state = .review(url: recorder.url, duration: min(duration, maximumDuration))
    }

    private func reset() {
        meterTimer?.invalidate()
        meterTimer = nil
        recorder = nil
        startedAt = nil
        state = .idle
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if flag { finishRecording() }
            else {
                reset()
                state = .failed("The voice recording stopped before it could be saved.")
            }
        }
    }
}
