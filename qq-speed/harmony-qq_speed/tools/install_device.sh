#!/bin/bash
# 真机部署一键脚本：安装 → 启动 → 日志验证
# 用法: bash tools/install_device.sh
set -e
HDC="${HDC:-/d/harmonyos-tools/sdk/windows/extracted/toolchains/toolchains/hdc.exe}"
HAP_DIR="$(cd "$(dirname "$0")/.." && pwd)/entry/build/default/outputs/default"
BUNDLE="com.riba2534.qqspeed3d"
ABILITY="EntryAbility"

echo "== device =="
"$HDC" list targets
echo "== install =="
# hdc 对绝对路径参数会与 cwd 拼接，必须 cd 到 HAP 目录用文件名
cd "$HAP_DIR"
"$HDC" install -r entry-default-signed.hap
echo "== launch =="
"$HDC" shell aa start -a "$ABILITY" -b "$BUNDLE"
sleep 3
echo "== process =="
"$HDC" shell "ps -ef | grep $BUNDLE | grep -v grep | head -1"
echo "== js errors =="
"$HDC" shell "hilog -z 300" | grep -iE "JSAPP.*(error|exception|fatal)" | head -5 || echo "(none)"
