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

# 签名：钥匙串里有“DuoBar Code Signing”证书时用它签，否则 ad-hoc。
# 用同一张证书签的每个版本，系统看到的签名特征都一样（identifier + 证书），
# 更新后定位、蓝牙等权限不会丢；ad-hoc 签名的特征是程序的哈希，每次构建都变。
# DUOBAR_SIGN_IDENTITY 可以指定别的证书，设成 - 就用 ad-hoc。
IDENTITY="${DUOBAR_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(security find-certificate -c "DuoBar Code Signing" -Z 2>/dev/null | awk '/SHA-1/ { print $3; exit }')
fi
codesign --force --sign "${IDENTITY:--}" "$APP"
# awk 读完整个输出再结束：提前退出会让 codesign 收到 SIGPIPE，在 pipefail 下整条管道算失败。
SIGNER=$(codesign -dv --verbose=2 "$APP" 2>&1 | awk -F= '/^Authority=/ && !found { print $2; found = 1 }')
echo "已生成 $APP（签名：${SIGNER:-ad-hoc}）"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x DuoBar 2>/dev/null || true
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/DuoBar.app"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/DuoBar.app"
  echo "已安装到 ~/Applications 并启动"
fi
