#!/bin/bash
# 用工具链自带 OpenHarmony 官方签名材料对 HAP 签名
# （OpenHarmony 设备/模拟器可直装；HarmonyOS NEXT 商用手机需 AGC 证书）
# 用法: sign_official.sh <unsigned.hap> <bundleName>
# 关键点:
#  - Profile JSON 字段用官方模板的连字符格式（Provision 类带 @SerializedName）
#  - distribution-certificate 必须是 CA 签发的「OpenHarmony Application Release」叶子证书
#    （取自 UnsgnedDebugProfileTemplate.json 内嵌证书；keystore 里同名条目是同一密钥的自签版）
#  - appCertFile 链序: 叶子(CA签发) → Application CA → Root CA
#  - keystore 口令 123456，且 -keyPwd 必须显式传
set -e

HAP="$1"
BUNDLE="${2:-com.riba2534.qqspeed3d}"
OUT="${3:-$(dirname "$0")/sign}"
LIB="${OH_LIB:-/d/harmonyos-tools/sdk/windows/extracted/toolchains/toolchains/lib}"
SIGNTOOL="$LIB/hap-sign-tool.jar"
KS="$LIB/OpenHarmony.p12"
KS_PWD="123456"

mkdir -p "$OUT"
S() { java -jar "$SIGNTOOL" "$@"; }
LIBW=$(cygpath -m "$LIB" 2>/dev/null || echo "$LIB")

# 1. 应用签名链: 模板内嵌 CA 签发叶子 + ProfileRelease PEM 中的 CA 与 Root
python - "$OUT/tpl-app-cert.cer" "$LIBW/UnsgnedDebugProfileTemplate.json" <<'PYEOF'
import json, sys
out, tplpath = sys.argv[1], sys.argv[2]
doc = json.load(open(tplpath))
pem = doc['bundle-info']['development-certificate'].replace('\\n', '\n')
open(out, 'w').write(pem if pem.endswith('\n') else pem + '\n')
PYEOF
awk '/BEGIN CERT/{n++} {print > pfx "_" n ".pem"}' pfx="$OUT/ohpem" "$LIB/OpenHarmonyProfileRelease.pem"
cat "$OUT/tpl-app-cert.cer" "$OUT/ohpem_2.pem" "$OUT/ohpem_1.pem" > "$OUT/oh-app-chain.cer"
rm -f "$OUT"/ohpem_*.pem

# 2. Profile JSON（官方模板格式，release 类型免设备 UDID 绑定）
python - "$OUT/oh-profile-release.json" "$BUNDLE" "$OUT/tpl-app-cert.cer" <<'PYEOF'
import json, sys
out, bundle, cert = sys.argv[1], sys.argv[2], sys.argv[3]
pem = open(cert).read()
doc = {
    "version-name": "1.0.0",
    "version-code": 1,
    "uuid": "fe686e1b-3770-4824-a938-961b140a7c98",
    "validity": {"not-before": 1610519532, "not-after": 1956579132},  # 2021 → 2031
    "type": "release",
    "bundle-info": {
        "developer-id": "OpenHarmony",
        "distribution-certificate": pem,
        "bundle-name": bundle,
        "apl": "normal",
        "app-feature": "hos_normal_app",
    },
    "acls": {"allowed-acls": [""]},
    "permissions": {"restricted-permissions": [""]},
    "issuer": "pki_internal",
}
json.dump(doc, open(out, 'w'), indent=2)
print("profile written:", out)
PYEOF

# 3. 签 Profile → p7b
S sign-profile -mode localSign \
  -keyAlias "openharmony application profile release" -keyPwd "$KS_PWD" -keystoreFile "$KS" -keystorePwd "$KS_PWD" \
  -profileCertFile "$LIB/OpenHarmonyProfileRelease.pem" \
  -inFile "$OUT/oh-profile-release.json" -signAlg SHA256withECDSA \
  -outFile "$OUT/oh-profile-release.p7b"

# 4. 签 HAP
S sign-app -mode localSign \
  -keyAlias "openharmony application release" -keyPwd "$KS_PWD" -keystoreFile "$KS" -keystorePwd "$KS_PWD" \
  -appCertFile "$OUT/oh-app-chain.cer" \
  -profileFile "$OUT/oh-profile-release.p7b" \
  -inFile "$HAP" -signAlg SHA256withECDSA \
  -outFile "${HAP%.hap}-signed.hap" -compatibleVersion 12 -signCode "1"

# 5. 自校验
S verify-app -inFile "${HAP%.hap}-signed.hap" -outCertChain "$OUT/verify-chain.cer" -outProfile "$OUT/verify-profile.p7b"
echo "SIGNED: ${HAP%.hap}-signed.hap"
