#!/usr/bin/env bash
# Rewrites the upstream (ambitionsoftware) signing identifiers so the project
# can be built under your own Apple Developer team.
#
# Usage: scripts/configure-signing.sh TEAM_ID [BUNDLE_PREFIX]
#
#   TEAM_ID        Your 10-character Apple Developer Team ID (e.g. AB12CD34EF)
#   BUNDLE_PREFIX  Bundle identifier for the app; extensions get suffixes
#                  appended automatically. Default: tw.wildfoo.foqos
#
# The changes are applied in place. Run this in CI (or once locally) before
# xcodebuild; do not commit the result if you want to keep merging upstream
# changes easily.
set -euo pipefail

TEAM_ID="${1:?Usage: scripts/configure-signing.sh TEAM_ID [BUNDLE_PREFIX]}"
BUNDLE_PREFIX="${2:-tw.wildfoo.foqos}"

OLD_TEAM="YR54789JNV"
OLD_BUNDLE="dev.ambitionsoftware.foqos"
OLD_GROUP="group.dev.ambitionsoftware.foqos"
NEW_GROUP="group.${BUNDLE_PREFIX}"

cd "$(dirname "$0")/.."

# 1. App group identifier, everywhere it appears (entitlements + Swift source).
#    Must run before the bundle id replacement since the strings overlap.
grep -rl --include='*.swift' --include='*.entitlements' "${OLD_GROUP}" . \
  | while read -r file; do
      sed -i.bak "s|${OLD_GROUP}|${NEW_GROUP}|g" "$file"
      rm -f "${file}.bak"
      echo "app group updated: $file"
    done

# 2. Bundle identifiers and team in the Xcode project.
PBXPROJ="foqos.xcodeproj/project.pbxproj"
sed -i.bak \
  -e "s|${OLD_BUNDLE}|${BUNDLE_PREFIX}|g" \
  -e "s|DEVELOPMENT_TEAM = ${OLD_TEAM};|DEVELOPMENT_TEAM = ${TEAM_ID};|g" \
  "$PBXPROJ"
rm -f "${PBXPROJ}.bak"
echo "project updated: team=${TEAM_ID} bundle=${BUNDLE_PREFIX}"

echo
echo "Register these identifiers in your Apple Developer account if the build"
echo "does not create them automatically:"
echo "  App IDs:    ${BUNDLE_PREFIX} (+ .FoqosDeviceMonitor .FoqosShieldConfig .FoqosShieldAction .FoqosWidget)"
echo "  App Group:  ${NEW_GROUP}"
