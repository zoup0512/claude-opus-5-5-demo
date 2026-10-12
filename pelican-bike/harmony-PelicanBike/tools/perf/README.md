# Pelican Bike 性能工具

本目录可独立运行，不依赖修改 Harmony 工程根配置或 `entry`。主引擎接入 `PEL_PERF` 日志后，可采集真机 hilog、运行稳定性场景并生成 JSON/Markdown 报告；HAP 或设备暂缺时，可用合成样例自检解析器。

## 快速自检（不需要设备）

```powershell
pwsh -File .\run_perf.ps1 -Mode self-test
```

或：

```powershell
node .\generate_sample.mjs
node .\parse_perf.mjs --self-test
node .\parse_perf.mjs --input .\sample_hilog.txt `
  --output-json .\out\self-test\report.json `
  --output-md .\out\self-test\report.md `
  --quality high --scenario soak10m --source sample --strict
```

样例报告始终写明 `synthetic: true`，不能当作设备结果。

## 真机采样

只采日志与 `hidumper` 伴随数据：

```powershell
pwsh -File .\run_perf.ps1 -Mode collect `
  -Bundle com.example.pelicanbike `
  -Ability EntryAbility `
  -Module entry `
  -DurationSec 600 `
  -Quality high `
  -RequireDevice
```

安装 HAP 后运行一个场景：

```powershell
pwsh -File .\run_perf.ps1 -Mode scenario -Scenario soak10m `
  -Hap D:\path\to\entry-default-signed.hap -Install `
  -Bundle com.example.pelicanbike -Ability EntryAbility -Module entry `
  -Quality high -ClearHilog -Strict -RequireDevice
```

运行整套（约束取决于 `scenarios.json`）：

```powershell
pwsh -File .\run_perf.ps1 -Mode suite `
  -Bundle com.example.pelicanbike -Ability EntryAbility -Module entry `
  -Quality high -Strict -RequireDevice
```

Git Bash/Linux 主机只采集 hilog：

```bash
BUNDLE=com.example.pelicanbike DURATION_SEC=600 ./collect_hilog.sh
```

## 文件

- `perf_config.json`：四档画质、显存估算与 pass/fail 阈值。
- `scenarios.json`：七个稳定性场景及引擎启动参数契约。
- `parse_perf.mjs`：解析 `PEL_PERF`，输出 JSON/Markdown 并执行阈值判断。
- `run_perf.ps1`：HDC/hilog/hidumper、Ability 启停、HOME 循环、截图与场景编排。
- `collect_hilog.sh`：跨平台基础采集脚本。
- `generate_sample.mjs`、`sample_hilog.txt`：不宣称设备结果的合成自检数据。

完整口径、协议与接入要求见 `../../docs/performance/README.md`。
