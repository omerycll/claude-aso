#!/bin/bash
# aso/upload-screenshots.sh — Upload screenshots to App Store Connect
# Usage:
#   bash aso/upload-screenshots.sh [path] [options]
#
# Path defaults to aso/screenshots/preview/ if omitted.
#
# Options:
#   --device-type TYPE   ASC device type (auto-detected if omitted)
#   --replace            Delete existing screenshots before upload
#   --skip-existing      Skip files with matching MD5
#   --dry-run            Show what would happen without making changes
#   --locale LOCALE      Only upload specific locale(s), comma-separated
#
# Examples:
#   bash aso/upload-screenshots.sh --replace
#   bash aso/upload-screenshots.sh --dry-run
#   bash aso/upload-screenshots.sh --replace --locale tr,en-US
#   bash aso/upload-screenshots.sh ./other-dir --device-type IPAD_PRO_3GEN_129

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# ── Parse Arguments ─────────────────────────────────────────────────────
INPUT=""
DEVICE_TYPE=""
REPLACE=false
SKIP_EXISTING=false
DRY_RUN=false
FILTER_LOCALE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device-type) DEVICE_TYPE="$2"; shift 2 ;;
    --replace) REPLACE=true; shift ;;
    --skip-existing) SKIP_EXISTING=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --locale) FILTER_LOCALE="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: bash aso/upload-screenshots.sh [path] [options]"
      echo ""
      echo "Path defaults to aso/screenshots/preview/ if omitted."
      echo ""
      echo "Options:"
      echo "  --device-type TYPE   ASC device type (auto-detected if omitted)"
      echo "  --replace            Delete existing screenshots before upload"
      echo "  --skip-existing      Skip files with matching MD5"
      echo "  --dry-run            Show what would happen"
      echo "  --locale LOCALE      Comma-separated locale filter"
      echo ""
      echo "Device types: IPHONE_55, IPHONE_65, IPHONE_67, IPAD_PRO_3GEN_129"
      exit 0
      ;;
    -*) fail "Unknown option: $1" ;;
    *) INPUT="$1"; shift ;;
  esac
done

# ── Find aso/config.json ────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASO_DIR="$SCRIPT_DIR"
[[ ! -f "$ASO_DIR/config.json" ]] && fail "aso/config.json not found"

# Default path: aso/screenshots/preview/
if [[ -z "$INPUT" ]]; then
  INPUT="$ASO_DIR/screenshots/preview"
fi

# ── Read Config ─────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || fail "jq not found. Install with: brew install jq"

ASC=$(jq -r '.asc_cli_path' "$ASO_DIR/config.json")
VERSION_ID=$(jq -r '.asc.version_id' "$ASO_DIR/config.json")
APP_NAME=$(jq -r '.app.name' "$ASO_DIR/config.json")

[[ -z "$ASC" || "$ASC" == "null" ]] && fail "asc_cli_path not set in config.json"
[[ -z "$VERSION_ID" || "$VERSION_ID" == "null" ]] && fail "version_id not set in config.json"
command -v "$ASC" >/dev/null 2>&1 || fail "asc CLI not found at $ASC"

info "App: $APP_NAME | Version ID: $VERSION_ID"

# ── Resolve Input ───────────────────────────────────────────────────────
SCREENSHOTS_DIR=""

if [[ -d "$INPUT" ]]; then
  SCREENSHOTS_DIR="$INPUT"
else
  fail "Directory not found: $INPUT"
fi

ok "Screenshots dir: $SCREENSHOTS_DIR"

# ── Auto-detect Device Type ────────────────────────────────────────────
if [[ -z "$DEVICE_TYPE" ]]; then
  FIRST_PNG=$(find "$SCREENSHOTS_DIR" -name "*.png" -type f 2>/dev/null | head -1)
  if [[ -z "$FIRST_PNG" ]]; then
    fail "No PNG files found. Use --device-type to specify manually."
  fi

  W=$(sips -g pixelWidth "$FIRST_PNG" 2>/dev/null | tail -1 | awk '{print $2}')
  H=$(sips -g pixelHeight "$FIRST_PNG" 2>/dev/null | tail -1 | awk '{print $2}')
  info "Detected image size: ${W}x${H}"

  # Normalize to portrait (W < H)
  if [[ $W -gt $H ]]; then
    TMP=$W; W=$H; H=$TMP
  fi

  case "${W}x${H}" in
    1242x2208) DEVICE_TYPE="IPHONE_55" ;;
    1242x2688|1284x2778) DEVICE_TYPE="IPHONE_65" ;;
    1290x2796|1320x2868|1260x2736) DEVICE_TYPE="IPHONE_67" ;;
    2048x2732|2064x2752) DEVICE_TYPE="IPAD_PRO_3GEN_129" ;;
    1668x2388|1668x2420|1640x2360|1488x2266) DEVICE_TYPE="IPAD_PRO_3GEN_11" ;;
    *) fail "Cannot auto-detect device type for ${W}x${H}. Use --device-type" ;;
  esac
fi

ok "Device type: $DEVICE_TYPE"

# ── Fetch Version Localizations from ASC ────────────────────────────────
info "Fetching version localizations from ASC..."

LOC_JSON=$("$ASC" localizations list --version "$VERSION_ID" --output json 2>/dev/null || echo '{"data":[]}')

# Build locale -> localization ID map (locale|id per line)
LOC_MAP=$(echo "$LOC_JSON" | jq -r '
  (if type == "array" then . else .data end)
  | .[]
  | "\(.attributes.locale)|\(.id)"
')

LOC_COUNT=$(echo "$LOC_MAP" | grep -c '|' || true)

if [[ "$LOC_COUNT" -eq 0 ]]; then
  fail "No version localizations found on ASC for version $VERSION_ID"
fi

ok "Found $LOC_COUNT localizations"

# Lookup function: locale -> localization ID
get_loc_id() {
  echo "$LOC_MAP" | grep "^$1|" | head -1 | cut -d'|' -f2
}

# ── Determine Locales to Upload ─────────────────────────────────────────
LOCALES_TO_UPLOAD=()

for dir in "$SCREENSHOTS_DIR"/*/; do
  [[ ! -d "$dir" ]] && continue
  locale=$(basename "$dir")

  # Skip junk directories
  [[ "$locale" == "__MACOSX" || "$locale" == ".DS_Store" ]] && continue

  # Apply locale filter
  if [[ -n "$FILTER_LOCALE" ]]; then
    if ! echo "$FILTER_LOCALE" | tr ',' '\n' | grep -qx "$locale"; then
      continue
    fi
  fi

  LOCALES_TO_UPLOAD+=("$locale")
done

if [[ ${#LOCALES_TO_UPLOAD[@]} -eq 0 ]]; then
  fail "No locale directories found in: $SCREENSHOTS_DIR"
fi

# Sort locales
IFS=$'\n' LOCALES_TO_UPLOAD=($(sort <<< "${LOCALES_TO_UPLOAD[*]}")); unset IFS

echo ""
info "Uploading ${#LOCALES_TO_UPLOAD[@]} locales: ${LOCALES_TO_UPLOAD[*]}"
echo ""

# ── Upload Screenshots ──────────────────────────────────────────────────
SUCCESS=0
FAILED=0
SKIPPED=0

for locale in "${LOCALES_TO_UPLOAD[@]}"; do
  LOC_ID=$(get_loc_id "$locale")

  if [[ -z "$LOC_ID" ]]; then
    warn "$locale — no matching ASC localization, skipping"
    ((SKIPPED++))
    continue
  fi

  PNG_COUNT=$(find "$SCREENSHOTS_DIR/$locale" -name "*.png" -type f | wc -l | tr -d ' ')

  if [[ "$PNG_COUNT" -eq 0 ]]; then
    warn "$locale — no PNG files, skipping"
    ((SKIPPED++))
    continue
  fi

  # Build upload command
  CMD=("$ASC" screenshots upload
    --version-localization "$LOC_ID"
    --path "$SCREENSHOTS_DIR/$locale"
    --device-type "$DEVICE_TYPE"
  )

  [[ "$REPLACE" == true ]] && CMD+=(--replace)
  [[ "$SKIP_EXISTING" == true ]] && CMD+=(--skip-existing)
  [[ "$DRY_RUN" == true ]] && CMD+=(--dry-run)

  echo -e "  ${CYAN}$locale${NC} ($PNG_COUNT PNGs) → $LOC_ID"

  if OUTPUT=$("${CMD[@]}" 2>&1); then
    ok "  $locale — done"
    # Show upload details if any
    if [[ -n "$OUTPUT" ]]; then
      echo "$OUTPUT" | while IFS= read -r line; do echo "    $line"; done
    fi
    ((SUCCESS++))
  else
    warn "  $locale — failed"
    echo "$OUTPUT" | while IFS= read -r line; do echo "    $line"; done
    ((FAILED++))
  fi
done

# ── Summary ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}════════════════════════════════════════${NC}"
echo -e "${BOLD}  Screenshot Upload Complete${NC}"
echo -e "${BOLD}════════════════════════════════════════${NC}"
echo -e "  Device:   ${CYAN}$DEVICE_TYPE${NC}"
echo -e "  Success:  ${GREEN}$SUCCESS${NC}"
[[ $SKIPPED -gt 0 ]] && echo -e "  Skipped:  ${YELLOW}$SKIPPED${NC}"
[[ $FAILED -gt 0 ]]  && echo -e "  Failed:   ${RED}$FAILED${NC}"
[[ "$DRY_RUN" == true ]] && echo -e "  ${YELLOW}(dry-run — no changes made)${NC}"
echo ""
