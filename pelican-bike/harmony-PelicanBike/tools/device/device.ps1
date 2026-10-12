[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = "help",

    [ValidateSet("auto", "signed", "unsigned")]
    [string]$PackageMode = "auto",

    [string]$DeviceName = "Pura90",
    [string]$Serial = "",
    [string]$Product = "default",
    [string]$Module = "entry",
    [string]$Target = "default",
    [string]$BuildMode = "debug",
    [string]$HapPath = "",
    [string]$Filter = "com\.riba2534\.pelicanbike|PelicanBike|EntryAbility",
    [string]$OutputPath = "",
    [ValidateRange(10, 1800)]
    [int]$TimeoutSec = 180,
    [switch]$SkipSync
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

# Never inherit the caller's working directory for project operations.
$script:ScriptRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$script:ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $script:ScriptRoot "..\.."))
if (-not (Test-Path -LiteralPath $script:ProjectRoot -PathType Container)) {
    throw "Project root does not exist: $script:ProjectRoot"
}
Set-Location -LiteralPath $script:ProjectRoot

$script:BundleName = "com.riba2534.pelicanbike"
$script:AbilityName = "EntryAbility"
$script:EnvironmentInitialized = $false

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-WarnMessage {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Convert-InputPath {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $PathValue
    }

    # Accept Git Bash paths such as /d/workspace/file.hap.
    if ($PathValue -match '^/([A-Za-z])/(.*)$') {
        $drive = $Matches[1].ToUpperInvariant()
        $rest = $Matches[2] -replace '/', '\'
        return "${drive}:\$rest"
    }

    return $PathValue
}

function Get-DevEcoHome {
    $candidates = New-Object System.Collections.Generic.List[string]

    foreach ($value in @($env:DEVECO_STUDIO_HOME, $env:DEVECOSTUDIO_HOME, $env:DEVECO_HOME)) {
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $candidates.Add($value.Trim('"'))
        }
    }

    $candidates.Add("C:\Program Files\Huawei\DevEco Studio")
    if (${env:ProgramFiles(x86)}) {
        $candidates.Add((Join-Path ${env:ProgramFiles(x86)} "Huawei\DevEco Studio"))
    }

    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    try {
        $installLocations = Get-ItemProperty -Path $registryPaths -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq "DevEco Studio" } |
            Select-Object -ExpandProperty InstallLocation
        foreach ($location in $installLocations) {
            if (-not [string]::IsNullOrWhiteSpace($location)) {
                $candidates.Add($location.Trim('"'))
            }
        }
    } catch {
        # Registry discovery is optional.
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        $devEcoPath = [System.IO.Path]::GetFullPath($candidate)
        if (Test-Path -LiteralPath (Join-Path $devEcoPath "product-info.json") -PathType Leaf) {
            return $devEcoPath
        }
    }

    throw "DevEco Studio was not found. Expected DevEco Studio 6.1.1, normally under C:\Program Files\Huawei\DevEco Studio."
}

function Get-Toolchain {
    $devEcoPath = Get-DevEcoHome
    $sdk = Join-Path $devEcoPath "sdk"
    $nodeHome = Join-Path $devEcoPath "tools\node"
    $jbr = Join-Path $devEcoPath "jbr"
    $ohpmBin = Join-Path $devEcoPath "tools\ohpm\bin"

    return [pscustomobject]@{
        Home = $devEcoPath
        ProductInfo = Join-Path $devEcoPath "product-info.json"
        NodeHome = $nodeHome
        Node = Join-Path $nodeHome "node.exe"
        OhpmBin = $ohpmBin
        OhpmCli = Join-Path $ohpmBin "pm-cli.js"
        HvigorCli = Join-Path $devEcoPath "tools\hvigor\bin\hvigorw.js"
        HvigorPackage = Join-Path $devEcoPath "tools\hvigor\hvigor\package.json"
        OhpmPackage = Join-Path $devEcoPath "tools\ohpm\package.json"
        Sdk = $sdk
        SdkPackage = Join-Path $sdk "default\sdk-pkg.json"
        Hdc = Join-Path $sdk "default\openharmony\toolchains\hdc.exe"
        Emulator = Join-Path $devEcoPath "tools\emulator\Emulator.exe"
        Jbr = $jbr
        JbrBin = Join-Path $jbr "bin"
        Java = Join-Path $jbr "bin\java.exe"
        Keytool = Join-Path $jbr "bin\keytool.exe"
        HapSignTool = Join-Path $sdk "default\openharmony\toolchains\lib\hap-sign-tool.jar"
        DebugProfileTemplate = Join-Path $sdk "default\openharmony\toolchains\lib\UnsgnedDebugProfileTemplate.json"
    }
}

function Assert-Toolchain {
    param($Tools)

    $required = [ordered]@{
        "DevEco product metadata" = $Tools.ProductInfo
        "DevEco Node" = $Tools.Node
        "OHPM CLI" = $Tools.OhpmCli
        "Hvigor CLI" = $Tools.HvigorCli
        "HarmonyOS SDK metadata" = $Tools.SdkPackage
        "HDC" = $Tools.Hdc
        "Emulator" = $Tools.Emulator
        "DevEco JBR Java" = $Tools.Java
        "DevEco keytool" = $Tools.Keytool
        "HAP sign tool" = $Tools.HapSignTool
        "OpenHarmony debug profile template" = $Tools.DebugProfileTemplate
    }

    foreach ($item in $required.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $item.Value -PathType Leaf)) {
            throw "$($item.Key) is missing: $($item.Value)"
        }
    }
}

function Initialize-DevEcoEnvironment {
    param($Tools)

    if ($script:EnvironmentInitialized) {
        return
    }

    # These changes are process-local only. No machine/user PATH is modified.
    # DevEco's JBR is prepended because Hvigor invokes its internal Java tools
    # by command name. Node/OHPM/Hvigor themselves are still called by absolute
    # path, and the caller's remaining PATH is preserved for native build tools.
    $env:NODE_HOME = $Tools.NodeHome
    $env:JAVA_HOME = $Tools.Jbr
    $env:DEVECO_SDK_HOME = $Tools.Sdk
    $env:HOS_SDK_HOME = $Tools.Sdk
    $env:OHOS_BASE_SDK_HOME = $Tools.Sdk

    $existing = @()
    if ($env:Path) {
        $existing = $env:Path -split ';'
    }
    $prefixes = @($Tools.JbrBin, $Tools.NodeHome, $Tools.OhpmBin)
    $env:Path = (($prefixes + $existing) | Where-Object { $_ } | Select-Object -Unique) -join ';'
    $script:EnvironmentInitialized = $true
}

function Invoke-Capture {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [switch]$AllowFailure
    )

    $lines = @(& $FilePath @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
    $text = $lines -join [Environment]::NewLine

    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "Command failed ($exitCode): $FilePath $($Arguments -join ' ')`n$text"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Lines = $lines
        Text = $text
    }
}

function Invoke-Streaming {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    & $FilePath @Arguments 2>&1 | ForEach-Object { Write-Host $_.ToString() }
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Command failed ($exitCode): $FilePath $($Arguments -join ' ')"
    }
}

function Invoke-ProcessWithTimeout {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 120
    )

    $process = $null
    try {
        $argumentLine = [string]::Join(' ', @($Arguments | ForEach-Object {
            '"' + ($_.Replace('"', '\"')) + '"'
        }))
        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName = $FilePath
        $startInfo.Arguments = $argumentLine
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = New-Object Diagnostics.Process
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw "Failed to start command: $FilePath"
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch {}
            throw "Command timed out after $TimeoutSeconds seconds: $FilePath $($Arguments -join ' ')"
        }
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $text = @($stdout, $stderr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.TrimEnd() }
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Text = ($text -join [Environment]::NewLine)
        }
    } finally {
        if ($process) {
            $process.Dispose()
        }
    }
}

function Assert-ProjectReady {
    param([switch]$RequireModule)

    Set-Location -LiteralPath $script:ProjectRoot
    $required = @("build-profile.json5", "oh-package.json5", "hvigorfile.ts", "AppScope\app.json5")
    foreach ($name in $required) {
        $path = Join-Path $script:ProjectRoot $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "HarmonyOS project is not generated yet. Missing $name under $script:ProjectRoot. Generate/open the main project first; this script will not create or alter root project files."
        }
    }

    $appConfigText = Get-Content -LiteralPath (Join-Path $script:ProjectRoot "AppScope\app.json5") -Raw
    $actualBundle = Get-ProfileStringValue -Text $appConfigText -Name "bundleName"
    if ($actualBundle -ne $script:BundleName) {
        throw "Target project identity mismatch. Found bundleName '$actualBundle', expected '$script:BundleName'."
    }

    if ($RequireModule) {
        $modulePath = Join-Path $script:ProjectRoot $Module
        if (-not (Test-Path -LiteralPath $modulePath -PathType Container)) {
            throw "Module '$Module' does not exist: $modulePath"
        }
        if (-not (Test-Path -LiteralPath (Join-Path $modulePath "build-profile.json5") -PathType Leaf)) {
            throw "Module '$Module' is incomplete: build-profile.json5 is missing."
        }
        $moduleConfigPath = Join-Path $modulePath "src\main\module.json5"
        if (-not (Test-Path -LiteralPath $moduleConfigPath -PathType Leaf)) {
            throw "Module '$Module' is incomplete: src\main\module.json5 is missing."
        }
        $moduleConfigText = Get-Content -LiteralPath $moduleConfigPath -Raw
        $mainElement = Get-ProfileStringValue -Text $moduleConfigText -Name "mainElement"
        if ($mainElement -ne $script:AbilityName) {
            throw "Target Ability mismatch in $moduleConfigPath. Found mainElement '$mainElement', expected '$script:AbilityName'."
        }
    }
}

function Get-ProjectBuildProfileText {
    $path = Join-Path $script:ProjectRoot "build-profile.json5"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }
    return Get-Content -LiteralPath $path -Raw
}

function Get-ProfileStringValue {
    param(
        [string]$Text,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $pattern = '"?' + [Regex]::Escape($Name) + '"?\s*:\s*"([^"]+)"'
    $match = [Regex]::Match($Text, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return $null
    }
    return $match.Groups[1].Value.Replace('\\', '\')
}

function Resolve-ProjectReferencedPath {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }
    $Value = Convert-InputPath $Value
    if ([System.IO.Path]::IsPathRooted($Value)) {
        return [System.IO.Path]::GetFullPath($Value)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $script:ProjectRoot $Value))
}

function Get-VerifiedProfile {
    param(
        $Tools,
        [string]$ProfilePath
    )

    $result = Invoke-Capture -FilePath $Tools.Java -Arguments @(
        "-jar", $Tools.HapSignTool,
        "verify-profile",
        "-inFile", $ProfilePath
    )
    $start = $result.Text.IndexOf('{')
    $end = $result.Text.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) {
        throw "Could not parse profile verification output for $ProfilePath"
    }
    $json = $result.Text.Substring($start, $end - $start + 1)
    return $json | ConvertFrom-Json
}

function Normalize-Pem {
    param([string]$Pem)
    if ($null -eq $Pem) {
        return ""
    }
    return ($Pem -replace '\s', '')
}

function Test-SigningConfiguration {
    param(
        $Tools,
        [switch]$Quiet
    )

    $profileText = Get-ProjectBuildProfileText
    if ([string]::IsNullOrWhiteSpace($profileText)) {
        return [pscustomobject]@{ Ready = $false; Message = "build-profile.json5 is missing" }
    }

    $hasSigningBlock = $profileText -match '(?is)"?signingConfigs"?\s*:\s*\[\s*\{'
    $hasProductReference = $profileText -match '(?is)"?signingConfig"?\s*:\s*"[^"]+"'
    if (-not $hasSigningBlock -or -not $hasProductReference) {
        return [pscustomobject]@{ Ready = $false; Message = "No complete project signingConfig is declared" }
    }

    $profileValue = Get-ProfileStringValue -Text $profileText -Name "profile"
    $certValue = Get-ProfileStringValue -Text $profileText -Name "certpath"
    $storeValue = Get-ProfileStringValue -Text $profileText -Name "storeFile"
    $profilePath = Resolve-ProjectReferencedPath $profileValue
    $certPath = Resolve-ProjectReferencedPath $certValue
    $storePath = Resolve-ProjectReferencedPath $storeValue

    foreach ($pair in @(
        [pscustomobject]@{ Name = "profile"; Path = $profilePath },
        [pscustomobject]@{ Name = "certificate"; Path = $certPath },
        [pscustomobject]@{ Name = "keystore"; Path = $storePath }
    )) {
        if ([string]::IsNullOrWhiteSpace($pair.Path) -or -not (Test-Path -LiteralPath $pair.Path -PathType Leaf)) {
            return [pscustomobject]@{ Ready = $false; Message = "Signing $($pair.Name) is missing: $($pair.Path)" }
        }
    }

    try {
        $verified = Get-VerifiedProfile -Tools $Tools -ProfilePath $profilePath
        if (-not $verified.verifiedPassed) {
            return [pscustomobject]@{ Ready = $false; Message = "Provision profile verification failed" }
        }

        $content = $verified.content
        $profileBundle = $content.'bundle-info'.'bundle-name'
        if ($profileBundle -ne $script:BundleName) {
            return [pscustomobject]@{
                Ready = $false
                Message = "Provision profile bundle-name '$profileBundle' does not match '$script:BundleName'. Never reuse another app profile."
            }
        }

        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $notBefore = [int64]$content.validity.'not-before'
        $notAfter = [int64]$content.validity.'not-after'
        if ($now -lt $notBefore -or $now -gt $notAfter) {
            return [pscustomobject]@{ Ready = $false; Message = "Provision profile is outside its validity window ($notBefore..$notAfter)" }
        }

        $profileCertificate = Normalize-Pem $content.'bundle-info'.'development-certificate'
        if ([string]::IsNullOrWhiteSpace($profileCertificate)) {
            return [pscustomobject]@{ Ready = $false; Message = "Provision profile has no development-certificate" }
        }

        $certResult = Invoke-Capture -FilePath $Tools.Keytool -Arguments @("-printcert", "-rfc", "-file", $certPath)
        $pemMatches = [Regex]::Matches(
            $certResult.Text,
            '-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----'
        )
        $certificateMatches = $false
        foreach ($pemMatch in $pemMatches) {
            if ((Normalize-Pem $pemMatch.Value) -eq $profileCertificate) {
                $certificateMatches = $true
                break
            }
        }
        if (-not $certificateMatches) {
            return [pscustomobject]@{
                Ready = $false
                Message = "Provision profile development-certificate does not match certpath. Regenerate project-specific signing material."
            }
        }

        return [pscustomobject]@{
            Ready = $true
            Message = "Profile is verified for $profileBundle; validity and development-certificate match"
            ProfilePath = $profilePath
            CertPath = $certPath
            StorePath = $storePath
            Issuer = $content.issuer
        }
    } catch {
        if (-not $Quiet) {
            Write-WarnMessage $_.Exception.Message
        }
        return [pscustomobject]@{ Ready = $false; Message = $_.Exception.Message }
    }
}

function Get-EmulatorInstances {
    param($Tools)

    $result = Invoke-Capture -FilePath $Tools.Emulator -Arguments @("-list", "-details")
    $start = $result.Text.IndexOf('[')
    $end = $result.Text.LastIndexOf(']')
    if ($start -lt 0 -or $end -lt $start) {
        throw "Could not parse Emulator -list -details output."
    }
    $json = $result.Text.Substring($start, $end - $start + 1)
    return @($json | ConvertFrom-Json)
}

function Get-EmulatorInstance {
    param($Tools)

    $instances = Get-EmulatorInstances -Tools $Tools
    $exact = @($instances | Where-Object { $_.name -eq $DeviceName })
    if ($exact.Count -eq 1) {
        return $exact[0]
    }
    if ($exact.Count -gt 1) {
        throw "More than one emulator instance is named '$DeviceName'."
    }
    throw "Emulator instance '$DeviceName' was not found. Available: $((@($instances | ForEach-Object { $_.name })) -join ', ')"
}

function Get-HdcTargets {
    param($Tools)

    $result = Invoke-Capture -FilePath $Tools.Hdc -Arguments @("list", "targets") -AllowFailure
    if ($result.ExitCode -ne 0) {
        return @()
    }

    $targets = @()
    foreach ($line in $result.Lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed -eq "[Empty]" -or $trimmed -match '^\*') {
            continue
        }
        $targets += (($trimmed -split '\s+')[0])
    }
    return ,@($targets | Select-Object -Unique)
}

function Select-HdcTarget {
    param(
        $Tools,
        [string[]]$Targets,
        [switch]$Waiting
    )

    if (-not [string]::IsNullOrWhiteSpace($Serial)) {
        if ($Targets -contains $Serial) {
            return $Serial
        }
        if (-not $Waiting) {
            throw "Requested HDC target '$Serial' is not connected. Connected: $($Targets -join ', ')"
        }
        return $null
    }

    if ($Targets.Count -eq 0) {
        if ($Waiting) {
            return $null
        }
        throw "No HDC target is connected. Start/wait for Pura90 first."
    }
    if ($Targets.Count -eq 1) {
        return $Targets[0]
    }

    throw "Multiple HDC targets are connected. Pass -Serial explicitly; the script will not guess which target is '$DeviceName': $($Targets -join ', ')"
}

function Resolve-DeviceSerial {
    param($Tools)

    $targets = @(Get-HdcTargets -Tools $Tools)
    return Select-HdcTarget -Tools $Tools -Targets $targets
}

function Invoke-HdcCapture {
    param(
        $Tools,
        [string]$ResolvedSerial,
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    $allArguments = @()
    if (-not [string]::IsNullOrWhiteSpace($ResolvedSerial)) {
        $allArguments += @("-t", $ResolvedSerial)
    }
    $allArguments += $Arguments
    return Invoke-Capture -FilePath $Tools.Hdc -Arguments $allArguments -AllowFailure:$AllowFailure
}

function Invoke-HdcStreaming {
    param(
        $Tools,
        [string]$ResolvedSerial,
        [string[]]$Arguments
    )

    $allArguments = @()
    if (-not [string]::IsNullOrWhiteSpace($ResolvedSerial)) {
        $allArguments += @("-t", $ResolvedSerial)
    }
    $allArguments += $Arguments
    Invoke-Streaming -FilePath $Tools.Hdc -Arguments $allArguments
    return
}

function Wait-HdcTarget {
    param($Tools)

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    do {
        $targets = @(Get-HdcTargets -Tools $Tools)
        $selected = Select-HdcTarget -Tools $Tools -Targets $targets -Waiting
        if (-not [string]::IsNullOrWhiteSpace($selected)) {
            Write-Info "HDC target is ready: $selected"
            return $selected
        }
        Start-Sleep -Seconds 2
    } while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSec)

    throw "Timed out after $TimeoutSec seconds waiting for an HDC target."
}

function Get-BuildStampPath {
    param(
        [ValidateSet("signed", "unsigned")]
        [string]$Mode
    )

    return Join-Path $script:ScriptRoot "last-$Mode-hap.txt"
}

function Set-BuildStamp {
    param(
        [ValidateSet("signed", "unsigned")]
        [string]$Mode,
        [string]$PathValue
    )

    $stampPath = Get-BuildStampPath -Mode $Mode
    [System.IO.File]::WriteAllText($stampPath, [System.IO.Path]::GetFullPath($PathValue) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

function Get-BuildStamp {
    param(
        [ValidateSet("signed", "unsigned")]
        [string]$Mode
    )

    $stampPath = Get-BuildStampPath -Mode $Mode
    if (-not (Test-Path -LiteralPath $stampPath -PathType Leaf)) {
        return $null
    }
    $value = (Get-Content -LiteralPath $stampPath -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }
    try {
        $fullPath = [System.IO.Path]::GetFullPath($value)
    } catch {
        return $null
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        return $null
    }
    $name = [System.IO.Path]::GetFileName($fullPath)
    if ($Mode -eq "signed" -and $name -notmatch '-signed\.hap$') {
        return $null
    }
    if ($Mode -eq "unsigned" -and $name -notmatch '-unsigned\.hap$') {
        return $null
    }
    return $fullPath
}

function Find-Hap {
    param(
        [ValidateSet("auto", "signed", "unsigned")]
        [string]$Preference = "auto"
    )

    if (-not [string]::IsNullOrWhiteSpace($HapPath)) {
        $candidate = Convert-InputPath $HapPath
        if (-not [System.IO.Path]::IsPathRooted($candidate)) {
            $candidate = Join-Path $script:ProjectRoot $candidate
        }
        $candidate = [System.IO.Path]::GetFullPath($candidate)
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "HAP does not exist: $candidate"
        }
        return $candidate
    }

    if ($Preference -eq "signed" -or $Preference -eq "unsigned") {
        $stamped = Get-BuildStamp -Mode $Preference
        if ($stamped) {
            return $stamped
        }
    } else {
        $stampedSigned = Get-BuildStamp -Mode "signed"
        if ($stampedSigned) {
            return $stampedSigned
        }
        $stampedUnsigned = Get-BuildStamp -Mode "unsigned"
        if ($stampedUnsigned) {
            return $stampedUnsigned
        }
    }

    $buildRoot = Join-Path (Join-Path $script:ProjectRoot $Module) "build"
    if (-not (Test-Path -LiteralPath $buildRoot -PathType Container)) {
        return $null
    }

    $all = @(Get-ChildItem -LiteralPath $buildRoot -Filter "*.hap" -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]ohosTest[\\/]' } |
        Sort-Object LastWriteTimeUtc -Descending)

    if ($Preference -eq "signed") {
        $all = @($all | Where-Object { $_.Name -match '-signed\.hap$' })
    } elseif ($Preference -eq "unsigned") {
        $all = @($all | Where-Object { $_.Name -match '-unsigned\.hap$' })
    } else {
        $signed = @($all | Where-Object { $_.Name -match '-signed\.hap$' })
        if ($signed.Count -gt 0) {
            return $signed[0].FullName
        }
        $all = @($all | Where-Object { $_.Name -match '-unsigned\.hap$' })
    }

    if ($all.Count -eq 0) {
        return $null
    }
    return $all[0].FullName
}

function Invoke-Sync {
    param($Tools)

    Assert-ProjectReady
    Initialize-DevEcoEnvironment -Tools $Tools
    Set-Location -LiteralPath $script:ProjectRoot

    Write-Info "Installing OHPM dependencies with DevEco Node: $($Tools.Node)"
    Invoke-Streaming -FilePath $Tools.Node -Arguments @($Tools.OhpmCli, "install", "--all")

    Write-Info "Synchronizing Hvigor project model."
    Invoke-Streaming -FilePath $Tools.Node -Arguments @(
        $Tools.HvigorCli,
        "--sync",
        "-p", "product=$Product",
        "--analyze=normal",
        "--parallel",
        "--incremental",
        "--no-daemon"
    )
}

function Invoke-Build {
    param($Tools)

    Assert-ProjectReady -RequireModule
    Initialize-DevEcoEnvironment -Tools $Tools
    Set-Location -LiteralPath $script:ProjectRoot

    $effectiveMode = $PackageMode
    $signing = Test-SigningConfiguration -Tools $Tools -Quiet
    if ($effectiveMode -eq "auto") {
        if ($signing.Ready) {
            $effectiveMode = "signed"
            Write-Info "Auto package mode selected signed output: $($signing.Message)"
        } else {
            $effectiveMode = "unsigned"
            Write-WarnMessage "Auto package mode selected unsigned output: $($signing.Message)"
        }
    }

    if ($effectiveMode -eq "signed" -and -not $signing.Ready) {
        throw "Signed build is not safe/ready: $($signing.Message). Open this exact project in DevEco Studio, enable automatic signing for '$script:BundleName', and let the IDE generate a project-specific profile once."
    }

    if (-not $SkipSync) {
        Invoke-Sync -Tools $Tools
    }

    $enableSign = if ($effectiveMode -eq "signed") { "true" } else { "false" }
    Write-Info "Running assembleHap ($effectiveMode) with DevEco Node 18."
    Invoke-Streaming -FilePath $Tools.Node -Arguments @(
        $Tools.HvigorCli,
        "-c", "properties.enableSignTask=$enableSign",
        "--mode", "module",
        "-p", "module=$Module@$Target",
        "-p", "product=$Product",
        "-p", "buildMode=$BuildMode",
        "assembleHap",
        "--analyze=normal",
        "--parallel",
        "--incremental",
        "--no-daemon"
    )

    $hap = Find-Hap -Preference $effectiveMode
    if ([string]::IsNullOrWhiteSpace($hap)) {
        throw "assembleHap completed but no $effectiveMode HAP was found under $Module\build."
    }
    Set-BuildStamp -Mode $effectiveMode -PathValue $hap
    Write-Info "HAP: $hap"
    return $hap
}

function Start-ConfiguredEmulator {
    param($Tools)

    $instance = Get-EmulatorInstance -Tools $Tools
    if ([string]$instance.'os.apiVersion' -ne "24") {
        throw "Emulator '$DeviceName' is API $($instance.'os.apiVersion'), expected API 24."
    }
    if ([string]$instance.isRunning -eq "true") {
        Write-Info "Emulator '$DeviceName' is already running."
        return
    }

    Write-Info "Starting '$DeviceName' with coldboot (preserves its data partition)."
    $argumentLine = '-start "{0}" -bootmode coldboot' -f ($DeviceName -replace '"', '\"')
    Start-Process -FilePath $Tools.Emulator -ArgumentList $argumentLine | Out-Null
}

function Stop-ConfiguredEmulator {
    param($Tools)

    $instance = Get-EmulatorInstance -Tools $Tools
    if ([string]$instance.isRunning -ne "true") {
        Write-Info "Emulator '$DeviceName' is already stopped."
        return
    }

    Write-Info "Stopping '$DeviceName'. No reset/delete/uninstall command is used."
    Invoke-Streaming -FilePath $Tools.Emulator -Arguments @("-stop", $DeviceName)
}

function Resolve-InstallHap {
    param($Tools)

    if (-not [string]::IsNullOrWhiteSpace($HapPath)) {
        $hap = Find-Hap -Preference "auto"
        if ([System.IO.Path]::GetFileName($hap) -match '-unsigned\.hap$') {
            throw "Refusing to install an explicitly unsigned HAP: $hap"
        }
        return $hap
    }

    $signing = Test-SigningConfiguration -Tools $Tools -Quiet
    if (-not $signing.Ready) {
        throw "Refusing automatic HAP installation because project signing is not verified: $($signing.Message). Pass an explicit trusted -HapPath, or configure DevEco automatic signing for this bundle."
    }

    $hap = Get-BuildStamp -Mode "signed"
    if ([string]::IsNullOrWhiteSpace($hap)) {
        $unsigned = Get-BuildStamp -Mode "unsigned"
        if ($unsigned) {
            throw "The last tool-managed build was unsigned: $unsigned. Build -PackageMode signed before install."
        }
        throw "No tool-managed signed HAP is recorded. Run build -PackageMode signed first, or pass an explicit trusted -HapPath."
    }
    return $hap
}

function Install-Hap {
    param(
        $Tools,
        [string]$ResolvedSerial,
        [string]$ResolvedHap
    )

    Write-Info "Installing with replacement semantics (no uninstall; app data is not intentionally deleted): $ResolvedHap"
    $installArguments = @("-t", $ResolvedSerial, "install", "-r", "-w", ([string]($TimeoutSec * 1000)), $ResolvedHap)
    $result = Invoke-ProcessWithTimeout -FilePath $Tools.Hdc -Arguments $installArguments -TimeoutSeconds ($TimeoutSec + 15)
    if ($result.Text) {
        Write-Host $result.Text
    }
    if ($result.ExitCode -ne 0 -or $result.Text -match '(?i)\bfailed\b|signature.*mismatch') {
        throw "HAP installation failed. The script will not auto-uninstall the existing app because that could delete user data. Resolve signing/version compatibility explicitly."
    }
}

function Launch-App {
    param(
        $Tools,
        [string]$ResolvedSerial
    )

    Write-Info "Launching $script:BundleName/$script:AbilityName"
    Invoke-HdcStreaming -Tools $Tools -ResolvedSerial $ResolvedSerial -Arguments @(
        "shell", "aa", "start",
        "-b", $script:BundleName,
        "-a", $script:AbilityName
    )
}

function Get-AppProcess {
    param(
        $Tools,
        [string]$ResolvedSerial
    )

    $pidResult = Invoke-HdcCapture -Tools $Tools -ResolvedSerial $ResolvedSerial -Arguments @("shell", "pidof", $script:BundleName) -AllowFailure
    $pidText = $pidResult.Text.Trim()
    if ($pidResult.ExitCode -eq 0 -and $pidText -match '\d') {
        return $pidText
    }

    $psResult = Invoke-HdcCapture -Tools $Tools -ResolvedSerial $ResolvedSerial -Arguments @("shell", "ps", "-ef") -AllowFailure
    $matching = @($psResult.Lines | Where-Object { $_ -match [Regex]::Escape($script:BundleName) })
    if ($matching.Count -gt 0) {
        return ($matching -join [Environment]::NewLine)
    }
    return $null
}

function Get-FilteredHilogSnapshot {
    param(
        $Tools,
        [string]$ResolvedSerial
    )

    $result = Invoke-HdcCapture -Tools $Tools -ResolvedSerial $ResolvedSerial -Arguments @("shell", "hilog", "-x") -AllowFailure
    if ($result.ExitCode -ne 0) {
        return @("hilog snapshot failed: $($result.Text)")
    }

    if ([string]::IsNullOrWhiteSpace($Filter)) {
        return @($result.Lines | Select-Object -Last 200)
    }

    try {
        return @($result.Lines | Where-Object { $_ -match $Filter } | Select-Object -Last 200)
    } catch {
        throw "Invalid -Filter regular expression: $Filter"
    }
}

function Invoke-HilogStream {
    param($Tools)

    $resolvedSerial = Resolve-DeviceSerial -Tools $Tools
    $arguments = @("-t", $resolvedSerial, "hilog")
    Write-Info "Streaming hilog from $resolvedSerial. Press Ctrl+C to stop. Filter: $Filter"

    if ([string]::IsNullOrWhiteSpace($Filter)) {
        & $Tools.Hdc @arguments
    } else {
        try {
            [void][Regex]::new($Filter)
            & $Tools.Hdc @arguments 2>&1 | ForEach-Object {
                $line = $_.ToString()
                if ($line -match $Filter) {
                    Write-Host $line
                }
            }
        } catch {
            throw "Invalid -Filter regular expression: $Filter"
        }
    }

    if ($LASTEXITCODE -ne 0) {
        throw "hilog exited with code $LASTEXITCODE"
    }
}

function Capture-Screenshot {
    param($Tools)

    $resolvedSerial = Resolve-DeviceSerial -Tools $Tools
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    # API 24 snapshot_display on this Pura90 image requires a .jpeg suffix.
    $remote = "/data/local/tmp/pelicanbike-$timestamp.jpeg"

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $artifactDirectory = Join-Path $script:ScriptRoot "artifacts"
        if (-not (Test-Path -LiteralPath $artifactDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $artifactDirectory | Out-Null
        }
        $local = Join-Path $artifactDirectory "pelicanbike-$timestamp.jpeg"
    } else {
        $local = Convert-InputPath $OutputPath
        if (-not [System.IO.Path]::IsPathRooted($local)) {
            $local = Join-Path $script:ProjectRoot $local
        }
        $local = [System.IO.Path]::GetFullPath($local)
        if ([System.IO.Path]::GetExtension($local) -notmatch '^(?i)\.jpe?g$') {
            throw "Pura90 snapshot_display requires a .jpeg or .jpg output path: $local"
        }
        $parent = Split-Path -Parent $local
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Path $parent | Out-Null
        }
    }

    try {
        Invoke-HdcStreaming -Tools $Tools -ResolvedSerial $resolvedSerial -Arguments @("shell", "snapshot_display", "-f", $remote)
        Invoke-HdcStreaming -Tools $Tools -ResolvedSerial $resolvedSerial -Arguments @("file", "recv", $remote, $local)
        if (-not (Test-Path -LiteralPath $local -PathType Leaf)) {
            throw "Screenshot pull reported success but the local file does not exist: $local"
        }
        Write-Info "Screenshot: $local"
    } finally {
        # Delete only the exact temporary file created above, never a directory or wildcard.
        if ($remote -match '^/data/local/tmp/pelicanbike-[0-9]{8}-[0-9]{6}\.jpeg$') {
            Invoke-HdcCapture -Tools $Tools -ResolvedSerial $resolvedSerial -Arguments @("shell", "rm", "-f", $remote) -AllowFailure | Out-Null
        }
    }
}

function Invoke-Smoke {
    param($Tools)

    $hap = Invoke-Build -Tools $Tools
    if ([System.IO.Path]::GetFileName($hap) -match '-unsigned\.hap$') {
        throw "Smoke stopped after a successful unsigned build. An installable signed HAP is required. Open this exact project in DevEco Studio and enable automatic signing once; do not copy another app's profile."
    }
    if (-not (Test-Path -LiteralPath $hap -PathType Leaf)) {
        throw "Smoke will not start an emulator because the built HAP does not exist: $hap"
    }

    $instance = Get-EmulatorInstance -Tools $Tools
    if ([string]$instance.isRunning -ne "true") {
        # Build succeeded and a signed HAP exists before the emulator is started.
        Start-ConfiguredEmulator -Tools $Tools
    }
    $resolvedSerial = Wait-HdcTarget -Tools $Tools

    Install-Hap -Tools $Tools -ResolvedSerial $resolvedSerial -ResolvedHap $hap
    Launch-App -Tools $Tools -ResolvedSerial $resolvedSerial
    Start-Sleep -Seconds 4

    $process = Get-AppProcess -Tools $Tools -ResolvedSerial $resolvedSerial
    if ([string]::IsNullOrWhiteSpace($process)) {
        throw "Smoke failed: no process was found for $script:BundleName after launch."
    }
    Write-Info "Process check passed: $process"

    $logs = @(Get-FilteredHilogSnapshot -Tools $Tools -ResolvedSerial $resolvedSerial)
    Write-Info "Filtered hilog snapshot ($($logs.Count) lines):"
    $logs | ForEach-Object { Write-Host $_ }

    $fatal = @($logs | Where-Object { $_ -match '(?i)fatal|uncaught|crash|abort|segmentation|exception' })
    if ($fatal.Count -gt 0) {
        throw "Smoke found fatal/crash indicators in filtered hilog."
    }
    if ($logs.Count -eq 0) {
        Write-WarnMessage "No app-specific hilog line matched '$Filter'; process check still passed."
    }
    Write-Info "Smoke passed."
}

function Invoke-Doctor {
    $failures = 0
    $warnings = 0

    function Report {
        param([string]$Level, [string]$Name, [string]$Detail)
        if ($Level -eq "OK") {
            Write-Host "[OK]   $Name - $Detail" -ForegroundColor Green
        } elseif ($Level -eq "WARN") {
            $script:DoctorWarnings++
            Write-Host "[WARN] $Name - $Detail" -ForegroundColor Yellow
        } else {
            $script:DoctorFailures++
            Write-Host "[FAIL] $Name - $Detail" -ForegroundColor Red
        }
    }

    $script:DoctorFailures = 0
    $script:DoctorWarnings = 0
    Report "OK" "Working directory" $script:ProjectRoot

    try {
        $tools = Get-Toolchain
        Report "OK" "DevEco home" $tools.Home
    } catch {
        Report "FAIL" "DevEco home" $_.Exception.Message
        return 1
    }

    $toolFiles = [ordered]@{
        "DevEco Node" = $tools.Node
        "OHPM CLI" = $tools.OhpmCli
        "OHPM metadata" = $tools.OhpmPackage
        "Hvigor CLI" = $tools.HvigorCli
        "Hvigor metadata" = $tools.HvigorPackage
        "HDC" = $tools.Hdc
        "Emulator.exe" = $tools.Emulator
        "DevEco JBR" = $tools.Java
        "DevEco keytool" = $tools.Keytool
        "HAP sign tool" = $tools.HapSignTool
        "OpenHarmony debug profile template" = $tools.DebugProfileTemplate
    }
    foreach ($item in $toolFiles.GetEnumerator()) {
        if (Test-Path -LiteralPath $item.Value -PathType Leaf) {
            Report "OK" $item.Key $item.Value
        } else {
            Report "FAIL" $item.Key "Missing: $($item.Value)"
        }
    }

    Initialize-DevEcoEnvironment -Tools $tools

    try {
        $product = Get-Content -LiteralPath $tools.ProductInfo -Raw | ConvertFrom-Json
        if ([string]$product.version -like "6.1.1.*") {
            Report "OK" "DevEco version" "$($product.version) ($($product.buildNumber))"
        } else {
            Report "FAIL" "DevEco version" "Found $($product.version), expected 6.1.1.x"
        }
    } catch {
        Report "FAIL" "DevEco version" $_.Exception.Message
    }

    try {
        $nodeVersion = (Invoke-Capture -FilePath $tools.Node -Arguments @("--version")).Text.Trim()
        if ($nodeVersion -match '^v18\.') {
            Report "OK" "DevEco Node version" $nodeVersion
        } else {
            Report "FAIL" "DevEco Node version" "Found $nodeVersion, expected Node 18"
        }
    } catch {
        Report "FAIL" "DevEco Node version" $_.Exception.Message
    }

    foreach ($packageCheck in @(
        [pscustomobject]@{ Name = "OHPM version"; Path = $tools.OhpmPackage },
        [pscustomobject]@{ Name = "Hvigor version"; Path = $tools.HvigorPackage }
    )) {
        try {
            $packageMetadata = Get-Content -LiteralPath $packageCheck.Path -Raw | ConvertFrom-Json
            Report "OK" $packageCheck.Name ([string]$packageMetadata.version)
        } catch {
            Report "FAIL" $packageCheck.Name $_.Exception.Message
        }
    }

    foreach ($versionCheck in @(
        [pscustomobject]@{ Name = "HDC version"; File = $tools.Hdc; Args = @("version") },
        [pscustomobject]@{ Name = "Emulator version"; File = $tools.Emulator; Args = @("-version") }
    )) {
        try {
            $versionText = (Invoke-Capture -FilePath $versionCheck.File -Arguments $versionCheck.Args).Text.Trim()
            Report "OK" $versionCheck.Name ($versionText -replace "`r?`n", "; ")
        } catch {
            Report "FAIL" $versionCheck.Name $_.Exception.Message
        }
    }

    try {
        $sdk = Get-Content -LiteralPath $tools.SdkPackage -Raw | ConvertFrom-Json
        if ([string]$sdk.data.apiVersion -eq "24") {
            Report "OK" "HarmonyOS SDK" "$($sdk.data.displayName), API $($sdk.data.apiVersion), $($sdk.data.version)"
        } else {
            Report "FAIL" "HarmonyOS SDK" "Found API $($sdk.data.apiVersion), expected API 24"
        }
    } catch {
        Report "FAIL" "HarmonyOS SDK" $_.Exception.Message
    }

    try {
        $instance = Get-EmulatorInstance -Tools $tools
        $running = [string]$instance.isRunning
        if ([string]$instance.'os.apiVersion' -eq "24") {
            Report "OK" "Pura90 emulator" "$($instance.name), $($instance.'os.osVersion'), API 24, running=$running, path=$($instance.instancePath)"
        } else {
            Report "FAIL" "Pura90 emulator" "API $($instance.'os.apiVersion') instead of API 24"
        }
    } catch {
        Report "FAIL" "Pura90 emulator" $_.Exception.Message
    }

    try {
        $targets = Get-HdcTargets -Tools $tools
        if ($targets.Count -eq 0) {
            Report "WARN" "HDC targets" "No target connected (doctor did not start an emulator)"
        } else {
            Report "OK" "HDC targets" ($targets -join ', ')
        }
    } catch {
        Report "WARN" "HDC targets" $_.Exception.Message
    }

    $signing = [pscustomobject]@{ Ready = $false; Message = "Target project is incomplete" }
    $projectFiles = @("build-profile.json5", "oh-package.json5", "hvigorfile.ts", "AppScope\app.json5")
    $missingProjectFiles = @($projectFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $script:ProjectRoot $_) -PathType Leaf) })
    if ($missingProjectFiles.Count -gt 0) {
        Report "FAIL" "Target project" "Not generated/incomplete; missing: $($missingProjectFiles -join ', ')"
    } else {
        Report "OK" "Target project" "Required root files exist"
        $profileText = Get-ProjectBuildProfileText
        $appConfigPath = Join-Path $script:ProjectRoot "AppScope\app.json5"
        if (Test-Path -LiteralPath $appConfigPath -PathType Leaf) {
            $appConfigText = Get-Content -LiteralPath $appConfigPath -Raw
            $bundle = Get-ProfileStringValue -Text $appConfigText -Name "bundleName"
        } else {
            $bundle = Get-ProfileStringValue -Text $profileText -Name "bundleName"
        }
        if ($bundle -eq $script:BundleName) {
            Report "OK" "bundleName" $bundle
        } else {
            Report "FAIL" "bundleName" "Found '$bundle', expected '$script:BundleName'"
        }
        if ($profileText -match '(?i)(6\.1\.1\s*\(24\)|\b24\b)') {
            Report "OK" "Project API" "API 24 reference found"
        } else {
            Report "WARN" "Project API" "No API 24 reference found in build-profile.json5"
        }

        $signing = Test-SigningConfiguration -Tools $tools -Quiet
        if ($signing.Ready) {
            Report "OK" "Project signing" $signing.Message
        } else {
            Report "WARN" "Project signing" "$($signing.Message). Unsigned builds remain available; use DevEco automatic signing for this exact bundle before install/smoke."
        }
    }

    $signedHap = Find-Hap -Preference "signed"
    $unsignedHap = Find-Hap -Preference "unsigned"
    if ($signedHap -and $signing.Ready) {
        Report "OK" "Signed HAP" $signedHap
    } elseif ($signedHap) {
        Report "WARN" "HAP output" "A signed-named HAP exists but current project signing is not verified, so install will not auto-select it: $signedHap"
    } elseif ($unsignedHap) {
        Report "WARN" "HAP output" "Only unsigned HAP found: $unsignedHap"
    } else {
        Report "WARN" "HAP output" "No HAP exists yet; doctor did not start an emulator"
    }

    $failures = $script:DoctorFailures
    $warnings = $script:DoctorWarnings
    Write-Host ""
    Write-Host "Doctor summary: $failures failure(s), $warnings warning(s)."
    if ($failures -gt 0) {
        return 1
    }
    return 0
}

function Show-Help {
    @"
PelicanBike HarmonyOS device tools

Usage (PowerShell):
  .\tools\device\device.ps1 <command> [options]

Usage (Git Bash):
  ./tools/device/device.sh <command> [options]

Commands:
  doctor          Validate DevEco 6.1.1, Node 18, OHPM, Hvigor, SDK API 24,
                  HDC, Emulator.exe, Pura90, target project, signing, and HAPs.
  sync            Run OHPM install --all and Hvigor --sync from the project root.
  build           Run assembleHap. -PackageMode auto|signed|unsigned.
  emulator-start  Start Pura90 with coldboot (preserves emulator data).
  emulator-stop   Stop Pura90 without reset/delete.
  emulator-wait   Wait for one HDC target; use -Serial when multiple exist.
  install         Install the last verified signed build, or explicit -HapPath.
  launch          Launch com.riba2534.pelicanbike/EntryAbility.
  hilog           Stream HDC hilog filtered by -Filter (regex).
  screenshot      Capture and pull a JPEG. Defaults under tools/device/artifacts.
  signing-check   Verify bundle-name, profile validity, and certificate match.
  smoke           Build, then start/wait if needed, install, launch, and check
                  process plus filtered hilog. Emulator starts only after a
                  signed HAP has been built and confirmed to exist.

Common options:
  -PackageMode auto|signed|unsigned  Build output selection (default auto)
  -SkipSync                          Skip sync before build/smoke
  -DeviceName Pura90                 Emulator instance name
  -Serial <hdc-target>               Required when multiple targets are connected
  -HapPath <path>                    Explicit HAP for install; Git Bash paths work
  -Filter <regex>                    hilog/smoke filter
  -OutputPath <path>                 screenshot destination
  -TimeoutSec 180                    emulator/HDC wait timeout
  -Product default -Module entry -Target default -BuildMode debug

Safety:
  The script never uses emulator reset/delete, hdc uninstall, or data-clearing
  commands. It never edits project configuration. PATH changes are child-process
  local only, and DevEco's absolute Node 18 executable runs OHPM/Hvigor.
"@ | Write-Host
}

try {
    $normalizedCommand = $Command.ToLowerInvariant()
    if ($normalizedCommand -in @("help", "-h", "--help")) {
        Show-Help
        exit 0
    }

    $tools = Get-Toolchain
    Assert-Toolchain -Tools $tools

    switch ($normalizedCommand) {
        "doctor" {
            $doctorExit = Invoke-Doctor
            exit $doctorExit
        }
        "sync" {
            Invoke-Sync -Tools $tools
        }
        "build" {
            Invoke-Build -Tools $tools | Out-Null
        }
        "emulator-start" {
            Start-ConfiguredEmulator -Tools $tools
        }
        "emulator-stop" {
            Stop-ConfiguredEmulator -Tools $tools
        }
        "emulator-wait" {
            Wait-HdcTarget -Tools $tools | Out-Null
        }
        "install" {
            $resolvedSerial = Resolve-DeviceSerial -Tools $tools
            $resolvedHap = Resolve-InstallHap -Tools $tools
            Install-Hap -Tools $tools -ResolvedSerial $resolvedSerial -ResolvedHap $resolvedHap
        }
        "launch" {
            $resolvedSerial = Resolve-DeviceSerial -Tools $tools
            Launch-App -Tools $tools -ResolvedSerial $resolvedSerial
        }
        "hilog" {
            Invoke-HilogStream -Tools $tools
        }
        "screenshot" {
            Capture-Screenshot -Tools $tools
        }
        "signing-check" {
            Assert-ProjectReady
            Initialize-DevEcoEnvironment -Tools $tools
            $signing = Test-SigningConfiguration -Tools $tools
            if (-not $signing.Ready) {
                throw $signing.Message
            }
            Write-Info $signing.Message
            Write-Info "Issuer: $($signing.Issuer)"
        }
        "smoke" {
            Invoke-Smoke -Tools $tools
        }
        default {
            throw "Unknown command '$Command'. Run 'help' for usage."
        }
    }
} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
