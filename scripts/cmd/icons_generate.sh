#!/bin/bash
# ── cmd/icons_generate.sh — AI icon generation ───────────────────────────
exec python3 "${SCRIPTS_DIR:-$ASO_DIR}/generate-icon.py" "$@"
