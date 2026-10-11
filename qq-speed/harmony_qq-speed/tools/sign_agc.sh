#!/bin/bash
# 用 AGC（AppGallery Connect）签发的调试证书对 HAP 签名 —— HarmonyOS NEXT 手机必需
# 前置: tools/sign/agc/ 下已有
#   app-debug.p12  本地生成的应用调试密钥（口令 123456, alias: app-debug-key）
#   app-debug.csr  上传给 AGC 换取 .cer 的请求文件
#   debug.cer      AGC 签发的调试证书（含链）
#   debug.p7b      AGC 签发的调试 Profile（已绑定设备 UDID）
# 用法: bash tools/sign_agc.sh
set -e
cd "$(dirname "$0")/sign/agc"
[ -f debug.cer ] || { echo "缺少 debug.cer（从 AGC 下载后放到 tools/sign/agc/）"; exit 1; }
[ -f debug.p7b ] || { echo "缺少 debug.p7b（从 AGC 下载后放到 tools/sign/agc/）"; exit 1; }

SIGNTOOL="${SIGNTOOL:-/d/harmonyos-tools/sdk/windows/extracted/toolchains/toolchains/lib/hap-sign-tool.jar}"
HAP="../../entry/build/default/outputs/default/entry-default-unsigned.hap"

java -jar "$SIGNTOOL" sign-app -mode localSign \
  -keyAlias "app-debug-key" -keyPwd 123456 \
  -keystoreFile app-debug.p12 -keystorePwd 123456 \
  -appCertFile debug.cer \
  -profileFile debug.p7b \
  -inFile "$HAP" -signAlg SHA256withECDSA \
  -outFile ../../entry/build/default/outputs/default/entry-default-signed.hap \
  -compatibleVersion 12 -signCode "1"

java -jar "$SIGNTOOL" verify-app -inFile ../../entry/build/default/outputs/default/entry-default-signed.hap \
  -outCertChain verify-chain.cer -outProfile verify-profile.p7b
echo "SIGNED (AGC): entry/build/default/outputs/default/entry-default-signed.hap"
