#!/bin/bash
# ── cmd/translate.sh — AI-powered metadata translation ─────────────────────
# Translates metadata to target locales using Gemini AI
# Usage: bash run.sh translate [--from en-US] [--to tr,de,fr,ja]

set -uo pipefail

require_gemini_key

header "Translate Metadata — $APP_NAME"

# Parse args
FROM_LOCALE=""
TO_LOCALES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM_LOCALE="$2"; shift 2 ;;
    --to)   TO_LOCALES="$2"; shift 2 ;;
    *)      shift ;;
  esac
done

# Find latest metadata
METADATA_FILE=$(ls -t "$ASO_DIR/data/research"/updated_metadata_*.json "$ASO_DIR/data/research"/optimized_metadata_*.json 2>/dev/null | head -1)
[[ -n "$METADATA_FILE" ]] || die "No metadata file found. Run: /aso metadata first"

info "Source: $(basename "$METADATA_FILE")"

# Auto-detect source locale if not specified
if [[ -z "$FROM_LOCALE" ]]; then
  FROM_LOCALE=$(python3 -c "
import json
data = json.load(open('$METADATA_FILE'))
locales = list(data.get('metadata', {}).keys())
# Prefer en-US, then first available
if 'en-US' in locales: print('en-US')
elif locales: print(locales[0])
" 2>/dev/null)
fi

[[ -n "$FROM_LOCALE" ]] || die "No source locale found in metadata"
info "Source locale: $FROM_LOCALE"

# Determine target locales
if [[ -z "$TO_LOCALES" ]]; then
  # Use configured locales minus the source
  TO_LOCALES=$(python3 -c "
import json
data = json.load(open('$CONFIG'))
locales = data.get('locales', [])
locales = [l for l in locales if l != '$FROM_LOCALE']
print(','.join(locales))
" 2>/dev/null)
fi

[[ -n "$TO_LOCALES" ]] || die "No target locales. Use: /aso translate --to tr,de,fr"
info "Target locales: $TO_LOCALES"
echo ""

# Run translation via Gemini
DATE=$(date +%Y-%m-%d)
OUTPUT_FILE="$ASO_DIR/data/research/translated_metadata_$DATE.json"

python3 - "$METADATA_FILE" "$FROM_LOCALE" "$TO_LOCALES" "$OUTPUT_FILE" "$GEMINI_API_KEY" << 'PYEOF'
import json, sys, os

METADATA_PATH = sys.argv[1]
FROM_LOCALE = sys.argv[2]
TO_LOCALES = sys.argv[3].split(",")
OUTPUT_PATH = sys.argv[4]
API_KEY = sys.argv[5]

try:
    from google import genai
except ImportError:
    print("Error: google-genai not installed. Run: pip3 install google-genai")
    sys.exit(1)

# Load source metadata
with open(METADATA_PATH) as f:
    data = json.load(f)

source = data.get("metadata", {}).get(FROM_LOCALE, {})
if not source:
    print(f"Error: No metadata found for locale {FROM_LOCALE}")
    sys.exit(1)

title = source.get("title", "")
subtitle = source.get("subtitle", "")
keywords = source.get("keywords", "")
description = source.get("description", "")

# Locale name mapping for better translations
LOCALE_NAMES = {
    "en-US": "English (US)", "en-GB": "English (UK)", "en-AU": "English (AU)",
    "tr": "Turkish", "de-DE": "German", "fr-FR": "French", "es-ES": "Spanish",
    "it": "Italian", "pt-BR": "Portuguese (Brazil)", "pt-PT": "Portuguese (Portugal)",
    "ja": "Japanese", "ko": "Korean", "zh-Hans": "Chinese (Simplified)",
    "zh-Hant": "Chinese (Traditional)", "ar-SA": "Arabic", "nl-NL": "Dutch",
    "sv": "Swedish", "no": "Norwegian", "da": "Danish", "fi": "Finnish",
    "ru": "Russian", "pl": "Polish", "th": "Thai", "vi": "Vietnamese",
    "id": "Indonesian", "ms": "Malay", "hi": "Hindi", "uk": "Ukrainian",
    "cs": "Czech", "el": "Greek", "ro": "Romanian", "hu": "Hungarian",
    "sk": "Slovak", "hr": "Croatian", "ca": "Catalan", "he": "Hebrew",
}

client = genai.Client(api_key=API_KEY)
result_metadata = dict(data.get("metadata", {}))

for locale in TO_LOCALES:
    locale = locale.strip()
    lang_name = LOCALE_NAMES.get(locale, locale)
    print(f"  Translating to {locale} ({lang_name})...")

    prompt = f"""You are an expert App Store Optimization (ASO) translator.
Translate the following iOS app metadata from {LOCALE_NAMES.get(FROM_LOCALE, FROM_LOCALE)} to {lang_name}.

RULES:
- Title: max 30 characters. Keep it catchy and natural in {lang_name}.
- Subtitle: max 30 characters. Complement the title.
- Keywords: max 100 characters. Comma-separated, NO spaces after commas, singular forms, locally relevant terms in {lang_name}. Do NOT repeat words from title or subtitle.
- Description: max 4000 characters. Natural, fluent {lang_name}. Not a word-by-word translation. Adapt cultural references. Keep App Store formatting (line breaks, emojis if present).

SOURCE ({LOCALE_NAMES.get(FROM_LOCALE, FROM_LOCALE)}):
Title: {title}
Subtitle: {subtitle}
Keywords: {keywords}
Description:
{description}

Respond ONLY with valid JSON (no markdown, no code blocks):
{{"title": "...", "subtitle": "...", "keywords": "...", "description": "..."}}"""

    try:
        response = client.models.generate_content(
            model="gemini-2.0-flash",
            contents=prompt
        )
        text = response.text.strip()
        # Clean potential markdown wrapping
        if text.startswith("```"):
            text = text.split("\n", 1)[1].rsplit("```", 1)[0].strip()

        translated = json.loads(text)

        # Validate lengths
        if len(translated.get("title", "")) > 30:
            translated["title"] = translated["title"][:30]
        if len(translated.get("subtitle", "")) > 30:
            translated["subtitle"] = translated["subtitle"][:30]
        if len(translated.get("keywords", "")) > 100:
            translated["keywords"] = translated["keywords"][:100]

        result_metadata[locale] = translated
        t = translated
        print(f"    ✓ Title: {t['title']} ({len(t['title'])}ch)")
        print(f"      Subtitle: {t['subtitle']} ({len(t['subtitle'])}ch)")
        print(f"      Keywords: {len(t['keywords'])}ch")
    except Exception as e:
        print(f"    ✗ Failed: {e}")

# Save
output = dict(data)
output["metadata"] = result_metadata
output["_translation"] = {
    "source_locale": FROM_LOCALE,
    "translated_locales": TO_LOCALES,
    "date": sys.argv[4].split("_")[-1].replace(".json", "")
}

with open(OUTPUT_PATH, "w") as f:
    json.dump(output, f, indent=2, ensure_ascii=False)

print(f"\n  ✓ Saved to {os.path.basename(OUTPUT_PATH)}")
print(f"  Total locales: {len(result_metadata)}")
PYEOF

echo ""
ok "Translation complete"
echo -e "  ${DIM}Review: cat $OUTPUT_FILE${NC}"
echo -e "  ${DIM}Push:   /aso push${NC}"
