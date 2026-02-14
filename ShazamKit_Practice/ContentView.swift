//
//  ContentView.swift
//  ShazamKit_Practice
//
//  Created by 水原樹 on 2026/02/15.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var recognizer = ShazamRecognizer()

    private var isListening: Bool { recognizer.isListening }

    var body: some View {
        VStack(spacing: 20) {
            Text("Shazam 認識モード")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("Spotify/Apple Music認証なしで、周囲やスマホの再生音を認識します。ネット接続がない場合は認識できません。")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Label(recognizer.state.description, systemImage: "waveform")
                .font(.headline)
                .foregroundStyle(isListening ? .green : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 8) {
                infoRow(title: "曲名", value: recognizer.songTitle)
                infoRow(title: "アーティスト", value: recognizer.artistName)
                infoRow(title: "サブタイトル", value: recognizer.subtitleText)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            Button {
                recognizer.toggleListening()
            } label: {
                Label(isListening ? "停止" : "認識開始", systemImage: isListening ? "stop.circle.fill" : "music.note")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            
            Text("マイクが拾える音だけを認識します。端末内だけで再生される音は認識しづらいので、スピーカー再生や別端末再生を推奨します。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .padding()
    }
    
    @ViewBuilder
    private func infoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}
#Preview {
    ContentView()
}
