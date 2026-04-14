#!/usr/bin/env python3
"""Generate Avataaars Neutral face assets for the ESP32 demo firmware.

This script downloads five state-specific PNGs from DiceBear, converts them
to RGB565, and writes a C++ header that can be included by the Arduino sketch.
"""

from __future__ import annotations

import io
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_HEADER = ROOT / "face_theme_assets.h"
PREVIEW_DIR = ROOT / "tools" / "generated_face_previews"
API_ROOT = "https://api.dicebear.com/9.x/avataaars-neutral/png"
IMAGE_SIZE = 168


STATE_CONFIGS = [
    {
        "name": "idle",
        "label": "IDLE",
        "background": "dbeeff",
        "eyebrows": "defaultNatural",
        "eyes": "default",
        "mouth": "smile",
    },
    {
        "name": "active",
        "label": "ACTIVE",
        "background": "dcf7e8",
        "eyebrows": "raisedExcitedNatural",
        "eyes": "happy",
        "mouth": "smile",
    },
    {
        "name": "listening",
        "label": "LISTENING",
        "background": "ffe6d8",
        "eyebrows": "upDownNatural",
        "eyes": "side",
        "mouth": "serious",
    },
    {
        "name": "processing",
        "label": "PROCESSING",
        "background": "ebe5ff",
        "eyebrows": "frownNatural",
        "eyes": "squint",
        "mouth": "concerned",
    },
    {
        "name": "speaking",
        "label": "SPEAKING",
        "background": "ffdfe8",
        "eyebrows": "raisedExcited",
        "eyes": "happy",
        "mouth": "default",
    },
]


def rgb888_to_565(red: int, green: int, blue: int) -> int:
    return ((red & 0xF8) << 8) | ((green & 0xFC) << 3) | (blue >> 3)


def bg_rgb565(color_hex: str) -> int:
    red = int(color_hex[0:2], 16)
    green = int(color_hex[2:4], 16)
    blue = int(color_hex[4:6], 16)
    return rgb888_to_565(red, green, blue)


def build_url(config: dict[str, str]) -> str:
    query = {
        "size": str(IMAGE_SIZE),
        "backgroundType": "solid",
        "backgroundColor": config["background"],
        "eyebrows": config["eyebrows"],
        "eyes": config["eyes"],
        "mouth": config["mouth"],
        "nose": "default",
    }
    return f"{API_ROOT}?{urllib.parse.urlencode(query)}"


def load_image(config: dict[str, str]) -> Image.Image:
    request = urllib.request.Request(
        build_url(config),
        headers={"User-Agent": "AI-Bot face asset generator"},
    )
    with urllib.request.urlopen(request) as response:
        payload = response.read()
    image = Image.open(io.BytesIO(payload)).convert("RGBA")
    if image.size != (IMAGE_SIZE, IMAGE_SIZE):
        image = image.resize((IMAGE_SIZE, IMAGE_SIZE), Image.LANCZOS)
    return image


def image_to_rgb565(image: Image.Image) -> list[int]:
    pixels: list[int] = []
    for red, green, blue, alpha in image.getdata():
        if alpha == 0:
            pixels.append(0)
            continue
        pixels.append(rgb888_to_565(red, green, blue))
    return pixels


def format_uint16_array(name: str, values: list[int]) -> str:
    lines = []
    for index in range(0, len(values), 12):
        chunk = ", ".join(f"0x{value:04X}" for value in values[index:index + 12])
        lines.append(f"    {chunk},")
    joined = "\n".join(lines)
    return f"static const uint16_t {name}[FACE_THEME_IMAGE_PIXELS] PROGMEM = {{\n{joined}\n}};\n"


def render_header(arrays: list[str]) -> str:
    background_lines = ",\n".join(
        f"    0x{bg_rgb565(config['background']):04X}" for config in STATE_CONFIGS
    )
    face_ptr_lines = ",\n".join(
        f"    faceTheme{config['label'].title().replace('_', '')}" for config in STATE_CONFIGS
    )
    arrays_block = "\n".join(arrays)
    return (
        "#ifndef FACE_THEME_ASSETS_H\n"
        "#define FACE_THEME_ASSETS_H\n\n"
        "#include <Arduino.h>\n"
        "#include <stdint.h>\n\n"
        f"static constexpr int FACE_THEME_IMAGE_W = {IMAGE_SIZE};\n"
        f"static constexpr int FACE_THEME_IMAGE_H = {IMAGE_SIZE};\n"
        "static constexpr int FACE_THEME_IMAGE_PIXELS = FACE_THEME_IMAGE_W * FACE_THEME_IMAGE_H;\n\n"
        f"{arrays_block.rstrip()}\n\n"
        "static const uint16_t FACE_THEME_BACKGROUNDS[5] = {\n"
        f"{background_lines}\n"
        "};\n\n"
        "static const uint16_t* const FACE_THEME_IMAGES[5] = {\n"
        f"{face_ptr_lines}\n"
        "};\n\n"
        "#endif  // FACE_THEME_ASSETS_H\n"
    )


def main() -> None:
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    arrays: list[str] = []
    for config in STATE_CONFIGS:
        image = load_image(config)
        image.save(PREVIEW_DIR / f"{config['name']}.png")
        variable_name = f"faceTheme{config['label'].title().replace('_', '')}"
        arrays.append(format_uint16_array(variable_name, image_to_rgb565(image)))
    OUTPUT_HEADER.write_text(render_header(arrays), encoding="utf-8")
    print(f"Wrote {OUTPUT_HEADER}")
    print(f"Preview PNGs: {PREVIEW_DIR}")


if __name__ == "__main__":
    main()
