#!/bin/bash
# ── lib/common.sh — Shared colors, logging, and utility functions ─────

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Logging
info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; }
die()   { echo -e "${RED}[FATAL]${NC} $1"; exit 1; }
step()  { echo -e "\n${BOLD}${CYAN}▸ $1${NC}"; }
header() {
  echo ""
  echo -e "${BOLD}════════════════════════════════════════${NC}"
  echo -e "${BOLD}  $1${NC}"
  echo -e "${BOLD}════════════════════════════════════════${NC}"
}

# Dependency check
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 not found. $2"
}
