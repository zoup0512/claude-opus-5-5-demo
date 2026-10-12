[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('collect', 'scenario', 'suite', 'self-test')]
    [string]$Mode,

    [ValidateSet('soak10m', 'dayNight24h', 'chunkBoundaries', 'cameraSwitch', 'background100', 'surfaceResizeRotate', 'screenshots20')]
    [string]$Scenario = 'soak10m',

    [string]$Bundle,
    [string]$Ability,
    [string]$Module = 'entry',
    [string]$Hap,
    [string]$Serial,
    [string]$Hdc = 'hdc',
    [string]$OutputDir,
    [string]$Quality = 'high',
    [int]$DurationSec = 0,
    [int]$SampleIntervalSec = 5,
    [switch]$Install,
    [switch]$ClearHilog,
    [switch]$Strict,
    [switch]$RequireDevice,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Parser = Join-Path $ScriptDir 'parse_perf.mjs'
$ScenarioConfigPath = Join-Path $ScriptDir 'scenarios.json'
$SampleGenerator = Join-Path $ScriptDir 'generate_sample.mjs'
$SampleLog = Join-Path $ScriptDir 'sample_hilog.txt'

function Write-Step([string]$Message) {
    Write-Host "[perf] $Message"
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [switch]$AllowFailure,
        [string]$CapturePath
    )
    $display = ($ArgumentList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    if ($DryRun) {
        Write-Host "DRY-RUN: $FilePath $display"
        return ''
    }
    $output = & $FilePath @ArgumentList 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    if ($CapturePath) {
        $parent = Split-Path -Parent $CapturePath
        if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        [IO.File]::WriteAllText($CapturePath, $output, [Text.UTF8Encoding]::new($false))
    }
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "$FilePath $display failed with exit code $exitCode`n$output"
    }
    return $output
}

function Get-HdcPrefix {
    if ($Serial) { return @('-t', $Serial) }
    return @()
}

function Invoke-Hdc {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure,
        [string]$CapturePath
    )
    return Invoke-Native -FilePath $Hdc -ArgumentList @((Get-HdcPrefix) + $Arguments) -AllowFailure:$AllowFailure -CapturePath $CapturePath
}

function Assert-Device {
    $command = Get-Command $Hdc -ErrorAction SilentlyContinue
    if (-not $command) {
        if ($RequireDevice) { throw "HDC not found: $Hdc" }
        return $false
    }
    $targets = Invoke-Native -FilePath $Hdc -ArgumentList @('list', 'targets') -AllowFailure
    $usable = @($targets -split "`r?`n" | Where-Object { $_.Trim() -and $_ -notmatch 'Empty|not found|failed' })
    if ($Serial) { $usable = @($usable | Where-Object { $_ -match [regex]::Escape($Serial) }) }
    if ($usable.Count -eq 0) {
        if ($RequireDevice) { throw 'No matching HDC target is connected.' }
        return $false
    }
    return $true
}

function Get-Pid {
    if (-not $Bundle) { return $null }
    $pidText = Invoke-Hdc -Arguments @('shell', 'pidof', $Bundle) -AllowFailure
    $match = [regex]::Match($pidText, '(?m)\b\d+\b')
    if ($match.Success) { return $match.Value }
    $psText = Invoke-Hdc -Arguments @('shell', "ps -A 2>/dev/null | grep '$Bundle' | grep -v grep") -AllowFailure
    $match = [regex]::Match($psText, '(?m)\b\d+\b')
    if ($match.Success) { return $match.Value }
    return $null
}

function Start-App([hashtable]$Params = @{}) {
    if (-not $Bundle -or -not $Ability) { throw 'Bundle and Ability are required to start the app.' }
    $args = @('shell', 'aa', 'start', '-a', $Ability, '-b', $Bundle)
    if ($Module) { $args += @('-m', $Module) }
    foreach ($key in $Params.Keys) { $args += @('--ps', [string]$key, [string]$Params[$key]) }
    Invoke-Hdc -Arguments $args | Out-Null
}

function Stop-App {
    if ($Bundle) { Invoke-Hdc -Arguments @('shell', 'aa', 'force-stop', $Bundle) -AllowFailure | Out-Null }
}

function Install-App {
    if (-not $Install) { return }
    if (-not $Hap) { throw '-Install requires -Hap.' }
    $resolved = (Resolve-Path $Hap).Path
    Write-Step "Installing $resolved"
    Invoke-Hdc -Arguments @('install', '-r', $resolved) | Out-Null
}

function Capture-Hilog {
    param([int]$Seconds, [string]$Path)
    $prefix = Get-HdcPrefix
    $arguments = @($prefix + @('hilog'))
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Hdc
    foreach ($arg in $arguments) { [void]$psi.ArgumentList.Add($arg) }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    if ($DryRun) {
        Write-Host "DRY-RUN: $Hdc $($arguments -join ' ') > $Path for ${Seconds}s"
        return
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    Start-Sleep -Seconds $Seconds
    if (-not $process.HasExited) { $process.Kill($true) }
    $process.WaitForExit()
    $text = $stdoutTask.Result + $stderrTask.Result
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
}

function Start-HilogCapture([string]$Path) {
    $prefix = Get-HdcPrefix
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Hdc
    foreach ($arg in @($prefix + @('hilog'))) { [void]$psi.ArgumentList.Add($arg) }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    if ($DryRun) { return $null }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    return [pscustomobject]@{
        Process = $process
        Stdout = $process.StandardOutput.ReadToEndAsync()
        Stderr = $process.StandardError.ReadToEndAsync()
        Path = $Path
    }
}

function Stop-HilogCapture($Capture) {
    if ($DryRun -or -not $Capture) { return }
    if (-not $Capture.Process.HasExited) { $Capture.Process.Kill($true) }
    $Capture.Process.WaitForExit()
    $text = $Capture.Stdout.Result + $Capture.Stderr.Result
    [IO.File]::WriteAllText($Capture.Path, $text, [Text.UTF8Encoding]::new($false))
}

function Start-DiagnosticsSampler {
    param([int]$Seconds, [string]$RawDir)
    $jobScript = {
        param($HdcExe, $SerialValue, $BundleValue, $SecondsValue, $IntervalValue, $RawPath)
        $prefix = @()
        if ($SerialValue) { $prefix = @('-t', $SerialValue) }
        $end = [DateTime]::UtcNow.AddSeconds($SecondsValue)
        $index = 0
        while ([DateTime]::UtcNow -lt $end) {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $pidText = ''
            if ($BundleValue) { $pidText = (& $HdcExe @prefix shell pidof $BundleValue 2>&1 | Out-String) }
            $pidMatch = [regex]::Match($pidText, '\b\d+\b')
            $pid = if ($pidMatch.Success) { $pidMatch.Value } else { '' }
            $parts = [Collections.Generic.List[string]]::new()
            $parts.Add("timestamp=$([DateTime]::UtcNow.ToString('o'))")
            $parts.Add("pid=$pid")
            if ($pid) {
                $parts.Add('--- hidumper --mem ---')
                $parts.Add((& $HdcExe @prefix shell hidumper --mem $pid 2>&1 | Out-String))
                $parts.Add('--- hidumper --cpuusage ---')
                $parts.Add((& $HdcExe @prefix shell hidumper --cpuusage $pid 2>&1 | Out-String))
                $parts.Add('--- RenderService PID memory ---')
                $parts.Add((& $HdcExe @prefix shell hidumper -s RenderService -a "dumpExistPidMem $pid" 2>&1 | Out-String))
            }
            if ($index -eq 0) {
                $parts.Add('--- RenderService GLES ---')
                $parts.Add((& $HdcExe @prefix shell hidumper -s RenderService -a gles 2>&1 | Out-String))
            }
            $parts.Add('--- RenderService surfaces memory ---')
            $parts.Add((& $HdcExe @prefix shell hidumper -s RenderService -a allSurfacesMem 2>&1 | Out-String))
            [IO.File]::WriteAllText((Join-Path $RawPath "diag-$stamp-$index.txt"), ($parts -join "`n"), [Text.UTF8Encoding]::new($false))
            $index++
            Start-Sleep -Seconds $IntervalValue
        }
    }
    if ($DryRun) { return $null }
    return Start-Job -ScriptBlock $jobScript -ArgumentList $Hdc, $Serial, $Bundle, $Seconds, $SampleIntervalSec, $RawDir
}

function Stop-DiagnosticsSampler($Job) {
    if (-not $Job) { return }
    if ($Job.State -eq 'Running') { Stop-Job $Job | Out-Null }
    Receive-Job $Job -ErrorAction SilentlyContinue | Out-Null
    Remove-Job $Job -Force
}

function Invoke-Parser([string]$Log, [string]$OutDir, [string]$ScenarioName, [string]$Source = 'device') {
    $args = @($Parser, '--input', $Log, '--output-json', (Join-Path $OutDir 'report.json'), '--output-md', (Join-Path $OutDir 'report.md'), '--quality', $Quality, '--scenario', $ScenarioName, '--source', $Source)
    if ($Strict) { $args += '--strict' }
    Invoke-Native -FilePath 'node' -ArgumentList $args | Out-Null
}

function Write-HostEvent([string]$Path, [hashtable]$Event) {
    $line = 'PEL_PERF ' + ($Event | ConvertTo-Json -Compress -Depth 10)
    Add-Content -Path $Path -Value $line -Encoding utf8
}

function Take-Screenshot([string]$LocalPath, [int]$Index) {
    $remote = "/data/local/tmp/pelican-perf-$Index.png"
    $capture = Invoke-Hdc -Arguments @('shell', 'uitest', 'screenCap', '-p', $remote) -AllowFailure
    if ($capture -match '(?i)failed|error') { return $false }
    $parent = Split-Path -Parent $LocalPath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $recv = Invoke-Hdc -Arguments @('file', 'recv', $remote, $LocalPath) -AllowFailure
    Invoke-Hdc -Arguments @('shell', 'rm', '-f', $remote) -AllowFailure | Out-Null
    return (Test-Path $LocalPath) -and ((Get-Item $LocalPath).Length -gt 0) -and ($recv -notmatch '(?i)failed|error')
}

function Run-HostScenario([string]$Name, [hashtable]$Spec, [string]$RunDir) {
    $hostLog = Join-Path $RunDir 'raw/host-events.log'
    $runId = "host-$Name-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
    Write-HostEvent $hostLog @{ v = 1; event = 'host_begin'; runId = $runId; scenario = $Name; quality = $Quality; tsMs = 0; producer = 'host'; note = 'host orchestration events; only the engine may emit the protocol begin/end events used for pass/fail' }
    $start = [Diagnostics.Stopwatch]::StartNew()
    $checks = @{}
    try {
        $launchParams = @{ perfScenario = $Name; perfQuality = $Quality; perfRunId = $runId }
        if ($Spec.ContainsKey('engineParams')) {
            foreach ($key in $Spec.engineParams.Keys) { $launchParams[$key] = [string]$Spec.engineParams[$key] }
        }
        Start-App $launchParams
        Start-Sleep -Milliseconds 1200
        switch ($Name) {
            'background100' {
                $cycles = [int]$Spec.cycles
                $maxResumeMs = 0.0
                for ($i = 1; $i -le $cycles; $i++) {
                    Invoke-Hdc -Arguments @('shell', 'uitest', 'uiInput', 'keyEvent', 'Home') | Out-Null
                    Start-Sleep -Milliseconds ([int]$Spec.backgroundHoldMs)
                    $resumeWatch = [Diagnostics.Stopwatch]::StartNew()
                    Start-App @{ perfScenario = $Name; perfQuality = $Quality; perfRunId = $runId; perfIteration = $i }
                    $resumeWatch.Stop()
                    $maxResumeMs = [Math]::Max($maxResumeMs, $resumeWatch.Elapsed.TotalMilliseconds)
                    Start-Sleep -Milliseconds ([int]$Spec.foregroundHoldMs)
                    if (($i % 10) -eq 0) { Write-Step "$Name $i/$cycles" }
                }
                $checks.completed_cycles = $true
                $checks.aa_start_success = $true
                $checks.host_max_aa_start_ms = [Math]::Round($maxResumeMs, 3)
            }
            'screenshots20' {
                $count = [int]$Spec.count
                $success = 0
                for ($i = 1; $i -le $count; $i++) {
                    if (Take-Screenshot (Join-Path $RunDir "screenshots/capture-$('{0:D2}' -f $i).png") $i) { $success++ }
                    Start-Sleep -Milliseconds ([int]$Spec.intervalMs)
                }
                $checks.completed_captures = ($success -eq $count)
                $checks.capture_success = ($success -eq $count)
                $checks.screenshot_success_count = $success
            }
            'surfaceResizeRotate' {
                $cycles = [int]$Spec.cycles
                $rotationCommand = [string]$Spec.rotationCommand
                if (-not $rotationCommand) { throw 'scenarios.json requires a device-confirmed rotationCommand, or an ohosTest case using Driver.setDisplayRotation. This runner will not substitute the ineffective touchpad rotation gesture.' }
                for ($i = 1; $i -le $cycles; $i++) {
                    $value = if (($i % 2) -eq 1) { '1' } else { '0' }
                    $expanded = $rotationCommand.Replace('{rotation}', $value)
                    Invoke-Hdc -Arguments @('shell', 'sh', '-c', $expanded) | Out-Null
                    Start-Sleep -Milliseconds ([int]$Spec.holdMs)
                }
                $checks.completed_cycles = $true
            }
            default {
                $wait = if ($DurationSec -gt 0) { $DurationSec } else { [int]$Spec.durationSec }
                Start-Sleep -Seconds $wait
            }
        }
        if ($Name -in @('dayNight24h', 'chunkBoundaries', 'cameraSwitch')) {
            # These are engine-driven scenarios. Completion is intentionally not forged by the host.
            $checks.host_wait_complete = $true
        }
    } catch {
        $checks.host_exception = $false
        $checks.host_error = $_.Exception.Message
        throw
    } finally {
        $start.Stop()
        Write-HostEvent $hostLog @{ v = 1; event = 'host_end'; runId = $runId; scenario = $Name; quality = $Quality; tsMs = [int64]$start.ElapsedMilliseconds; producer = 'host'; checks = $checks }
    }
}

function Get-ScenarioDuration([hashtable]$Spec) {
    if ($DurationSec -gt 0) { return $DurationSec }
    if ($Scenario -eq 'background100') { return [int](($Spec.cycles * ($Spec.backgroundHoldMs + $Spec.foregroundHoldMs) / 1000) + 60) }
    if ($Scenario -eq 'screenshots20') { return [int](($Spec.count * $Spec.intervalMs / 1000) + 30) }
    if ($Scenario -eq 'surfaceResizeRotate') { return [int](($Spec.cycles * $Spec.holdMs / 1000) + 30) }
    if ($Spec.ContainsKey('durationSec')) { return [int]$Spec.durationSec }
    return 120
}

function Invoke-SelfTest {
    Write-Step 'Generating synthetic sample log'
    Invoke-Native -FilePath 'node' -ArgumentList @($SampleGenerator, $SampleLog) | Out-Null
    Write-Step 'Running parser built-in self-test'
    Invoke-Native -FilePath 'node' -ArgumentList @($Parser, '--self-test') | Out-Null
    $out = if ($OutputDir) { $OutputDir } else { Join-Path $ScriptDir 'out/self-test' }
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    Invoke-Native -FilePath 'node' -ArgumentList @($Parser, '--input', $SampleLog, '--output-json', (Join-Path $out 'report.json'), '--output-md', (Join-Path $out 'report.md'), '--quality', 'high', '--scenario', 'soak10m', '--source', 'sample', '--strict') | Out-Null
    Write-Step "Self-test report: $out"
}

if ($Mode -eq 'self-test') {
    Invoke-SelfTest
    exit 0
}

if (-not (Test-Path $ScenarioConfigPath)) { throw "Missing $ScenarioConfigPath" }
$scenarioConfigObject = Get-Content $ScenarioConfigPath -Raw | ConvertFrom-Json -AsHashtable
$scenarios = $scenarioConfigObject.scenarios

if ($Mode -eq 'suite') {
    if (-not (Assert-Device)) { throw 'Suite mode requires a connected device.' }
    $base = if ($OutputDir) { $OutputDir } else { Join-Path $ScriptDir ("out/suite-" + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
    foreach ($name in $scenarioConfigObject.order) {
        & $MyInvocation.MyCommand.Path -Mode scenario -Scenario $name -Bundle $Bundle -Ability $Ability -Module $Module -Hap $Hap -Serial $Serial -Hdc $Hdc -OutputDir (Join-Path $base $name) -Quality $Quality -SampleIntervalSec $SampleIntervalSec -Install:$Install -ClearHilog:$ClearHilog -Strict:$Strict -RequireDevice -DryRun:$DryRun
        $Install = $false
    }
    exit 0
}

if (-not (Assert-Device)) {
    Write-Warning 'No HDC/HAP/device result was collected. Run -Mode self-test for parser-only validation.'
    exit 3
}

Install-App
$runDir = if ($OutputDir) { $OutputDir } else { Join-Path $ScriptDir ("out/$Scenario-" + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
$rawDir = Join-Path $runDir 'raw'
New-Item -ItemType Directory -Force -Path $rawDir | Out-Null
if ($ClearHilog) { Invoke-Hdc -Arguments @('shell', 'hilog', '-r') -AllowFailure -CapturePath (Join-Path $rawDir 'hilog-clear.txt') | Out-Null }

$spec = $scenarios[$Scenario]
if (-not $spec) { throw "Unknown scenario in scenarios.json: $Scenario" }
$seconds = Get-ScenarioDuration $spec
$hilogPath = Join-Path $rawDir 'hilog-device.txt'
$combinedLog = Join-Path $rawDir 'hilog-combined.txt'
$diagJob = Start-DiagnosticsSampler -Seconds $seconds -RawDir $rawDir
$capture = Start-HilogCapture -Path $hilogPath
try {
    if ($Mode -eq 'collect') {
        Write-Step "Collecting hilog for $seconds seconds"
        Start-Sleep -Seconds $seconds
    } else {
        Write-Step "Running $Scenario"
        Run-HostScenario -Name $Scenario -Spec $spec -RunDir $runDir
        $elapsed = [int]$spec.hostTailSec
        if ($elapsed -gt 0) { Start-Sleep -Seconds $elapsed }
    }
} finally {
    Stop-HilogCapture $capture
    Stop-DiagnosticsSampler $diagJob
}

Copy-Item $hilogPath $combinedLog -Force
$hostEvents = Join-Path $rawDir 'host-events.log'
if (Test-Path $hostEvents) { Get-Content $hostEvents | Add-Content -Path $combinedLog -Encoding utf8 }
Invoke-Hdc -Arguments @('shell', 'hidumper', '-e', '--list', '-n', '20') -AllowFailure -CapturePath (Join-Path $rawDir 'faults-after.txt') | Out-Null
Invoke-Parser -Log $combinedLog -OutDir $runDir -ScenarioName $Scenario -Source 'device'
Write-Step "Completed: $runDir"
