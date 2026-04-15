---
name: aso
description: >
  App Store Optimization toolkit for iOS/macOS apps. Use when the user wants to
  optimize their App Store listing — keyword research, metadata generation,
  screenshot capture & marketing image composition, AI icon generation,
  Apple Review Guidelines compliance checking, and App Store Connect sync.
  Triggers on: "ASO", "App Store optimization", "keyword research", "app store metadata",
  "app store screenshots", "app icon", "Apple guidelines check", "push to ASC".
user-invocable: true
argument-hint: <command> [options]
allowed-tools: Bash Read Write Edit Grep Glob
compatibility: macOS only. Requires Xcode, jq (brew install jq), asc CLI (brew install asc), Python 3. Optional: GEMINI_API_KEY for AI icon/screenshot generation.
metadata:
  author: ASOToolkit
  version: "1.0.0"
license: MIT
---

# ASO Toolkit — App Store Optimization for iOS/macOS

A complete ASO workflow inside Claude Code. Optimize keywords, metadata, screenshots, icons, and run Apple Guidelines compliance checks — all without leaving your terminal.

## Available Commands

Run commands with: `bash ${CLAUDE_SKILL_DIR}/scripts/run.sh <command>`

| Command | Description |
|---------|-------------|
| `init` | First-time setup — discovers Xcode project, queries App Store Connect, generates config |
| `status` | Show current ASO state (app info, ASC connection, data inventory) |
| `research` | Guided keyword research workflow for each locale |
| `metadata` | Generate/update metadata from keyword research with dedup & char limit validation |
| `push` | Push metadata (title, subtitle, keywords, description) to App Store Connect |
| `pull` | Pull current metadata from ASC as baseline |
| `export` | Export metadata as JSON, CSV, or human-readable text |
| `screenshots capture` | Capture app screenshots via iOS Simulator |
| `screenshots compose` | Generate marketing images with AI (Gemini) |
| `screenshots upload` | Upload screenshots to ASC with device detection & dedup |
| `icons generate` | AI-powered icon generation (27+ preset styles) |
| `translate` | AI-translate metadata to all configured locales |
| `competitor` | Competitor keyword analysis with AI |
| `whats-new` | Generate "What's New" release notes from git history |
| `score` | ASO readiness score with recommendations |
| `check` | Apple Review Guidelines compliance check (100+ rules) |
| `privacy-manifest` | Auto-generate PrivacyInfo.xcprivacy from code scan |

## How to Use

### Step 1: Initialize
The user must be in their iOS/macOS project root (where `.xcodeproj` lives).

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh init
```

This will automatically:
- Install missing dependencies (jq, asc CLI, google-genai, Pillow)
- Ask for Gemini API key (free from https://aistudio.google.com/apikey)
- Auto-detect the Xcode project, bundle ID, team ID, version
- Guide user through App Store Connect authentication (via Xcode keychain)
- Discover available simulators
- Generate `aso/config.json`

The init process installs everything needed. The user just needs to provide:
1. **Gemini API key** (optional, for AI features) — free from Google AI Studio
2. **App Store Connect access** — via their Xcode Apple ID (Settings → Accounts)
3. **Website URLs** (optional) — privacy policy, terms, support pages

### Step 2: Keyword Research & Metadata
```bash
# Start keyword research workflow
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh research

# Generate metadata from research
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh metadata

# Export to review
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh export --text
```

**Keyword research workflow:**
1. Research keywords for each locale (use your knowledge of ASO best practices)
2. Save results to `aso/data/research/keyword_research_YYYY-MM-DD.json`
3. Generate metadata with character limit validation
4. Save to `aso/data/research/updated_metadata_YYYY-MM-DD.json`

**Character limits:**
- Title: 30 chars
- Subtitle: 30 chars  
- Keywords: 100 chars (comma-separated, no spaces, singular forms)
- Description: 4000 chars

**Important rules:**
- Never repeat title/subtitle words in the keywords field
- Use singular forms for keywords
- Keywords are comma-separated with NO spaces after commas

### Step 3: Push to App Store Connect
```bash
# Push all locales
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh push

# Push specific locales only
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh push --locale tr,en-US

# Dry run (preview without changes)
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh push --dry-run
```

### Step 4: Screenshots
```bash
# Capture from simulator
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh screenshots capture

# Generate marketing composites (requires GEMINI_API_KEY)
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh screenshots compose

# Upload to ASC
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh screenshots upload
```

### Step 5: Icons
```bash
# Generate with preset style (requires GEMINI_API_KEY)
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh icons generate --preset modern-blob
```

Available presets: modern-blob, neubrutalist, clay, gradient, glossy, flat, aqua-mascot, and 20+ more.

### Step 6: Compliance Check
```bash
# Full check
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh check

# Specific section only
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh check --section 1

# Only show failures and warnings
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh check --fail-only

# JSON output (for CI/CD)
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh check --json
```

**Sections:** 1=Safety, 2=Performance, 3=Business, 4=Design, 5=Legal, 6=Technical, 7=ASC, 8=Website

### Step 7: Translate Metadata
```bash
# Translate from en-US to all configured locales
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh translate

# Specific source and targets
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh translate --from en-US --to tr,de-DE,ja,ko
```

### Step 8: Competitor Analysis
```bash
# Analyze competitor keywords
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh competitor "Spotify" "Apple Music" --locale en-US
```

### Step 9: What's New
```bash
# Generate from git log
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh whats-new

# Since specific tag, and push directly
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh whats-new --since v1.2.0 --push
```

### Step 10: ASO Score
```bash
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh score
```

### Step 11: Privacy Manifest
```bash
# Preview what will be generated
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh privacy-manifest --dry-run

# Generate and write
bash ${CLAUDE_SKILL_DIR}/scripts/run.sh privacy-manifest
```

## Argument Routing

When the user invokes `/aso <command>`, route to the appropriate action:

- `/aso` or `/aso help` → Show available commands
- `/aso init` → Run init
- `/aso status` → Run status
- `/aso research` → Start keyword research workflow
- `/aso metadata` → Generate metadata
- `/aso push [--locale X] [--dry-run]` → Push to ASC
- `/aso pull` → Pull from ASC
- `/aso export [--json|--csv|--text]` → Export metadata
- `/aso screenshots <capture|compose|upload>` → Screenshot workflow
- `/aso icons generate [--preset X]` → Icon generation
- `/aso translate [--from en-US] [--to tr,de,ja]` → AI translate metadata
- `/aso competitor "App1" "App2" [--locale X]` → Competitor analysis
- `/aso whats-new [--since v1.0] [--push]` → Generate release notes from git
- `/aso score [--json]` → ASO readiness score
- `/aso check [--section N] [--fail-only] [--json]` → Compliance check
- `/aso privacy-manifest [--dry-run]` → Generate PrivacyInfo.xcprivacy

If no argument is provided, show a helpful summary of available commands.

## Data Structure

All data is stored under `aso/` in the user's project:

```
aso/
├── config.json                     # Project config (generated by init)
├── data/
│   ├── research/                   # Keyword research & metadata files
│   │   ├── keyword_research_*.json
│   │   ├── updated_metadata_*.json
│   │   └── optimized_metadata_*.json
│   ├── baseline/                   # ASC backups before changes
│   └── changelog/                  # Version changelog
├── icons/                          # Generated icons
└── screenshots/
    ├── output/                     # Raw simulator screenshots
    └── marketing/                  # Composed marketing images
```

## Prerequisites

Before running, ensure these are installed:

| Tool | Install | Required For |
|------|---------|-------------|
| Xcode | Mac App Store | All (project detection, simulators) |
| jq | `brew install jq` | All (JSON processing) |
| asc | `brew install asc` | ASC sync (push/pull) |
| Python 3 | Pre-installed on macOS | Compliance check, icons |
| GEMINI_API_KEY | Auto-prompted on first use | AI icons & screenshot composition |

## API Key Management

API keys are stored securely in `~/.aso/credentials` (chmod 600).

- When a user runs `icons generate` or `screenshots compose` for the first time, the script will automatically ask for their Gemini API key
- The key is saved to `~/.aso/credentials` so they only need to enter it once
- Users can also set `export GEMINI_API_KEY=xxx` in their shell profile
- To get a free Gemini API key: https://aistudio.google.com/apikey

If the user asks about API keys or how to set them up, explain this flow.

## Tips for Claude

- Always run `init` first if `aso/config.json` doesn't exist
- Before `push`, always do a `pull` first to save baseline
- Use `--dry-run` with `push` to preview changes
- The `check` command is safe to run anytime — it's read-only
- Keyword research JSON format should match the expected schema in `data/research/`
- When helping with keyword research, apply ASO best practices: focus on relevance, search volume, and competition
- AI commands (icons, screenshots compose) will auto-prompt for Gemini API key if not set
- Credentials are stored in `~/.aso/credentials` — never commit this file
