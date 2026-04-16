#!/bin/bash
# ── cmd/score.sh — ASO Score Calculator ────────────────────────────────────
# Analyzes metadata completeness and quality, gives an ASO score
# Usage: bash run.sh score [--json]

set -uo pipefail

JSON_MODE=false
[[ "${1:-}" == "--json" ]] && JSON_MODE=true

header "ASO Score — $APP_NAME"

python3 - "$CONFIG" "$ASO_DIR" "$JSON_MODE" << 'PYEOF'
import json, sys, os, glob, subprocess

CONFIG_PATH = sys.argv[1]
ASO_DIR = sys.argv[2]
JSON_MODE = sys.argv[3] == "True"

# Colors
class C:
    RED = '\033[0;31m'; GREEN = '\033[0;32m'; YELLOW = '\033[1;33m'
    CYAN = '\033[0;36m'; BOLD = '\033[1m'; DIM = '\033[2m'; NC = '\033[0m'
    BAR_FULL = '█'; BAR_EMPTY = '░'

with open(CONFIG_PATH) as f:
    config = json.load(f)

app = config.get("app", {})
asc = config.get("asc", {})
urls = config.get("urls", {})
locales = config.get("locales", [])
limits = config.get("char_limits", {})

APP_NAME = app.get("name", "App")
PROJECT_ROOT = os.path.dirname(ASO_DIR)

# Find latest metadata
meta_files = sorted(
    glob.glob(os.path.join(ASO_DIR, "data/research/updated_metadata_*.json")) +
    glob.glob(os.path.join(ASO_DIR, "data/research/optimized_metadata_*.json")) +
    glob.glob(os.path.join(ASO_DIR, "data/research/translated_metadata_*.json")),
    key=os.path.getmtime, reverse=True
)

metadata = {}
if meta_files:
    with open(meta_files[0]) as f:
        metadata = json.load(f).get("metadata", {})

# ── Scoring categories ────────────────────────────────────────────────

scores = {}
details = {}
max_scores = {}

# 1. METADATA COMPLETENESS (25 points)
cat = "Metadata Completeness"
max_scores[cat] = 25
pts = 0
det = []

if metadata:
    for locale in locales or list(metadata.keys()):
        m = metadata.get(locale, {})
        if m.get("title"): pts += 2
        if m.get("subtitle"): pts += 2
        if m.get("keywords"): pts += 2
        if m.get("description"): pts += 2
    total_fields = max(len(locales or list(metadata.keys())) * 8, 1)
    pts = min(25, int(pts / total_fields * 25))
    det.append(f"{len(metadata)} locale(s) with metadata")
else:
    det.append("No metadata files found")

scores[cat] = pts
details[cat] = det

# 2. KEYWORD OPTIMIZATION (25 points)
cat = "Keyword Optimization"
max_scores[cat] = 25
pts = 0
det = []

for locale in list(metadata.keys())[:5]:  # Check up to 5 locales
    m = metadata.get(locale, {})
    title = m.get("title", "")
    subtitle = m.get("subtitle", "")
    keywords = m.get("keywords", "")

    # Title length usage (closer to 30 = better)
    if title:
        usage = len(title) / 30
        if usage >= 0.8: pts += 2; det.append(f"{locale}: title {len(title)}/30ch ✓")
        elif usage >= 0.5: pts += 1; det.append(f"{locale}: title {len(title)}/30ch — could use more")
        else: det.append(f"{locale}: title only {len(title)}/30ch ✗")

    # Subtitle usage
    if subtitle:
        usage = len(subtitle) / 30
        if usage >= 0.7: pts += 2
        elif usage >= 0.4: pts += 1

    # Keyword field usage
    if keywords:
        usage = len(keywords) / 100
        if usage >= 0.85: pts += 3; det.append(f"{locale}: keywords {len(keywords)}/100ch ✓")
        elif usage >= 0.6: pts += 2; det.append(f"{locale}: keywords {len(keywords)}/100ch — room for more")
        else: pts += 1; det.append(f"{locale}: keywords only {len(keywords)}/100ch ✗")

        # Check for spaces after commas (bad practice)
        if ", " in keywords:
            pts -= 1
            det.append(f"{locale}: keywords have spaces after commas (wasted chars)")

        # Check for duplicate words with title/subtitle
        kw_words = set(w.lower() for w in keywords.split(","))
        title_words = set(title.lower().split())
        dupes = kw_words & title_words
        if dupes:
            pts -= 1
            det.append(f"{locale}: keywords duplicate title words: {', '.join(list(dupes)[:3])}")

scores[cat] = min(25, max(0, pts))
details[cat] = det

# 3. APP STORE CONNECT (20 points)
cat = "App Store Connect"
max_scores[cat] = 20
pts = 0
det = []

if asc.get("app_id"):
    pts += 5; det.append("App connected ✓")
else:
    det.append("App not connected to ASC ✗")

if asc.get("version_id"):
    pts += 5; det.append(f"Version {asc.get('version_string', '?')} ready ✓")
else:
    det.append("No version in PREPARE_FOR_SUBMISSION ✗")

if len(locales) >= 3:
    pts += 5; det.append(f"{len(locales)} locales configured ✓")
elif len(locales) >= 1:
    pts += 3; det.append(f"Only {len(locales)} locale(s) — consider adding more")
else:
    det.append("No locales configured ✗")

# Screenshots
ss_count = len(glob.glob(os.path.join(ASO_DIR, "screenshots/marketing/*.png")))
if ss_count >= 10:
    pts += 5; det.append(f"{ss_count} marketing screenshots ✓")
elif ss_count >= 1:
    pts += 2; det.append(f"Only {ss_count} screenshots — need more")
else:
    det.append("No marketing screenshots ✗")

scores[cat] = pts
details[cat] = det

# 4. COMPLIANCE & QUALITY (15 points)
cat = "Compliance & Quality"
max_scores[cat] = 15
pts = 0
det = []

# Privacy policy
if urls.get("privacy"):
    pts += 4; det.append("Privacy policy URL set ✓")
else:
    det.append("No privacy policy URL ✗")

# Terms
if urls.get("terms"):
    pts += 3; det.append("Terms URL set ✓")
else:
    det.append("No terms URL ✗")

# Support URL
if urls.get("support"):
    pts += 3; det.append("Support URL set ✓")
else:
    det.append("No support URL ✗")

# App icon — recurse so nested Assets.xcassets catalogs are found
src_root = os.path.join(PROJECT_ROOT, app.get("source_dir", ""))
icon_candidates = glob.glob(os.path.join(src_root, "**", "AppIcon.appiconset"), recursive=True)
icon_dir = next((d for d in icon_candidates if os.path.isdir(d)), "")
if icon_dir and glob.glob(os.path.join(icon_dir, "*.png")):
    pts += 3; det.append("App icon present ✓")
else:
    det.append("App icon not found ✗")

# Privacy manifest — recurse so files kept in subfolders are detected
pm_matches = glob.glob(os.path.join(src_root, "**", "PrivacyInfo.xcprivacy"), recursive=True)
if pm_matches:
    pts += 2; det.append("Privacy manifest present ✓")
else:
    det.append("Privacy manifest missing ✗")

scores[cat] = pts
details[cat] = det

# 5. LOCALIZATION (15 points)
cat = "Localization"
max_scores[cat] = 15
pts = 0
det = []

locale_count = len(locales) if locales else len(metadata)
meta_locale_count = len(metadata)

if locale_count >= 10:
    pts += 8; det.append(f"{locale_count} locales — excellent coverage ✓")
elif locale_count >= 5:
    pts += 5; det.append(f"{locale_count} locales — good coverage")
elif locale_count >= 2:
    pts += 3; det.append(f"{locale_count} locales — consider adding more")
elif locale_count >= 1:
    pts += 1; det.append(f"Only {locale_count} locale")
else:
    det.append("No locales configured ✗")

# Check if all locales have metadata
if meta_locale_count >= locale_count and locale_count > 0:
    pts += 7; det.append(f"All {locale_count} locales have metadata ✓")
elif meta_locale_count > 0:
    pts += 3; det.append(f"{meta_locale_count}/{locale_count} locales have metadata")
else:
    det.append("No locales have metadata ✗")

scores[cat] = min(15, pts)
details[cat] = det

# ── Calculate total ───────────────────────────────────────────────────

total = sum(scores.values())
max_total = sum(max_scores.values())

# ── Output ────────────────────────────────────────────────────────────

if JSON_MODE:
    print(json.dumps({
        "app": APP_NAME,
        "score": total,
        "max_score": max_total,
        "percentage": round(total / max_total * 100),
        "grade": "A+" if total >= 90 else "A" if total >= 80 else "B" if total >= 65 else "C" if total >= 50 else "D" if total >= 35 else "F",
        "categories": {cat: {"score": scores[cat], "max": max_scores[cat], "details": details[cat]} for cat in scores}
    }, indent=2))
    sys.exit(0)

# Visual output
def bar(score, max_score, width=20):
    filled = int(score / max_score * width) if max_score > 0 else 0
    return C.GREEN + C.BAR_FULL * filled + C.DIM + C.BAR_EMPTY * (width - filled) + C.NC

def color_score(score, max_score):
    pct = score / max_score * 100 if max_score > 0 else 0
    if pct >= 80: return C.GREEN
    elif pct >= 50: return C.YELLOW
    return C.RED

print()
for cat in scores:
    s, m = scores[cat], max_scores[cat]
    c = color_score(s, m)
    print(f"  {C.BOLD}{cat}{C.NC}")
    print(f"  {bar(s, m)}  {c}{s}/{m}{C.NC}")
    for d in details[cat]:
        icon = "✓" if "✓" in d else "✗" if "✗" in d else "•"
        color = C.GREEN if "✓" in d else C.RED if "✗" in d else C.YELLOW
        clean = d.replace(" ✓", "").replace(" ✗", "")
        print(f"    {color}{icon}{C.NC} {clean}")
    print()

# Total
pct = round(total / max_total * 100)
grade = "A+" if pct >= 90 else "A" if pct >= 80 else "B" if pct >= 65 else "C" if pct >= 50 else "D" if pct >= 35 else "F"

grade_colors = {"A+": C.GREEN, "A": C.GREEN, "B": C.YELLOW, "C": C.YELLOW, "D": C.RED, "F": C.RED}
gc = grade_colors.get(grade, C.NC)

print(f"  {C.BOLD}{'═' * 44}{C.NC}")
print(f"  {C.BOLD}  ASO SCORE{C.NC}    {bar(total, max_total, 20)}  {gc}{C.BOLD}{total}/{max_total} ({pct}%) — Grade: {grade}{C.NC}")
print(f"  {C.BOLD}{'═' * 44}{C.NC}")
print()

# Recommendations
recs = []
if scores["Metadata Completeness"] < 15:
    recs.append("Run /aso research → /aso metadata to fill in missing metadata")
if scores["Keyword Optimization"] < 15:
    recs.append("Use all 100 keyword characters, remove spaces after commas")
if scores["App Store Connect"] < 12:
    recs.append("Connect to ASC with /aso init and add more screenshots")
if scores["Compliance & Quality"] < 10:
    recs.append("Add privacy policy, terms URLs and run /aso check")
if scores["Localization"] < 8:
    recs.append("Add more locales with /aso translate --to de-DE,fr-FR,ja,ko")

if recs:
    print(f"  {C.BOLD}Recommendations:{C.NC}")
    for r in recs:
        print(f"    {C.CYAN}→{C.NC} {r}")
    print()
PYEOF
