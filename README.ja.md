# VoxTypeMac

[English](README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Русский](README.ru.md) · [Українська](README.uk.md)

VoxTypeMac は Apple Silicon 搭載 Mac 向けの、ローカル優先の macOS メニューバー音声入力アプリです。選択したショートカットを押して話し、もう一度押すと、録音開始時にフォーカスされていた入力欄へ文字起こし結果を送ります。

## 動作環境

- macOS 27 以降、Apple Silicon 搭載 Mac
- Xcode 27
- ソース検証をすべて実行する場合は shellcheck
- ローカル補正モデルを使う場合は、任意で uv と固定バージョンの Qwen3-ASR 依存関係

Apple Speech、AppKit、SwiftUI、AVFoundation、アクセシビリティ API を使用します。アカウント機能、アナリティクス、クラウド文字起こしクライアントはなく、ソースツリーに個人データへの依存もありません。

## データとプライバシー

録音、文字起こし結果、設定、ダウンロードしたモデル、キャッシュ、一時ファイルはすべて ~/Library/Application Support/VoxTypeMac/ に保存されます。このディレクトリはソースツリーにもリリースアーカイブにも含まれません。Apple が音声関連のアセットを macOS 管理下のストレージへダウンロードする場合があります。TCC、ログイン項目、システムログも macOS が管理します。

VoxTypeMac は音声入力に「マイク」と「音声認識」、グローバルショートカットに「入力監視」、挿入が確認できるテキスト入力に「アクセシビリティ」のアクセスを求めます。挿入を確認できない場合、文字起こし結果はクリップボードに残ります。

## ビルドと検証

~~~
./verify-source.sh
./build-app.sh
open "runtime/build/VoxTypeMac.app"
~~~

ビルド成果物は無視対象の runtime/ ディレクトリに保存されます。ローカルビルドは固定の `Alex Local Code Signing` ID で署名し、再ビルド後も macOS のプライバシー許可を維持します。初回ビルド前に `./ensure-signing-identity.sh` を実行してください。アプリは未公証です。コントリビューターは `SIGNING_IDENTITY` を自身の固定コード署名証明書に変更できます。

ビルドしたアプリをローカルにインストールするには、次を実行します。

~~~
./install.sh
~~~

置き換えるのは ~/Applications/VoxTypeMac.app のみです。別の非公開インストールや、そのデータには変更を加えません。

## 任意の Qwen3-ASR 補正機能

~~~
./script/install-qwen.sh
~~~

このスクリプトは、固定バージョンの Python ランタイムとモデルを VoxTypeMac の Application Support ディレクトリにインストールします。ネットワークアクセスが必要なのはインストール時だけです。推論処理はローカルで実行されます。サードパーティのバージョンとライセンスは、THIRD_PARTY_NOTICES.md、config/qwen-asr.json、ハッシュで固定した Python 要件ファイルに記載しています。

## ソース構成

- Sources/VoxType/：アプリ、メニュー、録音、認識、出力、保存機能
- Tests/VoxTypeTests/：ネイティブ機能テストとデータ境界チェック
- Resources/：アプリのメタデータ、エンタイトルメント、製品アートワーク
- config/：製品 ID と、バージョンを固定した任意モデルの依存関係
- script/：ビルド、パッケージ化、モデルのインストール、ローカル実行用ヘルパー

ソースコードには MIT License が適用されます。任意のモデルとランタイムには、それぞれの上流プロジェクトの利用条件が適用されます。
