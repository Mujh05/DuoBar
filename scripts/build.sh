#!/bin/zsh
# 构建 build/DuoBar.app。
#   scripts/build.sh            只构建
#   scripts/build.sh --install  构建后装到 ~/Applications 并启动
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/DuoBar"
APP="$ROOT/build/DuoBar.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DuoBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# 应用图标由程序自己画出来。
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
"$BIN" --render-app-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# 本机自用，ad-hoc 签名即可。
codesign --force --sign - "$APP"
echo "已生成 $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x DuoBar 2>/dev/null || true
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/DuoBar.app"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/DuoBar.app"
  echo "已安装到 ~/Applications 并启动"
fi
