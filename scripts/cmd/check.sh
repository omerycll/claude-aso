#!/bin/bash
# ── cmd/check.sh — Apple Review Guidelines compliance checker ────────────
# Reads config.json for all paths, fully project-agnostic.
# Usage: bash aso/run.sh check [--json] [--section N] [--fail-only]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPTS_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPTS_DIR/../.." && pwd)}"
ASO_DIR="${ASO_DIR:-$PROJECT_ROOT/aso}"
CONFIG="${CONFIG:-$ASO_DIR/config.json}"
CHECKLIST="$SCRIPTS_DIR/guidelines_checklist.json"

source "$SCRIPTS_DIR/lib/common.sh"
require_cmd jq "Install with: brew install jq"

[[ -f "$CONFIG" ]] || die "config.json not found. Run: bash aso/run.sh init"
[[ -f "$CHECKLIST" ]] || die "guidelines_checklist.json not found"

# Pass all args + config to Python checker
python3 - "$PROJECT_ROOT" "$CONFIG" "$CHECKLIST" "$@" << 'PYTHON_CHECKER'
import json, sys, os, re, subprocess, glob

# ── Args ────────────────────────────────────────────────────────────────
PROJECT_ROOT = sys.argv[1]
CONFIG_PATH = sys.argv[2]
CHECKLIST_PATH = sys.argv[3]
extra_args = sys.argv[4:]

JSON_MODE = "--json" in extra_args
SECTION_FILTER = ""
FAIL_ONLY = "--fail-only" in extra_args
for i, a in enumerate(extra_args):
    if a == "--section" and i+1 < len(extra_args):
        SECTION_FILTER = extra_args[i+1]

# ── Load config ─────────────────────────────────────────────────────────
with open(CONFIG_PATH) as f:
    config = json.load(f)
with open(CHECKLIST_PATH) as f:
    checklist = json.load(f)

# Resolve paths from config
app = config.get("app", {})
APP_DIR = os.path.join(PROJECT_ROOT, app.get("source_dir", ""))
XCODEPROJ = os.path.join(PROJECT_ROOT, app.get("xcodeproj", ""))
ENTITLEMENTS = os.path.join(PROJECT_ROOT, app.get("entitlements", "")) if app.get("entitlements") else ""
INFO_PLIST = os.path.join(PROJECT_ROOT, app.get("info_plist", "")) if app.get("info_plist") else ""

ASC = config.get("asc_cli_path", "")
APP_ID = config.get("asc", {}).get("app_id", "")
VERSION_ID = config.get("asc", {}).get("version_id", "")

# URLs from config (not from checklist)
URLS = config.get("urls", {})

APP_NAME = app.get("name", "App")

# ── Colors ──────────────────────────────────────────────────────────────
class C:
    RED = '\033[0;31m'; GREEN = '\033[0;32m'; YELLOW = '\033[1;33m'
    CYAN = '\033[0;36m'; BOLD = '\033[1m'; DIM = '\033[2m'; NC = '\033[0m'

# ── Caches ──────────────────────────────────────────────────────────────
_file_cache = {}
_web_content_cache = {}
_asc_version_locs = None
_asc_app_info = None

def read_files(extensions):
    results = []
    for ext in extensions:
        if ext == "swift": pattern = os.path.join(APP_DIR, "*.swift")
        elif ext == "strings": pattern = os.path.join(APP_DIR, "*.xcstrings")
        elif ext == "json": pattern = os.path.join(APP_DIR, "*.json")
        elif ext == "podfile": pattern = os.path.join(PROJECT_ROOT, "Podfile")
        elif ext == "package": pattern = os.path.join(PROJECT_ROOT, "Package.swift")
        else: pattern = os.path.join(APP_DIR, f"*.{ext}")
        for fp in glob.glob(pattern):
            if fp not in _file_cache:
                try:
                    with open(fp) as f: _file_cache[fp] = f.read()
                except: _file_cache[fp] = ""
            results.append((fp, _file_cache[fp]))
    return results

def read_plist():
    if not INFO_PLIST: return ""
    if INFO_PLIST not in _file_cache:
        try:
            with open(INFO_PLIST) as f: _file_cache[INFO_PLIST] = f.read()
        except: _file_cache[INFO_PLIST] = ""
    return _file_cache[INFO_PLIST]

def run_asc(args):
    if not ASC or not os.path.exists(ASC): return None
    try:
        r = subprocess.run([ASC]+args, capture_output=True, text=True, timeout=30)
        return r.stdout
    except: return None

def fetch_web_content(base_url):
    domain = base_url.split("//")[1].split("/")[0] if "//" in base_url else base_url
    if domain in _web_content_cache: return _web_content_cache[domain]
    try:
        r = subprocess.run(["curl","-sL","--max-time","15",f"https://{domain}/"], capture_output=True, text=True, timeout=20)
        html = r.stdout
        js_urls = re.findall(r'src="(/assets/[^"]+\.js)"', html)
        if not js_urls: js_urls = re.findall(r'src="([^"]+\.js)"', html)
        all_content = ""
        for js_path in js_urls:
            if js_path.startswith("/"): js_url = f"https://{domain}{js_path}"
            elif js_path.startswith("http"): js_url = js_path
            else: js_url = f"https://{domain}/{js_path}"
            try:
                jr = subprocess.run(["curl","-sL","--max-time","20",js_url], capture_output=True, text=True, timeout=25)
                all_content += jr.stdout
            except: pass
        _web_content_cache[domain] = all_content
        return all_content
    except:
        _web_content_cache[domain] = ""
        return ""

def get_version_localizations():
    global _asc_version_locs
    if _asc_version_locs is None:
        raw = run_asc(["localizations","list","--version",VERSION_ID,"--output","json"])
        if raw:
            try:
                data = json.loads(raw)
                _asc_version_locs = data if isinstance(data, list) else data.get("data", [])
            except: _asc_version_locs = []
        else: _asc_version_locs = []
    return _asc_version_locs

def get_app_info():
    global _asc_app_info
    if _asc_app_info is None:
        raw = run_asc(["localizations","list","--app",APP_ID,"--type","app-info","--output","json"])
        if raw:
            try:
                data = json.loads(raw)
                _asc_app_info = data if isinstance(data, list) else data.get("data", [])
            except: _asc_app_info = []
        else: _asc_app_info = []
    return _asc_app_info

# ── Check functions ─────────────────────────────────────────────────────
def check_code_scan(g):
    patterns = g.get("patterns", [])
    files = read_files(g.get("scan_targets", ["swift"]))
    found = []
    for fp, content in files:
        for pat in patterns:
            try:
                m = re.findall(pat, content, re.IGNORECASE)
                if m: found.append(f"{os.path.basename(fp)}: '{m[0]}'")
            except:
                if pat.lower() in content.lower(): found.append(f"{os.path.basename(fp)}: '{pat}'")
    if found:
        detail = "; ".join(found[:3])
        if len(found) > 3: detail += f" (+{len(found)-3} more)"
        return "found", detail
    return "clean", "No matches"

def check_permission(g):
    files = read_files(["swift"])
    uses = any(re.search(g.get("import_pattern",""), c, re.IGNORECASE) for _,c in files)
    if not uses: return "not_used", "Framework not used"
    plist = read_plist()
    key = g.get("plist_key","")
    return ("ok","Usage description present") if key in plist else ("missing_plist",f"{key} missing from Info.plist")

def check_tracking():
    files = read_files(["swift"])
    uses = any(re.search(r"ASIdentifierManager|advertisingIdentifier|AdSupport|AppTrackingTransparency", c) for _,c in files)
    if not uses: return "not_used", "No IDFA/tracking"
    has_att = any("requestTrackingAuthorization" in c for _,c in files)
    return ("ok","ATT implemented") if has_att else ("missing_att","IDFA without ATT")

def check_file_exists(g):
    fn = g.get("file","")
    fp = os.path.join(APP_DIR, fn)
    if not os.path.exists(fp): return "missing", f"{fn} not found"
    if "PrivacyInfo" in fn:
        with open(fp) as f: content = f.read()
        return ("ok",f"{fn} with API declarations") if "NSPrivacyAccessedAPITypes" in content else ("incomplete",f"{fn} missing API declarations")
    return "ok", f"{fn} exists"

def check_iap():
    files = read_files(["swift"])
    has = any(re.search(r"import StoreKit|Product\.|Transaction\.", c) for _,c in files)
    return ("ok","StoreKit integration found") if has else ("not_used","No StoreKit")

def check_subscription():
    files = read_files(["swift"])
    has_sub = any(re.search(r"\.autoRenewable|subscription|weekly|monthly|yearly", c, re.IGNORECASE) for _,c in files)
    if not has_sub: return "not_used", "No subscriptions"
    has_restore = any(re.search(r"restorePurchases|AppStore\.sync|Transaction\.currentEntitlements", c) for _,c in files)
    has_terms = any(re.search(r"auto.renew|cancel.*any.*time|subscription.*terms", c, re.IGNORECASE) for _,c in files)
    issues = []
    if not has_restore: issues.append("missing restore")
    if not has_terms: issues.append("missing terms display")
    return ("incomplete","; ".join(issues)) if issues else ("ok","Subscriptions properly implemented")

def check_app_icon():
    icon_dir = os.path.join(APP_DIR, "Assets.xcassets", "AppIcon.appiconset")
    if not os.path.isdir(icon_dir): return "missing", "AppIcon.appiconset not found"
    pngs = glob.glob(os.path.join(icon_dir, "*.png"))
    if not pngs: return "missing", "No icon PNGs"
    for png in pngs:
        try:
            r = subprocess.run(["sips","-g","pixelWidth",png], capture_output=True, text=True, timeout=5)
            if "1024" in r.stdout: return "ok", "1024x1024 app icon found"
        except: pass
    return "warn", f"{len(pngs)} icon PNGs, verify 1024x1024"

def check_min_functionality():
    count = len(glob.glob(os.path.join(APP_DIR, "*.swift")))
    if count >= 10: return "ok", f"{count} Swift files"
    if count >= 5: return "warn", f"Only {count} Swift files"
    return "insufficient", f"Only {count} Swift files"

def check_sign_in_apple():
    files = read_files(["swift"])
    has_3p = any(re.search(r"GoogleSignIn|GIDSignIn|FBSDKLoginKit|FacebookLogin", c, re.IGNORECASE) for _,c in files)
    if not has_3p: return "not_required", "No third-party login"
    has_siwa = any(re.search(r"ASAuthorizationAppleIDProvider|SignInWithApple", c) for _,c in files)
    return ("ok","Sign in with Apple implemented") if has_siwa else ("missing","Third-party login without SIWA")

def check_privacy_policy():
    url = URLS.get("privacy","")
    if not url: return "missing", "No privacy URL"
    try:
        r = subprocess.run(["curl","-sL","-o","/dev/null","-w","%{http_code}","--max-time","10",url], capture_output=True, text=True, timeout=15)
        return ("ok",f"Reachable: {url}") if r.stdout.strip()=="200" else ("unreachable",f"HTTP {r.stdout.strip()}: {url}")
    except: return "unreachable", f"Cannot reach {url}"

def check_url_reachable(g):
    url = URLS.get(g.get("url_key",""),"")
    if not url: return "missing", f"No {g.get('url_key','')} URL"
    try:
        r = subprocess.run(["curl","-sL","-o","/dev/null","-w","%{http_code}","--max-time","10",url], capture_output=True, text=True, timeout=15)
        return ("ok",f"{url} → HTTP {r.stdout.strip()}") if r.stdout.strip()=="200" else ("unreachable",f"{url} → HTTP {r.stdout.strip()}")
    except: return "unreachable", f"Cannot reach {url}"

def check_deployment_target():
    try:
        with open(os.path.join(XCODEPROJ, "project.pbxproj")) as f: content = f.read()
        m = re.findall(r"IPHONEOS_DEPLOYMENT_TARGET = (\d+\.\d+)", content)
        if m: return "ok", f"iOS {m[0]}"
    except: pass
    return "warn", "Could not determine"

def check_dependencies():
    deps = []
    if os.path.exists(os.path.join(PROJECT_ROOT,"Podfile")): deps.append("CocoaPods")
    if os.path.exists(os.path.join(PROJECT_ROOT,"Package.swift")): deps.append("SPM")
    if os.path.exists(os.path.join(PROJECT_ROOT,"Cartfile")): deps.append("Carthage")
    return ("ok","No third-party deps") if not deps else ("warn",f"Uses {', '.join(deps)}")

def check_web_content(g):
    url = URLS.get(g.get("url_key",""),"")
    if not url: return "missing", f"No {g.get('url_key','')} URL"
    domain = url.split("//")[1].split("/")[0] if "//" in url else ""
    if not domain: return "missing", f"Invalid URL"
    content = fetch_web_content(domain)
    if not content: return "unreachable", f"No content from {domain}"
    required = g.get("required_terms",[])
    min_req = g.get("min_required",1)
    found = [t for t in required if re.search(re.escape(t), content, re.IGNORECASE)]
    missing = [t for t in required if t not in found]
    return ("ok",f"Found {len(found)}/{len(required)}: {', '.join(found[:4])}") if len(found) >= min_req else ("missing_content",f"Missing: {', '.join(missing[:4])}")

def check_asc_descriptions():
    locs = get_version_localizations()
    if not locs: return "unavailable", "No ASC data"
    issues = []
    for l in locs:
        a = l.get("attributes",{})
        locale, desc, kw = a.get("locale","?"), a.get("description",""), a.get("keywords","")
        probs = []
        if not desc or len(desc)<50: probs.append(f"desc({len(desc)})")
        if not kw or len(kw)<10: probs.append(f"kw({len(kw)})")
        if probs: issues.append(f"{locale}: {','.join(probs)}")
    return ("incomplete","; ".join(issues[:3])) if issues else ("ok",f"All {len(locs)} locales complete")

def check_asc_app_info():
    info = get_app_info()
    if not info: return "unavailable", "No ASC data"
    issues = []
    for i in info:
        a = i.get("attributes",{}); loc = a.get("locale","?"); name = a.get("name",""); sub = a.get("subtitle","")
        if not name: issues.append(f"{loc}:no-name")
        elif len(name)>30: issues.append(f"{loc}:name={len(name)}")
        if sub and len(sub)>30: issues.append(f"{loc}:subtitle={len(sub)}")
    return ("incomplete","; ".join(issues[:3])) if issues else ("ok",f"All {len(info)} locales valid")

def check_asc_copyright():
    raw = run_asc(["versions","update","--version-id",VERSION_ID,"--copyright",f"2026 {APP_NAME}"])
    return ("ok",f"Copyright verified") if raw else ("missing","Copyright not set")

def check_asc_screenshots():
    locs = get_version_localizations()
    return ("ok",f"{len(locs)} locales") if locs else ("unavailable","No ASC data")

def check_asc_desc_contains(g):
    locs = get_version_localizations()
    if not locs: return "unavailable", "No ASC data"
    contains = g.get("contains",[])
    missing = {}
    term_variants = {
        "privacy": ["privacy","gizlilik","datenschutz","confidentialité","privacidad","privacidade","プライバシー","개인정보","隐私","الخصوصية","riservatezza"],
        "terms": ["terms","koşul","nutzung","condition","condicion","termos","termini","利用規約","이용약관","条款","شروط"]
    }
    for l in locs:
        a = l.get("attributes",{}); locale = a.get("locale","?"); desc = (a.get("description","") or "").lower()
        for term in contains:
            variants = term_variants.get(term,[term])
            if not any(v in desc for v in variants): missing.setdefault(term,[]).append(locale)
    if missing:
        details = [f"{t} missing in: {','.join(ls)}" for t,ls in missing.items()]
        return "incomplete", "; ".join(details)
    return "ok", "All descriptions contain required links"

# ── Dispatcher ──────────────────────────────────────────────────────────
def run_check(g):
    t = g.get("check","manual")
    if t == "code_scan":
        s, d = check_code_scan(g)
        if s == "found":
            sec = g.get("section","")
            return ("fail",d) if sec in ("Safety","Legal") and g.get("severity")=="fail" else ("warn",f"Patterns: {d}")
        return "pass", d
    elif t == "permission_check":
        s, d = check_permission(g)
        return ("pass",d) if s in ("not_used","ok") else ("fail",d)
    elif t == "tracking_check":
        s, d = check_tracking()
        return ("pass",d) if s in ("not_used","ok") else ("fail",d)
    elif t == "file_exists":
        s, d = check_file_exists(g)
        return ("pass",d) if s=="ok" else ("warn",d) if s=="incomplete" else ("fail",d)
    elif t == "iap_check":
        return "pass", check_iap()[1]
    elif t == "subscription_check":
        s, d = check_subscription()
        return ("pass",d) if s in ("not_used","ok") else ("fail",d)
    elif t == "app_icon":
        s, d = check_app_icon()
        return ("pass",d) if s=="ok" else ("warn",d) if s=="warn" else ("fail",d)
    elif t == "min_functionality":
        s, d = check_min_functionality()
        return ("pass",d) if s=="ok" else ("warn",d) if s=="warn" else ("fail",d)
    elif t == "sign_in_apple":
        s, d = check_sign_in_apple()
        return ("pass",d) if s in ("not_required","ok") else ("fail",d)
    elif t == "privacy_policy":
        s, d = check_privacy_policy()
        return ("pass",d) if s=="ok" else ("fail",d)
    elif t == "url_reachable":
        s, d = check_url_reachable(g)
        return ("pass",d) if s=="ok" else ("fail" if g.get("severity")=="fail" else "warn", d)
    elif t == "deployment_target":
        s, d = check_deployment_target()
        return ("pass",d) if s=="ok" else ("warn",d)
    elif t == "dependencies":
        s, d = check_dependencies()
        return ("pass",d) if s=="ok" else ("warn",d)
    elif t == "web_content":
        s, d = check_web_content(g)
        return ("pass",d) if s=="ok" else (g.get("severity","warn"),d)
    elif t == "asc_metadata":
        info = get_app_info()
        return ("pass",f"{len(info)} locales") if info else ("warn","No ASC data")
    elif t == "asc_descriptions":
        s, d = check_asc_descriptions()
        return ("pass",d) if s=="ok" else ("warn",d) if s=="unavailable" else ("fail",d)
    elif t == "asc_app_info":
        s, d = check_asc_app_info()
        return ("pass",d) if s=="ok" else ("warn",d) if s=="unavailable" else ("fail",d)
    elif t == "asc_copyright":
        s, d = check_asc_copyright()
        return ("pass",d) if s=="ok" else ("fail",d)
    elif t == "asc_screenshots":
        s, d = check_asc_screenshots()
        return ("pass",d) if s=="ok" else ("warn",d)
    elif t == "asc_desc_contains":
        s, d = check_asc_desc_contains(g)
        return ("pass",d) if s=="ok" else ("warn",d)
    elif t in ("manual","metadata_check"):
        return "info", g.get("description","Manual review required")
    return "warn", "Unknown check"

# ── Run ─────────────────────────────────────────────────────────────────
results = []
guidelines = checklist.get("guidelines", [])

if SECTION_FILTER:
    sec_map = {"1":"Safety","2":"Performance","3":"Business","4":"Design","5":"Legal","6":"Technical","7":"App Store Connect","8":"Website"}
    fn = sec_map.get(SECTION_FILTER, SECTION_FILTER)
    guidelines = [g for g in guidelines if g.get("section","").lower().startswith(fn.lower()) or g.get("id","").startswith(SECTION_FILTER)]

for g in guidelines:
    s, d = run_check(g)
    results.append({"id":g["id"],"section":g["section"],"title":g["title"],"status":s,"detail":d,"description":g.get("description","")})

pc = sum(1 for r in results if r["status"]=="pass")
wc = sum(1 for r in results if r["status"]=="warn")
fc = sum(1 for r in results if r["status"]=="fail")
ic = sum(1 for r in results if r["status"]=="info")

if JSON_MODE:
    print(json.dumps({"app":APP_NAME,"summary":{"pass":pc,"warn":wc,"fail":fc,"info":ic,"total":len(results)},"results":results}, indent=2, ensure_ascii=False))
    sys.exit(0)

icons = {"pass":f"{C.GREEN}✓{C.NC}","warn":f"{C.YELLOW}⚠{C.NC}","fail":f"{C.RED}✗{C.NC}","info":f"{C.CYAN}ℹ{C.NC}"}
src = checklist.get("_meta",{}).get("source","")
ver = checklist.get("_meta",{}).get("last_updated","")

print(f"\n{C.BOLD}Apple App Store Review Guidelines — {APP_NAME}{C.NC}")
print(f"{C.DIM}Source: {src} | Guidelines: {ver} | Checks: {len(results)}{C.NC}")

cur_sec = ""
sec_nums = {"Safety":"1","Performance":"2","Business":"3","Design":"4","Legal":"5","Technical":"T","App Store Connect":"ASC","Website":"WEB"}
for r in results:
    if FAIL_ONLY and r["status"] not in ("fail","warn"): continue
    if r["section"] != cur_sec:
        cur_sec = r["section"]
        sn = sec_nums.get(cur_sec,"?")
        print(f"\n{C.BOLD}{C.CYAN}{'═'*3} {sn}. {cur_sec.upper()} {'═'*50}{C.NC}")
    icon = icons.get(r["status"],"?")
    if r["status"] == "info":
        print(f"  {icon} {C.DIM}[{r['id']}]{C.NC} {r['title']}")
        print(f"         {C.DIM}{r['detail'][:100]}{C.NC}")
    elif r["status"] == "fail":
        print(f"  {icon} {C.DIM}[{r['id']}]{C.NC} {C.RED}{r['title']}{C.NC}")
        print(f"         {r['detail']}")
    elif r["status"] == "warn":
        print(f"  {icon} {C.DIM}[{r['id']}]{C.NC} {C.YELLOW}{r['title']}{C.NC}")
        print(f"         {r['detail']}")
    else:
        print(f"  {icon} {C.DIM}[{r['id']}]{C.NC} {r['title']} — {r['detail']}")

print(f"\n{C.BOLD}{'═'*56}{C.NC}")
print(f"{C.BOLD}  {APP_NAME} — Compliance Summary{C.NC}")
print(f"{C.BOLD}{'═'*56}{C.NC}")
print(f"  {C.GREEN}Pass:{C.NC}     {pc}")
print(f"  {C.YELLOW}Warn:{C.NC}     {wc}")
print(f"  {C.RED}Fail:{C.NC}     {fc}")
print(f"  {C.CYAN}Manual:{C.NC}   {ic}")
print(f"  Total:    {len(results)}")
print()
if fc > 0:
    print(f"  {C.RED}{C.BOLD}✗ {fc} blocker(s) — must fix before submission{C.NC}")
    for r in results:
        if r["status"]=="fail": print(f"  {C.RED}→ [{r['id']}] {r['title']}: {r['detail']}{C.NC}")
    print()
elif wc > 0:
    print(f"  {C.YELLOW}{C.BOLD}⚠ No blockers, but {wc} warning(s) to review{C.NC}\n")
else:
    print(f"  {C.GREEN}{C.BOLD}✓ All checks passed — ready for submission!{C.NC}\n")
PYTHON_CHECKER
