import SwiftUI
import ShazamKit
import ReplayKit

struct ContentView: View {
    @StateObject private var recognizer = MusicRecognizer()
    
    var body: some View {
        VStack(spacing: 30) {
            Text("System Audio Recognizer")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // 認識状態表示
            StatusView(status: recognizer.status)
            
            // 認識結果表示
            if let result = recognizer.recognizedSong {
                ResultView(song: result)
            } else {
                Text("認識された曲はありません")
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // コントロールボタン
            if recognizer.isRecording {
                Button(action: {
                    recognizer.stopRecording()
                }) {
                    Label("停止", systemImage: "stop.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 200, height: 60)
                        .background(Color.red)
                        .cornerRadius(30)
                }
            } else {
                Button(action: {
                    recognizer.startRecording()
                }) {
                    Label("認識開始", systemImage: "waveform.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 200, height: 60)
                        .background(Color.blue)
                        .cornerRadius(30)
                }
            }
            
            Text("Spotify、YouTube Music等の\n再生中の曲を認識します")
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.bottom, 40)
        }
        .padding()
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
            return "録音中..."
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
            
            if let album = song.album {
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
