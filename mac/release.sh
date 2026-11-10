#!/bin/bash
# Prépare une nouvelle version : ./release.sh 0.3.0
# Produit build/MinimaStudio-0.3.0.zip (mise à jour) et build/MinimaStudio-0.3.0.dmg (installeur).
set -e
cd "$(dirname "$0")"
source ./scripts_common.sh

VERSION="$1"
if [ -z "$VERSION" ]; then
  echo "Indique le numéro de version, par exemple : ./release.sh 0.3.0"
  exit 1
fi

echo "Minima Studio, script de publication v4 (app universelle Intel + Apple Silicon)"
compile_app "$VERSION"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/MinimaStudio")"
if [[ "$ARCHS" != *x86_64* || "$ARCHS" != *arm64* ]]; then
  echo "✗ L'app n'est pas universelle ($ARCHS). Elle ne tournerait pas sur les Mac Intel. Publication annulée."
  exit 1
fi
sign_app

NOTARIZED=0
notarize() {
  local file="$1"
  local out
  out="$(xcrun notarytool submit "$file" --keychain-profile minima --wait 2>&1)" || true
  echo "$out" | tail -5
  echo "$out" | grep -q "status: Accepted"
}

if [ "$SIGNED" = "1" ]; then
  if xcrun notarytool history --keychain-profile minima >/dev/null 2>&1; then
    echo "→ Notarisation par Apple (1 à 5 minutes)…"
    ditto -c -k --keepParent "$APP" build/notarize.zip
    if notarize build/notarize.zip; then
      xcrun stapler staple "$APP"
      NOTARIZED=1
    else
      echo "✗ Apple a refusé la notarisation. Détails : xcrun notarytool log <id> --keychain-profile minima"
      exit 1
    fi
    rm -f build/notarize.zip
  else
    echo "⚠︎ Notarisation non configurée (voir LISEZMOI.md). On continue sans."
  fi
fi

ZIP="build/MinimaStudio-$VERSION.zip"
DMG="build/MinimaStudio-$VERSION.dmg"

echo "→ Archive de mise à jour…"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "→ Installeur .dmg…"
mkdir -p build/dmg
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "Minima Studio" -srcfolder build/dmg -ov -format UDZO "$DMG" >/dev/null
rm -rf build/dmg
if [ "$SIGNED" = "1" ]; then
  codesign --force --sign "$IDENTITY" --timestamp "$DMG"
  if [ "$NOTARIZED" = "1" ]; then
    echo "→ Notarisation du .dmg…"
    notarize "$DMG" && xcrun stapler staple "$DMG"
  fi
fi

install_locally

echo ""
echo "✓ Version $VERSION prête :"
echo "   $(pwd)/$ZIP"
echo "   $(pwd)/$DMG"
echo ""
echo "Dernière étape : dans Minima Studio > Mises à jour, choisis le .zip et clique sur Publier."
