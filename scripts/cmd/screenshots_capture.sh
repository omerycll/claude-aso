#!/bin/bash
# ── cmd/screenshots_capture.sh — Capture app screenshots ─────────────────
if [[ -f "$ASO_DIR/screenshots/screenshots.sh" ]]; then
  exec bash "$ASO_DIR/screenshots/screenshots.sh" "$@"
else
  die "screenshots/screenshots.sh not found. Run screenshots init first."
fi
