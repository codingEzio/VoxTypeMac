#!/usr/bin/env python3
"""Offline Qwen3-ASR final pass. Stdout contains only the recognized text."""
import argparse
import contextlib
from importlib.metadata import version
import json
from pathlib import Path
import sys
import time
import wave


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--audio", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.config.read_text())
    runtime = args.model.resolve().parent.parent
    if not args.audio.resolve().is_relative_to(runtime):
        raise ValueError("Audio must remain in the VoxTypeMac data directory")
    if version("mlx-qwen3-asr") != config["runtimePackage"].split("==")[1]:
        raise ValueError("The installed ASR runtime differs from the pinned version")
    if json.loads((args.model / "verified.json").read_text()) != config:
        raise ValueError("The model verification receipt differs from the selected model")

    started = time.monotonic()
    with contextlib.redirect_stdout(sys.stderr):
        import mlx.core as mx
        import numpy as np
        from mlx_qwen3_asr import Session

        if not mx.metal.is_available():
            raise RuntimeError("Metal is unavailable for local recognition")
        mx.set_default_device(mx.gpu)
        mx.set_memory_limit(config["memoryLimitBytes"])
        mx.set_cache_limit(config["cacheLimitBytes"])
        with wave.open(str(args.audio), "rb") as audio:
            if (audio.getframerate(), audio.getnchannels(), audio.getsampwidth()) != (16000, 1, 2):
                raise ValueError("Expected mono 16-bit PCM at 16 kHz")
            samples = np.frombuffer(audio.readframes(audio.getnframes()), dtype="<i2")
            samples = samples.astype(np.float32) / 32768.0
        if samples.size == 0 or not np.any(samples):
            return
        session = Session(model=str(args.model), dtype=mx.bfloat16)
        # Automatic language detection preserves code switching. No translation,
        # generated context, or forced single-language decoding is requested.
        result = session.transcribe(samples, language=None, max_new_tokens=config["maxNewTokens"])
        text = result.text.strip()
        if len(text.encode("utf-8")) > 1024 * 1024:
            raise ValueError("Recognition output exceeds the supported size")
        print("QWEN_METRICS " + json.dumps({
            "seconds": round(time.monotonic() - started, 3),
            "peakMemoryBytes": mx.get_peak_memory(), "device": "Metal GPU",
        }), file=sys.stderr)
    print(text, flush=True)


if __name__ == "__main__":
    main()
