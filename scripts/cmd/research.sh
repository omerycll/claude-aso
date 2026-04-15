#!/bin/bash
# ── cmd/research.sh — Keyword research workflow ─────────────────────────

header "Keyword Research — $APP_NAME"

info "This is a guided workflow. Use Claude to perform keyword research."
echo ""
echo -e "  ${BOLD}Current State:${NC}"
echo -e "    App:      $APP_NAME ($BUNDLE_ID)"
echo -e "    Locales:  ${LOCALES_ARRAY[*]}"
echo ""

LATEST=$(ls -t "$ASO_DIR/data/research"/keyword_research_*.json 2>/dev/null | head -1)
if [[ -n "$LATEST" ]]; then
  echo -e "    Latest research: $(basename "$LATEST")"
else
  echo -e "    ${DIM}No previous research found${NC}"
fi

echo ""
echo -e "  ${BOLD}Workflow:${NC}"
echo -e "    1. Research keywords for each locale"
echo -e "    2. Save to: aso/data/research/keyword_research_$(date +%Y-%m-%d).json"
echo -e "    3. Run: ${CYAN}bash aso/run.sh metadata${NC} to generate metadata"
echo -e "    4. Run: ${CYAN}bash aso/run.sh push${NC} to push to ASC"
echo ""
echo -e "  ${BOLD}Tips:${NC}"
echo -e "    • Keywords: comma-separated, no spaces, singular forms"
echo -e "    • Don't repeat title/subtitle words in keywords"
echo -e "    • Title max: ${LIMIT_TITLE} chars | Subtitle max: ${LIMIT_SUBTITLE} chars"
echo -e "    • Keywords max: ${LIMIT_KEYWORDS} chars | Description max: ${LIMIT_DESCRIPTION} chars"
echo ""
