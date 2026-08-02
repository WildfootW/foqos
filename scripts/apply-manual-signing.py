#!/usr/bin/env python3
"""Switch every signable target to manual signing with a named profile.

Usage: scripts/apply-manual-signing.py PROFILE_DIR [TEAM_ID]

xcodebuild's automatic signing provisions through developerservices2.apple.com,
which rejects App Store Connect API keys on some accounts with a misleading
"Authentication failed" for every target. The profiles are therefore created
out of band through the App Store Connect API and selected by name here.

Each .mobileprovision in PROFILE_DIR is matched to a target by the bundle
identifier embedded in its entitlements, so adding a target only needs a new
profile, not a change here.
"""
import glob
import os
import plistlib
import re
import sys

SIGNABLE_SUFFIXES = ("Tests", "UITests")


def read_profile(path):
    """Return (name, bundle identifier) for a .mobileprovision file."""
    with open(path, "rb") as f:
        raw = f.read()

    # The plist is wrapped in a CMS signature; the payload is plain XML.
    match = re.search(rb"<\?xml.*?</plist>", raw, re.S)
    if not match:
        raise SystemExit(f"{path}: no plist payload found")

    profile = plistlib.loads(match.group(0))
    application_id = profile["Entitlements"]["application-identifier"]
    # application-identifier is "<TEAMID>.<bundle id>"
    bundle_id = application_id.split(".", 1)[1]
    return profile["Name"], bundle_id, profile["Entitlements"]


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)

    profile_dir = sys.argv[1]
    team_id = sys.argv[2] if len(sys.argv) > 2 else None

    profiles = {}
    for path in sorted(glob.glob(os.path.join(profile_dir, "*.mobileprovision"))):
        name, bundle_id, entitlements = read_profile(path)
        profiles[bundle_id] = name
        groups = entitlements.get("com.apple.security.application-groups", [])
        family = "family-controls" if any(
            k.endswith("family-controls") for k in entitlements
        ) else "NO family-controls"
        print(f"profile '{name}' -> {bundle_id}  [groups: {groups or 'none'}, {family}]")

    if not profiles:
        raise SystemExit(f"no .mobileprovision files in {profile_dir}")

    pbxproj = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "foqos.xcodeproj",
        "project.pbxproj",
    )
    with open(pbxproj) as f:
        content = f.read()

    applied = []

    def rewrite(match):
        settings = match.group(1)
        found = re.search(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", settings)
        if not found:
            return match.group(0)

        bundle_id = found.group(1).strip().strip('"')
        if bundle_id not in profiles:
            return match.group(0)

        indent = "\t\t\t\t"
        settings = re.sub(
            r"CODE_SIGN_STYLE = \w+;",
            "CODE_SIGN_STYLE = Manual;",
            settings,
        )
        if "CODE_SIGN_STYLE" not in settings:
            settings = f"\n{indent}CODE_SIGN_STYLE = Manual;" + settings

        for key, value in (
            ("PROVISIONING_PROFILE_SPECIFIER", f'"{profiles[bundle_id]}"'),
            ("CODE_SIGN_IDENTITY", '"Apple Development"'),
            *((("DEVELOPMENT_TEAM", team_id),) if team_id else ()),
        ):
            settings = re.sub(rf"\n{indent}{key} = [^;]+;", "", settings)
            settings = f"\n{indent}{key} = {value};" + settings

        applied.append(bundle_id)
        return "buildSettings = {" + settings + "};"

    content = re.sub(
        r"buildSettings = \{(.*?)\n\t\t\t\};",
        rewrite,
        content,
        flags=re.S,
    )

    with open(pbxproj, "w") as f:
        f.write(content)

    print(f"\nmanual signing applied to {len(applied)} build configurations:")
    for bundle_id in sorted(set(applied)):
        print(f"  {bundle_id} -> {profiles[bundle_id]}")

    missing = set(profiles) - set(applied)
    if missing:
        print(f"\nWARNING: profiles with no matching target: {sorted(missing)}")


if __name__ == "__main__":
    main()
