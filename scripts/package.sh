#!/bin/zsh
# 打包 build/DuoBar-<版本>-arm64.dmg：里面是 DuoBar.app 和“应用程序”文件夹的快捷方式。
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

scripts/build.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG="$ROOT/build/DuoBar-$VERSION-$(uname -m).dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R build/DuoBar.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname DuoBar -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null

echo "已生成 $DMG"
shasum -a 256 "$DMG"
