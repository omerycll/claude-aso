#!/bin/bash
# ── cmd/privacy_manifest.sh — Auto-generate PrivacyInfo.xcprivacy ──────────
# Scans project for API usage and generates Apple-required privacy manifest
# Usage: bash run.sh privacy-manifest [--dry-run]

set -uo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

header "Privacy Manifest — $APP_NAME"

APP_SOURCE="$PROJECT_ROOT/${APP_SOURCE_DIR_REL:-$(jq -r '.app.source_dir // ""' "$CONFIG")}"
OUTPUT_PATH="$APP_SOURCE/PrivacyInfo.xcprivacy"

step "Scanning project for API usage..."

python3 - "$PROJECT_ROOT" "$APP_SOURCE" "$OUTPUT_PATH" "$DRY_RUN" << 'PYEOF'
import os, sys, re, glob, json

PROJECT_ROOT = sys.argv[1]
APP_SOURCE = sys.argv[2]
OUTPUT_PATH = sys.argv[3]
DRY_RUN = sys.argv[4] == "True"

C_GREEN = '\033[0;32m'
C_YELLOW = '\033[1;33m'
C_CYAN = '\033[0;36m'
C_BOLD = '\033[1m'
C_DIM = '\033[2m'
C_NC = '\033[0m'

# Apple's required API categories and their patterns
API_CATEGORIES = {
    "NSPrivacyAccessedAPICategoryFileTimestamp": {
        "name": "File timestamp APIs",
        "patterns": [
            r"\.modificationDate", r"\.creationDate", r"attributesOfItem",
            r"FileManager.*\.contentsOfDirectory", r"stat\(",
            r"\.resourceValues.*\.contentModificationDate",
        ],
        "reasons": {
            "DDA9.1": "Displaying file timestamps to the user",
            "C617.1": "Accessing timestamps within app container/group container",
            "3B52.1": "Accessing timestamps for files the user specifically granted access to",
            "0A2A.1": "Third-party SDK providing timestamps internally",
        }
    },
    "NSPrivacyAccessedAPICategorySystemBootTime": {
        "name": "System boot time APIs",
        "patterns": [
            r"systemUptime", r"ProcessInfo.*systemUptime",
            r"kern\.boottime", r"sysctl.*KERN_BOOTTIME",
        ],
        "reasons": {
            "35F9.1": "Measuring elapsed time (not accessing absolute boot time)",
            "8FFB.1": "Calculating timestamps from boot time",
        }
    },
    "NSPrivacyAccessedAPICategoryDiskSpace": {
        "name": "Disk space APIs",
        "patterns": [
            r"volumeAvailableCapacity", r"volumeTotalCapacity",
            r"systemFreeSize", r"systemSize", r"statfs\(",
            r"\.availableCapacity", r"URLResourceKey.*volume",
        ],
        "reasons": {
            "E174.1": "Writing or downloading data to disk; checking available space first",
            "85F4.1": "Displaying disk space to user",
            "7D9E.1": "Used by health research apps",
            "B728.1": "Accessing disk space inside the app container",
        }
    },
    "NSPrivacyAccessedAPICategoryActiveKeyboards": {
        "name": "Active keyboards API",
        "patterns": [
            r"activeInputModes", r"UITextInputMode",
        ],
        "reasons": {
            "3EC4.1": "Custom keyboard app checking active keyboards",
            "54BD.1": "Used to determine appropriate language for content",
        }
    },
    "NSPrivacyAccessedAPICategoryUserDefaults": {
        "name": "User defaults APIs",
        "patterns": [
            r"UserDefaults", r"NSUserDefaults",
            r"\.standard\.set", r"\.standard\.string",
            r"\.standard\.bool", r"\.standard\.integer",
            r"@AppStorage",
        ],
        "reasons": {
            "CA92.1": "Accessing user defaults within the app",
            "1C8F.1": "Accessing user defaults via third-party SDK",
        }
    },
}

# Scan files
swift_files = glob.glob(os.path.join(APP_SOURCE, "**/*.swift"), recursive=True)
swift_files += glob.glob(os.path.join(PROJECT_ROOT, "**/*.swift"), recursive=True)
swift_files = list(set(swift_files))

# Remove Pods/DerivedData
swift_files = [f for f in swift_files if "/Pods/" not in f and "/DerivedData/" not in f and "/.build/" not in f]

print(f"  Scanning {len(swift_files)} Swift files...")
print()

detected = {}

for filepath in swift_files:
    try:
        with open(filepath) as f:
            content = f.read()
    except:
        continue

    rel_path = os.path.relpath(filepath, PROJECT_ROOT)

    for category, info in API_CATEGORIES.items():
        for pattern in info["patterns"]:
            if re.search(pattern, content):
                if category not in detected:
                    detected[category] = {"files": [], "name": info["name"]}
                if rel_path not in detected[category]["files"]:
                    detected[category]["files"].append(rel_path)

# Check Podfile/Package.swift for third-party SDKs
for dep_file in ["Podfile", "Package.swift"]:
    dep_path = os.path.join(PROJECT_ROOT, dep_file)
    if os.path.exists(dep_path):
        with open(dep_path) as f:
            content = f.read()
        # Third-party SDKs often use UserDefaults
        if "NSPrivacyAccessedAPICategoryUserDefaults" not in detected:
            if any(sdk in content for sdk in ["Firebase", "Analytics", "Crashlytics", "Sentry", "Amplitude"]):
                detected["NSPrivacyAccessedAPICategoryUserDefaults"] = {
                    "files": [dep_file],
                    "name": "User defaults APIs"
                }

# Display findings
if not detected:
    print(f"  {C_GREEN}No privacy-sensitive APIs detected.{C_NC}")
    print(f"  {C_DIM}Your app might not need a privacy manifest, but Apple still recommends one.{C_NC}")
    print()

for category, info in detected.items():
    print(f"  {C_BOLD}{info['name']}{C_NC} ({category})")
    for f in info["files"][:5]:
        print(f"    {C_DIM}{f}{C_NC}")
    if len(info["files"]) > 5:
        print(f"    {C_DIM}... and {len(info['files'])-5} more{C_NC}")
    print()

# Generate PrivacyInfo.xcprivacy
print(f"  {C_BOLD}Generating PrivacyInfo.xcprivacy...{C_NC}")
print()

accessed_api_types = []
for category, info in detected.items():
    reasons_dict = API_CATEGORIES[category]["reasons"]
    # Pick the most common/safe reason
    reason = list(reasons_dict.keys())[0]
    reason_desc = reasons_dict[reason]

    accessed_api_types.append({
        "category": category,
        "reason": reason,
        "reason_desc": reason_desc
    })

    print(f"  {C_CYAN}{info['name']}{C_NC}")
    print(f"    Reason: {reason} — {reason_desc}")
    print(f"    {C_DIM}Other options:{C_NC}")
    for r_key, r_desc in list(reasons_dict.items())[1:]:
        print(f"      {C_DIM}{r_key}: {r_desc}{C_NC}")
    print()

# Build plist XML
api_types_xml = ""
for api in accessed_api_types:
    api_types_xml += f"""		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>{api['category']}</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>{api['reason']}</string>
			</array>
		</dict>
"""

plist_content = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array/>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
{api_types_xml.rstrip()}
	</array>
</dict>
</plist>
"""

if DRY_RUN:
    print(f"  {C_YELLOW}DRY RUN — would write to:{C_NC} {OUTPUT_PATH}")
    print()
    print(plist_content)
else:
    with open(OUTPUT_PATH, "w") as f:
        f.write(plist_content)
    print(f"  {C_GREEN}✓{C_NC} Written to {os.path.relpath(OUTPUT_PATH, PROJECT_ROOT)}")
    print()
    print(f"  {C_BOLD}Next steps:{C_NC}")
    print(f"  {C_DIM}1. Review the generated file and adjust API reasons if needed{C_NC}")
    print(f"  {C_DIM}2. Add PrivacyInfo.xcprivacy to your Xcode target{C_NC}")
    print(f"  {C_DIM}3. Run /aso check to verify compliance{C_NC}")
PYEOF

echo ""
ok "Privacy manifest generation complete"
