# ShazamKit_Practice

ShazamKit を使って「Shazam 認識モード」っぽい動作を試すための SwiftUI サンプルです。

## できること
- Spotify / Apple Music 認証なしで音楽認識
- マイク入力をストリーミングして ShazamKit に照合
- 一致した曲名・アーティスト・サブタイトルを表示

## 使い方
1. アプリ起動
2. **認識開始** をタップ
3. マイク許可ダイアログで許可
4. スマホや周辺で音楽を再生して認識結果を待つ

> イヤホン利用時でも、端末マイクに音が届く環境なら認識できます。

## トラブルシュート
- `com.apple.ShazamKit error 202` が出る場合は、
  - Target > Signing & Capabilities で **ShazamKit (Music Recognition)** を有効化
  - 実機に再インストール
  - ネットワーク接続を確認
 してください。

