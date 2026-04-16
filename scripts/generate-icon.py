#!/usr/bin/env python3
"""
Generate app icon using Google Gemini / Imagen.
Part of the portable aso/ system.

Usage:
  GEMINI_API_KEY=xxx python3 aso/generate-icon.py --preset blob-bird
  GEMINI_API_KEY=xxx python3 aso/generate-icon.py "your custom prompt"
  GEMINI_API_KEY=xxx python3 aso/generate-icon.py --all
  GEMINI_API_KEY=xxx python3 aso/generate-icon.py --label my_icon "custom prompt"
  GEMINI_API_KEY=xxx python3 aso/generate-icon.py --count 2 --preset blob-cat
"""

import sys
import os
import json
from datetime import datetime
from pathlib import Path
from io import BytesIO

from google import genai
from google.genai import types
from PIL import Image

ICONS_DIR = Path(__file__).parent / "icons"
ICONS_DIR.mkdir(exist_ok=True)

CONFIG_PATH = Path(__file__).parent / "config.json"
APP_NAME = "App"
if CONFIG_PATH.exists():
    with open(CONFIG_PATH) as f:
        cfg = json.load(f)
        APP_NAME = cfg.get("app", {}).get("name", "App")

# ── Style base prompts ──────────────────────────────────────────────
# These define the visual style. Character presets combine a character + style.

STYLES = {
    "modern-blob": "Modern iOS app icon. Minimal, soft 3D feel, subtle gradient, very simple blob-like shape. Soft warm cream background. No text, no extra details. Clean rounded iOS icon style. 1024x1024.",
    "neubrutalist": "Neubrutalist style iOS app icon. Thick black outlines, offset black shadow, bold playful graphic design. No text. 1024x1024.",
    "clay": "3D clay render iOS app icon. Soft puffy rounded shapes, smooth matte clay texture, subtle shadows, minimal design. Professional 1024x1024 app store icon. No text. Clean, modern, friendly.",
    "gradient": "Modern gradient iOS app icon. Smooth, clean, minimal. 1024x1024. No text.",
    "glossy": "3D glossy iOS app icon. Glass/glossy material, subtle reflections, modern premium feel. 1024x1024. No text.",
    "flat": "Ultra minimal flat iOS app icon. Clean lines, no gradients, no shadows. Swiss design style. 1024x1024. No text.",
    "aura-sketch": "Hand-drawn sketch-notebook style iOS illustration. Soft cream #FAFAF7 background, lime green #D4EC5B and mint #B9E4DD accents, thin ink outline, friendly childlike character design, SF Pro Rounded feeling, pinned notebook aesthetic. Transparent background suitable for SwiftUI asset. 1024x1024. No text.",
    "3d-mascot": "Cute 3D rendered character illustration for a mobile app. Pixar/Disney style, soft lighting, smooth rounded shapes, expressive big eyes, friendly and approachable. Soft neutral gradient background. No text, no UI elements. High quality 1024x1024 PNG with clean edges. The character should be suitable for use as an in-app mascot guide.",
    "3d-mascot-clean": "Cute 3D rendered character on a perfectly solid pure white #FFFFFF background. Pixar/Disney style, soft studio lighting, smooth rounded shapes, expressive big eyes. No shadows on background, no gradients, no floor, no environment. Character floating in center. Clean edges for easy background removal. No text. 1024x1024 PNG.",
}

# ── AuraGLP mascot: Auri the red panda ───────────────────────────────
# Generated poses for in-app character animation. See
# AuraGLP/Features/Character/CharacterView.swift for usage.
AURI_BASE = (
    "A cute round red panda character named Auri, mascot of a GLP-1 "
    "health tracking app. Soft rust-orange fur with cream face and "
    "belly, dark eye patches, round fluffy ears, big friendly eyes, "
    "bushy striped tail. Gentle, reassuring, non-judgmental expression."
)

# ── Character presets ────────────────────────────────────────────────
# Each preset = character description + default style

PRESETS = {
    # Blob characters (modern-blob style)
    "blob-bird": {
        "style": "modern-blob",
        "character": "A cute simple round bird character with two big round eyes, tiny beak, and small wings. Solid warm orange #FE7648.",
    },
    "blob-cat": {
        "style": "modern-blob",
        "character": "A cute simple round cat character with two big eyes and tiny ears on top. Solid orange #FE7648.",
    },
    "blob-fox": {
        "style": "modern-blob",
        "character": "A cute simple fox character face with pointed ears, big round eyes and a small nose. Solid warm orange #FE7648.",
    },
    "blob-bear": {
        "style": "modern-blob",
        "character": "A cute simple bear character face with round ears, big friendly eyes and a small snout. Solid warm orange #FE7648.",
    },
    "blob-octo": {
        "style": "modern-blob",
        "character": "A cute simple octopus character with big round eyes, small tentacles at the bottom. Solid warm orange #FE7648.",
    },
    "blob-ghost": {
        "style": "modern-blob",
        "character": "A cute simple blob ghost character with two big white oval eyes, like a friendly ghost. Solid orange #FE7648.",
    },
    "peek-blob": {
        "style": "modern-blob",
        "character": "A simple cute ghost-like blob character peeking up from the bottom, with two curious round eyes looking up. White/cream colored character with soft shadow. Gradient background from warm orange to coral instead of cream.",
    },

    # Neubrutalist characters
    "nb-bird": {
        "style": "neubrutalist",
        "character": "A cute round bird with big eyes and tiny beak. Orange #FE7648 and purple #A349FF colors. Lavender #EFEFFF background.",
    },
    "nb-robot": {
        "style": "neubrutalist",
        "character": "A cute friendly robot teacher holding a book and pencil. Purple #A349FF body, orange #FE7648 accents. Lavender #EFEFFF background.",
    },

    # Clay characters
    "clay-bird": {
        "style": "clay",
        "character": f"A cute round bird character for education app {APP_NAME}. Warm orange #FE7648 color. Soft cream background.",
    },

    # ── Auri (AuraGLP mascot) ───────────────────────────────────
    "auri-idle": {
        "style": "aura-sketch",
        "character": f"{AURI_BASE} Standing upright in a neutral idle pose, arms relaxed at sides, gentle closed-mouth smile. Default pose for in-app avatar.",
    },
    "auri-wave": {
        "style": "aura-sketch",
        "character": f"{AURI_BASE} Waving one paw cheerfully in greeting, warm welcoming expression. Used on onboarding welcome screen.",
    },
    "auri-celebrate": {
        "style": "aura-sketch",
        "character": f"{AURI_BASE} Both arms raised overhead in celebration, eyes squinted with joy, small confetti pieces floating around. Used on streak milestones and goal achievement.",
    },
    "auri-sleep": {
        "style": "aura-sketch",
        "character": f"{AURI_BASE} Curled up peacefully asleep, tail wrapped around body, small 'Z' symbols above. Used on bedtime reminders and empty night states.",
    },
    "auri-thinking": {
        "style": "aura-sketch",
        "character": f"{AURI_BASE} Sitting with one paw on chin in a thoughtful curious pose, head slightly tilted. Used on empty states and 'no data yet' screens.",
    },
    "auri-drink": {
        "style": "aura-sketch",
        "character": f"{AURI_BASE} Holding a large water droplet between both paws with a happy expression. Used on hydration tracker.",
    },
    "auri-dose": {
        "style": "aura-sketch",
        "character": f"{AURI_BASE} Gently holding a small safe-looking syringe icon with both paws, calm reassuring expression. Used on dose reminders. Non-alarming medical illustration.",
    },
    "auri-worried": {
        "style": "aura-sketch",
        "character": f"{AURI_BASE} Gentle concerned but warm expression, head slightly lowered, one paw raised caringly. Used when the user reports side effects.",
    },
    "auri-proud": {
        "style": "aura-sketch",
        "character": f"{AURI_BASE} Standing tall with paws on hips, small crown or sparkle above head, proud beaming smile. Used on Pro paywall and achievements.",
    },
}


def build_prompt(preset_name=None, custom_prompt=None, style_override=None):
    """Build a full prompt from preset or custom input."""
    if custom_prompt:
        return custom_prompt

    if preset_name and preset_name in PRESETS:
        preset = PRESETS[preset_name]
        style_key = style_override or preset["style"]
        style = STYLES.get(style_key, STYLES["modern-blob"])
        return f"{preset['character']} {style}"

    return custom_prompt or ""


def generate_imagen(prompt, api_key, num_images=4):
    """Generate images using Imagen 4."""
    client = genai.Client(api_key=api_key)

    response = client.models.generate_images(
        model="imagen-4.0-generate-001",
        prompt=prompt,
        config=types.GenerateImagesConfig(
            number_of_images=num_images,
            aspect_ratio="1:1",
        )
    )

    images = []
    for img in response.generated_images:
        image = Image.open(BytesIO(img.image.image_bytes))
        images.append(image)
    return images


def generate_gemini_flash(prompt, api_key, num_images=4):
    """Generate images using Gemini 2.5 Flash (image gen)."""
    client = genai.Client(api_key=api_key)

    images = []
    for i in range(num_images):
        print(f"  Generating {i+1}/{num_images}...")
        response = client.models.generate_content(
            model="gemini-2.5-flash-image",
            contents=prompt,
            config=types.GenerateContentConfig(
                response_modalities=["TEXT", "IMAGE"],
            )
        )
        for part in response.candidates[0].content.parts:
            if part.inline_data is not None:
                image = Image.open(BytesIO(part.inline_data.data))
                images.append(image)
    return images


def generate(prompt, api_key, num_images=4):
    """Try Imagen 4 first, fall back to Gemini 2.5 Flash."""
    try:
        print("  Using Imagen 4...")
        return generate_imagen(prompt, api_key, num_images)
    except Exception as e:
        print(f"  Imagen 4 failed: {e}")
        print("  Falling back to Gemini 2.5 Flash...")
        try:
            return generate_gemini_flash(prompt, api_key, num_images)
        except Exception as e2:
            print(f"  Gemini Flash also failed: {e2}")
            raise


def save_images(images, label):
    """Save images to icons directory."""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    saved = []
    for i, img in enumerate(images):
        img_resized = img.resize((1024, 1024), Image.LANCZOS)
        path = ICONS_DIR / f"{label}_{timestamp}_{i+1}.png"
        img_resized.save(path, "PNG")
        saved.append(path)
        print(f"  Saved: {path}")
    return saved


def main():
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        # Try loading from ~/.aso/credentials
        cred_file = os.path.expanduser("~/.aso/credentials")
        if os.path.exists(cred_file):
            with open(cred_file) as f:
                for line in f:
                    if line.startswith("GEMINI_API_KEY="):
                        api_key = line.strip().split("=", 1)[1]
                        break
    if not api_key:
        print("Error: Gemini API key not found.")
        print("Run: /aso icons generate  (it will ask for your key)")
        print("Or set: export GEMINI_API_KEY=your-key")
        sys.exit(1)

    args = sys.argv[1:]
    if not args:
        print(f"Usage:")
        print(f"  python3 aso/generate-icon.py --preset <name>")
        print(f"  python3 aso/generate-icon.py --all")
        print(f"  python3 aso/generate-icon.py --label <name> 'custom prompt'")
        print(f"  python3 aso/generate-icon.py 'custom prompt'")
        print(f"\nPresets: {', '.join(PRESETS.keys())}")
        print(f"Styles:  {', '.join(STYLES.keys())}")
        sys.exit(1)

    # Parse flags
    label = "custom"
    num_images = 4
    style_override = None
    i = 0
    positional = []

    while i < len(args):
        if args[i] == "--label" and i + 1 < len(args):
            label = args[i + 1]
            i += 2
        elif args[i] == "--count" and i + 1 < len(args):
            num_images = int(args[i + 1])
            i += 2
        elif args[i] == "--style" and i + 1 < len(args):
            style_override = args[i + 1]
            i += 2
        else:
            positional.append(args[i])
            i += 1

    # --all: generate all presets
    if positional and positional[0] == "--all":
        for name in PRESETS:
            print(f"\n{'='*50}")
            print(f"Preset: {name}")
            try:
                prompt = build_prompt(preset_name=name, style_override=style_override)
                images = generate(prompt, api_key, num_images=2)
                save_images(images, name)
            except Exception as e:
                print(f"  Failed: {e}")
        print(f"\nDone! Check: {ICONS_DIR}/")
        return

    # --preset <name>
    if positional and positional[0] == "--preset":
        name = positional[1] if len(positional) > 1 else "blob-bird"
        if name not in PRESETS:
            print(f"Unknown preset: {name}")
            print(f"Available: {', '.join(PRESETS.keys())}")
            sys.exit(1)
        prompt = build_prompt(preset_name=name, style_override=style_override)
        if label == "custom":
            label = name
    else:
        # Custom prompt
        prompt = " ".join(positional)

    print(f"App: {APP_NAME}")
    print(f"Label: {label}")
    print(f"Prompt: {prompt[:120]}...")
    print(f"Generating {num_images} variations...\n")

    images = generate(prompt, api_key, num_images=num_images)
    save_images(images, label)
    print(f"\nDone! {len(images)} icons in {ICONS_DIR}/")


if __name__ == "__main__":
    main()
