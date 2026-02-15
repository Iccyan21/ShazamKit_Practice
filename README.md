# ShazamKit_Practice

ShazamKit + ReplayKit を使って、**Spotify などを端末で再生している音声（音量ゼロ含む）**を認識する SwiftUI サンプルです。

## できること
- Spotify / Apple Music 認証なしで楽曲認識
- マイクではなく **システム音声（ReplayKit の audioApp）** を認識
- 一致した曲名・アーティスト・アルバムを表示

## 使い方
1. アプリ起動
2. **システム音声認識を開始** をタップ
3. ReplayKit のブロードキャスト開始 UI で開始
4. Spotify / YouTube Music などを端末内で再生
5. 認識結果が表示される

> 端末音量が 0 でも、デバイス内で再生中なら認識可能です（ReplayKit の取得音声に依存）。

## 必要な設定
- Signing & Capabilities で以下を有効化
  - **ShazamKit (Music Recognition)**
  - **App Groups**: `group.media.iccyan.ShazamKit-Practice`
- Broadcast Upload Extension（`ShazamRecognizer`）を有効にした状態で実機実行

## 補足
- 認識停止ボタンは「アプリ側の表示更新停止」です。
- ブロードキャスト自体の停止は iOS の画面収録 UI（Dynamic Island / ステータスバー）から行います。
