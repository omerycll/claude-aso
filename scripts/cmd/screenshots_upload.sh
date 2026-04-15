#!/bin/bash
# ── cmd/screenshots_upload.sh — Upload screenshots to ASC ────────────────
exec bash "${SCRIPTS_DIR:-$ASO_DIR}/upload-screenshots.sh" "$@"
