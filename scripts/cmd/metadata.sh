#!/bin/bash
# ── cmd/metadata.sh — Generate/update metadata from research ─────────────

header "Metadata — $APP_NAME"

LATEST=$(ls -t "$ASO_DIR/data/research"/keyword_research_*.json 2>/dev/null | head -1)

if [[ -z "$LATEST" ]]; then
  warn "No keyword research found. Run: bash aso/run.sh research"
  exit 1
fi

info "Latest research: $(basename "$LATEST")"
echo ""
echo -e "  ${BOLD}Workflow:${NC}"
echo -e "    1. Review research: ${CYAN}cat $(basename "$LATEST")${NC}"
echo -e "    2. Generate metadata with dedup check"
echo -e "    3. Save to: aso/data/research/updated_metadata_$(date +%Y-%m-%d).json"
echo -e "    4. Export: ${CYAN}bash aso/run.sh export --text${NC}"
echo -e "    5. Push: ${CYAN}bash aso/run.sh push${NC}"
echo ""
echo -e "  ${BOLD}Character Limits:${NC}"
echo -e "    Title:       ${LIMIT_TITLE} chars"
echo -e "    Subtitle:    ${LIMIT_SUBTITLE} chars"
echo -e "    Keywords:    ${LIMIT_KEYWORDS} chars (comma-separated, no spaces)"
echo -e "    Description: ${LIMIT_DESCRIPTION} chars"
echo ""
