#!/bin/bash
# ── cmd/export.sh — Export metadata ──────────────────────────────────────
# Wrapper around existing export.sh logic
exec bash "$(dirname "$0")/../export.sh" "$@"
