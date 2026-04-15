# ASO Toolkit

**App Store Optimization for iOS/macOS — as a Claude Code Skill**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Skill-blueviolet)](https://claude.com/claude-code)
[![Platform](https://img.shields.io/badge/Platform-macOS-lightgrey)]()

---

Keyword research, metadata generation, screenshot capture, AI icon generation, Apple Guidelines compliance checking, and App Store Connect sync — all from Claude Code.

## Quick Install

```bash
git clone https://github.com/ASOToolkit/aso.git ~/.claude/skills/aso
```

Or with the installer:

```bash
git clone https://github.com/ASOToolkit/aso.git /tmp/aso && bash /tmp/aso/install-skill.sh
```

Then restart Claude Code.

## Commands

| Command | What it does |
|---------|-------------|
| `/aso init` | Auto-detect Xcode project, connect to App Store Connect, generate config |
| `/aso status` | Show app info, ASC connection, data inventory |
| `/aso research` | Guided keyword research for each locale |
| `/aso metadata` | Generate metadata from research with character limit validation |
| `/aso push` | Push title, subtitle, keywords, description to ASC |
| `/aso pull` | Pull current metadata from ASC as baseline |
| `/aso export` | Export metadata as JSON, CSV, or text |
| `/aso screenshots capture` | Capture screenshots via iOS Simulator |
| `/aso screenshots compose` | Generate marketing images with Gemini AI |
| `/aso screenshots upload` | Upload screenshots to ASC |
| `/aso icons generate` | AI icon generation (27+ preset styles) |
| `/aso check` | Apple Review Guidelines compliance (100+ checks) |

## Demo

```
> /aso init

  ASO Toolkit — Init
  ▸ Discovering Xcode project...
  [ OK ] Found: MyApp.xcodeproj
  [ OK ] App: MyApp (com.example.myapp)
  [ OK ] Team: ABCDEF1234 | Version: 1.2.0
  ▸ Connecting to App Store Connect...
  [ OK ] App ID: 6449012345
  [ OK ] Version: 1.2.0
  [ OK ] Locales: en-US, tr, de, fr, ja

> /aso check

  Apple App Store Review Guidelines — MyApp
  ═══ 1. SAFETY ══════════════════════════════════════
    ✓ [1.1] No objectionable content
    ✓ [1.2] User-generated content safeguards
  ═══ 2. PERFORMANCE ═════════════════════════════════
    ✓ [2.1] App completeness verified
    ⚠ [2.3] Only 7 Swift files — consider adding more
  ═══ 5. LEGAL ═══════════════════════════════════════
    ✓ [5.1] Privacy policy reachable
    ✗ [5.2] Terms of use — HTTP 404

  Pass: 87  Warn: 5  Fail: 2  Manual: 12
```

## Prerequisites

Just have **Xcode** installed. Everything else is set up automatically by `/aso init`:

| Tool | Auto-installed? | What it does |
|------|:-:|-------------|
| **Xcode** | - | Project detection, simulators |
| **jq** | Yes | JSON processing |
| **asc CLI** | Yes | App Store Connect sync |
| **Python 3** | Bundled with macOS | Compliance check, icons |
| **google-genai** | Yes | AI icon & screenshot generation |
| **Pillow** | Yes | Image processing |

During setup, you'll be asked for:
- **Gemini API key** (free) — get it at [aistudio.google.com/apikey](https://aistudio.google.com/apikey)
- **App Store Connect** — uses your Xcode Apple ID (Xcode → Settings → Accounts)

## Workflow

```
  ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
  │   init   │────▶│ research │────▶│ metadata │────▶│   push   │
  └──────────┘     └──────────┘     └──────────┘     └──────────┘
                         │                                 │
                         ▼                                 ▼
                   ┌──────────┐                      ┌──────────┐
                   │  export  │                      │   pull   │
                   └──────────┘                      └──────────┘

  ┌──────────────────┐     ┌──────────────────┐     ┌──────────┐
  │ screenshots      │────▶│ screenshots      │────▶│ upload   │
  │ capture          │     │ compose (AI)     │     │ to ASC   │
  └──────────────────┘     └──────────────────┘     └──────────┘

  ┌──────────────────┐     ┌──────────────────┐
  │ icons generate   │     │ check (100+      │
  │ (AI, 27+ styles) │     │ Apple guidelines)│
  └──────────────────┘     └──────────────────┘
```

## Project Structure

```
aso/
├── SKILL.md                  # Claude Code skill definition
├── README.md                 # This file
├── LICENSE                   # MIT
├── install-skill.sh          # One-command installer
├── scripts/
│   ├── run.sh                # CLI entry point
│   ├── export.sh             # Metadata export
│   ├── upload-screenshots.sh # Screenshot upload
│   ├── generate-icon.py      # AI icon generation
│   ├── guidelines_checklist.json  # 100+ Apple review rules
│   ├── cmd/                  # Subcommands
│   │   ├── init.sh
│   │   ├── status.sh
│   │   ├── research.sh
│   │   ├── metadata.sh
│   │   ├── push.sh
│   │   ├── pull.sh
│   │   ├── check.sh
│   │   ├── export.sh
│   │   ├── screenshots_capture.sh
│   │   ├── screenshots_compose.sh
│   │   ├── screenshots_upload.sh
│   │   └── icons_generate.sh
│   └── lib/                  # Shared utilities
│       ├── common.sh
│       └── config.sh
└── references/
    └── (Apple guidelines docs)
```

## How It Works

1. **Install** the skill into `~/.claude/skills/aso/`
2. **Navigate** to your iOS/macOS project in Claude Code
3. **Run** `/aso init` to configure
4. **Use** any command — Claude understands the full ASO workflow

The skill runs entirely on your Mac. No data leaves your machine except:
- App Store Connect API calls (via `asc` CLI)
- Gemini API calls for AI features (icon/screenshot generation)

## Contributing

PRs welcome! Areas that could use help:

- [ ] Android/Google Play Store support
- [ ] More icon generation presets
- [ ] A/B testing metadata suggestions
- [ ] Competitor keyword analysis
- [ ] Localization quality scoring

## License

MIT - see [LICENSE](LICENSE)
