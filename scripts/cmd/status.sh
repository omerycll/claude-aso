#!/bin/bash
# ── cmd/status.sh — Show current ASO status ─────────────────────────────

header "ASO Status — $APP_NAME"

echo -e "  ${BOLD}App${NC}"
echo -e "    Name:       ${CYAN}$APP_NAME${NC}"
echo -e "    Bundle:     $BUNDLE_ID"
echo -e "    Version:    $MARKETING_VERSION"
echo -e "    Team:       $TEAM_ID"
echo ""

echo -e "  ${BOLD}App Store Connect${NC}"
echo -e "    App ID:     ${CYAN}$ASC_APP_ID${NC}"
echo -e "    Version ID: ${ASC_VERSION_ID:0:12}..."
echo -e "    Locales:    ${#LOCALES_ARRAY[@]} (${LOCALES_ARRAY[*]})"
echo ""

echo -e "  ${BOLD}URLs${NC}"
for label_var in "Privacy|$URL_PRIVACY" "Terms|$URL_TERMS" "Support|$URL_SUPPORT" "Marketing|$URL_MARKETING"; do
  IFS='|' read label url <<< "$label_var"
  if [[ -n "$url" ]]; then
    CODE=$(curl -sL -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
    if [[ "$CODE" == "200" ]]; then
      echo -e "    $label:  ${GREEN}$url${NC} (${GREEN}$CODE${NC})"
    else
      echo -e "    $label:  ${RED}$url${NC} (${RED}$CODE${NC})"
    fi
  else
    echo -e "    $label:  ${DIM}not set${NC}"
  fi
done
echo ""

echo -e "  ${BOLD}Project Structure${NC}"
echo -e "    Source:       $APP_SOURCE_DIR"
echo -e "    Xcodeproj:    $XCODEPROJ_PATH"
[[ -f "$ENTITLEMENTS_PATH" ]] && echo -e "    Entitlements:  ${GREEN}✓${NC}" || echo -e "    Entitlements:  ${RED}✗ not found${NC}"
[[ -f "$INFO_PLIST_PATH" ]] && echo -e "    Info.plist:    ${GREEN}✓${NC}" || echo -e "    Info.plist:    ${RED}✗ not found${NC}"
[[ -f "$APP_SOURCE_DIR/PrivacyInfo.xcprivacy" ]] && echo -e "    Privacy manifest: ${GREEN}✓${NC}" || echo -e "    Privacy manifest: ${RED}✗ missing${NC}"
echo ""

echo -e "  ${BOLD}Data${NC}"
RESEARCH_COUNT=$(find "$ASO_DIR/data/research" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
CHANGELOG_COUNT=$(find "$ASO_DIR/data/changelog" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
BASELINE_COUNT=$(find "$ASO_DIR/data/baseline" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
ICON_COUNT=$(find "$ASO_DIR/icons" -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
SS_COUNT=$(find "$ASO_DIR/screenshots/marketing" -name "*.png" 2>/dev/null | wc -l | tr -d ' ')

echo -e "    Research files:  $RESEARCH_COUNT"
echo -e "    Changelogs:      $CHANGELOG_COUNT"
echo -e "    Baselines:       $BASELINE_COUNT"
echo -e "    Icons:           $ICON_COUNT"
echo -e "    Marketing SS:    $SS_COUNT"
echo ""
