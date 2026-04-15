#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# ASO Toolkit — Claude Code Skill Installer
#
# One-line install:
#   curl -fsSL https://raw.githubusercontent.com/ASOToolkit/aso/main/install-skill.sh | bash
#
# Or clone and run:
#   git clone https://github.com/ASOToolkit/aso.git && bash aso/install-skill.sh
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SKILL_NAME="aso"
SKILL_DIR="$HOME/.claude/skills/$SKILL_NAME"
REPO_URL="https://github.com/ASOToolkit/aso.git"

echo ""
echo -e "${BOLD}  ╔═══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}  ║   ASO Toolkit — Claude Code Skill Setup   ║${NC}"
echo -e "${BOLD}  ╚═══════════════════════════════════════════╝${NC}"
echo ""

# Check if running from cloned repo or standalone
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || pwd)"
FROM_REPO=false

if [[ -f "$SCRIPT_DIR/SKILL.md" ]]; then
  FROM_REPO=true
  SOURCE_DIR="$SCRIPT_DIR"
  echo -e "  ${DIM}Installing from local directory${NC}"
else
  echo -e "  ${DIM}Cloning from GitHub...${NC}"
  TEMP_DIR=$(mktemp -d)
  trap "rm -rf $TEMP_DIR" EXIT
  git clone --depth 1 "$REPO_URL" "$TEMP_DIR" 2>/dev/null
  SOURCE_DIR="$TEMP_DIR"
fi

# Create skill directory
echo -e "  ${CYAN}Installing to:${NC} $SKILL_DIR"
mkdir -p "$SKILL_DIR/scripts/cmd"
mkdir -p "$SKILL_DIR/scripts/lib"
mkdir -p "$SKILL_DIR/references"

# Copy skill files
cp "$SOURCE_DIR/SKILL.md" "$SKILL_DIR/"
cp "$SOURCE_DIR/LICENSE" "$SKILL_DIR/" 2>/dev/null || true

# Copy scripts
cp "$SOURCE_DIR/scripts/run.sh" "$SKILL_DIR/scripts/"
cp "$SOURCE_DIR/scripts/export.sh" "$SKILL_DIR/scripts/"
cp "$SOURCE_DIR/scripts/upload-screenshots.sh" "$SKILL_DIR/scripts/"
cp "$SOURCE_DIR/scripts/generate-icon.py" "$SKILL_DIR/scripts/"
cp "$SOURCE_DIR/scripts/guidelines_checklist.json" "$SKILL_DIR/scripts/"
cp "$SOURCE_DIR/scripts/cmd/"*.sh "$SKILL_DIR/scripts/cmd/"
cp "$SOURCE_DIR/scripts/lib/"*.sh "$SKILL_DIR/scripts/lib/"

# Make executable
chmod +x "$SKILL_DIR/scripts/run.sh"
chmod +x "$SKILL_DIR/scripts/cmd/"*.sh
chmod +x "$SKILL_DIR/scripts/lib/"*.sh
chmod +x "$SKILL_DIR/scripts/export.sh"
chmod +x "$SKILL_DIR/scripts/upload-screenshots.sh"

echo ""
echo -e "  ${GREEN}${BOLD}Successfully installed!${NC}"
echo ""
echo -e "  ${BOLD}Usage in Claude Code:${NC}"
echo ""
echo -e "    ${CYAN}/aso${NC}                      Show available commands"
echo -e "    ${CYAN}/aso init${NC}                  Setup for your iOS project"
echo -e "    ${CYAN}/aso check${NC}                 Apple Guidelines compliance"
echo -e "    ${CYAN}/aso research${NC}              Keyword research workflow"
echo -e "    ${CYAN}/aso push${NC}                  Push metadata to App Store Connect"
echo -e "    ${CYAN}/aso screenshots capture${NC}   Capture app screenshots"
echo -e "    ${CYAN}/aso icons generate${NC}        AI icon generation"
echo ""
echo -e "  ${BOLD}Prerequisites:${NC}"
echo -e "    ${DIM}brew install jq asc${NC}"
echo -e "    ${DIM}export GEMINI_API_KEY=your-key  ${DIM}# for AI features${NC}"
echo ""
echo -e "  ${DIM}Restart Claude Code to activate the skill.${NC}"
echo ""
