#!/usr/bin/env python3
"""Download only pinned public model artifacts. Recordings never enter this process."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import subprocess
import shutil

ROOT = Path(__file__).resolve().parent.parent
CONFIG = json.loads((ROOT / "config/qwen-asr.json").read_text())
STATE_ROOT = Path(os.environ["VOXTYPE_STATE_ROOT"])
DESTINATION = STATE_ROOT / "models/qwen3-asr"


def verify(path, artifact):
    if not path.is_file() or path.stat().st_size != artifact["size"]:
        return False
    digest = hashlib.sha256() if artifact["sha256"] else hashlib.sha1()
    if not artifact["sha256"]:
        digest.update(f"blob {artifact['size']}\0".encode())
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest() == (artifact["sha256"] or artifact["gitBlob"])


def download(artifact):
    destination = DESTINATION / artifact["name"]
    if verify(destination, artifact):
        print(f"Verified cached {destination.name}", flush=True)
        return
    partial = destination.with_name(destination.name + ".partial")
    url = (f"https://huggingface.co/{CONFIG['repository']}/resolve/"
           f"{CONFIG['revision']}/{artifact['name']}?download=true")
    if artifact["size"] > 128 * 1024 * 1024:
        # Bounded range requests avoid a single slow CDN connection. Each range
        # is retained for restart; the assembled file still needs its full hash.
        chunk_size = 32 * 1024 * 1024
        ranges = [(start, min(start + chunk_size, artifact["size"]) - 1)
                  for start in range(0, artifact["size"], chunk_size)]

        def fetch_range(bounds):
            start, end = bounds
            part = destination.with_name(f"{destination.name}.range-{start}")
            if part.exists() and part.stat().st_size == end - start + 1:
                return part
            subprocess.run([
                "/usr/bin/curl", "--fail", "--location", "--silent", "--show-error",
                "--retry", "2", "--retry-all-errors", "--connect-timeout", "20", "--max-time", "600",
                "--range", f"{start}-{end}", "--output", str(part), url,
            ], check=True)
            if part.stat().st_size != end - start + 1:
                raise RuntimeError("Server did not honor the requested byte range")
            print(f"Verified range size {start}-{end}", flush=True)
            return part

        with ThreadPoolExecutor(max_workers=8) as pool:
            parts = list(pool.map(fetch_range, ranges))
        with partial.open("wb") as output:
            for part in parts:
                with part.open("rb") as source:
                    shutil.copyfileobj(source, output, 4 * 1024 * 1024)
        if not verify(partial, artifact):
            raise RuntimeError("Assembled model failed SHA-256 verification")
        partial.replace(destination)
        print(f"Downloaded and verified {destination.name}", flush=True)
        return
    subprocess.run([
        "/usr/bin/curl", "--fail", "--location", "--silent", "--show-error",
        "--retry", "2", "--retry-all-errors", "--connect-timeout", "20", "--speed-limit", "1024",
        "--speed-time", "60", "--continue-at", "-", "--output", str(partial), url,
    ], check=True)
    if not verify(partial, artifact):
        raise RuntimeError(f"Verification failed for {artifact['name']}; preserved partial file")
    partial.replace(destination)
    print(f"Downloaded and verified {destination.name}", flush=True)


if __name__ == "__main__":
    DESTINATION.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(download, CONFIG["files"]))
    receipt = DESTINATION / "verified.json"
    temporary = receipt.with_suffix(".pending")
    temporary.write_text(json.dumps(CONFIG, indent=2) + "\n")
    temporary.replace(receipt)
    print("Qwen3-ASR model ready; all artifacts verified.", flush=True)
