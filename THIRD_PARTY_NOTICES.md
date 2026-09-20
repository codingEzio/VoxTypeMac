# Third-party notices

## SenseVoiceSmall / FunASR

VoxTypeMac can download and use the SenseVoiceSmall q8 model and the FunASR
llama.cpp runtime for its local final transcription pass. These
artifacts are not included in VoxTypeMac or this repository.

- Model: SenseVoiceSmall by FunAudioLLM / FunASR / Alibaba Group
- Runtime: FunASR llama.cpp runtime
- Model terms: FunASR Model Open Source License Agreement 1.1
- Required attribution: retain the FunASR source, author information, and the
  SenseVoiceSmall model name.
- Source: https://github.com/FunAudioLLM/SenseVoice
- Model: https://huggingface.co/FunAudioLLM/SenseVoiceSmall-GGUF
- Terms: https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE

The runtime archive is pinned to `runtime-llamacpp-v0.1.4`; the q8 model is
pinned to Hugging Face revision
`90c1c61912018b70ada0fcc024ea24aca62f2e63`. VoxTypeMac verifies both artifacts by
SHA-256 before making them executable or available.

## Qwen3-ASR / MLX

- Original model: [Qwen3-ASR-1.7B](https://huggingface.co/Qwen/Qwen3-ASR-1.7B), Qwen team, Apache-2.0.
- Conversion: [mlx-community/Qwen3-ASR-1.7B-8bit](https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit), converted with mlx-audio 0.3.1, Apache-2.0. Exact revision, sizes and hashes: `config/qwen-asr.json`.
- Runtime: [mlx-qwen3-asr 0.4.0](https://github.com/moona3k/mlx-qwen3-asr), Apache-2.0. Runs original and quantized Qwen checkpoints with MLX on Apple Silicon.
- [Apple MLX](https://github.com/ml-explore/mlx), MIT. The dependency lock identifies the exact Python and Metal wheels, NumPy, tokenizer and Hugging Face client dependencies. Their installed `.dist-info` directories retain their own license files.
- Installer: [uv](https://docs.astral.sh/uv/), MIT / Apache-2.0, separately installed tool; verified with 0.12.13. CPython 3.12.14 (PSF license) is installed under the VoxTypeMac Application Support directory.

Run `./script/install-qwen.sh` to fetch the pinned runtime and model. All of these
runtime artifacts stay outside Git and the app bundle under the VoxTypeMac
Application Support directory. Only
the small project-owned helper and model manifest are bundled. Internet access
is needed for setup; model inference runs locally and offline. The native app
remains macOS-only. The Python inference helper is Apple Silicon-specific due
to MLX; a Linux deployment is not part of this upgrade.
