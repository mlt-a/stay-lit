#!/bin/bash
# Builds a Developer ID signed, notarized DMG for distribution outside the App Store.
# Needs a "Developer ID Application" certificate and a notarytool keychain profile (see README).
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

profile="${NOTARY_PROFILE:-staylit}"
team="${TEAM_ID:-$(sed -nE 's/^DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Z0-9]+).*/\1/p' Config/Local.xcconfig 2>/dev/null || true)}"
if [[ -z "$team" ]]; then
  echo "error: set TEAM_ID, or DEVELOPMENT_TEAM in Config/Local.xcconfig" >&2
  exit 1
fi

out=build/release
archive="$out/StayLit.xcarchive"
rm -rf "$out"
mkdir -p "$out"

echo "==> Archive"
/usr/bin/xcodebuild archive -quiet -scheme StayLit -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$archive"

# Generated at build time so the team ID never lands in git.
cat > "$out/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF

echo "==> Export (Developer ID)"
/usr/bin/xcodebuild -exportArchive -quiet -allowProvisioningUpdates \
  -archivePath "$archive" -exportOptionsPlist "$out/ExportOptions.plist" -exportPath "$out/export"

app="$out/export/Stay Lit.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
dmg="$out/StayLit-$version.dmg"

echo "==> DMG"
stage="$out/dmg"
mkdir -p "$stage"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
/usr/bin/hdiutil create -quiet -volname "Stay Lit" -srcfolder "$stage" -ov -format UDZO "$dmg"
# By SHA-1: a name match is ambiguous when an old certificate sits next to a new one.
identity=$(/usr/bin/security find-identity -v -p codesigning \
  | awk -v team="($team)" '/"Developer ID Application: / && index($0, team) { print $2; exit }')
if [[ -z "$identity" ]]; then
  echo "error: no valid Developer ID Application certificate for team $team" >&2
  exit 1
fi
/usr/bin/codesign --sign "$identity" --timestamp "$dmg"

echo "==> Notarize"
result=$(/usr/bin/xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait --output-format json)
status=$(/usr/bin/plutil -extract status raw - <<<"$result")
if [[ "$status" != "Accepted" ]]; then
  id=$(/usr/bin/plutil -extract id raw - <<<"$result")
  echo "error: notarization $status. Log: xcrun notarytool log $id --keychain-profile $profile" >&2
  exit 1
fi
/usr/bin/xcrun stapler staple -q "$dmg"

echo "==> Gatekeeper check"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose "$dmg"

echo "$dmg"
