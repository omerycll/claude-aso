#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# ASO Toolkit — App Store Optimization CLI
#
# A reusable toolkit for iOS/macOS app ASO: keyword research, metadata,
# marketing screenshots, icon generation, and Apple guidelines compliance.
#
# Usage:
#   bash aso/run.sh <command> [options]
#
# Commands:
#   init                    First-time setup (discovers Xcode project, queries ASC)
#   status                  Show current ASO status
#   research                Keyword research workflow
#   metadata                Generate/update metadata
#   push                    Push metadata to App Store Connect
#   pull                    Pull current metadata from ASC
#   export                  Export metadata (json/csv/text)
#   screenshots capture     Capture app screenshots via simulator
#   screenshots compose     Generate marketing images (Gemini AI)
#   screenshots upload      Upload screenshots to ASC
#   icons generate          AI icon generation (Gemini/Imagen)
#   translate               AI-translate metadata to other locales
#   competitor              Competitor keyword analysis
#   whats-new               Generate "What's New" from git history
#   score                   ASO readiness score
#   check                   Apple Review Guidelines compliance check
#   privacy-manifest        Generate PrivacyInfo.xcprivacy
#   help                    Show this help
#
# Setup:
#   cd your-project && bash aso/run.sh init
# ══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

# ── Resolve paths ───────────────────────────────────────────────────────
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${ASO_PROJECT_ROOT:-$(pwd)}"
ASO_DIR="$PROJECT_ROOT/aso"
CONFIG="$ASO_DIR/config.json"

# Ensure aso/ data dir exists in project
mkdir -p "$ASO_DIR/data/research" "$ASO_DIR/data/changelog" "$ASO_DIR/data/baseline"
mkdir -p "$ASO_DIR/icons" "$ASO_DIR/screenshots/output" "$ASO_DIR/screenshots/marketing"

export ASO_DIR SCRIPTS_DIR PROJECT_ROOT CONFIG

# ── Source shared libs ──────────────────────────────────────────────────
source "$SCRIPTS_DIR/lib/common.sh"
source "$SCRIPTS_DIR/lib/credentials.sh"

# ── Parse command ───────────────────────────────────────────────────────
CMD="${1:-help}"
SUB="${2:-}"

# ── Pre-flight (skip for init and help) ─────────────────────────────────
preflight() {
  require_cmd jq "Install with: brew install jq"
  if [[ "$CMD" != "init" && "$CMD" != "help" ]]; then
    [[ -f "$CONFIG" ]] || die "Not initialized. Run: /aso init"
    source "$SCRIPTS_DIR/lib/config.sh"
    load_config "$CONFIG"
  fi
}

# ── Command router ──────────────────────────────────────────────────────
route() {
  case "$CMD" in
    init)
      shift_args 1
      source "$SCRIPTS_DIR/cmd/init.sh" "$@"
      ;;
    status)
      shift_args 1
      source "$SCRIPTS_DIR/cmd/status.sh" "$@"
      ;;
    research)
      shift_args 1
      source "$SCRIPTS_DIR/cmd/research.sh" "$@"
      ;;
    metadata)
      shift_args 1
      source "$SCRIPTS_DIR/cmd/metadata.sh" "$@"
      ;;
    push)
      shift_args 1
      source "$SCRIPTS_DIR/cmd/push.sh" "$@"
      ;;
    pull)
      shift_args 1
      source "$SCRIPTS_DIR/cmd/pull.sh" "$@"
      ;;
    export)
      shift_args 1
      bash "$SCRIPTS_DIR/cmd/export.sh" "$@"
      ;;
    screenshots)
      case "$SUB" in
        capture)  shift_args 2; source "$SCRIPTS_DIR/cmd/screenshots_capture.sh" "$@" ;;
        compose)  shift_args 2; require_gemini_key; source "$SCRIPTS_DIR/cmd/screenshots_compose.sh" "$@" ;;
        upload)   shift_args 2; source "$SCRIPTS_DIR/cmd/screenshots_upload.sh" "$@" ;;
        *)        echo "Usage: /aso screenshots <capture|compose|upload>"; exit 1 ;;
      esac
      ;;
    icons)
      case "$SUB" in
        generate) shift_args 2; require_gemini_key; source "$SCRIPTS_DIR/cmd/icons_generate.sh" "$@" ;;
        *)        echo "Usage: bash aso/run.sh icons generate [options]"; exit 1 ;;
      esac
      ;;
    translate)
      shift_args 1
      source "$SCRIPTS_DIR/cmd/translate.sh" "$@"
      ;;
    whats-new)
      shift_args 1
      source "$SCRIPTS_DIR/cmd/whats_new.sh" "$@"
      ;;
    score)
      shift_args 1
      source "$SCRIPTS_DIR/cmd/score.sh" "$@"
      ;;
    competitor)
      shift_args 1
      source "$SCRIPTS_DIR/cmd/competitor.sh" "$@"
      ;;
    privacy-manifest)
      shift_args 1
      source "$SCRIPTS_DIR/cmd/privacy_manifest.sh" "$@"
      ;;
    check)
      shift_args 1
      bash "$SCRIPTS_DIR/cmd/check.sh" "$@"
      ;;
    help|-h|--help)
      show_help
      ;;
    *)
      echo -e "${RED}Unknown command: $CMD${NC}"
      echo ""
      show_help
      exit 1
      ;;
  esac
}

shift_args() {
  local n=$1
  shift $n 2>/dev/null || true
}

show_help() {
  cat << 'EOF'

  ASO Toolkit — App Store Optimization CLI

  Usage: bash aso/run.sh <command> [options]

  Setup:
    init                         First-time project setup

  Metadata:
    research                     Keyword research workflow
    metadata                     Generate/update metadata from research
    push [--locale tr,en-US]     Push metadata to App Store Connect
    pull                         Pull current metadata from ASC
    export [--json|--csv|--text] Export metadata in various formats

  Screenshots:
    screenshots capture [locales]    Capture app screenshots via simulator
    screenshots compose [locales]    Generate marketing images (Gemini AI)
    screenshots upload [--replace]   Upload screenshots to ASC

  Icons:
    icons generate [--preset name]   AI icon generation

  AI Tools:
    translate [--to tr,de,ja]    AI-translate metadata to other locales
    competitor "App1" "App2"     Competitor keyword analysis
    whats-new [--since v1.0]     Generate "What's New" from git history

  Compliance:
    check [--section N] [--json]      Apple guidelines check
    privacy-manifest [--dry-run]      Generate PrivacyInfo.xcprivacy
    score [--json]                    ASO readiness score

  Info:
    status                       Show current ASO status
    help                         Show this help

EOF
}

# ── Run ─────────────────────────────────────────────────────────────────
preflight
route "$@"
