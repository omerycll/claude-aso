#!/bin/bash
# ── cmd/pull.sh — Pull current metadata from ASC ────────────────────────

set -uo pipefail
require_asc
require_version

header "Pull Metadata from ASC"

DATE=$(date +%Y-%m-%d)

step "Pulling app-info..."
"$ASC_CLI" localizations list --app "$ASC_APP_ID" --type app-info --output json \
  > "$ASO_DIR/data/baseline/appinfo_$DATE.json" 2>/dev/null && ok "Saved appinfo_$DATE.json"

step "Pulling version metadata..."
"$ASC_CLI" localizations list --version "$ASC_VERSION_ID" --output json \
  > "$ASO_DIR/data/baseline/version_$DATE.json" 2>/dev/null && ok "Saved version_$DATE.json"

# Display summary
step "Current metadata:"
python3 -c "
import json
data = json.load(open('$ASO_DIR/data/baseline/appinfo_$DATE.json'))
items = data if isinstance(data, list) else data.get('data', [])
print(f'  App Info: {len(items)} locales')
for i in items:
    a = i.get('attributes', {})
    print(f\"    {a.get('locale','?'):8s}  {a.get('name',''):30s}  {a.get('subtitle','')}\")
" 2>/dev/null

echo ""
python3 -c "
import json
data = json.load(open('$ASO_DIR/data/baseline/version_$DATE.json'))
items = data if isinstance(data, list) else data.get('data', [])
print(f'  Version: {len(items)} locales')
for i in items:
    a = i.get('attributes', {})
    desc = a.get('description','')
    kw = a.get('keywords','')
    print(f\"    {a.get('locale','?'):8s}  desc={len(desc):4d}chars  kw={len(kw):3d}chars\")
" 2>/dev/null

echo ""
ok "Baseline saved to data/baseline/"
