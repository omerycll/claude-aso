#!/bin/bash
# ── cmd/init.sh — First-time ASO setup ──────────────────────────────────
# Discovers Xcode project, installs dependencies, queries ASC, generates config.json
# Usage: /aso init

set -uo pipefail

header "ASO Toolkit — Setup"

# ══════════════════════════════════════════════════════════════════════════
# STEP 1: Install Dependencies
# ══════════════════════════════════════════════════════════════════════════
step "Checking dependencies..."

# Homebrew
if ! command -v brew >/dev/null 2>&1; then
  warn "Homebrew not found."
  echo -e "  ${BOLD}Install Homebrew:${NC}"
  echo -e "  ${CYAN}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${NC}"
  echo ""
  read -rp "  Continue without Homebrew? (y/N): " cont
  [[ "$cont" != "y" && "$cont" != "Y" ]] && exit 1
fi

# jq
if command -v jq >/dev/null 2>&1; then
  ok "jq $(jq --version 2>/dev/null || echo '')"
else
  info "Installing jq..."
  if command -v brew >/dev/null 2>&1; then
    brew install jq 2>/dev/null && ok "jq installed" || die "Failed to install jq"
  else
    die "jq not found. Install with: brew install jq"
  fi
fi

# asc CLI (App Store Connect)
if command -v asc >/dev/null 2>&1; then
  ok "asc CLI found: $(command -v asc)"
else
  info "Installing asc CLI (App Store Connect)..."
  echo -e "  ${DIM}This lets you push/pull metadata directly to App Store Connect${NC}"
  if command -v brew >/dev/null 2>&1; then
    brew install asc 2>/dev/null && ok "asc CLI installed" || warn "Failed to install asc — ASC features will be limited"
  else
    warn "asc CLI not found. Install with: brew install asc"
  fi
fi

# Python 3
if command -v python3 >/dev/null 2>&1; then
  ok "Python $(python3 --version 2>&1 | awk '{print $2}')"
else
  die "Python 3 not found. Install Xcode Command Line Tools: xcode-select --install"
fi

# google-genai (Python package for Gemini)
if python3 -c "import google.genai" 2>/dev/null; then
  ok "google-genai Python package"
else
  info "Installing google-genai (for AI icon/screenshot generation)..."
  pip3 install -q google-genai 2>/dev/null && ok "google-genai installed" || warn "Failed to install google-genai — AI features will be limited"
fi

# Pillow (Python image library)
if python3 -c "from PIL import Image" 2>/dev/null; then
  ok "Pillow (image processing)"
else
  info "Installing Pillow..."
  pip3 install -q Pillow 2>/dev/null && ok "Pillow installed" || warn "Failed to install Pillow"
fi

# ══════════════════════════════════════════════════════════════════════════
# STEP 2: Gemini API Key
# ══════════════════════════════════════════════════════════════════════════
step "API Keys"

load_credentials

if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  ok "Gemini API key found"
else
  echo ""
  echo -e "  ${BOLD}Gemini API Key${NC} (for AI icon & screenshot generation)"
  echo ""
  echo -e "  ${DIM}How to get your free API key:${NC}"
  echo -e "  ${CYAN}1.${NC} Go to ${CYAN}https://aistudio.google.com/apikey${NC}"
  echo -e "  ${CYAN}2.${NC} Sign in with your Google account"
  echo -e "  ${CYAN}3.${NC} Click ${BOLD}\"Create API Key\"${NC}"
  echo -e "  ${CYAN}4.${NC} Copy the key and paste it below"
  echo ""
  read -rp "  Gemini API Key (or Enter to skip): " gemini_key

  if [[ -n "$gemini_key" ]]; then
    save_credential "GEMINI_API_KEY" "$gemini_key"
    export GEMINI_API_KEY="$gemini_key"
    ok "Gemini API key saved"
  else
    warn "Skipped — AI features (icons, screenshots compose) won't work without it"
    echo -e "  ${DIM}You can add it later: run /aso init again or /aso icons generate${NC}"
  fi
fi

# ══════════════════════════════════════════════════════════════════════════
# STEP 3: Find Xcode Project
# ══════════════════════════════════════════════════════════════════════════
step "Discovering Xcode project..."

XCODEPROJ=$(find "$PROJECT_ROOT" -maxdepth 2 -name "*.xcodeproj" -not -path "*/Pods/*" | head -1)
[[ -n "$XCODEPROJ" ]] || die "No .xcodeproj found in $PROJECT_ROOT"

XCODEPROJ_REL=$(python3 -c "import os; print(os.path.relpath('$XCODEPROJ', '$PROJECT_ROOT'))")
XCODEPROJ_NAME=$(basename "$XCODEPROJ" .xcodeproj)
ok "Found: $XCODEPROJ_REL"

# ══════════════════════════════════════════════════════════════════════════
# STEP 4: Extract Build Settings
# ══════════════════════════════════════════════════════════════════════════
step "Reading build settings..."

BUILD_SETTINGS=$(xcodebuild -project "$XCODEPROJ" -showBuildSettings -scheme "$XCODEPROJ_NAME" 2>/dev/null || \
                 xcodebuild -project "$XCODEPROJ" -showBuildSettings 2>/dev/null || echo "")

extract() { echo "$BUILD_SETTINGS" | grep -m1 "^\s*$1 = " | sed "s/.*= //" | tr -d ' '; }

PRODUCT_NAME=$(extract "PRODUCT_NAME")
BUNDLE_ID=$(extract "PRODUCT_BUNDLE_IDENTIFIER")
TEAM_ID=$(extract "DEVELOPMENT_TEAM")
VERSION=$(extract "MARKETING_VERSION")

[[ -z "$PRODUCT_NAME" ]] && PRODUCT_NAME="$XCODEPROJ_NAME"
[[ -z "$VERSION" ]] && VERSION="1.0"

ok "App: $PRODUCT_NAME ($BUNDLE_ID)"
ok "Team: $TEAM_ID | Version: $VERSION"

# ══════════════════════════════════════════════════════════════════════════
# STEP 5: Auto-detect Paths
# ══════════════════════════════════════════════════════════════════════════
step "Detecting project structure..."

# Source directory (main app target)
SOURCE_DIR=""
for candidate in "$PRODUCT_NAME" "$XCODEPROJ_NAME" "Sources" "App"; do
  if [[ -d "$PROJECT_ROOT/$candidate" ]]; then
    SOURCE_DIR="$candidate"
    break
  fi
done
[[ -z "$SOURCE_DIR" ]] && SOURCE_DIR="$PRODUCT_NAME"
ok "Source dir: $SOURCE_DIR/"

# Entitlements
ENTITLEMENTS_REL=$(find "$PROJECT_ROOT" -maxdepth 3 -name "*.entitlements" -path "*/$SOURCE_DIR/*" 2>/dev/null | head -1)
if [[ -n "$ENTITLEMENTS_REL" ]]; then
  ENTITLEMENTS_REL=$(python3 -c "import os; print(os.path.relpath('$ENTITLEMENTS_REL', '$PROJECT_ROOT'))")
  ok "Entitlements: $ENTITLEMENTS_REL"
else
  ENTITLEMENTS_REL=""
  warn "No entitlements file found"
fi

# Info.plist
INFO_PLIST_REL=$(find "$PROJECT_ROOT/$SOURCE_DIR" -maxdepth 2 -name "Info.plist" 2>/dev/null | head -1)
if [[ -n "$INFO_PLIST_REL" ]]; then
  INFO_PLIST_REL=$(python3 -c "import os; print(os.path.relpath('$INFO_PLIST_REL', '$PROJECT_ROOT'))")
  ok "Info.plist: $INFO_PLIST_REL"
else
  INFO_PLIST_REL=""
  warn "No Info.plist found"
fi

# UI Test target
UITEST_TARGET=$(find "$PROJECT_ROOT" -maxdepth 1 -type d -name "*UITests" | head -1 | xargs basename 2>/dev/null || echo "")
[[ -n "$UITEST_TARGET" ]] && ok "UI Test target: $UITEST_TARGET" || warn "No UI test target found"

# Scheme
SCHEME="$XCODEPROJ_NAME"

# ══════════════════════════════════════════════════════════════════════════
# STEP 6: Simulators
# ══════════════════════════════════════════════════════════════════════════
step "Detecting simulators..."

IPHONE_SIM=$(xcrun simctl list devices available -j 2>/dev/null | \
  python3 -c "
import json,sys
data = json.load(sys.stdin)
for runtime, devices in data.get('devices',{}).items():
  if 'iOS' in runtime:
    for d in devices:
      if 'iPhone' in d['name'] and 'Pro' in d['name'] and 'Max' not in d['name']:
        print(d['name']); exit()
" 2>/dev/null || echo "")

IPAD_SIM=$(xcrun simctl list devices available -j 2>/dev/null | \
  python3 -c "
import json,sys
data = json.load(sys.stdin)
for runtime, devices in data.get('devices',{}).items():
  if 'iOS' in runtime or 'iPadOS' in runtime:
    for d in devices:
      if 'iPad Pro' in d['name'] and '11' in d['name']:
        print(d['name']); exit()
" 2>/dev/null || echo "")

[[ -n "$IPHONE_SIM" ]] && ok "iPhone: $IPHONE_SIM" || warn "No iPhone simulator found"
[[ -n "$IPAD_SIM" ]] && ok "iPad: $IPAD_SIM" || warn "No iPad simulator found"

# ══════════════════════════════════════════════════════════════════════════
# STEP 7: App Store Connect
# ══════════════════════════════════════════════════════════════════════════
step "Connecting to App Store Connect..."

ASC_CLI=$(command -v asc || echo "/opt/homebrew/bin/asc")
ASC_APP_ID=""
ASC_VERSION_ID=""
ASC_VERSION_STRING=""
ASC_LOCALES=()

if command -v "$ASC_CLI" >/dev/null 2>&1; then
  ok "asc CLI ready"

  echo ""
  echo -e "  ${BOLD}App Store Connect Authentication${NC}"
  echo ""
  echo -e "  ${DIM}The asc CLI uses your Xcode keychain for authentication.${NC}"
  echo -e "  ${DIM}Make sure you are signed into your Apple Developer account in Xcode:${NC}"
  echo ""
  echo -e "  ${CYAN}1.${NC} Open ${BOLD}Xcode → Settings → Accounts${NC}"
  echo -e "  ${CYAN}2.${NC} Ensure your Apple ID is listed with the correct team"
  echo -e "  ${CYAN}3.${NC} If not, click ${BOLD}+${NC} to add your Apple ID"
  echo ""

  # Find app by bundle ID
  info "Searching for app with bundle ID: $BUNDLE_ID"
  APP_JSON=$("$ASC_CLI" apps list --bundle-id "$BUNDLE_ID" --output json 2>/dev/null || echo "")
  if [[ -n "$APP_JSON" ]]; then
    ASC_APP_ID=$(echo "$APP_JSON" | jq -r '(if type == "array" then .[0] else .data[0] // . end) | .id // empty' 2>/dev/null || echo "")
  fi

  if [[ -z "$ASC_APP_ID" ]]; then
    echo -e "  ${YELLOW}Could not find app automatically.${NC}"
    echo ""
    echo -e "  ${DIM}To find your App ID manually:${NC}"
    echo -e "  ${CYAN}1.${NC} Go to ${CYAN}https://appstoreconnect.apple.com/apps${NC}"
    echo -e "  ${CYAN}2.${NC} Click your app"
    echo -e "  ${CYAN}3.${NC} Look at the URL: apps.apple.com/app/id${BOLD}XXXXXXXXXX${NC}"
    echo -e "  ${CYAN}   ${NC}Or check ${BOLD}App Information → General${NC} section"
    echo ""
    read -rp "  Enter ASC App ID (or Enter to skip): " ASC_APP_ID
  fi

  if [[ -n "$ASC_APP_ID" ]]; then
    ok "App ID: $ASC_APP_ID"

    # Get version
    VER_JSON=$("$ASC_CLI" versions list --app "$ASC_APP_ID" --state PREPARE_FOR_SUBMISSION --output json 2>/dev/null || echo "")
    if [[ -n "$VER_JSON" ]]; then
      ASC_VERSION_ID=$(echo "$VER_JSON" | jq -r '(if type == "array" then .[0] else .data[0] // . end) | .id // empty' 2>/dev/null || echo "")
      ASC_VERSION_STRING=$(echo "$VER_JSON" | jq -r '(if type == "array" then .[0] else .data[0] // . end) | .attributes.versionString // empty' 2>/dev/null || echo "")
    fi
    [[ -n "$ASC_VERSION_ID" ]] && ok "Version: $ASC_VERSION_STRING (ID: ${ASC_VERSION_ID:0:8}...)" || warn "No version in PREPARE_FOR_SUBMISSION state"

    # Get locales
    if [[ -n "$ASC_VERSION_ID" ]]; then
      LOC_JSON=$("$ASC_CLI" localizations list --version "$ASC_VERSION_ID" --output json 2>/dev/null || echo "")
      if [[ -n "$LOC_JSON" ]]; then
        mapfile -t ASC_LOCALES < <(echo "$LOC_JSON" | jq -r '(if type == "array" then . else .data end) | .[].attributes.locale' 2>/dev/null)
      fi
    fi
    [[ ${#ASC_LOCALES[@]} -gt 0 ]] && ok "Locales: ${ASC_LOCALES[*]}"
  fi
else
  warn "asc CLI not available — ASC features (push/pull) will be skipped"
  echo -e "  ${DIM}Install later with: brew install asc${NC}"
fi

# ══════════════════════════════════════════════════════════════════════════
# STEP 8: Website URLs
# ══════════════════════════════════════════════════════════════════════════
step "Website URLs (for compliance checker)"

URL_PRIVACY="" URL_TERMS="" URL_SUPPORT="" URL_MARKETING=""

# Check if existing config has URLs
if [[ -f "$CONFIG" ]]; then
  URL_PRIVACY=$(jq -r '.urls.privacy // empty' "$CONFIG" 2>/dev/null)
  URL_TERMS=$(jq -r '.urls.terms // empty' "$CONFIG" 2>/dev/null)
  URL_SUPPORT=$(jq -r '.urls.support // empty' "$CONFIG" 2>/dev/null)
  URL_MARKETING=$(jq -r '.urls.marketing // empty' "$CONFIG" 2>/dev/null)
fi

echo ""
echo -e "  ${DIM}These URLs are checked during Apple Guidelines compliance review.${NC}"
echo -e "  ${DIM}Press Enter to skip any you don't have yet.${NC}"
echo ""

read -rp "  Privacy Policy URL [$URL_PRIVACY]: " input; [[ -n "$input" ]] && URL_PRIVACY="$input"
read -rp "  Terms of Use URL [$URL_TERMS]: " input; [[ -n "$input" ]] && URL_TERMS="$input"
read -rp "  Support/Contact URL [$URL_SUPPORT]: " input; [[ -n "$input" ]] && URL_SUPPORT="$input"
read -rp "  Marketing URL [$URL_MARKETING]: " input; [[ -n "$input" ]] && URL_MARKETING="$input"

# ══════════════════════════════════════════════════════════════════════════
# STEP 9: Write config.json
# ══════════════════════════════════════════════════════════════════════════
step "Writing config.json..."

LOCALES_ARR="[]"
if [[ ${#ASC_LOCALES[@]} -gt 0 ]]; then
  LOCALES_ARR=$(printf '%s\n' "${ASC_LOCALES[@]}" | jq -R . | jq -s .)
fi

cat > "$CONFIG" << JSONEOF
{
  "version": 2,
  "app": {
    "name": "$PRODUCT_NAME",
    "slug": "$(echo "$PRODUCT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')",
    "bundle_id": "$BUNDLE_ID",
    "team_id": "$TEAM_ID",
    "marketing_version": "$VERSION",
    "source_dir": "$SOURCE_DIR",
    "xcodeproj": "$XCODEPROJ_REL",
    "scheme": "$SCHEME",
    "uitest_target": "$UITEST_TARGET",
    "entitlements": "$ENTITLEMENTS_REL",
    "info_plist": "$INFO_PLIST_REL"
  },
  "asc": {
    "app_id": "$ASC_APP_ID",
    "version_id": "$ASC_VERSION_ID",
    "version_string": "$ASC_VERSION_STRING"
  },
  "devices": {
    "iphone": "$IPHONE_SIM",
    "ipad": "$IPAD_SIM"
  },
  "locales": $LOCALES_ARR,
  "char_limits": {
    "title": 30,
    "subtitle": 30,
    "keywords": 100,
    "description": 4000
  },
  "urls": {
    "privacy": "$URL_PRIVACY",
    "terms": "$URL_TERMS",
    "support": "$URL_SUPPORT",
    "marketing": "$URL_MARKETING"
  },
  "asc_cli_path": "$ASC_CLI",
  "created_at": "$(date +%Y-%m-%d)"
}
JSONEOF

ok "config.json written"

# ── Create directories ────────────────────────────────────────────────
mkdir -p "$ASO_DIR/data/research" "$ASO_DIR/data/changelog" "$ASO_DIR/data/baseline"
mkdir -p "$ASO_DIR/icons" "$ASO_DIR/screenshots/output" "$ASO_DIR/screenshots/marketing"

# ── Gitignore ─────────────────────────────────────────────────────────
cat > "$ASO_DIR/.gitignore" << 'GI'
.DS_Store
*.tmp
screenshots/output/
screenshots/marketing/
screenshots/preview/
screenshots/inspirations/
screenshots/overlay_text
icons/
data/baseline/
GI

# ── Pull baseline (if ASC connected) ─────────────────────────────────
if [[ -n "$ASC_APP_ID" && -n "$ASC_VERSION_ID" ]] && command -v "$ASC_CLI" >/dev/null 2>&1; then
  step "Pulling baseline from ASC..."
  DATE=$(date +%Y-%m-%d)
  "$ASC_CLI" localizations list --app "$ASC_APP_ID" --type app-info --output json \
    > "$ASO_DIR/data/baseline/appinfo_$DATE.json" 2>/dev/null && ok "App info baseline saved"
  "$ASC_CLI" localizations list --version "$ASC_VERSION_ID" --output json \
    > "$ASO_DIR/data/baseline/version_$DATE.json" 2>/dev/null && ok "Version baseline saved"
fi

# ══════════════════════════════════════════════════════════════════════════
# DONE
# ══════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║        ASO Toolkit — Ready!                  ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}App${NC}       $PRODUCT_NAME ($BUNDLE_ID)"
[[ -n "$ASC_APP_ID" ]] && echo -e "  ${BOLD}ASC${NC}       ${GREEN}Connected${NC} — $ASC_APP_ID v$ASC_VERSION_STRING"
[[ -z "$ASC_APP_ID" ]] && echo -e "  ${BOLD}ASC${NC}       ${YELLOW}Not connected${NC}"
[[ -n "${GEMINI_API_KEY:-}" ]] && echo -e "  ${BOLD}Gemini${NC}    ${GREEN}API key set${NC}"
[[ -z "${GEMINI_API_KEY:-}" ]] && echo -e "  ${BOLD}Gemini${NC}    ${YELLOW}Not configured${NC} (AI features disabled)"
echo -e "  ${BOLD}Locales${NC}   ${#ASC_LOCALES[@]} configured"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo -e "    ${CYAN}/aso status${NC}      — see current ASO state"
echo -e "    ${CYAN}/aso check${NC}       — Apple guidelines compliance"
echo -e "    ${CYAN}/aso research${NC}    — start keyword research"
echo ""
