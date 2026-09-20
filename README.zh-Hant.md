# VoxTypeMac

[English](README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Русский](README.ru.md) · [Українська](README.uk.md)

VoxTypeMac 是一款以本機為優先、適用於 Apple Silicon 的 macOS 選單列聽寫 App。按下所選快捷鍵後開始說話，再按一次快捷鍵；轉錄文字會送到開始錄音時焦點所在的輸入欄位。

## 系統需求

- Apple Silicon 上的 macOS 27 或更新版本
- Xcode 27
- 執行完整原始碼驗證工具所需的 shellcheck
- 選用：用於本機潤飾模型的 uv 與鎖定版本 Qwen3-ASR 相依套件

App 使用 Apple Speech、AppKit、SwiftUI、AVFoundation 與輔助使用 API。它沒有帳號系統、分析功能或雲端轉錄用戶端；原始碼目錄不依賴私人使用者資料。

## 資料與隱私權

錄音、轉錄文字、設定、下載的模型、快取與暫存檔案都保存在 ~/Library/Application Support/VoxTypeMac/。原始碼目錄與發行封存檔不包含該資料夾。Apple 可能會將語音資產下載至 macOS 管理的儲存空間。TCC、登入項目與系統記錄也由 macOS 管理。

VoxTypeMac 會為聽寫要求「麥克風」與「語音辨識」權限，為全域快捷鍵要求「輸入監控」權限。若要在游標位置插入文字並確認是否成功，VoxTypeMac 也會要求「輔助使用」權限。若無法確認文字已成功插入，轉錄文字會保留在剪貼簿。

## 建置與驗證

~~~
./verify-source.sh
./build-app.sh
open "runtime/build/VoxTypeMac.app"
~~~

建置輸出會留在已忽略的 runtime/ 目錄。開發版本採 ad hoc 簽署，因此重新建置後 macOS 可能會再次要求授權。穩定的發行簽署身分與公證不在這個本機原始碼候選版本的範圍內。

若要在本機安裝建置好的 App：

~~~
./install.sh
~~~

此操作只會取代 ~/Applications/VoxTypeMac.app，不會修改其他私人安裝版本或其資料。

## 選用的 Qwen3-ASR 潤飾

~~~
./script/install-qwen.sh
~~~

此腳本會在 VoxTypeMac 的 Application Support 資料夾下安裝鎖定版本的 Python 執行環境與模型。只有安裝時需要網路；推論會在本機執行。第三方版本與授權條款列於 THIRD_PARTY_NOTICES.md、config/qwen-asr.json，以及經雜湊鎖定的 Python 相依套件清單。

## 原始碼導覽

- Sources/VoxType/：App、選單、錄音、語音辨識、文字傳送與儲存
- Tests/VoxTypeTests/：原生功能與資料邊界檢查
- Resources/：App 中繼資料、權限宣告與產品圖稿
- config/：產品識別與鎖定版本的選用模型相依套件
- script/：建置、封裝、模型安裝與本機執行輔助工具

原始碼採用 MIT License。選用模型與執行環境各自適用其上游條款。
