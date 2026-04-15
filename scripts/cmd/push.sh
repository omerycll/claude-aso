#!/bin/bash
# ── cmd/push.sh — Push metadata to App Store Connect ────────────────────
# Usage: bash aso/run.sh push [--locale tr,en-US] [--dry-run]

set -uo pipefail
require_asc
require_version

FILTER_LOCALE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --locale) FILTER_LOCALE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) shift ;;
  esac
done

# Find latest metadata file
METADATA_FILE=$(ls -t "$ASO_DIR/data/research"/updated_metadata_*.json "$ASO_DIR/data/research"/optimized_metadata_*.json 2>/dev/null | head -1)
[[ -n "$METADATA_FILE" ]] || die "No metadata file found in $ASO_DIR/data/research/"

header "Push Metadata to ASC"
info "Source: $(basename "$METADATA_FILE")"
info "App: $APP_NAME ($ASC_APP_ID)"
info "Version: $ASC_VERSION_STRING ($ASC_VERSION_ID)"
$DRY_RUN && warn "DRY RUN — no changes will be made"
echo ""

# Save baseline first
step "Saving baseline..."
DATE=$(date +%Y-%m-%d)
"$ASC_CLI" localizations list --app "$ASC_APP_ID" --type app-info --output json \
  > "$ASO_DIR/data/baseline/appinfo_pre_push_$DATE.json" 2>/dev/null && ok "App info baseline"
"$ASC_CLI" localizations list --version "$ASC_VERSION_ID" --output json \
  > "$ASO_DIR/data/baseline/version_pre_push_$DATE.json" 2>/dev/null && ok "Version baseline"

# Push per locale
step "Pushing metadata..."

SUCCESS=0; FAILED=0; SKIPPED=0

python3 -c "
import json, sys

data = json.load(open('$METADATA_FILE'))
metadata = data.get('metadata', {})
filter_loc = '$FILTER_LOCALE'

for locale, meta in metadata.items():
    if filter_loc and locale not in filter_loc.split(','):
        continue
    title = meta.get('title', '')
    subtitle = meta.get('subtitle', '')
    keywords = meta.get('keywords', '')
    description = meta.get('description', '')
    print(f'{locale}|||{title}|||{subtitle}|||{keywords}|||{description}')
" 2>/dev/null | while IFS='|||' read locale title subtitle keywords description; do
  [[ -z "$locale" ]] && continue

  echo -e "  ${CYAN}$locale${NC}"

  if $DRY_RUN; then
    echo "    title: $title"
    echo "    subtitle: $subtitle"
    echo "    keywords: ${keywords:0:50}..."
    ((SKIPPED++))
    continue
  fi

  # Update app-info (name + subtitle)
  if [[ -n "$title" ]]; then
    "$ASC_CLI" localizations update --app "$ASC_APP_ID" --type app-info \
      --locale "$locale" --name "$title" --subtitle "$subtitle" >/dev/null 2>&1 && \
      echo -e "    ${GREEN}✓${NC} app-info" || echo -e "    ${RED}✗${NC} app-info"
  fi

  # Update version (keywords + description)
  if [[ -n "$keywords" ]]; then
    "$ASC_CLI" localizations update --version "$ASC_VERSION_ID" \
      --locale "$locale" --keywords "$keywords" --description "$description" >/dev/null 2>&1 && \
      echo -e "    ${GREEN}✓${NC} version" || echo -e "    ${RED}✗${NC} version"
  fi
done

echo ""
ok "Push complete"
