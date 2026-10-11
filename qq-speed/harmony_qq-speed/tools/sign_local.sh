#!/bin/bash
# 本地生成调试证书链并对 HAP 签名（OpenHarmony 设备/模拟器可直装；
# HarmonyOS NEXT 手机需 AGC 签发的证书，本脚本产物会被拒绝）
# 用法: sign_local.sh <unsigned.hap> <bundleName> [outDir]
set -e

HAP="$1"
BUNDLE="${2:-com.riba2534.qqspeed3d}"
OUT="${3:-$(dirname "$0")/sign}"
SIGNTOOL="${SIGNTOOL:-/d/harmonyos-tools/sdk/windows/extracted/toolchains/toolchains/lib/hap-sign-tool.jar}"

KS_PWD="123456"
KS_APP="$OUT/app-keypair.p12"
KS_PROFILE="$OUT/profile-keypair.p12"
KS_ROOT="$OUT/root-keypair.p12"

SUBJ_ROOT="C=CN,O=LocalDebug,OU=LocalDebug Community,CN=Local Debug Root CA"
SUBJ_APP_CA="C=CN,O=LocalDebug,OU=LocalDebug Community,CN=Application Debug Signature Service CA"
SUBJ_APP="C=CN,O=LocalDebug,OU=LocalDebug Community,CN=$BUNDLE Debug"
SUBJ_PROFILE_CA="C=CN,O=LocalDebug,OU=LocalDebug Community,CN=Profile Debug Signature Service CA"
SUBJ_PROFILE="C=CN,O=LocalDebug,OU=LocalDebug Community,CN=Provision Profile Debug"

mkdir -p "$OUT"
S() { java -jar "$SIGNTOOL" "$@"; }

echo "== 1. root CA =="
[ -f "$OUT/root-ca.cer" ] || S generate-ca \
  -keyAlias "root-ca-key" -keyAlg ECC -keySize NIST-P-256 \
  -subject "$SUBJ_ROOT" -validity 3650 -signAlg SHA256withECDSA \
  -keystoreFile "$KS_ROOT" -keystorePwd "$KS_PWD" -outFile "$OUT/root-ca.cer"

echo "== 2. app sign sub-CA =="
[ -f "$OUT/app-sub-ca.cer" ] || S generate-ca \
  -keyAlias "app-sub-ca-key" -keyAlg ECC -keySize NIST-P-256 \
  -issuer "$SUBJ_ROOT" -issuerKeyAlias "root-ca-key" -issuerKeystoreFile "$KS_ROOT" -issuerKeystorePwd "$KS_PWD" \
  -subject "$SUBJ_APP_CA" -validity 1825 -signAlg SHA256withECDSA \
  -keystoreFile "$KS_APP" -keystorePwd "$KS_PWD" -outFile "$OUT/app-sub-ca.cer"

echo "== 3. profile sign sub-CA =="
[ -f "$OUT/profile-sub-ca.cer" ] || S generate-ca \
  -keyAlias "profile-sub-ca-key" -keyAlg ECC -keySize NIST-P-256 \
  -issuer "$SUBJ_ROOT" -issuerKeyAlias "root-ca-key" -issuerKeystoreFile "$KS_ROOT" -issuerKeystorePwd "$KS_PWD" \
  -subject "$SUBJ_PROFILE_CA" -validity 1825 -signAlg SHA256withECDSA \
  -keystoreFile "$KS_PROFILE" -keystorePwd "$KS_PWD" -outFile "$OUT/profile-sub-ca.cer"

echo "== 3.5. app/profile leaf keypairs =="
S generate-keypair -keyAlias "app-key" -keyAlg ECC -keySize NIST-P-256 \
  -keystoreFile "$KS_APP" -keystorePwd "$KS_PWD" || echo "app-key exists"
S generate-keypair -keyAlias "profile-key" -keyAlg ECC -keySize NIST-P-256 \
  -keystoreFile "$KS_PROFILE" -keystorePwd "$KS_PWD" || echo "profile-key exists"

echo "== 4. app debug cert (chain) =="
S generate-app-cert \
  -keyAlias "app-key" \
  -issuer "$SUBJ_APP_CA" -issuerKeyAlias "app-sub-ca-key" -issuerKeystoreFile "$KS_APP" -issuerKeystorePwd "$KS_PWD" \
  -subject "$SUBJ_APP" -validity 1095 -signAlg SHA256withECDSA \
  -rootCaCertFile "$OUT/root-ca.cer" -subCaCertFile "$OUT/app-sub-ca.cer" -outForm certChain \
  -keystoreFile "$KS_APP" -keystorePwd "$KS_PWD" -outFile "$OUT/app-debug-cert.cer"

echo "== 5. profile debug cert (chain) =="
S generate-profile-cert \
  -keyAlias "profile-key" \
  -issuer "$SUBJ_PROFILE_CA" -issuerKeyAlias "profile-sub-ca-key" -issuerKeystoreFile "$KS_PROFILE" -issuerKeystorePwd "$KS_PWD" \
  -subject "$SUBJ_PROFILE" -validity 1095 -signAlg SHA256withECDSA \
  -rootCaCertFile "$OUT/root-ca.cer" -subCaCertFile "$OUT/profile-sub-ca.cer" -outForm certChain \
  -keystoreFile "$KS_PROFILE" -keystorePwd "$KS_PWD" -outFile "$OUT/profile-debug-cert.cer"

echo "== 6. profile json =="
APP_CERT_PEM="$OUT/app-debug-cert.cer"
PROFILE_JSON="$OUT/profile-debug.json"
NOT_BEFORE=$(($(date +%s%3N) - 86400000))
EXPIRE=$(($(date +%s%3N) + 365 * 86400000))
python - "$PROFILE_JSON" "$BUNDLE" "$APP_CERT_PEM" "$NOT_BEFORE" "$EXPIRE" <<'PYEOF'
import json, sys, re
out, bundle, cert, nb, exp = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
pem = open(cert, 'r', errors='ignore').read()
m = re.search(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', pem, re.S)
pem = m.group(0) if m else pem
# 字段名 = hap-sign-tool Provision 模型的 Java 字段（Gson 默认映射，非 AGC 连字符格式）
doc = {
    "type": "debug",
    "appDistributionType": "app_gallery",
    "issuer": "LocalDebug",
    "validity": {"notBefore": nb, "notAfter": exp},
    "bundleInfo": {
        "developerId": "localdebug",
        "developmentCertificate": pem,
        "distributionCertificate": pem,
        "bundleName": bundle,
        "apl": "normal",
        "appFeature": "hos_normal_app",
    },
    "debuginfo": {"deviceIdType": "udid", "deviceIds": []},
    "acls": {"allowedAcls": []},
}
json.dump(doc, open(out, 'w'), indent=2)
print("profile json written:", out)
PYEOF

echo "== 7. sign profile =="
S sign-profile -mode localSign \
  -keyAlias "profile-key" -keystoreFile "$KS_PROFILE" -keystorePwd "$KS_PWD" \
  -profileCertFile "$OUT/profile-debug-cert.cer" \
  -inFile "$PROFILE_JSON" -signAlg SHA256withECDSA \
  -outFile "$OUT/debug-profiles.p7b"

echo "== 8. sign app =="
S sign-app -mode localSign \
  -keyAlias "app-key" -keystoreFile "$KS_APP" -keystorePwd "$KS_PWD" \
  -appCertFile "$OUT/app-debug-cert.cer" \
  -profileFile "$OUT/debug-profiles.p7b" \
  -inFile "$HAP" -signAlg SHA256withECDSA \
  -outFile "${HAP%.hap}-signed.hap" -compatibleVersion 12 -signCode "1"

echo "SIGNED: ${HAP%.hap}-signed.hap"
