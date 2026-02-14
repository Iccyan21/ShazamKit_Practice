//
//  SampleHandler.swift
//  ShazamRecognizer
//
//  Created by 水原樹 on 2026/02/15.
//

import ReplayKit
import ReplayKit
import ShazamKit
import AVFoundation
import Accelerate

class SampleHandler: RPBroadcastSampleHandler {
    
    private let signatureGenerator = SHSignatureGenerator()
    private var session: SHSession?
    private var audioBufferCount = 0
    private let appGroupID = "group.media.iccyan.ShazamKit-Practice"
    
    override init() {
        super.init()
        session = SHSession()
        session?.delegate = self
        print("📡 Broadcast Extension起動")
    }
    
    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        print("✅ 放送開始")
        audioBufferCount = 0
    }
    
    override func broadcastPaused() {
        print("⏸️ 放送一時停止")
    }
    
    override func broadcastResumed() {
        print("▶️ 放送再開")
    }
    
    override func broadcastFinished() {
        print("🛑 放送終了")
    }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case RPSampleBufferType.audioApp:
            // システムオーディオ（Spotify等）
            processAudio(sampleBuffer)
        case RPSampleBufferType.audioMic:
            // マイク音声（使わない）
            break
        case RPSampleBufferType.video:
            // 映像（使わない）
            break
        @unknown default:
            break
        }
    }
    
    private func processAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let audioBuffer = sampleBuffer.toAVAudioPCMBuffer() else {
            return
        }
        
        do {
            try signatureGenerator.append(audioBuffer, at: nil)
            audioBufferCount += 1
            
            // 5秒ごとに認識（約215バッファ）
            if audioBufferCount >= 215 {
                print("🔍 認識開始... (バッファ数: \(audioBufferCount))")
                let signature = signatureGenerator.signature()
                session?.match(signature)
                audioBufferCount = 0
            }
        } catch {
            print("❌ エラー: \(error)")
        }
    }
}

// MARK: - SHSessionDelegate

extension SampleHandler: SHSessionDelegate {
    func session(_ session: SHSession, didFind match: SHMatch) {
        guard let mediaItem = match.mediaItems.first else { return }
        
        let title = mediaItem.title ?? "不明なタイトル"
        let artist = mediaItem.artist ?? "不明なアーティスト"
        let album = mediaItem.subtitle ?? ""
        
        print("🎉 曲を認識: \(title) - \(artist)")
        
        // App Groupsでメインアプリに通知
        if let userDefaults = UserDefaults(suiteName: appGroupID) {
            userDefaults.set(title, forKey: "songTitle")
            userDefaults.set(artist, forKey: "songArtist")
            userDefaults.set(album, forKey: "songAlbum")
            userDefaults.set(Date(), forKey: "lastUpdated")
            userDefaults.synchronize()
        }
    }
    
    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        if let error = error {
            print("❌ 認識失敗: \(error)")
        } else {
            print("❌ 曲を認識できませんでした")
        }
    }
}

// MARK: - CMSampleBuffer Extension

extension CMSampleBuffer {
    func toAVAudioPCMBuffer() -> AVAudioPCMBuffer? {
        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            self,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        
        guard let formatDescription = CMSampleBufferGetFormatDescription(self),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            return nil
        }
        
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: asbd.mSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            return nil
        }
        
        let frameCount = CMSampleBufferGetNumSamples(self)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                           frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        guard let dstMono = buffer.floatChannelData?[0] else {
            return nil
        }
        
        if let data = audioBufferList.mBuffers.mData {
            let srcInt16 = data.assumingMemoryBound(to: Int16.self)
            let channelCount = Int(asbd.mChannelsPerFrame)
            
            for i in 0..<frameCount {
                var sample: Float = 0.0
                
                for channel in 0..<channelCount {
                    let int16Value = srcInt16[i * channelCount + channel]
                    sample += Float(int16Value) / 32768.0
                }
                
                dstMono[i] = sample / Float(channelCount)
            }
        }
        
        return buffer
    }
}
