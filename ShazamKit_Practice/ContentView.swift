import SwiftUI
import ReplayKit

struct ContentView: View {
    @StateObject private var recognizer = MusicRecognizer()
    @State private var startBroadcastTrigger = UUID()

    var body: some View {
        VStack(spacing: 24) {
            Text("System Audio Recognizer")
                .font(.largeTitle)
                .fontWeight(.bold)

            StatusView(status: recognizer.status)

            if let result = recognizer.recognizedSong {
                ResultView(song: result)
            } else {
                Text("認識された曲はありません")
                    .foregroundColor(.gray)
            }

            if let errorMessage = recognizer.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // ReplayKit のシステムブロードキャストピッカー（不可視）
            BroadcastPickerView(startTrigger: $startBroadcastTrigger)
                .frame(width: 0, height: 0)
                .opacity(0.01)

            VStack(spacing: 12) {
                Button {
                    recognizer.startRecording()
                    startBroadcastTrigger = UUID()
                } label: {
                    Label("システム音声認識を開始", systemImage: "dot.radiowaves.left.and.right")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.blue)
                        .cornerRadius(16)
                }

                Button {
                    recognizer.stopRecording()
                } label: {
                    Label("認識表示を停止", systemImage: "stop.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.red)
                        .cornerRadius(16)
                }
            }

            Text("Spotify などを端末で再生中に開始すると、音量ゼロでも（出力先に関係なく）システム音声から曲認識できます。\n※ ブロードキャスト停止は iOS の画面収録UIから行ってください。")
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.bottom, 24)
        }
        .padding()
    }
}

struct BroadcastPickerView: UIViewRepresentable {
    @Binding var startTrigger: UUID

    class Coordinator {
        var lastTrigger: UUID?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView()
        picker.showsMicrophoneButton = false
        picker.preferredExtension = "iccyan.shazam-practice.ShazamRecognizer"
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        uiView.preferredExtension = "iccyan.shazam-practice.ShazamRecognizer"

        guard context.coordinator.lastTrigger != startTrigger else { return }
        context.coordinator.lastTrigger = startTrigger

        DispatchQueue.main.async {
            guard let button = uiView.subviews.compactMap({ $0 as? UIButton }).first else { return }
            button.sendActions(for: .touchUpInside)
        }
    }
}

struct StatusView: View {
    let status: RecognitionStatus

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)

            Text(statusText)
                .font(.headline)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }

    private var statusColor: Color {
        switch status {
        case .idle:
            return .gray
        case .recording:
            return .red
        case .recognizing:
            return .orange
        case .success:
            return .green
        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch status {
        case .idle:
            return "待機中"
        case .recording:
            return "システム音声監視中..."
        case .recognizing:
            return "認識中..."
        case .success:
            return "認識成功！"
        case .error:
            return "エラー"
        }
    }
}

struct ResultView: View {
    let song: RecognizedSong

    var body: some View {
        VStack(spacing: 15) {
            Text(song.title)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(song.artist)
                .font(.title3)
                .foregroundColor(.secondary)

            if let album = song.album, !album.isEmpty {
                Text(album)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            if let appleMusicURL = song.appleMusicURL {
                Link("Apple Musicで開く", destination: appleMusicURL)
                    .font(.caption)
                    .padding(8)
                    .background(Color.pink.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(15)
    }
}

enum RecognitionStatus {
    case idle
    case recording
    case recognizing
    case success
    case error
}

struct RecognizedSong: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let album: String?
    let appleMusicURL: URL?
}

#Preview {
    ContentView()
}
