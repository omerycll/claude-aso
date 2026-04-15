#!/bin/bash
# ── cmd/whats_new.sh — Generate "What's New" from git history ──────────────
# Usage: bash run.sh whats-new [--since v1.0] [--locale en-US,tr] [--push]

set -uo pipefail

header "What's New — $APP_NAME"

# Parse args
SINCE=""
TARGET_LOCALES=""
DO_PUSH=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)  SINCE="$2"; shift 2 ;;
    --locale) TARGET_LOCALES="$2"; shift 2 ;;
    --push)   DO_PUSH=true; shift ;;
    *)        shift ;;
  esac
done

# Determine git range
cd "$PROJECT_ROOT"

if [[ -z "$SINCE" ]]; then
  # Find last tag
  SINCE=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
  if [[ -z "$SINCE" ]]; then
    # Last 20 commits
    SINCE="HEAD~20"
    info "No tags found, using last 20 commits"
  else
    info "Since last tag: $SINCE"
  fi
fi

# Get git log
step "Reading git history..."

GIT_LOG=$(git log "$SINCE"..HEAD --oneline --no-merges 2>/dev/null || git log -20 --oneline --no-merges 2>/dev/null)

if [[ -z "$GIT_LOG" ]]; then
  warn "No commits found since $SINCE"
  exit 0
fi

COMMIT_COUNT=$(echo "$GIT_LOG" | wc -l | tr -d ' ')
ok "$COMMIT_COUNT commits found"
echo ""
echo -e "  ${DIM}$GIT_LOG${NC}"
echo ""

# Determine locales
if [[ -z "$TARGET_LOCALES" ]]; then
  TARGET_LOCALES=$(python3 -c "
import json
data = json.load(open('$CONFIG'))
print(','.join(data.get('locales', ['en-US'])))
" 2>/dev/null || echo "en-US")
fi

# Generate What's New with Gemini
step "Generating release notes..."

load_credentials

DATE=$(date +%Y-%m-%d)
OUTPUT_FILE="$ASO_DIR/data/changelog/whats_new_$DATE.json"

if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  python3 - "$GIT_LOG" "$TARGET_LOCALES" "$OUTPUT_FILE" "$GEMINI_API_KEY" "$APP_NAME" << 'PYEOF'
import json, sys

GIT_LOG = sys.argv[1]
LOCALES = sys.argv[2].split(",")
OUTPUT_PATH = sys.argv[3]
API_KEY = sys.argv[4]
APP_NAME = sys.argv[5]

try:
    from google import genai
except ImportError:
    print("Error: google-genai not installed. Run: pip3 install google-genai")
    sys.exit(1)

LOCALE_NAMES = {
    "en-US": "English", "en-GB": "English", "tr": "Turkish", "de-DE": "German",
    "fr-FR": "French", "es-ES": "Spanish", "it": "Italian", "pt-BR": "Portuguese",
    "ja": "Japanese", "ko": "Korean", "zh-Hans": "Chinese", "ar-SA": "Arabic",
    "nl-NL": "Dutch", "sv": "Swedish", "ru": "Russian", "pl": "Polish",
}

client = genai.Client(api_key=API_KEY)
results = {}

for locale in LOCALES:
    locale = locale.strip()
    lang = LOCALE_NAMES.get(locale, "English")
    print(f"  Generating for {locale} ({lang})...")

    prompt = f"""You are writing App Store "What's New" release notes for {APP_NAME}.

Based on these git commits, write user-friendly release notes in {lang}:

{GIT_LOG}

RULES:
- Max 4000 characters
- Focus on USER-FACING changes only (ignore internal refactors, CI, docs)
- Use bullet points with emojis
- Group by category: New Features, Improvements, Bug Fixes
- Keep it concise and exciting
- Skip empty categories
- Do NOT mention technical details (file names, function names, etc.)
- Write naturally in {lang}, not a translation

Respond with ONLY the release notes text, no JSON, no markdown code blocks."""

    try:
        response = client.models.generate_content(
            model="gemini-2.0-flash",
            contents=prompt
        )
        text = response.text.strip()
        results[locale] = text
        # Show preview (first 2 lines)
        preview = "\n".join(text.split("\n")[:3])
        print(f"    ✓ {preview}...")
    except Exception as e:
        print(f"    ✗ Failed: {e}")

with open(OUTPUT_PATH, "w") as f:
    json.dump({"app": APP_NAME, "date": OUTPUT_PATH.split("_")[-1].replace(".json",""), "whats_new": results}, f, indent=2, ensure_ascii=False)

print(f"\n  ✓ Saved to {OUTPUT_PATH.split('/')[-1]}")
PYEOF

else
  # No API key — generate simple English version from git log
  warn "No Gemini API key — generating basic release notes"

  python3 -c "
import json, re

git_log = '''$GIT_LOG'''
lines = git_log.strip().split('\n')

features, fixes, improvements = [], [], []
for line in lines:
    msg = re.sub(r'^[a-f0-9]+ ', '', line).strip()
    lower = msg.lower()
    if any(w in lower for w in ['fix', 'bug', 'crash', 'issue', 'resolve']):
        fixes.append(msg)
    elif any(w in lower for w in ['add', 'new', 'feature', 'implement', 'create']):
        features.append(msg)
    else:
        improvements.append(msg)

notes = []
if features:
    notes.append('🆕 New Features')
    notes.extend(f'• {f}' for f in features[:5])
    notes.append('')
if improvements:
    notes.append('✨ Improvements')
    notes.extend(f'• {i}' for i in improvements[:5])
    notes.append('')
if fixes:
    notes.append('🐛 Bug Fixes')
    notes.extend(f'• {f}' for f in fixes[:5])

text = '\n'.join(notes)
result = {'app': '$APP_NAME', 'whats_new': {'en-US': text}}
with open('$OUTPUT_FILE', 'w') as f:
    json.dump(result, f, indent=2)
print(text)
" 2>/dev/null
fi

echo ""

# Push if requested
if $DO_PUSH; then
  require_asc
  require_version
  step "Pushing What's New to ASC..."
  python3 -c "
import json
data = json.load(open('$OUTPUT_FILE'))
for locale, text in data.get('whats_new', {}).items():
    print(f'{locale}|||{text}')
" 2>/dev/null | while IFS='|||' read locale text; do
    "$ASC_CLI" localizations update --version "$ASC_VERSION_ID" \
      --locale "$locale" --whats-new "$text" >/dev/null 2>&1 && \
      echo -e "  ${GREEN}✓${NC} $locale" || echo -e "  ${RED}✗${NC} $locale"
  done
  ok "What's New pushed to ASC"
else
  echo -e "  ${DIM}To push: /aso whats-new --push${NC}"
fi

ok "Done — $OUTPUT_FILE"
