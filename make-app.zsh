#!/bin/zsh
# Builds Mini Deck.app and installs it to ~/Applications.
set -euo pipefail

root=${0:A:h}
name="Mini Deck"
exe=MiniDeck
work="${TMPDIR:-/tmp}/minideck-build"
app="$work/$name.app"
dest="$HOME/Applications/$name.app"
target="$(uname -m)-apple-macos14.0"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  print "Swift compiler not found. Install Apple's Command Line Tools: xcode-select --install"
  exit 1
fi

print "Building $name..."
rm -rf "$work"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$work/cache"
export CLANG_MODULE_CACHE_PATH="$work/cache"

xcrun swiftc -O -parse-as-library -swift-version 5 -module-name "$exe" -target "$target" \
  -module-cache-path "$work/cache" \
  "$root"/Sources/**/*.swift -o "$app/Contents/MacOS/$exe"

print "Drawing the icon..."
if xcrun swiftc -O -target "$target" -module-cache-path "$work/cache" "$root/Tools/MakeIcon.swift" -o "$work/MakeIcon" \
   && "$work/MakeIcon" "$work/AppIcon.iconset" \
   && iconutil -c icns "$work/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"; then
  :
else
  print "Icon step skipped; the app still works."
fi

cp "$root/Info.plist" "$app/Contents/Info.plist"
print -n "APPL????" > "$app/Contents/PkgInfo"

# Files from the Desktop or iCloud carry Finder metadata that codesign rejects.
xattr -cr "$app"
codesign --force --deep --sign - "$app"

print "Installing to $dest..."
mkdir -p "$HOME/Applications"
pkill -x "$exe" 2>/dev/null || true
rm -rf "$dest"
ditto --noextattr --norsrc "$app" "$dest"

print "Done. Open it with:  open \"$dest\""
