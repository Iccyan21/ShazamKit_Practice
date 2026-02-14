import AVFAudio
import Foundation
import ShazamKit
import Combine

@MainActor
final class ShazamRecognizer: NSObject, ObservableObject {
    enum RecognitionState {
        case idle
        case requestingPermission
        case listening
        case matched
        case warning(String)
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
            case let .warning(message):
                return "注意: \(message)"
            case let .failed(message):
                return "エラー: \(message)"
            }
        }
    }

    @Published private(set) var state: RecognitionState = .idle
    @Published private(set) var songTitle = "-"
    @Published private(set) var artistName = "-"
    @Published private(set) var subtitleText = "-"
    @Published private(set) var isListening = false

    private let audioEngine = AVAudioEngine()
    private let session = SHSession()
    private var listeningStartedAt: Date?

    override init() {
        super.init()
        session.delegate = self
    }

    func toggleListening() {
        if isListening {
            stopListening()
            return
        }

        Task {
            await startListening()
        }
    }

    func stopListening() {
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        audioEngine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isListening = false
        listeningStartedAt = nil
        state = .idle
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
            listeningStartedAt = Date()
            isListening = true
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
            guard isListening else { return }

            if let error {
                let nsError = error as NSError
                if nsError.domain == "com.apple.ShazamKit", nsError.code == 202 {
                    // 認識開始直後に返ることがあるため即失敗にしない
                    if elapsedListeningTime < 5 {
                        state = .listening
                        return
                    }
                    state = .warning("認識結果の取得に時間がかかっています。通信状態を確認して続行してください。")
                    return
                }

                state = .failed(nsError.localizedDescription)
                return
            }

            if elapsedListeningTime >= 10 {
                state = .warning("まだ一致する曲が見つかっていません。音量を上げるか、端末を音源に近づけてください。")
            } else {
                state = .listening
            }
        }
    }

    private var elapsedListeningTime: TimeInterval {
        guard let listeningStartedAt else { return 0 }
        return Date().timeIntervalSince(listeningStartedAt)
    }
}
