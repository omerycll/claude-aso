#!/bin/bash
# ── cmd/competitor.sh — Competitor keyword analysis ────────────────────────
# Analyzes competitor apps and suggests keywords
# Usage: bash run.sh competitor <app-name-or-id> [<app2>] [--locale en-US]

set -uo pipefail

require_gemini_key

header "Competitor Analysis — $APP_NAME"

# Parse args
COMPETITORS=()
LOCALE="en-US"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --locale) LOCALE="$2"; shift 2 ;;
    *)        COMPETITORS+=("$1"); shift ;;
  esac
done

if [[ ${#COMPETITORS[@]} -eq 0 ]]; then
  echo -e "  ${BOLD}Usage:${NC} /aso competitor \"App Name 1\" \"App Name 2\" [--locale en-US]"
  echo ""
  echo -e "  ${DIM}Examples:${NC}"
  echo -e "    /aso competitor \"Spotify\" \"Apple Music\" \"YouTube Music\""
  echo -e "    /aso competitor \"Notion\" --locale tr"
  echo ""
  exit 1
fi

info "Analyzing ${#COMPETITORS[@]} competitor(s) for locale: $LOCALE"
echo ""

# Get our current metadata for comparison
OUR_METADATA=""
META_FILE=$(ls -t "$ASO_DIR/data/research"/updated_metadata_*.json "$ASO_DIR/data/research"/translated_metadata_*.json 2>/dev/null | head -1)
if [[ -n "$META_FILE" ]]; then
  OUR_METADATA=$(python3 -c "
import json
data = json.load(open('$META_FILE'))
m = data.get('metadata', {}).get('$LOCALE', {})
print(json.dumps(m))
" 2>/dev/null || echo "{}")
fi

DATE=$(date +%Y-%m-%d)
OUTPUT_FILE="$ASO_DIR/data/research/competitor_analysis_$DATE.json"

# Competitor analysis with Gemini
python3 - "$GEMINI_API_KEY" "$APP_NAME" "$LOCALE" "$OUR_METADATA" "$OUTPUT_FILE" "${COMPETITORS[@]}" << 'PYEOF'
import json, sys, os

API_KEY = sys.argv[1]
APP_NAME = sys.argv[2]
LOCALE = sys.argv[3]
OUR_META_STR = sys.argv[4]
OUTPUT_PATH = sys.argv[5]
COMPETITORS = sys.argv[6:]

try:
    from google import genai
except ImportError:
    print("Error: google-genai not installed. Run: pip3 install google-genai")
    sys.exit(1)

our_meta = json.loads(OUR_META_STR) if OUR_META_STR and OUR_META_STR != "{}" else None

client = genai.Client(api_key=API_KEY)

LOCALE_NAMES = {
    "en-US": "English", "tr": "Turkish", "de-DE": "German", "fr-FR": "French",
    "es-ES": "Spanish", "ja": "Japanese", "ko": "Korean", "zh-Hans": "Chinese",
    "it": "Italian", "pt-BR": "Portuguese", "ar-SA": "Arabic", "nl-NL": "Dutch",
}
lang = LOCALE_NAMES.get(LOCALE, "English")

our_section = ""
if our_meta:
    our_section = f"""
OUR APP ({APP_NAME}) current metadata:
- Title: {our_meta.get('title', 'N/A')}
- Subtitle: {our_meta.get('subtitle', 'N/A')}
- Keywords: {our_meta.get('keywords', 'N/A')}
"""

competitors_list = "\n".join(f"- {c}" for c in COMPETITORS)

prompt = f"""You are an expert App Store Optimization analyst.

Analyze these competitor apps in the context of {lang} App Store ({LOCALE}):
{competitors_list}

{our_section}

For EACH competitor, provide:
1. Their likely App Store title and subtitle
2. Probable keywords they target
3. Their positioning strategy
4. Strengths and weaknesses in ASO

Then provide:

KEYWORD OPPORTUNITIES:
- Keywords our competitors use that we DON'T (gaps)
- High-value keywords in this category
- Long-tail keyword suggestions
- Trending terms in this app category

RECOMMENDATIONS FOR {APP_NAME}:
- Suggested new keywords (comma-separated, {lang}, max 100 chars total, no spaces after commas)
- Title improvement suggestions (max 30 chars)
- Subtitle improvement suggestions (max 30 chars)
- Positioning strategy to differentiate

Respond with valid JSON (no markdown code blocks):
{{
  "competitors": [
    {{
      "name": "...",
      "likely_title": "...",
      "likely_subtitle": "...",
      "probable_keywords": ["..."],
      "positioning": "...",
      "strengths": ["..."],
      "weaknesses": ["..."]
    }}
  ],
  "keyword_gaps": ["..."],
  "high_value_keywords": ["..."],
  "long_tail_keywords": ["..."],
  "trending_terms": ["..."],
  "recommendations": {{
    "suggested_keywords": "...",
    "title_suggestions": ["..."],
    "subtitle_suggestions": ["..."],
    "positioning_strategy": "..."
  }}
}}"""

print("  Analyzing competitors with AI...")
print()

try:
    response = client.models.generate_content(
        model="gemini-2.0-flash",
        contents=prompt
    )
    text = response.text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1].rsplit("```", 1)[0].strip()

    result = json.loads(text)
    result["_meta"] = {
        "our_app": APP_NAME,
        "locale": LOCALE,
        "competitors_analyzed": COMPETITORS,
        "date": OUTPUT_PATH.split("_")[-1].replace(".json", "")
    }

    # Save
    with open(OUTPUT_PATH, "w") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    # Display
    C_GREEN = '\033[0;32m'
    C_CYAN = '\033[0;36m'
    C_YELLOW = '\033[1;33m'
    C_BOLD = '\033[1m'
    C_DIM = '\033[2m'
    C_NC = '\033[0m'

    # Competitor summaries
    for comp in result.get("competitors", []):
        print(f"  {C_BOLD}{comp['name']}{C_NC}")
        print(f"    Title: {C_CYAN}{comp.get('likely_title', 'N/A')}{C_NC}")
        print(f"    Subtitle: {comp.get('likely_subtitle', 'N/A')}")
        print(f"    Positioning: {C_DIM}{comp.get('positioning', '')}{C_NC}")
        strengths = comp.get('strengths', [])
        if strengths:
            print(f"    {C_GREEN}+{C_NC} {', '.join(strengths[:3])}")
        weaknesses = comp.get('weaknesses', [])
        if weaknesses:
            print(f"    {C_YELLOW}-{C_NC} {', '.join(weaknesses[:3])}")
        print()

    # Keyword opportunities
    gaps = result.get("keyword_gaps", [])
    high_value = result.get("high_value_keywords", [])
    trending = result.get("trending_terms", [])

    if gaps:
        print(f"  {C_BOLD}Keyword Gaps (they have, we don't):{C_NC}")
        print(f"    {C_CYAN}{', '.join(gaps[:10])}{C_NC}")
        print()

    if high_value:
        print(f"  {C_BOLD}High-Value Keywords:{C_NC}")
        print(f"    {C_GREEN}{', '.join(high_value[:10])}{C_NC}")
        print()

    if trending:
        print(f"  {C_BOLD}Trending Terms:{C_NC}")
        print(f"    {C_YELLOW}{', '.join(trending[:10])}{C_NC}")
        print()

    # Recommendations
    recs = result.get("recommendations", {})
    if recs:
        print(f"  {C_BOLD}═══ Recommendations for {APP_NAME} ═══{C_NC}")
        if recs.get("suggested_keywords"):
            print(f"  {C_BOLD}Keywords:{C_NC} {recs['suggested_keywords']}")
        if recs.get("title_suggestions"):
            print(f"  {C_BOLD}Title ideas:{C_NC}")
            for t in recs["title_suggestions"][:3]:
                print(f"    → {t}")
        if recs.get("subtitle_suggestions"):
            print(f"  {C_BOLD}Subtitle ideas:{C_NC}")
            for s in recs["subtitle_suggestions"][:3]:
                print(f"    → {s}")
        if recs.get("positioning_strategy"):
            print(f"  {C_BOLD}Strategy:{C_NC} {C_DIM}{recs['positioning_strategy']}{C_NC}")
        print()

except Exception as e:
    print(f"  Error: {e}")
    sys.exit(1)

print(f"  ✓ Full analysis saved to {os.path.basename(OUTPUT_PATH)}")
PYEOF

echo ""
ok "Competitor analysis complete"
