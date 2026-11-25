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
  embed_derush
}

# Moteur de dérush hors ligne (Python + ffmpeg), compilé par GitHub pour chaque architecture.
DERUSH_VERSION="0.2.0"
embed_derush() {
  local base="https://github.com/minimalistbelgium-coder/minima-studio-windows/releases/download/derush-v$DERUSH_VERSION"
  local cache=".build/derush-$DERUSH_VERSION"
  mkdir -p "$cache"
  for pair in "arm64:mac-arm64" "x86_64:mac-x64"; do
    local arch="${pair%%:*}" name="${pair#*:}"
    if [ ! -f "$cache/$name.zip" ]; then
      echo "→ Téléchargement du moteur de dérush ($arch)…"
      curl -fsSL -o "$cache/$name.zip" "$base/minima-derush-$name.zip" || { echo "✗ Moteur de dérush introuvable ($base)"; exit 1; }
    fi
    mkdir -p "$APP/Contents/Resources/derush/$arch"
    ditto -x -k "$cache/$name.zip" "$APP/Contents/Resources/derush/$arch/" || exit 1
  done
  xattr -cr "$APP/Contents/Resources/derush" 2>/dev/null || true
}

# Signe chaque exécutable et bibliothèque du moteur (le signature --deep ne les voit pas dans Resources).
sign_derush() {
  local id="$1"
  [ -d "$APP/Contents/Resources/derush" ] || return 0
  local ent="$(mktemp)"
  cat > "$ent" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.cs.disable-library-validation</key><true/>
<key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
</dict></plist>
PL
  find "$APP/Contents/Resources/derush" -type f | while read -r f; do
    if file "$f" | grep -q "Mach-O"; then
      if [ "$id" = "-" ]; then codesign --force --sign - "$f" 2>/dev/null
      else codesign --force --options runtime --timestamp --entitlements "$ent" --sign "$id" "$f" || exit 1; fi
    fi
  done
  rm -f "$ent"
}

# Signe avec le certificat « Developer ID Application » s'il existe, sinon signature locale.
sign_app() {
  IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')"
  if [ -n "$IDENTITY" ]; then
    echo "→ Signature : $IDENTITY"
    sign_derush "$IDENTITY"
    codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
    SIGNED=1
  else
    echo "⚠︎ Pas de certificat « Developer ID Application » : signature locale seulement."
    echo "  (voir LISEZMOI.md, section « Signature Apple », pour que l'app s'installe sans alerte chez les monteurs)"
    sign_derush "-"
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
