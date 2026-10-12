# PelicanBike debug 签名说明

目标 bundleName：`com.riba2534.pelicanbike`。

## 结论

本工程目标是 **HarmonyOS API 24**，运行目标是 DevEco 的 **Pura90 HarmonyOS 6.1.1(24)** 模拟器。默认且推荐的可安装 debug 签名路径是：

> 使用 DevEco Studio 为这个工程、这个 bundleName 执行一次自动签名，让 IDE/华为账号服务生成项目专属的 debug profile、证书和密钥配置。

不要复用相邻应用的 `.p7b`、`.cer`、`.p12` 或整段 `signingConfigs`。Provision Profile 内绑定 bundleName、开发证书和设备信息；复制其他应用 profile 不等价于“共用 debug 证书”。

DevEco 随 SDK 提供的 `hap-sign-tool.jar` 确实支持完整、非交互的 OpenHarmony 本地签名链，但这是另一套信任体系。OpenHarmony 本地自签 HAP **不保证能被当前 Pura90 HarmonyOS 模拟器接受**。因此：

- `tools/device/device.ps1 build -PackageMode unsigned` 始终可用于无签名构建；
- `build -PackageMode signed` 只消费并严格校验工程已有的项目专属签名；
- 脚本不会把 OpenHarmony 本地自签材料自动接入 HarmonyOS 工程；
- 若需要在 OpenHarmony 设备/镜像上研究本地自签，按本文后半部分在隔离目录手工执行，并先验证设备信任链。

## 本机相邻工程的签名模式

只读调查显示两种常见模式：

1. DevEco 自动签名把项目专属材料放到：

   ```text
   C:\Users\vyron\.ohos\config\default_<project>_<unique-id>.cer
   C:\Users\vyron\.ohos\config\default_<project>_<unique-id>.csr
   C:\Users\vyron\.ohos\config\default_<project>_<unique-id>.p12
   C:\Users\vyron\.ohos\config\default_<project>_<unique-id>.p7b
   ```

   工程 `build-profile.json5` 的 `signingConfigs[].material` 引用这些文件。每个工程/配置的 unique-id 不同。

2. 少数工程把手工签名材料放在工程自己的 `sign/debug` 下，再由相对路径引用。

无论是哪种模式，当前工程都应生成自己的 profile。调查相邻工程仅用于理解配置结构，不能把其 profile 复制到 PelicanBike。

## HarmonyOS 推荐路径：DevEco 自动签名一次

截至当前本机安装的 DevEco Studio 6.1.1，没有找到一个足够可靠、已文档化、可无交互替代 IDE/账号服务并签发 **HarmonyOS 官方 debug profile** 的 CLI。SDK 中的 `hap-sign-tool.jar` 是 OpenHarmony 本地签名工具，不等价于华为账号/官方 profile 服务。

因此首次配置按以下步骤执行：

1. 使用 DevEco Studio 打开：

   ```text
   D:\workspace\My\harmony\harmony-PelicanBike
   ```

2. 确认工程 `AppScope/app.json5` 中：

   ```json5
   bundleName: "com.riba2534.pelicanbike"
   ```

3. 在 DevEco 的项目签名配置页选择 debug/default 产品，启用 **Automatically generate signature / 自动生成签名**。

4. 登录拥有调试签名权限的华为开发者账号；根据 IDE 提示选择/注册调试设备。Pura90 模拟器的 UDID 是否需进入 profile 由当前 DevEco/账号流程决定。

5. 让 IDE 完成一次 Sync/Build/Run。预期结果是 DevEco 为当前工程写入项目专属 `signingConfigs`，并在用户 `.ohos\config` 下生成一组新的 `.cer/.csr/.p12/.p7b`。

6. 不要手工把其他工程 `build-profile.json5` 的密码密文或材料路径粘贴过来。

7. 回到命令行验证：

   ```powershell
   .\tools\device\device.ps1 signing-check
   .\tools\device\device.ps1 build -PackageMode signed
   ```

   或：

   ```bash
   ./tools/device/device.sh signing-check
   ./tools/device/device.sh build -PackageMode signed
   ```

### signing-check 校验内容

脚本会使用 DevEco 自带 Java 和：

```text
C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar
```

执行 `verify-profile`，并检查：

1. profile 签名可验证；
2. `content.bundle-info.bundle-name == com.riba2534.pelicanbike`；
3. 当前 Unix 时间位于 `validity.not-before` 和 `validity.not-after` 之间；
4. `content.bundle-info.development-certificate` 存在；
5. `certpath` 中至少一张证书与上述 development-certificate 完全一致；
6. `.p7b`、`.cer`、`.p12` 均存在。

这能拦截最危险的错误：使用了别的应用 profile，或 profile 和 app certificate 不属于同一套材料。

### 为什么不能只改 bundle-name

`.p7b` 是签名后的 Provision Profile。直接编辑文件会破坏签名；复制别的 `.p7b` 再仅改工程 bundleName，则 Hvigor 的 bundle 校验或设备安装校验会失败。正确做法是重新签发 profile。

## unsigned 构建

未配置签名时：

```powershell
.\tools\device\device.ps1 build -PackageMode unsigned
```

```bash
./tools/device/device.sh build -PackageMode unsigned
```

脚本使用 Hvigor 的临时命令行配置：

```text
-c properties.enableSignTask=false
```

该开关仅对本次进程生效，不修改根配置。产物通常为：

```text
entry\build\default\outputs\default\entry-default-unsigned.hap
```

unsigned HAP 可用于确认 ArkTS/C++/资源/打包链路，但通常不能直接安装到 Pura90 HarmonyOS 模拟器。

## OpenHarmony 本地自签：能力与边界

### 工具能力

本机 SDK 的 `hap-sign-tool.jar -h` 明确支持：

- `generate-keypair`
- `generate-csr`
- `generate-cert`
- `generate-ca`
- `generate-app-cert`
- `generate-profile-cert`
- `sign-profile`
- `verify-profile`
- `sign-app`
- `verify-app`

每个生成/签名命令都支持 `-pwdInputMode 0`，因此技术上可以完成全链非交互 CLI。

SDK 还包含：

```text
C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\lib\UnsgnedDebugProfileTemplate.json
```

注意文件名确实拼写为 `Unsgned`。

### 信任边界

这套流程可以创建你自己的：

- 根 CA；
- 应用签名中间 CA；
- Profile 签名中间 CA；
- 应用实体密钥和证书链；
- Profile 实体密钥和证书链；
- debug profile `.p7b`；
- signed HAP。

但是设备必须信任该 CA/profile 签发体系。标准 HarmonyOS Pura90 模拟器通常要求 HarmonyOS 官方签发/认可的 profile；一个任意本地根 CA 生成的 OpenHarmony HAP 可能被安装服务拒绝。不要把“工具能生成”误认为“目标 HarmonyOS 模拟器必然信任”。

### 安全建议

若要实验本地自签：

- 使用工程外、访问受限的隔离目录存放私钥；
- 不提交 `.p12`、密码、私钥或自建 CA 到仓库；
- 不使用相邻应用的 profile；
- 使用新随机密码；
- 给每个 bundle 生成独立应用实体密钥/profile；
- 仅在明确允许自定义信任根的 OpenHarmony 设备/镜像上使用。

下述命令是研究模板，不由默认脚本执行。

## OpenHarmony 本地 debug 全链示例

以下 PowerShell 变量仅为命令示意。请在工程外创建隔离工作目录，并替换强密码：

```powershell
$Java = "C:\Program Files\Huawei\DevEco Studio\jbr\bin\java.exe"
$Tool = "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar"
$Template = "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\lib\UnsgnedDebugProfileTemplate.json"
$Work = "D:\private-signing\pelicanbike-debug"
$Store = Join-Path $Work "pelicanbike-debug.p12"
$StorePassword = "REPLACE_WITH_RANDOM_STORE_PASSWORD"
$KeyPassword = "REPLACE_WITH_RANDOM_KEY_PASSWORD"
New-Item -ItemType Directory -Path $Work -Force | Out-Null
Set-Location -LiteralPath $Work
```

为减少别名混淆，示例把所有密钥存放在一个 PKCS#12 keystore 中，但每个角色使用独立 alias：

- `pelican-root-ca`
- `pelican-app-ca`
- `pelican-profile-ca`
- `pelican-app-debug`
- `pelican-profile-debug`

### 1. 根 CA

```powershell
& $Java -jar $Tool generate-ca `
  -keyAlias pelican-root-ca `
  -keyPwd $KeyPassword `
  -keyAlg ECC `
  -keySize NIST-P-256 `
  -subject "C=CN,O=PelicanBike,OU=Local Development,CN=PelicanBike Root CA" `
  -validity 3650 `
  -signAlg SHA256withECDSA `
  -basicConstraintsPathLen 2 `
  -keystoreFile $Store `
  -keystorePwd $StorePassword `
  -outFile (Join-Path $Work "root-ca.cer") `
  -pwdInputMode 0
```

### 2. 应用签名中间 CA

```powershell
& $Java -jar $Tool generate-ca `
  -keyAlias pelican-app-ca `
  -keyPwd $KeyPassword `
  -keyAlg ECC `
  -keySize NIST-P-256 `
  -issuer "C=CN,O=PelicanBike,OU=Local Development,CN=PelicanBike Root CA" `
  -issuerKeyAlias pelican-root-ca `
  -issuerKeyPwd $KeyPassword `
  -subject "C=CN,O=PelicanBike,OU=Local Development,CN=Application Debug Signature Service CA" `
  -validity 1825 `
  -signAlg SHA256withECDSA `
  -basicConstraintsPathLen 0 `
  -keystoreFile $Store `
  -keystorePwd $StorePassword `
  -issuerKeystoreFile $Store `
  -issuerKeystorePwd $StorePassword `
  -outFile (Join-Path $Work "app-ca.cer") `
  -pwdInputMode 0
```

### 3. Profile 签名中间 CA

```powershell
& $Java -jar $Tool generate-ca `
  -keyAlias pelican-profile-ca `
  -keyPwd $KeyPassword `
  -keyAlg ECC `
  -keySize NIST-P-256 `
  -issuer "C=CN,O=PelicanBike,OU=Local Development,CN=PelicanBike Root CA" `
  -issuerKeyAlias pelican-root-ca `
  -issuerKeyPwd $KeyPassword `
  -subject "C=CN,O=PelicanBike,OU=Local Development,CN=Provision Profile Debug Signature Service CA" `
  -validity 1825 `
  -signAlg SHA256withECDSA `
  -basicConstraintsPathLen 0 `
  -keystoreFile $Store `
  -keystorePwd $StorePassword `
  -issuerKeystoreFile $Store `
  -issuerKeystorePwd $StorePassword `
  -outFile (Join-Path $Work "profile-ca.cer") `
  -pwdInputMode 0
```

### 4. 应用实体密钥

```powershell
& $Java -jar $Tool generate-keypair `
  -keyAlias pelican-app-debug `
  -keyPwd $KeyPassword `
  -keyAlg ECC `
  -keySize NIST-P-256 `
  -keystoreFile $Store `
  -keystorePwd $StorePassword `
  -pwdInputMode 0
```

### 5. 应用 debug 证书链

```powershell
& $Java -jar $Tool generate-app-cert `
  -keyAlias pelican-app-debug `
  -keyPwd $KeyPassword `
  -issuer "C=CN,O=PelicanBike,OU=Local Development,CN=Application Debug Signature Service CA" `
  -issuerKeyAlias pelican-app-ca `
  -issuerKeyPwd $KeyPassword `
  -subject "C=CN,O=PelicanBike,OU=Application,CN=PelicanBike Debug" `
  -validity 365 `
  -signAlg SHA256withECDSA `
  -issuerKeystoreFile $Store `
  -issuerKeystorePwd $StorePassword `
  -keystoreFile $Store `
  -keystorePwd $StorePassword `
  -outForm certChain `
  -rootCaCertFile (Join-Path $Work "root-ca.cer") `
  -subCaCertFile (Join-Path $Work "app-ca.cer") `
  -outFile (Join-Path $Work "app-debug-cert-chain.cer") `
  -pwdInputMode 0
```

证书 subject 字段顺序保持 `C, O, OU, CN`。

### 6. Profile 实体密钥

```powershell
& $Java -jar $Tool generate-keypair `
  -keyAlias pelican-profile-debug `
  -keyPwd $KeyPassword `
  -keyAlg ECC `
  -keySize NIST-P-256 `
  -keystoreFile $Store `
  -keystorePwd $StorePassword `
  -pwdInputMode 0
```

### 7. Profile debug 证书链

```powershell
& $Java -jar $Tool generate-profile-cert `
  -keyAlias pelican-profile-debug `
  -keyPwd $KeyPassword `
  -issuer "C=CN,O=PelicanBike,OU=Local Development,CN=Provision Profile Debug Signature Service CA" `
  -issuerKeyAlias pelican-profile-ca `
  -issuerKeyPwd $KeyPassword `
  -subject "C=CN,O=PelicanBike,OU=Profile,CN=PelicanBike Debug Profile" `
  -validity 365 `
  -signAlg SHA256withECDSA `
  -issuerKeystoreFile $Store `
  -issuerKeystorePwd $StorePassword `
  -keystoreFile $Store `
  -keystorePwd $StorePassword `
  -outForm certChain `
  -rootCaCertFile (Join-Path $Work "root-ca.cer") `
  -subCaCertFile (Join-Path $Work "profile-ca.cer") `
  -outFile (Join-Path $Work "profile-debug-cert-chain.cer") `
  -pwdInputMode 0
```

### 8. 生成 debug profile JSON

先复制模板：

```powershell
Copy-Item -LiteralPath $Template -Destination (Join-Path $Work "pelicanbike-debug-profile.json")
```

然后必须修改 JSON。至少满足：

```text
type = debug
bundle-info.bundle-name = com.riba2534.pelicanbike
bundle-info.development-certificate = 应用实体证书 PEM
validity.not-before <= 当前 Unix 时间 < validity.not-after
debug-info.device-ids 包含目标 OpenHarmony 设备 UDID
```

目标设备 UDID 可通过下列命令查询：

```text
hdc shell bm get --udid
```

关键点：

- `development-certificate` 是第 5 步生成的 **应用实体证书**，不是 Profile 证书、不是中间 CA、也不是其他应用证书；
- 若 `app-debug-cert-chain.cer` 含多张 PEM，只取实体证书（证书链第一张）写入 JSON；
- `bundle-name` 必须与 HAP 内 `com.riba2534.pelicanbike` 完全一致；
- profile 的有效期必须覆盖当前时间，且不要超出相关实体证书/CA 的有效期；
- debug profile 必须列出允许安装的设备 UDID；
- 不要继续使用 SDK 模板里的 `com.OpenHarmony.app.test`、过期时间或样例证书。

### 9. 签名 profile

```powershell
& $Java -jar $Tool sign-profile `
  -mode localSign `
  -keyAlias pelican-profile-debug `
  -keyPwd $KeyPassword `
  -profileCertFile (Join-Path $Work "profile-debug-cert-chain.cer") `
  -inFile (Join-Path $Work "pelicanbike-debug-profile.json") `
  -signAlg SHA256withECDSA `
  -keystoreFile $Store `
  -keystorePwd $StorePassword `
  -outFile (Join-Path $Work "pelicanbike-debug-profile.p7b") `
  -pwdInputMode 0
```

立即验证：

```powershell
& $Java -jar $Tool verify-profile `
  -inFile (Join-Path $Work "pelicanbike-debug-profile.p7b")
```

检查输出中的：

- `verifiedPassed: true`
- `bundle-info.bundle-name`
- `validity`
- `development-certificate`
- `debug-info.device-ids`

### 10. 签名 unsigned HAP

先用设备脚本构建 unsigned HAP：

```powershell
& "D:\workspace\My\harmony\harmony-PelicanBike\tools\device\device.ps1" build -PackageMode unsigned
```

然后：

```powershell
$UnsignedHap = "D:\workspace\My\harmony\harmony-PelicanBike\entry\build\default\outputs\default\entry-default-unsigned.hap"
$SignedHap = Join-Path $Work "entry-default-local-openharmony-signed.hap"

& $Java -jar $Tool sign-app `
  -mode localSign `
  -keyAlias pelican-app-debug `
  -keyPwd $KeyPassword `
  -appCertFile (Join-Path $Work "app-debug-cert-chain.cer") `
  -profileFile (Join-Path $Work "pelicanbike-debug-profile.p7b") `
  -profileSigned 1 `
  -inForm zip `
  -inFile $UnsignedHap `
  -signAlg SHA256withECDSA `
  -keystoreFile $Store `
  -keystorePwd $StorePassword `
  -outFile $SignedHap `
  -compatibleVersion 24 `
  -signCode 1 `
  -pwdInputMode 0
```

最后验证应用签名：

```powershell
& $Java -jar $Tool verify-app `
  -inFile $SignedHap `
  -outCertChain (Join-Path $Work "verified-app-chain.cer") `
  -outProfile (Join-Path $Work "verified-profile.p7b")
```

再次运行 `verify-profile` 检查导出的 profile。

### 11. 安装前的判定

只有在目标设备明确接受这套本地 CA/profile 时才尝试安装。对当前 Pura90 HarmonyOS 模拟器，优先使用 DevEco 自动签名；若本地自签安装失败，不要通过替换其他应用 profile、关闭校验或自动卸载旧应用来绕过。

## 密码与凭据

DevEco 自动生成的 `build-profile.json5` 可能包含 DevEco 加密格式的 `storePassword` 和 `keyPassword`。这些值仍属于签名配置，不能复制到文档、issue、日志或其他应用。

本文档示例中的密码是占位符，绝不能原样使用。脚本也不会读取相邻工程密码或将其写入 PelicanBike。
