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

cp -R build/app.noindex/DuoBar.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
# macOS 27 上 hdiutil 已不推荐使用，优先用 diskutil image create（macOS 14 起才有）；这台 Mac 上的 diskutil 不支持时还用 hdiutil。
# 两种方式做出来的安装包一样：UDZO 压缩，GUID 分区表里一个名为 DuoBar 的 APFS 卷。
USAGE=$(diskutil image create from --help 2>/dev/null || true)
if [[ $USAGE == *--volumeName* && $USAGE == *UDZO* ]]; then
  diskutil image create from --format UDZO --volumeName DuoBar "$STAGE" "$DMG" >/dev/null
  echo  # 进度写在标准错误里，结尾没有换行
else
  hdiutil create -volname DuoBar -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
fi

echo "已生成 $DMG"
shasum -a 256 "$DMG"
