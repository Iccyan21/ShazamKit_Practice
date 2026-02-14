import AVFoundation
import ShazamKit
import Combine
import Accelerate

@MainActor
class MusicRecognizer: NSObject, ObservableObject {
    @Published var status: RecognitionStatus = .idle
    @Published var recognizedSong: RecognizedSong?
    @Published var isRecording = false
    @Published var errorMessage: String?
    
    private var audioEngine: AVAudioEngine?
    private var session: SHSession?
    private let signatureGenerator = SHSignatureGenerator()
    
    override init() {
        super.init()
        setupShazamSession()
        setupAudioEngine()
    }
    
    private func setupShazamSession() {
        session = SHSession()
        session?.delegate = self
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
    }
    
    func startRecording() {
        // マイク権限をリクエスト
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard granted else {
                Task { @MainActor in
                    self?.errorMessage = "マイクへのアクセスが拒否されました"
                    self?.status = .error
                }
                return
            }
            
            Task { @MainActor in
                self?.startListening()
            }
        }
    }
    
    private func startListening() {
        guard let audioEngine = audioEngine else { return }
        
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            // ★★★ ここを修正 ★★★
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .mixWithOthers]
            )
            try audioSession.setActive(true)
            
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, time in
                guard let self = self else { return }
                
                do {
                    try self.signatureGenerator.append(buffer, at: time)
                    
                    // 音量チェック（デバッグ用）
                    if let channelData = buffer.floatChannelData {
                        let frameCount = Int(buffer.frameLength)
                        var maxAmplitude: Float = 0
                        
                        for i in 0..<frameCount {
                            let sample = abs(channelData[0][i])
                            if sample > maxAmplitude {
                                maxAmplitude = sample
                            }
                        }
                        
                        let avgPower = 20 * log10(maxAmplitude + 0.0001)
                        if avgPower > -80 {
                            print("🔊 音声検出: \(avgPower) dB")
                        }
                    }
                } catch {
                    print("❌ エラー: \(error)")
                }
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
            self.isRecording = true
            self.status = .recording
            print("✅ マイク録音開始（Spotify再生継続）")
            
            Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] timer in
                guard let self = self, self.isRecording else {
                    timer.invalidate()
                    return
                }
                
                Task { @MainActor in
                    self.tryRecognition()
                }
            }
            
        } catch {
            errorMessage = "音声エンジン起動エラー: \(error.localizedDescription)"
            status = .error
        }
    }
    
    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("エラー: \(error)")
        }
        
        isRecording = false
        status = .idle
        print("🛑 録音停止")
    }
    
    private func tryRecognition() {
        status = .recognizing
        
        Task {
            do {
                let signature = signatureGenerator.signature()
                try await session?.match(signature)
                print("✅ 認識リクエスト送信")
            } catch {
                errorMessage = "認識エラー: \(error.localizedDescription)"
                status = .error
            }
        }
    }
}

extension MusicRecognizer: SHSessionDelegate {
    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        Task { @MainActor in
            guard let mediaItem = match.mediaItems.first else { return }
            
            print("🎉 曲を認識: \(mediaItem.title ?? "") - \(mediaItem.artist ?? "")")
            
            self.recognizedSong = RecognizedSong(
                title: mediaItem.title ?? "不明なタイトル",
                artist: mediaItem.artist ?? "不明なアーティスト",
                album: mediaItem.subtitle,
                appleMusicURL: mediaItem.appleMusicURL
            )
            
            self.status = .success
        }
    }
    
    nonisolated func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.errorMessage = "認識失敗: \(error.localizedDescription)"
            } else {
                self.errorMessage = "曲を認識できませんでした"
            }
            
            if self.status == .recognizing {
                self.status = .recording
            }
        }
    }
}
