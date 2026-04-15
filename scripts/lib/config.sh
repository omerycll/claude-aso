#!/bin/bash
# ── lib/config.sh — Config loader: reads config.json into shell variables ─

load_config() {
  local config_file="${1:-$ASO_DIR/config.json}"

  [[ -f "$config_file" ]] || die "config.json not found at $config_file. Run: bash aso/run.sh init"

  # App info
  APP_NAME=$(jq -r '.app.name // empty' "$config_file")
  APP_SLUG=$(jq -r '.app.slug // empty' "$config_file")
  BUNDLE_ID=$(jq -r '.app.bundle_id // empty' "$config_file")
  TEAM_ID=$(jq -r '.app.team_id // empty' "$config_file")
  MARKETING_VERSION=$(jq -r '.app.marketing_version // empty' "$config_file")

  # Paths (relative to PROJECT_ROOT)
  APP_SOURCE_DIR_REL=$(jq -r '.app.source_dir // empty' "$config_file")
  XCODEPROJ_REL=$(jq -r '.app.xcodeproj // empty' "$config_file")
  ENTITLEMENTS_REL=$(jq -r '.app.entitlements // empty' "$config_file")
  INFO_PLIST_REL=$(jq -r '.app.info_plist // empty' "$config_file")
  SCHEME=$(jq -r '.app.scheme // empty' "$config_file")
  UITEST_TARGET=$(jq -r '.app.uitest_target // empty' "$config_file")

  # Resolve absolute paths
  APP_SOURCE_DIR="$PROJECT_ROOT/$APP_SOURCE_DIR_REL"
  XCODEPROJ_PATH="$PROJECT_ROOT/$XCODEPROJ_REL"
  ENTITLEMENTS_PATH="$PROJECT_ROOT/$ENTITLEMENTS_REL"
  INFO_PLIST_PATH="$PROJECT_ROOT/$INFO_PLIST_REL"

  # ASC
  ASC_APP_ID=$(jq -r '.asc.app_id // empty' "$config_file")
  ASC_VERSION_ID=$(jq -r '.asc.version_id // empty' "$config_file")
  ASC_VERSION_STRING=$(jq -r '.asc.version_string // empty' "$config_file")
  ASC_CLI=$(jq -r '.asc_cli_path // empty' "$config_file")

  # Locales
  LOCALES_JSON=$(jq -r '.locales // []' "$config_file")
  LOCALES_ARRAY=($(jq -r '.locales[]' "$config_file" 2>/dev/null))

  # URLs
  URL_PRIVACY=$(jq -r '.urls.privacy // empty' "$config_file")
  URL_TERMS=$(jq -r '.urls.terms // empty' "$config_file")
  URL_SUPPORT=$(jq -r '.urls.support // empty' "$config_file")
  URL_MARKETING=$(jq -r '.urls.marketing // empty' "$config_file")

  # Char limits
  LIMIT_TITLE=$(jq -r '.char_limits.title // 30' "$config_file")
  LIMIT_SUBTITLE=$(jq -r '.char_limits.subtitle // 30' "$config_file")
  LIMIT_KEYWORDS=$(jq -r '.char_limits.keywords // 100' "$config_file")
  LIMIT_DESCRIPTION=$(jq -r '.char_limits.description // 4000' "$config_file")

  # Devices
  DEVICE_IPHONE=$(jq -r '.devices.iphone // empty' "$config_file")
  DEVICE_IPAD=$(jq -r '.devices.ipad // empty' "$config_file")

  # Export all
  export APP_NAME APP_SLUG BUNDLE_ID TEAM_ID MARKETING_VERSION
  export APP_SOURCE_DIR XCODEPROJ_PATH ENTITLEMENTS_PATH INFO_PLIST_PATH SCHEME UITEST_TARGET
  export ASC_APP_ID ASC_VERSION_ID ASC_VERSION_STRING ASC_CLI
  export LOCALES_JSON LOCALES_ARRAY
  export URL_PRIVACY URL_TERMS URL_SUPPORT URL_MARKETING
  export LIMIT_TITLE LIMIT_SUBTITLE LIMIT_KEYWORDS LIMIT_DESCRIPTION
  export DEVICE_IPHONE DEVICE_IPAD
}

require_asc() {
  [[ -n "$ASC_CLI" ]] && command -v "$ASC_CLI" >/dev/null 2>&1 || die "asc CLI not found. Install: brew install asc"
  [[ -n "$ASC_APP_ID" ]] || die "ASC App ID not set in config.json"
}

require_version() {
  [[ -n "$ASC_VERSION_ID" ]] || die "ASC Version ID not set in config.json"
}
