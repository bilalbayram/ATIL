#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: scripts/release.sh <version>  (e.g. 1.0.0)}"
TAG="v${VERSION}"
DMG="ATIL-${VERSION}.dmg"

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

echo "==> Notarizing app"
ditto -c -k --keepParent build/Build/Products/Release/ATIL.app /tmp/ATIL-notarize.zip
xcrun notarytool submit /tmp/ATIL-notarize.zip --keychain-profile "notary" --wait
xcrun stapler staple build/Build/Products/Release/ATIL.app

echo "==> Creating DMG"
rm -rf /tmp/ATIL-dmg
mkdir /tmp/ATIL-dmg
cp -R build/Build/Products/Release/ATIL.app /tmp/ATIL-dmg/
ln -s /Applications /tmp/ATIL-dmg/Applications
hdiutil create -volname ATIL -srcfolder /tmp/ATIL-dmg -ov -format UDZO "${DMG}"

echo "==> Notarizing DMG"
xcrun notarytool submit "${DMG}" --keychain-profile "notary" --wait
xcrun stapler staple "${DMG}"

echo "==> Publishing GitHub release ${TAG}"
gh release create "${TAG}" "${DMG}" \
  --title "ATIL ${TAG}" \
  --generate-notes

echo "==> Cleaning up"
rm -rf build /tmp/ATIL-dmg /tmp/ATIL-notarize.zip "${DMG}"

echo "==> Done! https://github.com/bilalbayram/ATIL/releases/tag/${TAG}"
