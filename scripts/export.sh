#!/bin/bash
# aso/export.sh — Export latest metadata for screenshots & marketing
# Usage:
#   bash aso/export.sh              → all locales, readable format
#   bash aso/export.sh tr en-US     → specific locales only
#   bash aso/export.sh --json       → JSON output (for tools)
#   bash aso/export.sh --csv        → CSV output (for spreadsheets)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESEARCH_DIR="${ASO_DIR:-$SCRIPT_DIR}/data/research"

# Find latest metadata file (prefer updated_metadata > optimized_metadata)
LATEST=$(ls -t "$RESEARCH_DIR"/updated_metadata*.json "$RESEARCH_DIR"/optimized_metadata*.json 2>/dev/null | head -1)

if [ -z "$LATEST" ]; then
  echo "No metadata files found in $RESEARCH_DIR" >&2
  exit 1
fi

echo "Source: $(basename "$LATEST")" >&2

# Parse args
FORMAT="text"
LOCALES=()
for arg in "$@"; do
  case "$arg" in
    --json) FORMAT="json" ;;
    --csv)  FORMAT="csv" ;;
    *)      LOCALES+=("$arg") ;;
  esac
done

# Build jq locale filter
if [ ${#LOCALES[@]} -gt 0 ]; then
  LOCALE_FILTER=$(printf '"%s",' "${LOCALES[@]}")
  LOCALE_FILTER="[${LOCALE_FILTER%,}]"
else
  LOCALE_FILTER="null"
fi

case "$FORMAT" in
  json)
    jq --argjson locales "$LOCALE_FILTER" '
      .metadata | to_entries
      | if $locales then map(select(.key as $k | $locales | index($k))) else . end
      | map({
          locale: .key,
          title: .value.title,
          subtitle: .value.subtitle,
          keywords: .value.keywords,
          description_snippets: (
            .value.description_additions // []
            | map(select(.content != null) | .content)
          )
        })
    ' "$LATEST"
    ;;

  csv)
    echo "locale,title,subtitle,keywords"
    jq -r --argjson locales "$LOCALE_FILTER" '
      .metadata | to_entries
      | if $locales then map(select(.key as $k | $locales | index($k))) else . end
      | .[]
      | [.key, .value.title, .value.subtitle, .value.keywords]
      | @csv
    ' "$LATEST"
    ;;

  text)
    jq -r --argjson locales "$LOCALE_FILTER" '
      .metadata | to_entries
      | if $locales then map(select(.key as $k | $locales | index($k))) else . end
      | .[]
      | "════════════════════════════════════════",
        "  \(.key)",
        "════════════════════════════════════════",
        "  Title:     \(.value.title)",
        "  Subtitle:  \(.value.subtitle)",
        "  Keywords:  \(.value.keywords)",
        (if .value.description_additions then
          (.value.description_additions[]
           | if .content then "  ──────────",
             "  Screenshot text:",
             "  \(.content | split("\n") | join("\n  "))"
             else empty end)
         else empty end),
        ""
    ' "$LATEST"
    ;;
esac
