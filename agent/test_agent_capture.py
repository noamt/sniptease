#!/usr/bin/env python3
"""
SnipTease Agent Capture — Proof of Concept

Tests the full pipeline: screenshot → VLM → bounding box → framed capture.
Simulates what an MCP tool would do when an agent says
"capture the paragraph about X for LinkedIn."

Usage:
    export GEMINI_API_KEY="your-key-here"
    python test_agent_capture.py "the code editor" --preset linkedin-feed
    python test_agent_capture.py "the email subject line" --preset ig-portrait
    python test_agent_capture.py "the terminal output showing test results"

Get a free Gemini API key at: https://aistudio.google.com/apikey
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from datetime import datetime

try:
    from PIL import Image
except ImportError:
    print("Installing Pillow...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "Pillow", "-q"])
    from PIL import Image

try:
    import requests
except ImportError:
    print("Installing requests...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "requests", "-q"])
    import requests


# ── Presets (same as the Swift app) ─────────────────────────────────

PRESETS = {
    "linkedin-feed":      {"ratio": (1, 1),     "margin": 0.08, "export_w": 1200},
    "linkedin-landscape": {"ratio": (1200, 627), "margin": 0.06, "export_w": 1200},
    "x-square":           {"ratio": (1, 1),     "margin": 0.07, "export_w": 1080},
    "x-landscape":        {"ratio": (16, 9),    "margin": 0.06, "export_w": 1200},
    "ig-square":          {"ratio": (1, 1),     "margin": 0.08, "export_w": 1080},
    "ig-portrait":        {"ratio": (4, 5),     "margin": 0.08, "export_w": 1080},
    "ig-story":           {"ratio": (9, 16),    "margin": 0.10, "export_w": 1080},
}


# ── Step 1: Screenshot ──────────────────────────────────────────────

def take_screenshot() -> Path:
    """Capture the full screen silently using macOS screencapture."""
    path = Path(tempfile.mktemp(suffix=".png"))
    subprocess.run(["screencapture", "-x", str(path)], check=True)
    print(f"  📸 Screenshot: {path} ({path.stat().st_size // 1024}KB)")
    return path


# ── Step 2: Ask VLM for bounding box ───────────────────────────────

def find_region(screenshot_path: Path, description: str, api_key: str) -> dict:
    """
    Send screenshot + description to Gemini, get back bounding box.
    Gemini returns coordinates in [0, 1000] scale as [y0, x0, y1, x1].
    """
    with open(screenshot_path, "rb") as f:
        img_b64 = base64.b64encode(f.read()).decode()

    prompt = f"""Look at this screenshot. Find the region containing: "{description}"

Return ONLY a JSON object with the bounding box of that region:
{{"box_2d": [y_min, x_min, y_max, x_max]}}

Coordinates must be on a 0-1000 scale where (0,0) is top-left and (1000,1000) is bottom-right.
Be precise — the box should tightly wrap the described content with minimal padding.
Return ONLY the JSON, no other text."""

    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={api_key}"

    payload = {
        "contents": [{
            "parts": [
                {"inline_data": {"mime_type": "image/png", "data": img_b64}},
                {"text": prompt}
            ]
        }],
        "generationConfig": {
            "temperature": 0.1,
            "maxOutputTokens": 256
        }
    }

    print(f"  🧠 Asking Gemini: \"{description}\"...")
    resp = requests.post(url, json=payload, timeout=30)
    resp.raise_for_status()

    result = resp.json()
    text = result["candidates"][0]["content"]["parts"][0]["text"]

    # Parse JSON from response (strip markdown fences if present)
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1].rsplit("```", 1)[0].strip()

    box_data = json.loads(text)
    box = box_data["box_2d"]  # [y_min, x_min, y_max, x_max] in 0-1000 scale
    print(f"  📍 Found region: {box}")
    return {"y_min": box[0], "x_min": box[1], "y_max": box[2], "x_max": box[3]}


# ── Step 3: Frame for preset ────────────────────────────────────────

def frame_for_preset(
    screenshot: Image.Image,
    region: dict,
    preset_name: str
) -> Image.Image:
    """
    Given the content region and a preset, calculate the capture frame
    that places the content inside the safe zone at the correct aspect ratio.
    Then crop and resize to export dimensions.
    """
    preset = PRESETS[preset_name]
    img_w, img_h = screenshot.size
    ratio_w, ratio_h = preset["ratio"]
    aspect = ratio_w / ratio_h
    margin = preset["margin"]
    export_w = preset["export_w"]
    export_h = int(export_w / aspect)

    # Convert 0-1000 coordinates to pixels
    content_x0 = region["x_min"] / 1000 * img_w
    content_y0 = region["y_min"] / 1000 * img_h
    content_x1 = region["x_max"] / 1000 * img_w
    content_y1 = region["y_max"] / 1000 * img_h
    content_w = content_x1 - content_x0
    content_h = content_y1 - content_y0

    print(f"  📐 Content region: {int(content_w)}×{int(content_h)}px at ({int(content_x0)}, {int(content_y0)})")

    # The content must fit inside the safe zone (frame minus margins).
    # safe_zone = frame_size * (1 - 2 * margin)
    # So frame_size = content_size / (1 - 2 * margin)
    safe_scale = max(1 - 2 * margin, 0.4)
    min_frame_w = content_w / safe_scale
    min_frame_h = content_h / safe_scale

    # Enforce the aspect ratio — expand to fit
    frame_w = max(min_frame_w, min_frame_h * aspect)
    frame_h = frame_w / aspect
    if frame_h < min_frame_h:
        frame_h = min_frame_h
        frame_w = frame_h * aspect

    # Clamp to screen bounds
    frame_w = min(frame_w, img_w)
    frame_h = min(frame_h, img_h)
    # Re-enforce aspect after clamping
    if frame_w / frame_h > aspect:
        frame_w = frame_h * aspect
    else:
        frame_h = frame_w / aspect

    # Center the frame on the content
    content_cx = (content_x0 + content_x1) / 2
    content_cy = (content_y0 + content_y1) / 2
    frame_x0 = content_cx - frame_w / 2
    frame_y0 = content_cy - frame_h / 2

    # Keep frame within screen bounds
    frame_x0 = max(0, min(frame_x0, img_w - frame_w))
    frame_y0 = max(0, min(frame_y0, img_h - frame_h))

    print(f"  🖼️  Capture frame: {int(frame_w)}×{int(frame_h)}px at ({int(frame_x0)}, {int(frame_y0)})")

    # Crop
    cropped = screenshot.crop((
        int(frame_x0), int(frame_y0),
        int(frame_x0 + frame_w), int(frame_y0 + frame_h)
    ))

    # Resize to export dimensions (high quality)
    if cropped.size[0] >= export_w:
        result = cropped.resize((export_w, export_h), Image.LANCZOS)
        print(f"  ↘️  Downscaled to {export_w}×{export_h}")
    else:
        result = cropped
        print(f"  ✅ Kept native {cropped.size[0]}×{cropped.size[1]} (larger than export = upscale, skipped)")

    return result


# ── Main ────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="SnipTease Agent Capture — proof of concept"
    )
    parser.add_argument(
        "description",
        help="What to capture, in plain English"
    )
    parser.add_argument(
        "--preset", "-p",
        default="linkedin-feed",
        choices=list(PRESETS.keys()),
        help="Social media preset (default: linkedin-feed)"
    )
    parser.add_argument(
        "--output", "-o",
        default=None,
        help="Output path (default: Desktop)"
    )
    parser.add_argument(
        "--input", "-i",
        default=None,
        help="Use an existing screenshot instead of capturing one"
    )
    args = parser.parse_args()

    # API key
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print("❌ Set GEMINI_API_KEY environment variable first.")
        print("   Get a free key at: https://aistudio.google.com/apikey")
        sys.exit(1)

    print(f"\n🎯 SnipTease Agent Capture")
    print(f"   Description: \"{args.description}\"")
    print(f"   Preset: {args.preset}\n")

    # Pipeline
    if args.input:
        screenshot_path = Path(args.input)
        print(f"  📸 Using: {screenshot_path}")
    else:
        screenshot_path = take_screenshot()
    screenshot = Image.open(screenshot_path)

    region = find_region(screenshot_path, args.description, api_key)
    result = frame_for_preset(screenshot, region, args.preset)

    # Save
    if args.output:
        output_path = Path(args.output)
    else:
        ts = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        output_path = Path.home() / "Desktop" / f"SnipTease_agent_{args.preset}_{ts}.png"

    # Set DPI to 144 (Retina)
    result.save(str(output_path), "PNG", dpi=(144, 144))

    # Cleanup (only if we took the screenshot ourselves)
    if not args.input:
        screenshot_path.unlink(missing_ok=True)

    print(f"\n✅ Saved: {output_path}")
    print(f"   Dimensions: {result.size[0]}×{result.size[1]}")
    print(f"   Preset: {args.preset}")
    print(f"   Size: {output_path.stat().st_size // 1024}KB\n")


if __name__ == "__main__":
    main()
