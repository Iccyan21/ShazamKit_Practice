import AVFAudio
import Combine
import Foundation
import Network
import ShazamKit

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
    private var session = SHSession()
    private var listeningStartedAt: Date?
    private var lastMatchAt: Date?

    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "ShazamRecognizer.PathMonitor")
    private var isNetworkReachable = true

    private var refreshTask: Task<Void, Never>?

    override init() {
        super.init()
        configureSession()
        setupPathMonitor()
    }

    deinit {
        pathMonitor.cancel()
        refreshTask?.cancel()
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
        refreshTask?.cancel()
        refreshTask = nil

        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        audioEngine.stop()
        audioEngine.reset()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isListening = false
        listeningStartedAt = nil
        lastMatchAt = nil
        state = .idle
    }

    private func startListening() async {
        state = .requestingPermission

        guard isNetworkReachable else {
            state = .failed("インターネット接続がありません。通信状態を確認してから再試行してください。")
            return
        }

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
            lastMatchAt = nil
            isListening = true
            state = .listening
            startRefreshLoop()
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
        try avSession.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
        try avSession.setPreferredSampleRate(44_100)
        try avSession.setPreferredIOBufferDuration(0.02)
        try avSession.setActive(true)
    }

    private func installTap() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, audioTime in
            self?.session.matchStreamingBuffer(buffer, at: audioTime)
        }

        songTitle = "-"
        artistName = "-"
        subtitleText = "-"
    }

    private func setupPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { @MainActor in
                self.isNetworkReachable = path.status == .satisfied
                guard self.isListening else { return }

                if self.isNetworkReachable == false {
                    self.state = .warning("オフラインのため認識できません。通信状態が復旧するまで待機します。")
                } else if case .warning = self.state {
                    self.state = .listening
                }
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard !Task.isCancelled else { return }
                await self.refreshRecognitionSessionIfNeeded()
            }
        }
    }

    private func refreshRecognitionSessionIfNeeded() {
        guard isListening else { return }
        guard elapsedListeningTime > 15 else { return }

        if let lastMatchAt, Date().timeIntervalSince(lastMatchAt) < 12 {
            return
        }

        resetSession()
        state = .listening
    }

    private func resetSession() {
        session = SHSession()
        session.delegate = self
    }

    private func configureSession() {
        session.delegate = self
    }
}

extension ShazamRecognizer: SHSessionDelegate {
    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        Task { @MainActor in
            let mediaItem = match.mediaItems.first
            songTitle = mediaItem?.title ?? "不明"
            artistName = mediaItem?.artist ?? "不明"
            subtitleText = mediaItem?.subtitle ?? "サブタイトルなし"
            lastMatchAt = Date()
            state = .matched
        }
    }

    nonisolated func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: (any Error)?) {
        Task { @MainActor in
            guard isListening else { return }

            if isNetworkReachable == false {
                state = .warning("通信がオフラインです。接続後にそのまま認識を続行します。")
                return
            }

            if let error {
                let nsError = error as NSError
                if nsError.domain == "com.apple.ShazamKit", nsError.code == 202 {
                    if elapsedListeningTime < 5 {
                        state = .listening
                        return
                    }

                    state = .warning("認識結果の取得に時間がかかっています。周囲の音量を上げるか、曲のサビ部分でお試しください。")
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
