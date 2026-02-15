import Foundation
import Combine

@MainActor
class MusicRecognizer: ObservableObject {
    @Published var status: RecognitionStatus = .idle
    @Published var recognizedSong: RecognizedSong?
    @Published var isRecording = false
    @Published var errorMessage: String?

    private let appGroupID = "group.media.iccyan.ShazamKit-Practice"
    private var pollingTimer: Timer?
    private var lastUpdated: Date?

    func startRecording() {
        status = .recording
        errorMessage = nil
        isRecording = true
        startPollingRecognizedSong()
    }

    func stopRecording() {
        isRecording = false
        status = .idle
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func startPollingRecognizedSong() {
        pollingTimer?.invalidate()

        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchLatestRecognizedSong()
            }
        }
    }

    private func fetchLatestRecognizedSong() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            errorMessage = "App Group にアクセスできません。Signing & Capabilities で App Groups を設定してください。"
            status = .error
            return
        }

        guard let updatedAt = defaults.object(forKey: "lastUpdated") as? Date else { return }
        guard lastUpdated != updatedAt else { return }

        lastUpdated = updatedAt

        let title = defaults.string(forKey: "songTitle") ?? "不明なタイトル"
        let artist = defaults.string(forKey: "songArtist") ?? "不明なアーティスト"
        let album = defaults.string(forKey: "songAlbum")

        recognizedSong = RecognizedSong(
            title: title,
            artist: artist,
            album: album,
            appleMusicURL: nil
        )
        status = .success
    }
}
