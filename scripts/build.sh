#!/bin/zsh
# 构建 build/app.noindex/DuoBar.app。
# 放在名字以 .noindex 结尾的文件夹里：Spotlight 不收录，开发版就不会出现在启动台里。
#   scripts/build.sh            只构建
#   scripts/build.sh --install  构建后装到 ~/Applications 并启动
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

# SwiftUI 的宏插件只在 Xcode 里有。当前开发工具是 Command Line Tools 时，改用 Xcode 的工具链。
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/DuoBar"
APP="$ROOT/build/app.noindex/DuoBar.app"

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
