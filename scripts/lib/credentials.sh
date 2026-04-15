#!/bin/bash
# ── lib/credentials.sh — API key management ────────────────────────────────
# Stores credentials in ~/.aso/credentials
# Usage:
#   source lib/credentials.sh
#   require_gemini_key    # ensures GEMINI_API_KEY is set

CREDENTIALS_DIR="$HOME/.aso"
CREDENTIALS_FILE="$CREDENTIALS_DIR/credentials"

# Load saved credentials
load_credentials() {
  if [[ -f "$CREDENTIALS_FILE" ]]; then
    source "$CREDENTIALS_FILE"
  fi
}

# Save a credential
save_credential() {
  local key="$1"
  local value="$2"
  mkdir -p "$CREDENTIALS_DIR"
  chmod 700 "$CREDENTIALS_DIR"

  # Remove old entry if exists
  if [[ -f "$CREDENTIALS_FILE" ]]; then
    grep -v "^${key}=" "$CREDENTIALS_FILE" > "${CREDENTIALS_FILE}.tmp" 2>/dev/null || true
    mv "${CREDENTIALS_FILE}.tmp" "$CREDENTIALS_FILE"
  fi

  # Append new entry
  echo "${key}=${value}" >> "$CREDENTIALS_FILE"
  chmod 600 "$CREDENTIALS_FILE"
}

# Ensure GEMINI_API_KEY is available
require_gemini_key() {
  load_credentials

  # Already in env?
  if [[ -n "${GEMINI_API_KEY:-}" ]]; then
    export GEMINI_API_KEY
    return 0
  fi

  # Ask user
  echo ""
  echo -e "${BOLD}Gemini API Key Required${NC}"
  echo -e "${DIM}AI features (icon generation, screenshot composition) need a Google Gemini API key.${NC}"
  echo -e "${DIM}Get one free at: https://aistudio.google.com/apikey${NC}"
  echo ""
  read -rp "  Enter your Gemini API Key: " key

  if [[ -z "$key" ]]; then
    die "Gemini API key is required for this command."
  fi

  # Validate format (basic check)
  if [[ ${#key} -lt 20 ]]; then
    die "Invalid API key format."
  fi

  # Save for future use
  save_credential "GEMINI_API_KEY" "$key"
  export GEMINI_API_KEY="$key"

  echo -e "  ${GREEN}✓${NC} API key saved to ~/.aso/credentials"
  echo ""
}
