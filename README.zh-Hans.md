# VoxTypeMac

[English](README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Русский](README.ru.md) · [Українська](README.uk.md)

VoxTypeMac 是一款面向 Apple Silicon 的 macOS 菜单栏听写应用，优先在本机处理数据。按下所选快捷键后即可开始说话，再按一次快捷键，转写文本会发送到开始录音时获得焦点的输入框。

## 系统要求

- macOS 27 或更高版本，运行于 Apple Silicon
- Xcode 27
- 完整源码验证需要 `shellcheck`
- 可选：本地优化模型所需的 `uv` 和已锁定版本的 Qwen3-ASR 依赖项

应用使用 Apple Speech、AppKit、SwiftUI、AVFoundation 和辅助功能 API。应用不设账号系统，不收集分析数据，不使用云端转写客户端，也不依赖源码目录之外的私人用户数据。

## 数据与隐私

录音、转写文本、设置、下载的模型、缓存和临时文件均保存在 `~/Library/Application Support/VoxTypeMac/` 下。源码目录和发行压缩包不包含此目录。Apple 可能会将语音资源下载到由 macOS 管理的存储空间。TCC、登录项和系统日志也由 macOS 管理。

VoxTypeMac 会请求麦克风和语音识别权限，以便听写；会请求输入监控权限，以便使用全局快捷键；并会请求辅助功能权限，以验证文字是否已插入。如果无法确认文字已插入，转写文本会保留在剪贴板中。

## 构建与验证

```sh
./verify-source.sh
./build-app.sh
open "runtime/build/VoxTypeMac.app"
```

构建输出保存在已忽略的 `runtime/` 目录中。开发构建使用临时签名，因此每次重新构建后，macOS 可能会再次要求授权。本地源码候选版本尚未设置稳定的发行签名身份或公证。

如需在本机安装构建好的应用：

```sh
./install.sh
```

此操作只会替换 `~/Applications/VoxTypeMac.app`。它不会更改其他独立安装或其数据。

## 可选的 Qwen3-ASR 转写优化

```sh
./script/install-qwen.sh
```

此脚本会在 VoxTypeMac 的 Application Support 目录下安装已锁定版本的 Python 运行环境和模型。安装时需要网络连接；推理过程在本机运行。第三方版本和许可证列于 `THIRD_PARTY_NOTICES.md`、`config/qwen-asr.json` 和带哈希锁定的 Python 依赖清单中。

## 源码目录说明

- `Sources/VoxType/`：应用、菜单、录音、语音识别、文字发送和存储
- `Tests/VoxTypeTests/`：原生功能和数据边界检查
- `Resources/`：应用元数据、授权配置和产品美术资源
- `config/`：产品身份和可选模型的锁定依赖项
- `script/`：构建、打包、模型安装和本机运行辅助脚本

源码依据 MIT License 提供。可选模型和运行环境遵循各自上游的许可条款。
