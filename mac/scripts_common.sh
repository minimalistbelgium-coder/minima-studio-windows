# Fonctions partagées par build.sh et release.sh
APP="build/Minima Studio.app"

# Compile une architecture dans son propre dossier, avec macOS 13 comme version minimale,
# puis copie le binaire à part (les nouveaux Xcode écrivent les deux au même endroit).
build_arch() {
  local arch="$1"
  local triple="$arch-apple-macosx13.0"
  local scratch=".build/arch-$arch"
  swift build -c release --triple "$triple" --scratch-path "$scratch" || exit 1
  local bin="$(swift build -c release --triple "$triple" --scratch-path "$scratch" --show-bin-path)/MinimaStudio"
  mkdir -p .build/universal
  cp "$bin" ".build/universal/MinimaStudio-$arch" || exit 1
  local got="$(lipo -archs ".build/universal/MinimaStudio-$arch")"
  if [ "$got" != "$arch" ]; then
    echo "✗ La compilation $arch a produit : $got"
    exit 1
  fi
  local minos="$(vtool -arch "$arch" -show-build ".build/universal/MinimaStudio-$arch" 2>/dev/null | awk '/minos/{print $2; exit}')"
  echo "   $arch OK, macOS minimum : ${minos:-?}"
}

compile_app() {
  local version="$1"
  echo "→ Compilation Apple Silicon…"
  build_arch arm64
  echo "→ Compilation Intel…"
  build_arch x86_64
  local arm=".build/universal/MinimaStudio-arm64"
  local intel=".build/universal/MinimaStudio-x86_64"

  rm -rf build
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  # Binaire universel : tourne sur les Mac Apple Silicon et Intel
  lipo -create "$arm" "$intel" -output "$APP/Contents/MacOS/MinimaStudio" || exit 1
  echo "→ Architectures : $(lipo -archs "$APP/Contents/MacOS/MinimaStudio")"
  cp Info.plist "$APP/Contents/Info.plist"
  if [ -n "$version" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$APP/Contents/Info.plist"
  fi
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M)" "$APP/Contents/Info.plist"
  iconutil -c icns Assets/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
}

# Signe avec le certificat « Developer ID Application » s'il existe, sinon signature locale.
sign_app() {
  IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')"
  if [ -n "$IDENTITY" ]; then
    echo "→ Signature : $IDENTITY"
    codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
    SIGNED=1
  else
    echo "⚠︎ Pas de certificat « Developer ID Application » : signature locale seulement."
    echo "  (voir LISEZMOI.md, section « Signature Apple », pour que l'app s'installe sans alerte chez les monteurs)"
    codesign --force --deep --sign - "$APP"
    SIGNED=0
  fi
}

install_locally() {
  echo "→ Installation dans /Applications…"
  pkill -x MinimaStudio 2>/dev/null || true
  sleep 1
  rm -rf "/Applications/Minima Studio.app"
  cp -R "$APP" "/Applications/"
  open "/Applications/Minima Studio.app"
}
