#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: scripts/release.sh <version>  (e.g. 1.0.0)}"
TAG="v${VERSION}"
DMG="ATIL-${VERSION}.dmg"
ZIP="ATIL-${VERSION}.zip"
REPO="bilalbayram/ATIL"
APP_PATH="build/Build/Products/Release/ATIL.app"

# ── Sparkle tools ────────────────────────────────────────────────────
SPARKLE_TOOLS="${HOME}/.cache/sparkle-tools"
SPARKLE_VER="2.9.0"

if [ ! -f "${SPARKLE_TOOLS}/sign_update" ]; then
    echo "==> Downloading Sparkle tools ${SPARKLE_VER}"
    mkdir -p "${SPARKLE_TOOLS}" /tmp/sparkle-extract
    curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VER}/Sparkle-${SPARKLE_VER}.tar.xz" \
        -o /tmp/sparkle.tar.xz
    tar -xJf /tmp/sparkle.tar.xz -C /tmp/sparkle-extract
    cp /tmp/sparkle-extract/bin/sign_update "${SPARKLE_TOOLS}/"
    cp /tmp/sparkle-extract/bin/generate_keys "${SPARKLE_TOOLS}/"
    chmod +x "${SPARKLE_TOOLS}/sign_update" "${SPARKLE_TOOLS}/generate_keys"
    rm -rf /tmp/sparkle-extract /tmp/sparkle.tar.xz
fi

# ── Build ────────────────────────────────────────────────────────────
echo "==> Updating version in Project.swift"
sed -i '' "s/\"MARKETING_VERSION\": \".*\"/\"MARKETING_VERSION\": \"${VERSION}\"/" Project.swift

echo "==> Building ATIL ${TAG}"
tuist install && tuist generate

xcodebuild -workspace ATIL.xcworkspace -scheme ATIL \
  -configuration Release -derivedDataPath build \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="3N28465E96" \
  CODE_SIGN_STYLE="Manual" \
  ENABLE_HARDENED_RUNTIME=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  MARKETING_VERSION="${VERSION}" \
  clean build

# ── Notarize app ─────────────────────────────────────────────────────
echo "==> Notarizing app"
ditto -c -k --keepParent "${APP_PATH}" /tmp/ATIL-notarize.zip
xcrun notarytool submit /tmp/ATIL-notarize.zip --keychain-profile "notary" --wait
xcrun stapler staple "${APP_PATH}"

# ── Create DMG (for first-time downloads) ────────────────────────────
echo "==> Creating DMG"
rm -rf /tmp/ATIL-dmg
mkdir /tmp/ATIL-dmg
cp -R "${APP_PATH}" /tmp/ATIL-dmg/
ln -s /Applications /tmp/ATIL-dmg/Applications
hdiutil create -volname ATIL -srcfolder /tmp/ATIL-dmg -ov -format UDZO "${DMG}"

echo "==> Notarizing DMG"
xcrun notarytool submit "${DMG}" --keychain-profile "notary" --wait
xcrun stapler staple "${DMG}"

# ── Create Sparkle update archive ────────────────────────────────────
echo "==> Creating Sparkle update archive"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP}"

echo "==> Signing update with EdDSA"
ENCLOSURE_ATTRS=$("${SPARKLE_TOOLS}/sign_update" "${ZIP}")

# ── Update appcast.xml ───────────────────────────────────────────────
echo "==> Updating appcast.xml"
PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ZIP}"

# Insert new item before </channel>, preserving previous entries
python3 -c "
import sys
item = '''        <item>
            <title>Version ${VERSION}</title>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <pubDate>${PUB_DATE}</pubDate>
            <enclosure url=\"${DOWNLOAD_URL}\" ${ENCLOSURE_ATTRS} type=\"application/octet-stream\"/>
        </item>'''
content = open('appcast.xml').read()
content = content.replace('    </channel>', item + '\n    </channel>')
open('appcast.xml', 'w').write(content)
"

# ── Publish ──────────────────────────────────────────────────────────
echo "==> Publishing GitHub release ${TAG}"
gh release create "${TAG}" "${DMG}" "${ZIP}" \
  --title "ATIL ${TAG}" \
  --generate-notes

echo "==> Committing updated appcast"
git add appcast.xml Project.swift
git commit -m "Update appcast for ${TAG}"
git push

# ── Clean up ─────────────────────────────────────────────────────────
echo "==> Cleaning up"
rm -rf build /tmp/ATIL-dmg /tmp/ATIL-notarize.zip "${DMG}" "${ZIP}"

echo "==> Done! https://github.com/${REPO}/releases/tag/${TAG}"
