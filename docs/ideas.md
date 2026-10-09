# 今後のアイデア

上流 ([Stengo/DeskPad](https://github.com/Stengo/DeskPad)) の PR から、そのままは取り込まずにアイデアだけ残しておくもの。

## ScreenCaptureKit + Metal による描画 (上流 PR #68)

macOS への負荷を下げるため、いずれ実装したい。

- **キャプチャ**: `CGDisplayStream` (macOS 15 SDK で非推奨) をやめて ScreenCaptureKit の `SCStream` にする。IOSurface のフレームをコピーせずにそのまま描画まで渡す。
- **描画**: `CAMetalLayer` と `CAMetalDisplayLink` を使い、IOSurface から `MTLTexture` を作ってキャッシュする。フレームに変化があるときだけ描画する。
- **アイドル時の節約**: `SCFrameStatus.complete` のフレームだけを処理し、画面が止まっているときは GPU を使わない。描画内容の変化の頻度に応じて、低遅延と省電力のキャプチャ間隔を切り替える。
- **代替の描画方式**: `AVSampleBufferDisplayLayer` を使う省電力寄りの描画方式。メニューで切り替えられるようにする。
- **権限**: 画面収録の許可を 0.5 秒ごとに確認し、許可された時点でキャプチャを始める (再起動が不要になる)。
- **出力サイズ**: 現状は仮想画面のフル解像度 × スケールで常にストリームしている。ウインドウの実サイズに合わせて出力を縮めるだけでも負荷は下がる。

PR 作者による実測 (M1 Pro、3360×2100): 遅延 4〜13 ms、ミラー中の CPU 7〜11%、静止時 1〜2%。

注意点: デプロイメントターゲットが macOS 15 に上がる。差分が +13,901 行と大きく、開発用スクリプトや設定ファイルも含まれるので、取り込むなら段階的に書き直す。

## 近代化 (上流 PR #64)

- ReSwift をやめて Combine (または Observation) で状態を流す。
- 状態の型を `Sendable` にし、Swift Concurrency に対応する。
- `applicationSupportsSecureRestorableState` を実装する。

注意点: 変更が広範囲で、エンタイトルメントの変更も含まれるので、取り込むなら必要なものを個別に入れる。
