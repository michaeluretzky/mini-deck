#!/bin/zsh
# Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
# Free for personal use. See LICENSE.
# Builds a universal (Apple silicon + Intel) Mini Deck.app and zips it into dist/.
# Used by the GitHub release workflow. You can also run it on your own Mac.
set -euo pipefail

root=${0:A:h}
name="Mini Deck"
exe=MiniDeck
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$root/Info.plist")
work="${TMPDIR:-/tmp}/minideck-release"
app="$work/$name.app"
dist="$root/dist"
zip="$dist/Mini-Deck-$version.zip"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  print "Swift compiler not found. Install Apple's Command Line Tools: xcode-select --install"
  exit 1
fi

rm -rf "$work"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$work/cache" "$dist"
export CLANG_MODULE_CACHE_PATH="$work/cache"

for arch in arm64 x86_64; do
  print "Building $name $version for $arch..."
  xcrun swiftc -O -parse-as-library -swift-version 5 -module-name "$exe" \
    -target "$arch-apple-macos14.0" -module-cache-path "$work/cache" \
    "$root"/Sources/**/*.swift -o "$work/$exe-$arch"
done
lipo -create "$work/$exe-arm64" "$work/$exe-x86_64" -output "$app/Contents/MacOS/$exe"
lipo -info "$app/Contents/MacOS/$exe"

print "Drawing the icon..."
host="$(uname -m)-apple-macos14.0"
xcrun swiftc -O -target "$host" -module-cache-path "$work/cache" "$root/Tools/MakeIcon.swift" -o "$work/MakeIcon"
"$work/MakeIcon" "$work/AppIcon.iconset"
iconutil -c icns "$work/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"

cp "$root/Info.plist" "$app/Contents/Info.plist"
cp "$root/LICENSE" "$app/Contents/Resources/LICENSE.txt"
print -n "APPL????" > "$app/Contents/PkgInfo"

xattr -cr "$app"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"

rm -f "$zip"
ditto -c -k --keepParent --norsrc --noextattr "$app" "$zip"
( cd "$dist" && shasum -a 256 "${zip:t}" > "${zip:t}.sha256" )
print "Done: $zip"
cat "$zip.sha256"
