#!/usr/bin/env python3
"""Index a caller-supplied HEVC recording for the DEBUG simulator backend.

No sample video is downloaded or distributed. Outputs remain in ignored .local/.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video", type=Path)
    parser.add_argument("--fps", type=float, default=25)
    args = parser.parse_args()
    if not 1 <= args.fps <= 120:
        parser.error("--fps must be between 1 and 120")
    video = args.video.expanduser().resolve(strict=True)
    result = subprocess.run([
        "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_packets",
        "-show_entries", "packet=pos,size:format=format_name:stream=codec_name",
        "-of", "json", str(video),
    ], check=True, capture_output=True, text=True)
    probed = json.loads(result.stdout)
    if probed.get("format", {}).get("format_name") != "hevc":
        parser.error("supply a raw Annex-B HEVC recording (.hevc), not a movie container")
    packets = [{"offset": int(p["pos"]), "size": int(p["size"])}
               for p in probed["packets"]]
    size = video.stat().st_size
    if not packets or len(packets) >= 100_000 or any(
        p["offset"] < 0 or p["size"] <= 0 or p["offset"] + p["size"] > size
        for p in packets
    ):
        parser.error("recording has no valid access units or exceeds the preview limit")
    output = Path(__file__).resolve().parent.parent / ".local" / "preview-replay"
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    media = output / "Luna-preview-recording.mp4"
    os.umask(0o077)
    subprocess.run([
        "ffmpeg", "-v", "error", "-y", "-fflags", "+genpts", "-r", str(args.fps),
        "-i", str(video), "-c", "copy", "-tag:v", "hvc1", str(media),
    ], check=True)
    index = output / "index.json"
    index.write_text(json.dumps({
        "videoPath": str(video), "mediaPath": str(media),
        "framesPerSecond": args.fps, "packets": packets,
    }) + "\n")
    index.chmod(0o600)
    media.chmod(0o600)
    print(index)


if __name__ == "__main__":
    main()
