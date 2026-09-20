# VoxTypeMac

[English](README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Русский](README.ru.md) · [Українська](README.uk.md)

VoxTypeMac은 Apple Silicon용 로컬 우선 macOS 메뉴 막대 받아쓰기 앱입니다. 선택한 단축키를 누르고 말한 다음 단축키를 다시 누르면, 녹음을 시작할 때 포커스되어 있던 입력란에 변환된 텍스트를 보냅니다.

## 요구 사항

- Apple Silicon이 탑재된 Mac 및 macOS 27 이상
- Xcode 27
- 전체 소스 검증에 필요한 `shellcheck`
- 선택 사항: 로컬 텍스트 다듬기 모델에 필요한 `uv` 및 고정 버전 Qwen3-ASR 종속 항목

앱은 Apple Speech, AppKit, SwiftUI, AVFoundation 및 손쉬운 사용 API를 사용합니다. 계정 시스템, 분석 기능, 클라우드 음성 텍스트 변환 클라이언트가 없으며 소스 트리 실행에 개인 사용자 데이터가 필요하지 않습니다.

## 데이터와 개인정보 보호

녹음, 텍스트, 설정, 다운로드한 모델, 캐시 및 임시 파일은 `~/Library/Application Support/VoxTypeMac/` 아래에 저장됩니다. 소스 트리와 릴리스 아카이브에는 이 디렉터리가 포함되지 않습니다. macOS가 음성 인식 리소스를 macOS에서 관리하는 저장 공간에 다운로드할 수 있습니다. TCC, 로그인 항목 및 시스템 로그도 macOS에서 관리합니다.

VoxTypeMac은 받아쓰기에 마이크 및 음성 인식 권한을, 전역 단축키에 입력 모니터링 권한을 요청합니다. 텍스트를 입력한 뒤 결과를 확인하려면 손쉬운 사용 권한도 필요합니다. 삽입 여부를 확인할 수 없으면 변환된 텍스트는 클립보드에 남습니다.

## 빌드 및 검증

```sh
./verify-source.sh
./build-app.sh
open "runtime/build/VoxTypeMac.app"
```

빌드 결과물은 무시 대상인 `runtime/` 디렉터리에 저장됩니다. 개발 빌드는 애드혹 서명되므로 다시 빌드한 뒤 macOS에서 권한을 다시 요청할 수 있습니다. 안정적인 배포용 코드 서명 ID와 공증은 이 로컬 소스 버전의 범위에 포함되지 않습니다.

빌드한 앱을 로컬에 설치하려면 다음 명령을 실행합니다.

```sh
./install.sh
```

이 명령은 `~/Applications/VoxTypeMac.app`만 교체합니다. 별도의 비공개 설치본이나 그 데이터는 수정하지 않습니다.

## 선택 사항: Qwen3-ASR 텍스트 다듬기

```sh
./script/install-qwen.sh
```

이 스크립트는 고정 버전의 Python 런타임과 모델을 VoxTypeMac의 Application Support 디렉터리에 설치합니다. 네트워크는 설치할 때만 필요하며 추론은 로컬에서 수행됩니다. 타사 버전 및 라이선스는 `THIRD_PARTY_NOTICES.md`, `config/qwen-asr.json` 및 해시로 고정된 Python 요구 사항 파일에 정리되어 있습니다.

## 소스 안내

- `Sources/VoxType/`: 앱, 메뉴, 녹음, 음성 인식, 결과 전달 및 저장
- `Tests/VoxTypeTests/`: 네이티브 기능 및 데이터 경계 검사
- `Resources/`: 앱 메타데이터, 권한 설정 및 제품 아트워크
- `config/`: 제품 식별 정보 및 고정된 선택 모델 종속 항목
- `script/`: 빌드, 패키징, 모델 설치 및 로컬 실행 도구

소스 코드는 MIT 라이선스로 제공됩니다. 선택 사항인 모델과 런타임에는 각 상위 프로젝트의 이용 약관이 적용됩니다.
