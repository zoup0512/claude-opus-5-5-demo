# PelicanBike HarmonyOS 设备工作流

本目录说明 `tools/device` 下的本机开发脚本。脚本面向当前工程：

- 工程根：`D:\workspace\My\harmony\harmony-PelicanBike`
- bundleName：`com.riba2534.pelicanbike`
- Ability：`EntryAbility`
- 默认模块/产品/目标：`entry` / `default` / `default`
- 默认模拟器实例：`Pura90`
- 目标 API：HarmonyOS API 24

签名原理和项目专属 debug 签名步骤见 [signing.md](./signing.md)。

## 设计约束

- `device.ps1` 从脚本自身位置向上两级解析工程根，并在执行任何 OHPM/Hvigor 工程命令前切换到该目录，不继承调用者当前目录。
- DevEco Node、OHPM、Hvigor、HDC、Emulator 和 Java 均通过绝对路径或 DevEco 安装目录自动探测。
- OHPM/Hvigor 明确使用 DevEco 自带 Node 18；仅修改脚本子进程的环境变量，不修改系统或用户 PATH。
- 不修改 `build-profile.json5`、`AppScope`、`entry` 或其他工程文件。
- 不调用 `hdc uninstall`、模拟器 `-delete`、`reset` 或其他清除应用/模拟器用户数据的命令。
- 安装使用 `hdc install -r`。若遇到签名不一致，脚本停止并要求人工处理，不会通过卸载来“修复”。
- `smoke` 只有在构建成功且确认存在 signed HAP 后才可能启动模拟器；没有 HAP 或只有 unsigned HAP 时不会启动。

## 本机探测结果（2026-10-04）

| 组件 | 探测结果 |
| --- | --- |
| DevEco Studio | `6.1.1.300`，build `243.24978.46.36.611300` |
| DevEco 安装目录 | `C:\Program Files\Huawei\DevEco Studio` |
| DevEco Node | `18.20.1` |
| OHPM | `6.1.2.285` |
| Hvigor | `6.24.4` |
| HDC | `3.2.0d` |
| Emulator.exe | `6.1.1.350` |
| HarmonyOS SDK | `HarmonyOS 6.1.1`，API `24`，SDK version `6.1.1.125` |
| 默认 Pura90 | `Pura90`，`HarmonyOS 6.1.1(24)`，software `6.1.0.126` |
| Pura90 实例目录 | `C:\Users\vyron\AppData\Local\Huawei\Emulator\deployed\Pura90` |

本机另有名为 `Pura 90` 的 API 24 Beta1 实例。脚本默认使用无空格的正式镜像实例 `Pura90`，避免误启 Beta1。

## 入口

### PowerShell

从任意目录均可调用：

```powershell
& "D:\workspace\My\harmony\harmony-PelicanBike\tools\device\device.ps1" doctor
```

在工程根内可简写：

```powershell
.\tools\device\device.ps1 doctor
```

如执行策略阻止本地脚本：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\device\device.ps1 doctor
```

### Git Bash

```bash
./tools/device/device.sh doctor
```

`device.sh` 只负责找到 Windows PowerShell、把脚本路径转换为 Windows 路径，并原样转发参数。它不会改系统 PATH。PowerShell 风格参数在 Git Bash 中也照常使用，例如：

```bash
./tools/device/device.sh build -PackageMode unsigned
```

## 命令

### 1. doctor

验证以下内容：

- DevEco Studio 6.1.1
- DevEco Node 18
- OHPM、Hvigor、HDC、Emulator.exe、DevEco JBR 与签名工具
- HarmonyOS SDK API 24
- `Pura90` 实例及其 API
- 当前 HDC 连接
- 目标工程根文件、bundleName 与 API
- 项目签名 profile 的 bundle-name、有效期和 development-certificate 一致性
- signed/unsigned HAP 是否已存在

```powershell
.\tools\device\device.ps1 doctor
```

```bash
./tools/device/device.sh doctor
```

`doctor` 不启动模拟器。没有连接设备、没有签名、没有 HAP 均作为警告；工具链或工程关键配置错误才会返回失败。

本次最终验证为 `0 failure(s)`。警告数量取决于实时状态；当前工程尚未配置项目专属签名，且目前只有 unsigned HAP，因此会报告对应警告。若模拟器未运行，还会额外报告没有 HDC target。

### 2. sync

在工程根依次执行：

1. DevEco Node + OHPM `install --all`；
2. DevEco Node + Hvigor `--sync`。

```powershell
.\tools\device\device.ps1 sync
```

```bash
./tools/device/device.sh sync
```

如果工程根尚未生成 `build-profile.json5`、`oh-package.json5`、`hvigorfile.ts`，脚本会给出明确错误，不会在错误目录创建项目缓存。

### 3. build

默认执行 `assembleHap`，并使用：

- `--mode module`
- `module=entry@default`
- `product=default`
- `buildMode=debug`
- `--no-daemon`

默认先执行 `sync`；确认依赖已同步后可加 `-SkipSync`。

#### auto（默认）

```powershell
.\tools\device\device.ps1 build
```

```bash
./tools/device/device.sh build
```

- 项目签名配置完整且校验通过：构建 signed HAP；
- 没有可靠签名：自动降级为 unsigned HAP，并明确提示原因。

#### 强制 unsigned

```powershell
.\tools\device\device.ps1 build -PackageMode unsigned
```

```bash
./tools/device/device.sh build -PackageMode unsigned
```

unsigned 模式通过 Hvigor 命令行覆盖：

```text
-c properties.enableSignTask=false
```

不会修改工程 `hvigor-config.json5` 或 `build-profile.json5`。

#### 强制 signed

```powershell
.\tools\device\device.ps1 build -PackageMode signed
```

```bash
./tools/device/device.sh build -PackageMode signed
```

signed 模式在构建前执行严格检查：

- 产品引用了已定义的 `signingConfig`；
- `.p7b`、`.cer`、`.p12` 均存在；
- `.p7b` 能通过 `hap-sign-tool.jar verify-profile`；
- profile 的 `bundle-info.bundle-name` 必须恰为 `com.riba2534.pelicanbike`；
- profile 当前处于有效期内；
- profile 内 `development-certificate` 与 `certpath` 中的证书一致。

任一条件不满足都会在 Hvigor 前失败。该行为用于防止误用相邻工程的 profile。

常见输出位置为：

```text
entry\build\default\outputs\default\entry-default-unsigned.hap
entry\build\default\outputs\default\entry-default-signed.hap
```

### 4. emulator-start / emulator-wait / emulator-stop

启动默认实例：

```powershell
.\tools\device\device.ps1 emulator-start
.\tools\device\device.ps1 emulator-wait -TimeoutSec 240
```

```bash
./tools/device/device.sh emulator-start
./tools/device/device.sh emulator-wait -TimeoutSec 240
```

启动使用 `-bootmode coldboot`，会保留数据分区；不会使用 `reset`。

停止：

```powershell
.\tools\device\device.ps1 emulator-stop
```

```bash
./tools/device/device.sh emulator-stop
```

如果连接了多个 HDC target，脚本不会猜测哪个属于 `Pura90`，必须明确指定：

```powershell
.\tools\device\device.ps1 emulator-wait -Serial 127.0.0.1:5555
```

### 5. install

安装由本工具最近一次成功的 signed build 记录下来的 HAP：

```powershell
.\tools\device\device.ps1 install
```

```bash
./tools/device/device.sh install
```

指定 HAP：

```powershell
.\tools\device\device.ps1 install -HapPath "D:\path with spaces\entry-default-signed.hap"
```

Git Bash 路径也可传入：

```bash
./tools/device/device.sh install -HapPath /d/path/to/entry-default-signed.hap
```

脚本拒绝已知的 `*-unsigned.hap`。自动选择 HAP 时还要求当前项目签名通过 `signing-check`，并要求存在 `tools/device/last-signed-hap.txt`（由本工具成功完成 signed build 后写入）。这样不会把目录中历史遗留、仅名称为 `*-signed.hap` 的未知产物误当成可信包。也可用 `-HapPath` 明确指定你已独立验证的 signed HAP；显式路径仍拒绝 `*-unsigned.hap`。

### 6. launch

```powershell
.\tools\device\device.ps1 launch
```

```bash
./tools/device/device.sh launch
```

实际命令等价于：

```text
hdc shell aa start -b com.riba2534.pelicanbike -a EntryAbility
```

若模拟器锁屏，HarmonyOS 可能拒绝拉起 Ability；先在模拟器 GUI 中解锁后重试。

### 7. hilog

默认过滤 bundle、应用名和 Ability：

```powershell
.\tools\device\device.ps1 hilog
```

```bash
./tools/device/device.sh hilog
```

自定义正则：

```powershell
.\tools\device\device.ps1 hilog -Filter "PelicanBike|RNOH|fatal|crash"
```

不做过滤：

```powershell
.\tools\device\device.ps1 hilog -Filter ""
```

按 `Ctrl+C` 结束流式日志。

### 8. screenshot

默认输出到 `tools/device/artifacts`：

```powershell
.\tools\device\device.ps1 screenshot
```

```bash
./tools/device/device.sh screenshot
```

指定输出路径：

```powershell
.\tools\device\device.ps1 screenshot `
  -OutputPath .\tools\device\artifacts\home.jpeg
```

流程是：

1. 在设备 `/data/local/tmp` 创建带时间戳的临时 JPEG（API 24 Pura90 的 `snapshot_display` 要求 `.jpeg` 后缀）；
2. `hdc file recv` 拉取；
3. 仅删除本次创建、且文件名严格匹配的单个远端临时文件。

不会删除目录或使用通配符。

### 9. signing-check

```powershell
.\tools\device\device.ps1 signing-check
```

```bash
./tools/device/device.sh signing-check
```

该命令仅验证工程当前签名配置，不生成、复制或修改签名文件。

### 10. smoke

```powershell
.\tools\device\device.ps1 smoke -PackageMode signed
```

```bash
./tools/device/device.sh smoke -PackageMode signed
```

串联步骤：

1. sync（除非 `-SkipSync`）；
2. `assembleHap`；
3. 确认 signed HAP 真实存在；
4. 无 HDC target 时才启动 `Pura90`；
5. 等待 HDC；
6. `hdc install -r`；
7. 启动 `com.riba2534.pelicanbike/EntryAbility`；
8. 用 `pidof`，必要时回退到 `ps -ef`，检查进程；
9. 获取一次 `hilog -x` 快照并按 `-Filter` 过滤；
10. 检查 fatal/crash/abort/uncaught/exception 指示。

以下情况都会在启动模拟器之前停止：

- 工程不完整；
- 构建失败；
- HAP 不存在；
- 只有 unsigned HAP；
- 项目签名校验不通过。

## 自定义构建参数

```powershell
.\tools\device\device.ps1 build `
  -Product default `
  -Module entry `
  -Target default `
  -BuildMode debug `
  -PackageMode unsigned
```

这些参数只影响本次命令，不写入工程配置。

## 常见问题

### “HarmonyOS project is not generated yet”

确认工程根包含：

- `build-profile.json5`
- `oh-package.json5`
- `hvigorfile.ts`

脚本不会代替项目生成器创建这些文件。

### signed build 提示 profile bundle-name 不匹配

不要复制或改写相邻应用的 `.p7b`。在 DevEco Studio 中为当前工程和 `com.riba2534.pelicanbike` 重新执行一次自动签名，步骤见 [signing.md](./signing.md)。

### 安装提示签名不一致

设备上旧版本可能使用了另一签名。脚本不会自动卸载，因为卸载可能删除用户数据。先决定是否需要备份/保留数据，再人工处理旧安装。

### 多个设备连接

所有设备命令在多 target 时拒绝猜测。使用：

```powershell
.\tools\device\device.ps1 install -Serial <target>
```

### 路径中有空格

PowerShell 使用参数数组调用外部程序；Git Bash 包装器通过 `cygpath` 转换脚本路径。带空格的 DevEco 安装目录和 HAP 路径均无需手工转义为 8.3 路径。
