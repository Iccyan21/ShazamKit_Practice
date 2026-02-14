import AVFAudio
import Foundation
import ShazamKit

@MainActor
final class ShazamRecognizer: NSObject, ObservableObject {
    enum RecognitionState {
        case idle
        case requestingPermission
        case listening
        case matched
        case noMatch
        case failed(String)

        var description: String {
            switch self {
            case .idle:
                return "待機中"
            case .requestingPermission:
                return "マイク権限を確認中…"
            case .listening:
                return "認識中…"
            case .matched:
                return "曲を認識しました"
            case .noMatch:
                return "一致する曲が見つかりませんでした"
            case let .failed(message):
                return "エラー: \(message)"
            }
        }
    }

    @Published private(set) var state: RecognitionState = .idle
    @Published private(set) var songTitle = "-"
    @Published private(set) var artistName = "-"
    @Published private(set) var subtitleText = "-"

    private let audioEngine = AVAudioEngine()
    private let session = SHSession()

    override init() {
        super.init()
        session.delegate = self
    }

    func toggleListening() {
        switch state {
        case .listening:
            stopListening()
            state = .idle
        default:
            Task {
                await startListening()
            }
        }
    }

    func stopListening() {
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        audioEngine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startListening() async {
        state = .requestingPermission

        let permitted = await requestMicrophonePermission()
        guard permitted else {
            state = .failed("マイクの権限がありません。設定アプリで許可してください。")
            return
        }

        do {
            try configureAudioSession()
            try installTap()
            try audioEngine.start()
            state = .listening
        } catch {
            stopListening()
            state = .failed(error.localizedDescription)
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        let avSession = AVAudioSession.sharedInstance()
        switch avSession.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                avSession.requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        @unknown default:
            return false
        }
    }

    private func configureAudioSession() throws {
        let avSession = AVAudioSession.sharedInstance()
        try avSession.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
        try avSession.setActive(true)
    }

    private func installTap() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, audioTime in
            self?.session.matchStreamingBuffer(buffer, at: audioTime)
        }

        songTitle = "-"
        artistName = "-"
        subtitleText = "-"

    }
}

extension ShazamRecognizer: SHSessionDelegate {
    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        Task { @MainActor in
            let mediaItem = match.mediaItems.first
            songTitle = mediaItem?.title ?? "不明"
            artistName = mediaItem?.artist ?? "不明"
            subtitleText = mediaItem?.subtitle ?? "サブタイトルなし"

            state = .matched
        }
    }

    nonisolated func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: (any Error)?) {
        Task { @MainActor in
            if let error {
                state = .failed(error.localizedDescription)
            } else {
                state = .noMatch
            }
        }
    }
}
